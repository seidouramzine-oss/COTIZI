import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import 'format.dart';
import 'models.dart';

/// Erreur métier avec un message prêt à afficher.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Essai ou abonnement du tontinier terminé : création impossible.
class SubscriptionExpired extends AppException {
  const SubscriptionExpired()
    : super(
        'Votre essai gratuit ou votre abonnement est terminé. '
        'Renouvelez-le pour créer de nouvelles tontines.',
      );
}

/// Accès aux données COTIZI (Firebase Auth + Firestore).
/// Les règles de firebase/firestore.rules vérifient chaque écriture.
class Api {
  Api._();

  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static String get uid => _auth.currentUser!.uid;

  static FieldValue get _now => FieldValue.serverTimestamp();

  static Profile? _me;
  static bool? _admin;

  /// Le numéro sert d'identifiant : le compte Firebase utilise un email
  /// technique dérivé du numéro (aucun email n'est envoyé).
  static String phoneToEmail(String phone) =>
      '${phone.replaceFirst('+', '')}@phone.cotizi.app';

  static String get _accountPhone =>
      '+${_auth.currentUser!.email!.split('@').first}';

  // ---------------------------------------------------------------- Compte

  static Stream<User?> authChanges() => _auth.authStateChanges();

  /// Inscription en cours : le profil est créé juste après le compte, on
  /// l'attend avant de chercher le profil (sinon il paraîtrait manquant).
  static Future<void>? _signingUp;

  /// Un client ([Role.membre]) s'inscrit avec le code d'invitation de son
  /// tontinier : s'il est introuvable, le compte n'est pas créé.
  static Future<void> signUp({
    required String phone,
    required String password,
    required String fullName,
    Role role = Role.tontinier,
    String? inviteCode,
  }) {
    final future = _signUp(phone, password, fullName, role, inviteCode);
    _signingUp = future;
    return future.whenComplete(() => _signingUp = null);
  }

  static Future<void> _signUp(
    String phone,
    String password,
    String fullName,
    Role role,
    String? inviteCode,
  ) async {
    _me = null;
    _admin = null;
    try {
      await _auth.createUserWithEmailAndPassword(
        email: phoneToEmail(phone),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw const AppException('Ce numéro est déjà inscrit. Connectez-vous.');
      }
      rethrow;
    }
    if (role == Role.membre) {
      try {
        await verifyInviteCode(inviteCode ?? '');
      } catch (_) {
        // Code faux : on annule l'inscription pour pouvoir la refaire
        await _auth.currentUser?.delete().catchError((_) => _auth.signOut());
        rethrow;
      }
    }
    await createProfile(fullName, role: role);
  }

  /// Code d'invitation sans espaces ni tirets, en majuscules.
  static String normalizeCode(String input) =>
      input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Vérifie qu'un code d'invitation existe ; renvoie le code normalisé.
  static Future<String> verifyInviteCode(String input) async {
    final code = normalizeCode(input);
    if (code.isEmpty || !(await _db.doc('invites/$code').get()).exists) {
      throw const AppException(
        'Code d\'invitation introuvable. Vérifiez le code envoyé par votre '
        'tontinier.',
      );
    }
    return code;
  }

  static Future<void> signIn({
    required String phone,
    required String password,
  }) async {
    _me = null;
    _admin = null;
    await _auth.signInWithEmailAndPassword(
      email: phoneToEmail(phone),
      password: password,
    );
  }

  static Future<void> signOut() async {
    _me = null;
    _admin = null;
    await _auth.signOut();
  }

  /// Profil de l'utilisateur connecté (null s'il n'a pas encore été créé).
  static Future<Profile?> myProfile() async {
    if (_signingUp != null) await _signingUp!.catchError((_) {});
    // Inscription annulée (code d'invitation faux) : plus de compte
    if (_auth.currentUser == null) return null;
    if (_me != null) return _me;
    final doc = await _db.doc('users/$uid').get();
    if (!doc.exists) return null;
    return _me = Profile.fromJson(doc.data()!);
  }

  /// Profil relu depuis le serveur (abonnement prolongé entre-temps…).
  static Future<Profile?> reloadProfile() {
    _me = null;
    return myProfile();
  }

  /// Administrateur de COTIZI (document admins/{uid} créé dans la console).
  static Future<bool> isAdmin() async {
    if (_admin != null) return _admin!;
    try {
      return _admin = (await _db.doc('admins/$uid').get()).exists;
    } on FirebaseException {
      return false;
    }
  }

  /// Création de tontine, groupe ou carnet : réservée aux tontiniers dont
  /// l'essai ou l'abonnement est en cours (et à l'administrateur).
  static Future<void> ensureCanCreate() async {
    final me = await _requireMe();
    if (me.isMember) {
      throw const AppException(
        'Votre compte client sert à participer aux tontines de votre tontinier.',
      );
    }
    if (me.canCreateAt(DateTime.now()) || await isAdmin()) return;
    final fresh = await reloadProfile();
    if (fresh != null && fresh.canCreateAt(DateTime.now())) return;
    throw const SubscriptionExpired();
  }

  static Future<Profile> _requireMe() async =>
      await myProfile() ??
      (throw const AppException('Complétez votre profil pour continuer'));

  static Future<void> createProfile(
    String fullName, {
    Role role = Role.tontinier,
  }) async {
    final profile = Profile(
      fullName: fullName.trim(),
      phone: _accountPhone,
      role: role,
      createdAt: DateTime.now(),
    );
    await _db.doc('users/$uid').set({
      'fullName': profile.fullName,
      'phone': profile.phone,
      'role': role.name,
      'createdAt': _now,
    });
    _me = profile;
  }

  static Future<Profile> updateName(String fullName) async {
    final name = fullName.trim();
    await _db.doc('users/$uid').update({'fullName': name});
    final me = await myProfile();
    return _me = (me ?? Profile(fullName: name, phone: _accountPhone)).withName(
      name,
    );
  }

  static Future<void> changePassword(String current, String next) async {
    final user = _auth.currentUser!;
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: current),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw const AppException('Mot de passe actuel incorrect');
      }
      rethrow;
    }
    await user.updatePassword(next);
  }

  // ---------------------------------------------------------- Administration

  /// Tous les comptes (réservé à l'administrateur).
  static Future<List<Account>> accounts() async {
    final snap = await _db.collection('users').get();
    return [
      for (final d in snap.docs)
        Account(id: d.id, profile: Profile.fromJson(d.data())),
    ]..sort(
      (a, b) => a.profile.fullName.toLowerCase().compareTo(
        b.profile.fullName.toLowerCase(),
      ),
    );
  }

  /// Ajoute [months] mois à l'abonnement, à partir de sa fin actuelle si
  /// elle n'est pas encore passée.
  static Future<Account> extendSubscription(Account a, int months) async {
    final now = DateTime.now();
    final current = a.profile.accessEnd;
    final end = addMonths(
      current != null && current.isAfter(now) ? current : now,
      months,
    );
    await _db.doc('users/${a.id}').update({
      'subscriptionEnd': Timestamp.fromDate(end),
    });
    return Account(id: a.id, profile: a.profile.withSubscriptionEnd(end));
  }

  /// Arrête l'abonnement tout de suite (fin = maintenant).
  static Future<Account> stopSubscription(Account a) async {
    await _db.doc('users/${a.id}').update({'subscriptionEnd': _now});
    return Account(
      id: a.id,
      profile: a.profile.withSubscriptionEnd(DateTime.now()),
    );
  }

  static Future<SubscriptionSettings> subscriptionSettings() async {
    final doc = await _db.doc('settings/subscription').get();
    return SubscriptionSettings.fromJson(doc.data());
  }

  static Future<void> saveSubscriptionSettings(SubscriptionSettings s) =>
      _db.doc('settings/subscription').set({
        'monthlyPrice': s.monthlyPrice,
        'paymentPhone': s.paymentPhone.trim(),
        'supportPhone': s.supportPhone.trim(),
      });

  /// Le tontinier demande un abonnement de [months] mois : la demande
  /// apparaît dans l'Administration, il écrit ensuite à COTIZI sur WhatsApp.
  static Future<void> requestSubscription(int months, int amount) async {
    final me = await _requireMe();
    await _db.doc('subscriptionRequests/$uid').set({
      'fullName': me.fullName,
      'phone': me.phone,
      'months': months,
      'amount': amount,
      'requestedAt': _now,
    });
  }

  /// Demandes d'abonnement en attente (administrateur), les plus anciennes
  /// d'abord.
  static Future<List<SubscriptionRequest>> subscriptionRequests() async {
    final snap = await _db.collection('subscriptionRequests').get();
    return snap.docs.map(SubscriptionRequest.fromDoc).toList()
      ..sort((a, b) => a.requestedAt.compareTo(b.requestedAt));
  }

  /// Ma demande d'abonnement en attente, s'il y en a une.
  static Future<SubscriptionRequest?> myRequest() async {
    final doc = await _db.doc('subscriptionRequests/$uid').get();
    return doc.exists ? SubscriptionRequest.fromDoc(doc) : null;
  }

  static Future<void> closeSubscriptionRequest(String userId) =>
      _db.doc('subscriptionRequests/$userId').delete();

  // ---------------------------------------------------------- Notifications

  static final _managedId = RegExp(r'^p\d+$');

  /// Prévient [to] d'une opération (cloche de notifications). Envoi au mieux :
  /// une erreur n'annule jamais l'opération elle-même.
  static Future<void> _notify({
    required String? to,
    required String type,
    required String title,
    required String body,
    String? groupId,
    String? carnetId,
  }) async {
    if (to == null || to == uid || _managedId.hasMatch(to)) return;
    try {
      final me = await _requireMe();
      await _db.collection('users/$to/notifications').add({
        'type': type,
        'title': title,
        'body': body.length > 300 ? body.substring(0, 300) : body,
        'groupId': groupId,
        'carnetId': carnetId,
        'actorId': uid,
        'actorName': me.fullName,
        'read': false,
        'at': _now,
      });
    } catch (_) {}
  }

  /// Mes notifications, les plus récentes d'abord.
  static Future<List<AppNotification>> notifications({int limit = 50}) async {
    final snap = await _db
        .collection('users/$uid/notifications')
        .orderBy('at', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(AppNotification.fromDoc).toList();
  }

  /// Nombre de notifications non lues (au plus 99).
  static Future<int> unreadCount() async {
    final snap = await _db
        .collection('users/$uid/notifications')
        .where('read', isEqualTo: false)
        .limit(99)
        .get();
    return snap.size;
  }

  static Future<void> markAllRead(List<AppNotification> list) async {
    final unread = list.where((n) => !n.read).toList();
    if (unread.isEmpty) return;
    final batch = _db.batch();
    for (final n in unread) {
      batch.update(_db.doc('users/$uid/notifications/${n.id}'), {'read': true});
    }
    await batch.commit();
  }

  // --------------------------------------------------------------- Accueils

  /// Tableau de bord du tontinier : ses groupes, ses carnets et tous les
  /// paiements qui attendent sa validation.
  static Future<OwnerOverview> ownerOverview() async {
    final results = await Future.wait([
      _db.collection('tontines').where('ownerId', isEqualTo: uid).count().get(),
      _db.collection('groups').where('ownerId', isEqualTo: uid).get(),
      _db.collection('carnets').where('ownerId', isEqualTo: uid).get(),
    ]);
    final tontineCount = (results[0] as AggregateQuerySnapshot).count ?? 0;
    final groups = await Future.wait(
      (results[1] as QuerySnapshot<Json>).docs
          .map(Group.fromDoc)
          .map(
            (g) => g.status == GroupStatus.active && !g.isLegacy
                ? group(g.id)
                : Future.value(g),
          ),
    );
    final carnets = (results[2] as QuerySnapshot<Json>).docs
        .map(Carnet.fromDoc)
        .toList();
    final pending = await Future.wait([
      for (final g in groups.where(
        (g) => g.status == GroupStatus.active && !g.isLegacy,
      ))
        _pendingOf('groups/${g.id}/payments').then(
          (list) => [for (final p in list) PendingReview(payment: p, group: g)],
        ),
      for (final c in carnets.where((c) => c.pendingCases > 0))
        _pendingOf('carnets/${c.id}/payments').then(
          (list) => [
            for (final p in list) PendingReview(payment: p, carnet: c),
          ],
        ),
    ]);
    return OwnerOverview(
      tontineCount: tontineCount,
      groups: groups,
      carnets: carnets,
      pending: pending.expand((l) => l).toList()
        ..sort((a, b) => a.payment.declaredAt.compareTo(b.payment.declaredAt)),
    );
  }

  static Future<List<Payment>> _pendingOf(String collection) async {
    final snap = await _db
        .collection(collection)
        .where('status', isEqualTo: 'pending')
        .get();
    return snap.docs.map(Payment.fromDoc).toList();
  }

  /// Accueil du participant : ce qu'il doit payer dans chaque groupe et
  /// l'avancement de ses carnets.
  static Future<MemberOverview> memberOverview() async {
    final results = await Future.wait([myGroups(), myCarnets()]);
    final groups = results[0] as List<Group>;
    final today = DateTime.now();
    final statuses = await Future.wait(
      groups.map((g) async {
        final detail = await group(g.id);
        final payments = await groupPayments(detail);
        final me = detail.memberById(uid);
        final pos = me?.drawPosition;
        Payout? toConfirm;
        if (!detail.isLegacy && pos != null && pos <= detail.paidOutCount) {
          final doc = await _db.doc('groups/${detail.id}/payouts/$pos').get();
          final payout = doc.exists ? Payout.fromDoc(doc) : null;
          if (payout != null && !payout.confirmed && payout.problem == null) {
            toConfirm = payout;
          }
        }
        return MemberGroupStatus(
          group: detail,
          payments: payments,
          payoutToConfirm: toConfirm,
          standing: me == null
              ? MemberStanding(
                  due: 0,
                  declared: 0,
                  approved: 0,
                  total: detail.totalContributions,
                )
              : detail.standingOf(me, today),
        );
      }),
    );
    return MemberOverview(
      groups: statuses,
      carnets: results[1] as List<Carnet>,
    );
  }

  // -------------------------------------------------------------- Tontines

  static Future<List<Tontine>> myTontines() async {
    final snap = await _db
        .collection('tontines')
        .where('ownerId', isEqualTo: uid)
        .get();
    final tontines = snap.docs.map(Tontine.fromDoc).toList();
    final withCounts = await Future.wait(
      tontines.map((t) async {
        final count = await _db
            .collection(t.type == TontineType.cagnotte ? 'groups' : 'carnets')
            .where('ownerId', isEqualTo: uid)
            .where('tontineId', isEqualTo: t.id)
            .count()
            .get();
        return t.withCount(count.count ?? 0);
      }),
    );
    return withCounts..sort((a, b) => a.name.compareTo(b.name));
  }

  static Future<Tontine> createTontine(String name, TontineType type) async {
    await ensureCanCreate();
    final me = await _requireMe();
    final ref = _db.collection('tontines').doc();
    await ref.set({
      'ownerId': uid,
      'ownerName': me.fullName,
      'name': name.trim(),
      'type': type.name,
      'createdAt': _now,
    });
    return Tontine(id: ref.id, ownerId: uid, name: name.trim(), type: type);
  }

  // ------------------------------------------------------ Codes d'invitation

  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static String _newCode() {
    final rand = Random.secure();
    return List.generate(
      6,
      (_) => _codeAlphabet[rand.nextInt(_codeAlphabet.length)],
    ).join();
  }

  /// Crée un groupe ou un carnet avec son code ; réessaie si le code
  /// tiré existe déjà (refus des règles). [extra] ajoute d'autres écritures
  /// au même envoi (journal).
  static Future<String> _createWithInvite(
    String collection,
    String kind,
    Json Function(String code) data, {
    void Function(WriteBatch batch, String id)? extra,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final code = _newCode();
      final ref = _db.collection(collection).doc();
      final batch = _db.batch()
        ..set(ref, data(code))
        ..set(_db.doc('invites/$code'), {
          'kind': kind,
          'targetId': ref.id,
          'ownerId': uid,
        });
      extra?.call(batch, ref.id);
      try {
        await batch.commit();
        return ref.id;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied' || attempt >= 4) rethrow;
      }
    }
  }

  /// Chiffres du numéro du compte (sans le +).
  static String get _phoneDigits => _auth.currentUser!.email!.split('@').first;

  /// Identifiant de la place réservée pour un numéro (+229…) : p229…
  static String managedId(String phone) => 'p${phone.replaceAll('+', '')}';

  /// Rejoint un groupe ou un carnet ; renvoie (type, id).
  static Future<(String kind, String id)> joinWithCode(String input) async {
    final code = normalizeCode(input);
    final invite = await _db.doc('invites/$code').get();
    if (!invite.exists) {
      throw const AppException('Code d\'invitation introuvable');
    }
    final kind = invite['kind'] as String;
    final targetId = invite['targetId'] as String;
    if (invite['ownerId'] == uid) {
      throw AppException(
        kind == 'group'
            ? 'Vous êtes le tontinier de ce groupe'
            : 'Vous êtes le tontinier de ce carnet',
      );
    }
    final me = await _requireMe();

    if (kind == 'group') {
      if (await _canRead('groups/$targetId')) return (kind, targetId);
      final ref = _db.doc('groups/$targetId');
      // Place réservée par le tontinier à ce numéro ?
      final reserved = await ref
          .collection('members')
          .doc('p$_phoneDigits')
          .get();
      final batch = _db.batch();
      final (eventRef, eventData) = _eventDoc(
        targetId,
        me,
        'joined',
        reserved.exists
            ? '${me.fullName} a rejoint le groupe (place réservée)'
            : '${me.fullName} a rejoint le groupe',
      );
      if (reserved.exists && reserved.data()?['claimedBy'] == null) {
        final spot = GroupMember.fromDoc(reserved);
        batch
          ..set(ref.collection('members').doc(uid), {
            'fullName': me.fullName,
            'phone': me.phone,
            'joinedAt': _now,
            'drawPosition': spot.drawPosition,
            'declaredCount': spot.declaredCount,
            'approvedCount': spot.approvedCount,
            'lastPaymentId': null,
            'penaltyPaid': spot.penaltyPaid,
            'claimedFrom': reserved.id,
          })
          ..update(ref, {
            'memberIds': FieldValue.arrayUnion([uid]),
          });
        // Pendant les inscriptions la place est remplacée ; ensuite elle est
        // gardée pour l'historique de ses paiements.
        if (spot.drawPosition == null) {
          batch.delete(reserved.reference);
        } else {
          batch.update(reserved.reference, {'claimedBy': uid});
        }
      } else {
        batch
          ..update(ref, {
            'joinedCount': FieldValue.increment(1),
            'memberIds': FieldValue.arrayUnion([uid]),
          })
          ..set(ref.collection('members').doc(uid), {
            'fullName': me.fullName,
            'phone': me.phone,
            'joinedAt': _now,
            'drawPosition': null,
            'declaredCount': 0,
            'approvedCount': 0,
            'lastPaymentId': null,
            'penaltyPaid': 0,
          });
      }
      batch.set(eventRef, eventData);
      try {
        await batch.commit();
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          throw AppException(
            reserved.exists
                ? 'Le tirage au sort est en cours : réessayez dès que '
                      'votre numéro est tiré.'
                : 'Ce groupe est complet ou les inscriptions sont terminées',
          );
        }
        rethrow;
      }
      final name = (await ref.get()).data()?['name'] as String? ?? '';
      await _notify(
        to: invite['ownerId'] as String?,
        type: 'joined',
        title: 'Nouveau participant',
        body: '${me.fullName} a rejoint le groupe « $name ».',
        groupId: targetId,
      );
      return (kind, targetId);
    }

    if (await _canRead('carnets/$targetId')) return (kind, targetId);
    try {
      await _db.doc('carnets/$targetId').update({
        'clientId': uid,
        'clientName': me.fullName,
        'clientPhone': me.phone,
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const AppException('Ce carnet a déjà un client');
      }
      rethrow;
    }
    await _notify(
      to: invite['ownerId'] as String?,
      type: 'joined',
      title: 'Nouveau client',
      body: '${me.fullName} a pris un de vos carnets.',
      carnetId: targetId,
    );
    return (kind, targetId);
  }

  static Future<bool> _canRead(String path) async {
    try {
      await _db.doc(path).get();
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return false;
      rethrow;
    }
  }

  // ----------------------------------------------------------- Journal

  /// Ligne du journal : visible de tous ([memberId] null) ou seulement du
  /// tontinier et du participant [memberId].
  static (DocumentReference<Json>, Json) _eventDoc(
    String groupId,
    Profile me,
    String type,
    String text, {
    String? memberId,
  }) => (
    _db.collection('groups/$groupId/events').doc(),
    {
      'type': type,
      'text': text,
      'actorId': uid,
      'actorName': me.fullName,
      'memberId': memberId,
      'visibility': memberId == null ? 'all' : 'member',
      'at': _now,
    },
  );

  /// Journal du groupe, le plus récent d'abord.
  static Future<List<GroupEvent>> events(Group g) async {
    final col = _db.collection('groups/${g.id}/events');
    final List<QuerySnapshot<Json>> snaps;
    if (g.ownerId == uid) {
      snaps = [await col.get()];
    } else {
      final ids = g.memberById(uid)?.paymentIds ?? [uid];
      snaps = await Future.wait([
        col.where('visibility', isEqualTo: 'all').get(),
        col.where('memberId', whereIn: ids).get(),
      ]);
    }
    final seen = <String>{};
    return [
      for (final snap in snaps)
        for (final d in snap.docs)
          if (seen.add(d.id)) GroupEvent.fromDoc(d),
    ]..sort((a, b) => b.at.compareTo(a.at));
  }

  // ------------------------------------------------- Tontine à cagnotte

  static Future<List<Group>> groupsOf(String tontineId) async {
    final snap = await _db
        .collection('groups')
        .where('ownerId', isEqualTo: uid)
        .where('tontineId', isEqualTo: tontineId)
        .get();
    final groups = snap.docs.map(Group.fromDoc).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Future.wait(
      groups.map((g) async {
        final pending = await _db
            .collection('groups/${g.id}/payments')
            .where('status', isEqualTo: 'pending')
            .count()
            .get();
        return g.copyWith(pendingCount: pending.count ?? 0);
      }),
    );
  }

  static Future<List<Group>> myGroups() async {
    final snap = await _db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .get();
    return snap.docs.map(Group.fromDoc).toList();
  }

  /// Groupe et ses participants (sans les places reprises par leur
  /// titulaire), dans l'ordre des remises.
  static Future<Group> group(String id) async {
    final results = await Future.wait([
      _db.doc('groups/$id').get(),
      _db.collection('groups/$id/members').get(),
    ]);
    final members =
        (results[1] as QuerySnapshot<Json>).docs
            .map(GroupMember.fromDoc)
            .where((m) => m.claimedBy == null)
            .toList()
          ..sort(
            (a, b) => (a.drawPosition ?? 1 << 30).compareTo(
              b.drawPosition ?? 1 << 30,
            ),
          );
    return Group.fromDoc(results[0] as DocumentSnapshot<Json>)
        .copyWith(members: members);
  }

  static Json _terms(GroupTerms t) => {
    'name': t.name.trim(),
    'memberCount': t.memberCount,
    'contributionAmount': t.contributionAmount,
    'frequency': t.frequency.name,
    'startDate': dateKey(t.startDate),
    'contributionsPerPot': t.contributionsPerPot,
    'firstPayoutDate': dateKey(t.firstPayoutDate),
    'orderMode': t.orderMode.name,
    'penaltyAmount': t.penaltyAmount,
    'penaltyGraceDays': t.penaltyGraceDays,
    'commissionType': t.commissionType.name,
    'commissionValue': t.commissionValue,
    'penaltyType': t.penaltyType.name,
    'rulesText': t.rulesText.trim(),
  };

  static Future<String> createGroup(Tontine tontine, GroupTerms terms) async {
    await ensureCanCreate();
    final me = await _requireMe();
    return _createWithInvite(
      'groups',
      'group',
      (code) => {
        'tontineId': tontine.id,
        'tontineName': tontine.name,
        'ownerId': uid,
        'ownerName': me.fullName,
        ..._terms(terms),
        'paidOutCount': 0,
        'inviteCode': code,
        'status': 'recruiting',
        'joinedCount': 0,
        'drawnCount': 0,
        'memberIds': <String>[],
        'startedAt': null,
        'createdAt': _now,
        // Règlement à accepter par chaque participant avant le démarrage
        'termsVersion': 1,
        'accepted': <String, int>{},
      },
      extra: (batch, id) {
        final (ref, data) = _eventDoc(
          id,
          me,
          'created',
          'Groupe créé : ${terms.memberCount} participants, '
              '${money(terms.contributionAmount)} ${frequencyLower(terms.frequency)}',
        );
        batch.set(ref, data);
      },
    );
  }

  /// Modification pendant les inscriptions. Si les conditions changent
  /// (montants, pénalités, règles…), le règlement passe à une nouvelle
  /// version que chacun doit accepter de nouveau.
  static Future<void> updateGroup(Group g, GroupTerms terms) async {
    final me = await _requireMe();
    final changed =
        terms.memberCount != g.memberCount ||
        terms.contributionAmount != g.contributionAmount ||
        terms.frequency != g.frequency ||
        terms.contributionsPerPot != g.perPot ||
        terms.orderMode != g.orderMode ||
        terms.penaltyAmount != g.penaltyAmount ||
        terms.penaltyGraceDays != g.penaltyGraceDays ||
        terms.penaltyType != g.penaltyType ||
        terms.commissionType != g.commissionType ||
        terms.commissionValue != g.commissionValue ||
        terms.rulesText.trim() != g.rulesText;
    final newVersion = g.termsVersion != null && changed;
    final (ref, data) = _eventDoc(
      g.id,
      me,
      'edited',
      newVersion
          ? 'Règlement modifié : chaque participant doit l\'accepter de nouveau'
          : 'Conditions du groupe modifiées',
    );
    await (_db.batch()
          ..update(_db.doc('groups/${g.id}'), {
            ..._terms(terms),
            if (newVersion) 'termsVersion': g.termsVersion! + 1,
          })
          ..set(ref, data))
        .commit();
  }

  /// Le participant accepte le règlement en vigueur du groupe.
  static Future<void> acceptRules(Group g) async {
    final me = await _requireMe();
    final (ref, data) = _eventDoc(
      g.id,
      me,
      'rules_accepted',
      '${me.fullName} a accepté le règlement',
    );
    await (_db.batch()
          ..update(_db.doc('groups/${g.id}'), {'accepted.$uid': g.termsVersion})
          ..set(ref, data))
        .commit();
    await _notify(
      to: g.ownerId,
      type: 'rules_accepted',
      title: 'Règlement accepté',
      body: '${me.fullName} a accepté le règlement de « ${g.name} ».',
      groupId: g.id,
    );
  }

  /// Suppression d'un groupe qui n'a pas démarré (avec ses participants,
  /// son tirage, son journal et son code d'invitation).
  static Future<void> deleteGroup(Group g) async {
    final base = _db.doc('groups/${g.id}');
    final subs = await Future.wait([
      base.collection('members').get(),
      base.collection('draws').get(),
      base.collection('events').get(),
    ]);
    final batch = _db.batch();
    for (final snap in subs) {
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
    }
    batch
      ..delete(base)
      ..delete(_db.doc('invites/${g.inviteCode}'));
    await batch.commit();
  }

  /// Le tontinier ajoute un participant sans application : sa place est
  /// réservée à son numéro.
  static Future<void> addManagedMember(
    Group g,
    String fullName,
    String phone,
  ) async {
    final me = await _requireMe();
    final id = managedId(phone);
    final ref = _db.doc('groups/${g.id}/members/$id');
    if ((await ref.get()).exists ||
        g.members.any((m) => m.profile.phone == phone)) {
      throw const AppException('Ce numéro est déjà dans le groupe');
    }
    final (eventRef, eventData) = _eventDoc(
      g.id,
      me,
      'managed_added',
      '${fullName.trim()} ajouté par le tontinier (sans application)',
    );
    await (_db.batch()
          ..set(ref, {
            'fullName': fullName.trim(),
            'phone': phone,
            'joinedAt': _now,
            'drawPosition': null,
            'declaredCount': 0,
            'approvedCount': 0,
            'lastPaymentId': null,
            'penaltyPaid': 0,
            'managed': true,
            'claimedBy': null,
          })
          ..update(_db.doc('groups/${g.id}'), {
            'joinedCount': FieldValue.increment(1),
          })
          ..set(eventRef, eventData))
        .commit();
  }

  /// Retrait d'un participant pendant les inscriptions.
  static Future<void> removeMember(Group g, GroupMember m) async {
    final me = await _requireMe();
    final (eventRef, eventData) = _eventDoc(
      g.id,
      me,
      'member_removed',
      '${m.name} retiré du groupe',
    );
    await (_db.batch()
          ..delete(_db.doc('groups/${g.id}/members/${m.userId}'))
          ..update(_db.doc('groups/${g.id}'), {
            'joinedCount': FieldValue.increment(-1),
            'memberIds': FieldValue.arrayRemove([m.userId]),
            if (g.accepted.containsKey(m.userId))
              'accepted.${m.userId}': FieldValue.delete(),
          })
          ..set(eventRef, eventData))
        .commit();
  }

  /// Le tontinier voit tous les paiements ; un participant seulement les
  /// siens (y compris ceux de sa place réservée).
  static Future<List<Payment>> groupPayments(Group g) async {
    Query<Json> query = _db.collection('groups/${g.id}/payments');
    if (g.ownerId != uid) {
      query = query.where(
        'userId',
        whereIn: g.memberById(uid)?.paymentIds ?? [uid],
      );
    }
    final snap = await query.get();
    return snap.docs.map(Payment.fromDoc).toList()
      ..sort((a, b) => b.declaredAt.compareTo(a.declaredAt));
  }

  /// Lance le tirage : l'ordre de passage est tiré au hasard ici, puis
  /// chaque participant découvre son numéro en « tirant ».
  static Future<void> startDraw(Group g) async {
    final me = await _requireMe();
    final members = (await _db.collection('groups/${g.id}/members').get()).docs
        .where((d) => d.data()['claimedBy'] == null)
        .toList();
    if (members.length != g.memberCount) {
      throw AppException(
        'Le groupe n\'est pas encore complet (${members.length} / ${g.memberCount})',
      );
    }
    final positions = List.generate(g.memberCount, (i) => i + 1)
      ..shuffle(Random.secure());
    final (eventRef, eventData) = _eventDoc(
      g.id,
      me,
      'draw_started',
      'Tirage au sort lancé',
    );
    final batch = _db.batch()
      ..update(_db.doc('groups/${g.id}'), {'status': 'drawing'})
      ..set(eventRef, eventData);
    for (var i = 0; i < members.length; i++) {
      batch.set(_db.doc('groups/${g.id}/draws/${members[i].id}'), {
        'position': positions[i],
      });
    }
    await batch.commit();
  }

  /// Un participant découvre son numéro.
  static Future<int> drawLot(String groupId) async {
    final me = await _requireMe();
    return _db.runTransaction((tx) async {
      final group = await tx.get(_db.doc('groups/$groupId'));
      final member = await tx.get(_db.doc('groups/$groupId/members/$uid'));
      final existing = member.data()?['drawPosition'];
      if (existing != null) return (existing as num).toInt();
      final draw = await tx.get(_db.doc('groups/$groupId/draws/$uid'));
      if (!draw.exists) {
        throw const AppException('Le tirage au sort n\'est pas encore ouvert');
      }
      final position = (draw['position'] as num).toInt();
      final (eventRef, eventData) = _eventDoc(
        groupId,
        me,
        'number_drawn',
        '${me.fullName} a tiré le n°$position',
      );
      tx
        ..update(member.reference, {'drawPosition': position})
        ..update(group.reference, {
          'drawnCount': (group['drawnCount'] as num).toInt() + 1,
        })
        ..set(eventRef, eventData);
      return position;
    });
  }

  /// Le tontinier révèle les numéros des participants qui n'ont pas tiré
  /// (et des participants sans application).
  static Future<void> finishDraw(Group g) async {
    final me = await _requireMe();
    final members = await _db.collection('groups/${g.id}/members').get();
    final batch = _db.batch();
    for (final m in members.docs.where(
      (d) => d['drawPosition'] == null && d.data()['claimedBy'] == null,
    )) {
      final draw = await _db.doc('groups/${g.id}/draws/${m.id}').get();
      batch.update(m.reference, {'drawPosition': draw['position']});
    }
    final (eventRef, eventData) = _eventDoc(
      g.id,
      me,
      'draw_finished',
      'Tirage au sort terminé',
    );
    batch
      ..update(_db.doc('groups/${g.id}'), {'drawnCount': g.memberCount})
      ..set(eventRef, eventData);
    await batch.commit();
  }

  /// Ordre des remises fixé par le tontinier ([ordered] : 1er bénéficiaire
  /// en premier).
  static Future<void> setManualOrder(Group g, List<GroupMember> ordered) async {
    final me = await _requireMe();
    final batch = _db.batch();
    for (var i = 0; i < ordered.length; i++) {
      batch.update(_db.doc('groups/${g.id}/members/${ordered[i].userId}'), {
        'drawPosition': i + 1,
      });
    }
    if (g.status == GroupStatus.recruiting) {
      batch.update(_db.doc('groups/${g.id}'), {
        'status': 'drawing',
        'drawnCount': g.memberCount,
      });
    }
    final (eventRef, eventData) = _eventDoc(
      g.id,
      me,
      'order_set',
      'Ordre des remises fixé : ${[for (final m in ordered) m.name].join(', ')}',
    );
    batch.set(eventRef, eventData);
    await batch.commit();
  }

  /// Démarrage : dates de la 1re cotisation et de la 1re remise figées.
  static Future<void> startGroup(
    Group g,
    DateTime start,
    DateTime firstPayout,
    String summary,
  ) async {
    final me = await _requireMe();
    final (eventRef, eventData) = _eventDoc(
      g.id,
      me,
      'started',
      'Tontine démarrée : $summary',
    );
    await (_db.batch()
          ..update(_db.doc('groups/${g.id}'), {
            'status': 'active',
            'startDate': dateKey(start),
            'firstPayoutDate': dateKey(firstPayout),
            'startedAt': _now,
            'levels': {'0': g.memberCount},
          })
          ..set(eventRef, eventData))
        .commit();
    for (final id in g.memberIds) {
      await _notify(
        to: id,
        type: 'started',
        title: 'Tontine démarrée',
        body:
            '« ${g.name} » a démarré : $summary. Vous pouvez payer vos '
            'cotisations.',
        groupId: g.id,
      );
    }
  }

  /// Le participant déclare [count] cotisations, payées par Mobile Money
  /// (capture) ou en espèces. Les pénalités de retard sont ajoutées.
  static Future<void> declareContributions({
    required Group group,
    required int count,
    required PaymentMethod method,
    Uint8List? proof,
    String? mime,
    String? note,
  }) async {
    final me = await _requireMe();
    final memberRef = _db.doc('groups/${group.id}/members/$uid');
    var declared = 0;
    await _db.runTransaction((tx) async {
      final member = GroupMember.fromDoc(await tx.get(memberRef));
      final remaining = group.totalContributions - member.declaredCount;
      if (count > remaining) {
        throw AppException(
          remaining == 0
              ? 'Vous avez déjà déclaré toutes vos cotisations'
              : 'Il ne vous reste que $remaining cotisation(s) à payer',
        );
      }
      final penalty = group.penaltyFor(
        member.declaredCount + 1,
        count,
        DateTime.now(),
      );
      String? proofId;
      if (method == PaymentMethod.mobileMoney) {
        final proofRef = _db.collection('proofs').doc();
        tx.set(
          proofRef,
          _proofData(proof!, mime!, 'group', group.id, group.ownerId),
        );
        proofId = proofRef.id;
      }
      final amount = count * group.contributionAmount + penalty;
      declared = amount;
      final payRef = _db.collection('groups/${group.id}/payments').doc();
      tx.set(payRef, {
        'userId': uid,
        'payerName': me.fullName,
        'payerPhone': me.phone,
        'count': count,
        'amount': amount,
        'penalty': penalty,
        'method': _methodKey(method),
        'note': _cleanNote(note),
        'proofId': proofId,
        'status': 'pending',
        'rejectionReason': null,
        'declaredAt': _now,
        'reviewedAt': null,
        'recordedBy': 'member',
      });
      tx.update(memberRef, {
        'declaredCount': member.declaredCount + count,
        'lastPaymentId': payRef.id,
      });
      final (eventRef, eventData) = _eventDoc(
        group.id,
        me,
        'payment_declared',
        'Paiement déclaré : ${contributionsLabel(count)}, ${money(amount)} '
            '(${method == PaymentMethod.cash ? 'espèces' : 'Mobile Money'})',
        memberId: uid,
      );
      tx.set(eventRef, eventData);
    });
    await _notify(
      to: group.ownerId,
      type: 'payment_declared',
      title: 'Paiement à valider',
      body:
          '${me.fullName} · ${group.name} : ${contributionsLabel(count)}, '
          '${money(declared)} '
          '(${method == PaymentMethod.cash ? 'espèces' : 'Mobile Money'}).',
      groupId: group.id,
    );
  }

  static String _methodKey(PaymentMethod m) =>
      m == PaymentMethod.cash ? 'cash' : 'mobile_money';

  /// Niveaux du groupe quand un participant passe de [from] à [to]
  /// cotisations validées (null : rien à changer). Le niveau est le nombre
  /// de cagnottes qu'il a entièrement payées ; le serveur s'en sert pour
  /// refuser une remise avant la fin de la collecte.
  static Json? _levelsPatch(Json group, String memberId, int from, int to) {
    final raw = group['levels'];
    if (raw is! Map) return null;
    final perPot = (group['contributionsPerPot'] as num).toInt();
    final a = '${from ~/ perPot}';
    final b = '${to ~/ perPot}';
    if (a == b) return null;
    final levels = {
      for (final e in raw.entries) e.key as String: (e.value as num).toInt(),
    };
    levels[a] = (levels[a] ?? 0) - 1;
    if (levels[a]! <= 0) levels.remove(a);
    levels[b] = (levels[b] ?? 0) + 1;
    return {'levels': levels, 'levelsMember': memberId};
  }

  static String? _cleanNote(String? note) {
    final n = note?.trim() ?? '';
    return n.isEmpty ? null : (n.length > 200 ? n.substring(0, 200) : n);
  }

  /// Validation : les cotisations (et pénalités) comptent comme payées ;
  /// refus : elles redeviennent à payer.
  static Future<void> reviewContributions(
    String groupId,
    Payment p,
    bool approve,
    String? reason,
  ) async {
    final me = await _requireMe();
    final memberRef = _db.doc('groups/$groupId/members/${p.userId}');
    final groupRef = _db.doc('groups/$groupId');
    var groupName = '';
    await _db.runTransaction((tx) async {
      final group = (await tx.get(groupRef)).data()!;
      groupName = group['name'] as String? ?? '';
      final member = GroupMember.fromDoc(await tx.get(memberRef));
      final levels = approve
          ? _levelsPatch(
              group,
              p.userId,
              member.approvedCount,
              member.approvedCount + p.count,
            )
          : null;
      if (levels != null) tx.update(groupRef, levels);
      tx
        ..update(
          _db.doc('groups/$groupId/payments/${p.id}'),
          _review(approve, reason),
        )
        ..update(
          memberRef,
          approve
              ? {
                  'approvedCount': member.approvedCount + p.count,
                  'penaltyPaid': member.penaltyPaid + p.penalty,
                }
              : {'declaredCount': member.declaredCount - p.count},
        );
      final (eventRef, eventData) = _eventDoc(
        groupId,
        me,
        approve ? 'payment_approved' : 'payment_rejected',
        approve
            ? 'Paiement de ${p.payer.fullName} validé : ${money(p.amount)}'
            : 'Paiement de ${p.payer.fullName} refusé : ${reason ?? ''}',
        memberId: p.userId,
      );
      tx.set(eventRef, eventData);
    });
    await _notify(
      to: p.userId,
      type: approve ? 'payment_approved' : 'payment_rejected',
      title: approve ? 'Paiement validé' : 'Paiement refusé',
      body: approve
          ? '$groupName : votre paiement de ${money(p.amount)} est validé.'
          : '$groupName : votre paiement de ${money(p.amount)} est refusé '
                '(${reason ?? ''}). Les cotisations sont à repayer.',
      groupId: groupId,
    );
  }

  /// Le tontinier encaisse lui-même un paiement (validé d'office).
  static Future<Payment> recordPayment({
    required Group group,
    required GroupMember member,
    required int count,
    required PaymentMethod method,
    required int penalty,
    String? note,
  }) async {
    final me = await _requireMe();
    final memberRef = _db.doc('groups/${group.id}/members/${member.userId}');
    final payRef = _db.collection('groups/${group.id}/payments').doc();
    final amount = count * group.contributionAmount + penalty;
    final groupRef = _db.doc('groups/${group.id}');
    await _db.runTransaction((tx) async {
      final groupData = (await tx.get(groupRef)).data()!;
      final fresh = GroupMember.fromDoc(await tx.get(memberRef));
      if (count > group.totalContributions - fresh.declaredCount) {
        throw const AppException('Plus que les cotisations restantes');
      }
      final levels = _levelsPatch(
        groupData,
        member.userId,
        fresh.approvedCount,
        fresh.approvedCount + count,
      );
      if (levels != null) tx.update(groupRef, levels);
      tx
        ..set(payRef, {
          'userId': member.userId,
          'payerName': fresh.name,
          'payerPhone': fresh.profile.phone,
          'count': count,
          'amount': amount,
          'penalty': penalty,
          'method': _methodKey(method),
          'note': _cleanNote(note),
          'proofId': null,
          'status': 'approved',
          'rejectionReason': null,
          'declaredAt': _now,
          'reviewedAt': _now,
          'recordedBy': 'owner',
        })
        ..update(memberRef, {
          'declaredCount': fresh.declaredCount + count,
          'approvedCount': fresh.approvedCount + count,
          'penaltyPaid': fresh.penaltyPaid + penalty,
        });
      final (eventRef, eventData) = _eventDoc(
        group.id,
        me,
        'payment_recorded',
        'Encaissé par le tontinier : ${fresh.name}, '
            '${contributionsLabel(count)}, ${money(amount)} '
            '(${method == PaymentMethod.cash ? 'espèces' : 'Mobile Money'})',
        memberId: member.userId,
      );
      tx.set(eventRef, eventData);
    });
    await _notify(
      to: member.userId,
      type: 'payment_recorded',
      title: 'Paiement encaissé',
      body:
          '${group.name} : le tontinier a encaissé ${contributionsLabel(count)} '
          '(${money(amount)}) pour vous.',
      groupId: group.id,
    );
    return Payment.fromDoc(await payRef.get());
  }

  /// Remises déjà confirmées, par numéro de cagnotte.
  static Future<Map<int, Payout>> payouts(String groupId) async {
    final snap = await _db.collection('groups/$groupId/payouts').get();
    return {
      for (final d in snap.docs) Payout.fromDoc(d).pot: Payout.fromDoc(d),
    };
  }

  /// Le tontinier confirme avoir remis la cagnotte en cours.
  /// La remise n'est possible que lorsque la collecte est complète (le
  /// serveur le vérifie aussi).
  static Future<void> confirmPayout(Group g, PaymentMethod method) async {
    final me = await _requireMe();
    final pot = g.paidOutCount + 1;
    final beneficiary = g.beneficiaryOf(pot);
    if (beneficiary == null) {
      throw const AppException('Bénéficiaire introuvable');
    }
    if (!g.isPotComplete(pot)) {
      throw AppException(
        'La collecte n\'est pas complète : il manque ${money(g.missingFor(pot))}.',
      );
    }
    final (eventRef, eventData) = _eventDoc(
      g.id,
      me,
      'payout_confirmed',
      'Cagnotte n°$pot remise à ${beneficiary.name} : ${money(g.netPot)} '
          '(${method == PaymentMethod.cash ? 'espèces' : 'Mobile Money'})',
    );
    await (_db.batch()
          ..set(_db.doc('groups/${g.id}/payouts/$pot'), {
            'tour': pot,
            'beneficiaryId': beneficiary.userId,
            'beneficiaryName': beneficiary.name,
            'amount': g.netPot,
            'method': _methodKey(method),
            'paidAt': _now,
            'receivedAt': null,
            'problem': null,
          })
          ..update(_db.doc('groups/${g.id}'), {'paidOutCount': pot})
          ..set(eventRef, eventData))
        .commit();
    await _notify(
      to: beneficiary.userId,
      type: 'payout_confirmed',
      title: 'Cagnotte remise',
      body:
          '${g.name} : le tontinier indique vous avoir remis '
          '${money(g.netPot)}. Confirmez la réception.',
      groupId: g.id,
    );
  }

  /// Le bénéficiaire confirme avoir reçu la cagnotte, ou signale un
  /// problème ([problem]).
  static Future<void> answerPayout(
    String groupId,
    Payout p, {
    String? problem,
  }) async {
    final me = await _requireMe();
    final (eventRef, eventData) = _eventDoc(
      groupId,
      me,
      problem == null ? 'payout_received' : 'payout_problem',
      problem == null
          ? '${me.fullName} confirme avoir reçu la cagnotte n°${p.pot}'
          : '${me.fullName} signale un problème sur la cagnotte n°${p.pot} : '
                '$problem',
    );
    await (_db.batch()
          ..update(_db.doc('groups/$groupId/payouts/${p.pot}'), {
            'receivedAt': problem == null ? _now : null,
            'problem': problem?.trim(),
          })
          ..set(eventRef, eventData))
        .commit();
    final group = (await _db.doc('groups/$groupId').get()).data();
    await _notify(
      to: group?['ownerId'] as String?,
      type: problem == null ? 'payout_received' : 'payout_problem',
      title: problem == null ? 'Cagnotte reçue' : 'Problème sur une remise',
      body: problem == null
          ? '${me.fullName} confirme avoir reçu la cagnotte n°${p.pot} '
                '(${group?['name'] ?? ''}).'
          : '${me.fullName} signale un problème sur la cagnotte n°${p.pot} : '
                '$problem',
      groupId: groupId,
    );
  }

  static Json _review(bool approve, String? reason) => {
    'status': approve ? 'approved' : 'rejected',
    'rejectionReason': approve ? null : reason!.trim(),
    'reviewedAt': _now,
  };

  // --------------------------------------------------- Tontine à carnet

  static Future<List<Carnet>> carnetsOf(String tontineId) async {
    final snap = await _db
        .collection('carnets')
        .where('ownerId', isEqualTo: uid)
        .where('tontineId', isEqualTo: tontineId)
        .get();
    return snap.docs.map(Carnet.fromDoc).toList()
      ..sort((a, b) => a.label.compareTo(b.label));
  }

  static Future<List<Carnet>> myCarnets() async {
    final snap = await _db
        .collection('carnets')
        .where('clientId', isEqualTo: uid)
        .get();
    return snap.docs.map(Carnet.fromDoc).toList();
  }

  static Future<Carnet> carnet(String id) async =>
      Carnet.fromDoc(await _db.doc('carnets/$id').get());

  static Future<String> createCarnet({
    required Tontine tontine,
    required String label,
    required int caseAmount,
  }) async {
    await ensureCanCreate();
    final me = await _requireMe();
    return _createWithInvite(
      'carnets',
      'carnet',
      (code) => {
        'tontineId': tontine.id,
        'tontineName': tontine.name,
        'ownerId': uid,
        'ownerName': me.fullName,
        'label': label.trim(),
        'caseAmount': caseAmount,
        'caseCount': 31,
        'clientId': null,
        'clientName': null,
        'clientPhone': null,
        'inviteCode': code,
        'usedCases': 0,
        'approvedCases': 0,
        'lastPaymentId': null,
        'createdAt': _now,
      },
    );
  }

  static Future<List<Payment>> carnetPayments(Carnet c) async {
    Query<Json> query = _db.collection('carnets/${c.id}/payments');
    if (c.ownerId != uid) query = query.where('userId', isEqualTo: uid);
    final snap = await query.get();
    return snap.docs.map(Payment.fromDoc).toList()
      ..sort((a, b) => b.declaredAt.compareTo(a.declaredAt));
  }

  static Future<void> declareCarnetPayment({
    required Carnet carnet,
    required int caseCount,
    required PaymentMethod method,
    Uint8List? proof,
    String? mime,
    String? note,
  }) async {
    final me = await _requireMe();
    final carnetRef = _db.doc('carnets/${carnet.id}');
    await _db.runTransaction((tx) async {
      final fresh = Carnet.fromDoc(await tx.get(carnetRef));
      if (caseCount > fresh.remainingCases) {
        throw AppException(
          'Il ne reste que ${fresh.remainingCases} case(s) à payer sur ce carnet',
        );
      }
      String? proofId;
      if (method == PaymentMethod.mobileMoney) {
        final proofRef = _db.collection('proofs').doc();
        tx.set(
          proofRef,
          _proofData(proof!, mime!, 'carnet', carnet.id, carnet.ownerId),
        );
        proofId = proofRef.id;
      }
      final payRef = carnetRef.collection('payments').doc();
      tx
        ..set(payRef, {
          'userId': uid,
          'payerName': me.fullName,
          'payerPhone': me.phone,
          'caseCount': caseCount,
          'amount': caseCount * fresh.caseAmount,
          'method': _methodKey(method),
          'note': _cleanNote(note),
          'proofId': proofId,
          'status': 'pending',
          'rejectionReason': null,
          'declaredAt': _now,
          'reviewedAt': null,
          'recordedBy': 'member',
        })
        ..update(carnetRef, {
          'usedCases': fresh.usedCases + caseCount,
          'lastPaymentId': payRef.id,
        });
    });
    await _notify(
      to: carnet.ownerId,
      type: 'payment_declared',
      title: 'Paiement à valider',
      body:
          '${me.fullName} · ${carnet.label} : $caseCount case(s), '
          '${money(caseCount * carnet.caseAmount)} '
          '(${method == PaymentMethod.cash ? 'espèces' : 'Mobile Money'}).',
      carnetId: carnet.id,
    );
  }

  /// Le tontinier encaisse lui-même des cases (validées d'office).
  static Future<Payment> recordCarnetPayment({
    required Carnet carnet,
    required int caseCount,
    required PaymentMethod method,
    String? note,
  }) async {
    final carnetRef = _db.doc('carnets/${carnet.id}');
    final payRef = carnetRef.collection('payments').doc();
    await _db.runTransaction((tx) async {
      final fresh = Carnet.fromDoc(await tx.get(carnetRef));
      if (caseCount > fresh.remainingCases) {
        throw AppException(
          'Il ne reste que ${fresh.remainingCases} case(s) à payer sur ce carnet',
        );
      }
      tx
        ..set(payRef, {
          'userId': fresh.clientId,
          'payerName': fresh.client?.fullName,
          'payerPhone': fresh.client?.phone,
          'caseCount': caseCount,
          'amount': caseCount * fresh.caseAmount,
          'method': _methodKey(method),
          'note': _cleanNote(note),
          'proofId': null,
          'status': 'approved',
          'rejectionReason': null,
          'declaredAt': _now,
          'reviewedAt': _now,
          'recordedBy': 'owner',
        })
        ..update(carnetRef, {
          'usedCases': fresh.usedCases + caseCount,
          'approvedCases': fresh.approvedCases + caseCount,
        });
    });
    await _notify(
      to: carnet.clientId,
      type: 'payment_recorded',
      title: 'Paiement encaissé',
      body:
          '${carnet.label} : le tontinier a encaissé $caseCount case(s) '
          '(${money(caseCount * carnet.caseAmount)}) pour vous.',
      carnetId: carnet.id,
    );
    return Payment.fromDoc(await payRef.get());
  }

  /// Validation : les cases deviennent payées ; refus : elles sont libérées.
  static Future<void> reviewCarnetPayment(
    String carnetId,
    Payment p,
    bool approve,
    String? reason,
  ) async {
    final carnetRef = _db.doc('carnets/$carnetId');
    var label = '';
    await _db.runTransaction((tx) async {
      final fresh = Carnet.fromDoc(await tx.get(carnetRef));
      label = fresh.label;
      tx.update(
        carnetRef.collection('payments').doc(p.id),
        _review(approve, reason),
      );
      tx.update(
        carnetRef,
        approve
            ? {'approvedCases': fresh.approvedCases + p.caseCount}
            : {'usedCases': fresh.usedCases - p.caseCount},
      );
    });
    await _notify(
      to: p.userId,
      type: approve ? 'payment_approved' : 'payment_rejected',
      title: approve ? 'Paiement validé' : 'Paiement refusé',
      body: approve
          ? '$label : votre paiement de ${money(p.amount)} est validé.'
          : '$label : votre paiement de ${money(p.amount)} est refusé '
                '(${reason ?? ''}).',
      carnetId: carnetId,
    );
  }

  // ---------------------------------------------------- Profil pro

  static final _businesses = <String, Business?>{};

  /// Profil pro d'un tontinier (null s'il ne l'a pas rempli).
  static Future<Business?> business(String ownerId) async {
    if (_businesses.containsKey(ownerId)) return _businesses[ownerId];
    try {
      final doc = await _db.doc('businesses/$ownerId').get();
      return _businesses[ownerId] = doc.exists ? Business.fromDoc(doc) : null;
    } on FirebaseException {
      return null;
    }
  }

  static Future<void> saveBusiness(Business b) async {
    await _db.doc('businesses/$uid').set({
      'name': b.name.trim(),
      'city': b.city.trim(),
      'contactPhone': b.contactPhone.trim(),
      'logo': b.logo,
      'logoMime': b.logoMime,
      'accounts': [
        for (final a in b.accounts)
          if (a.number.trim().isNotEmpty) a.toJson(),
      ],
      'updatedAt': _now,
    });
    _businesses.remove(uid);
  }

  /// Logo choisi dans la galerie (déjà réduit) : base64 et type.
  static Future<(String, String)> readLogo(XFile file) async {
    final (bytes, mime) = await readProof(file);
    final data = base64.encode(bytes);
    if (data.length > 200000) {
      throw const AppException(
        'Logo trop lourd. Choisissez une image plus petite.',
      );
    }
    return (data, mime);
  }

  // ---------------------------------------------------- Gains du tontinier

  /// Tableau de bord des gains : encaissements du mois, commissions,
  /// pénalités, retards et prochaines remises.
  static Future<Gains> gains() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final today = DateTime(now.year, now.month, now.day);
    final results = await Future.wait([
      _db.collection('groups').where('ownerId', isEqualTo: uid).get(),
      _db.collection('carnets').where('ownerId', isEqualTo: uid).get(),
    ]);
    final groupDocs = results[0].docs
        .map(Group.fromDoc)
        .where((g) => !g.isLegacy && g.isStarted)
        .toList();
    final carnets = results[1].docs.map(Carnet.fromDoc).toList();
    final groups = await Future.wait(groupDocs.map((g) => group(g.id)));

    Future<int> collected(String path) async {
      final snap = await _db
          .collection(path)
          .where('status', isEqualTo: 'approved')
          .get();
      return snap.docs
          .map(Payment.fromDoc)
          .where((p) {
            final at = p.reviewedAt ?? p.declaredAt;
            return !at.isBefore(monthStart);
          })
          .fold<int>(0, (n, p) => n + p.amount);
    }

    final sums = await Future.wait([
      for (final g in groups) collected('groups/${g.id}/payments'),
      for (final c in carnets.where((c) => c.clientId != null))
        collected('carnets/${c.id}/payments'),
    ]);

    var earned = 0;
    var upcoming = 0;
    var penalties = 0;
    var lateAmount = 0;
    var lateMembers = 0;
    final payouts = <(Group, int, DateTime)>[];
    for (final g in groups) {
      earned += g.paidOutCount * g.commission;
      upcoming += (g.memberCount - g.paidOutCount) * g.commission;
      for (final m in g.members) {
        penalties += m.penaltyPaid;
        final s = g.standingOf(m, now);
        if (s.late > 0 && g.status == GroupStatus.active) {
          lateMembers++;
          lateAmount += s.late * g.contributionAmount + s.penaltyDue;
        }
      }
      if (g.status == GroupStatus.active) {
        final pot = g.currentPot;
        final date = g.payoutDate(pot);
        if (!date.isAfter(today.add(const Duration(days: 7)))) {
          payouts.add((g, pot, date));
        }
      }
    }
    for (final c in carnets) {
      if (c.isComplete) {
        earned += c.caseAmount;
      } else if (c.clientId != null) {
        upcoming += c.caseAmount;
      }
    }
    payouts.sort((a, b) => a.$3.compareTo(b.$3));
    return Gains(
      collectedThisMonth: sums.fold(0, (n, s) => n + s),
      commissionsEarned: earned,
      commissionsUpcoming: upcoming,
      penaltiesCollected: penalties,
      lateAmount: lateAmount,
      lateMembers: lateMembers,
      upcomingPayouts: payouts,
      activeGroups: groups.where((g) => g.status == GroupStatus.active).length,
      activeCarnets: carnets
          .where((c) => c.clientId != null && !c.isComplete)
          .length,
    );
  }

  // ------------------------------------------------------ Preuves (images)

  /// Taille maximale d'une capture encodée (limite d'un document Firestore).
  static const _maxProofChars = 900000;

  /// Lit la capture choisie ; image_picker l'a déjà réduite et compressée.
  static Future<(Uint8List, String)> readProof(XFile file) async {
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final mime = name.endsWith('.png')
        ? 'image/png'
        : name.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    if (base64.encode(bytes).length > _maxProofChars) {
      throw const AppException(
        'Image trop lourde. Choisissez une capture d\'écran plus petite.',
      );
    }
    return (bytes, mime);
  }

  static Json _proofData(
    Uint8List bytes,
    String mime,
    String kind,
    String targetId,
    String reviewerId,
  ) => {
    'ownerId': uid,
    'reviewerId': reviewerId,
    'kind': kind,
    'targetId': targetId,
    'data': base64.encode(bytes),
    'mime': mime,
    'createdAt': _now,
  };

  static Future<Uint8List> proofImage(String proofId) async {
    final doc = await _db.doc('proofs/$proofId').get();
    return base64.decode(doc['data'] as String);
  }
}
