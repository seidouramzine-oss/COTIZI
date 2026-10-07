import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

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
      });

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
    final groups = (results[1] as QuerySnapshot<Json>).docs
        .map(Group.fromDoc)
        .toList();
    final carnets = (results[2] as QuerySnapshot<Json>).docs
        .map(Carnet.fromDoc)
        .toList();
    final pending = await Future.wait([
      for (final g in groups.where((g) => g.status == GroupStatus.active))
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
        final (due, next) = detail.status == GroupStatus.active
            ? detail.unpaidTours(uid, payments, today)
            : (const <int>[], null);
        return MemberGroupStatus(
          group: detail,
          payments: payments,
          dueTours: due,
          nextTour: next,
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
  /// tiré existe déjà (refus des règles).
  static Future<String> _createWithInvite(
    String collection,
    String kind,
    Json Function(String code) data,
  ) async {
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
      try {
        await batch.commit();
        return ref.id;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied' || attempt >= 4) rethrow;
      }
    }
  }

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
      final batch = _db.batch()
        ..update(ref, {
          'joinedCount': FieldValue.increment(1),
          'memberIds': FieldValue.arrayUnion([uid]),
        })
        ..set(ref.collection('members').doc(uid), {
          'fullName': me.fullName,
          'phone': me.phone,
          'joinedAt': _now,
          'drawPosition': null,
        });
      try {
        await batch.commit();
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          throw const AppException(
            'Ce groupe est complet ou le tirage au sort a déjà commencé',
          );
        }
        rethrow;
      }
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

  static Future<Group> group(String id) async {
    final results = await Future.wait([
      _db.doc('groups/$id').get(),
      _db.collection('groups/$id/members').get(),
    ]);
    final members =
        (results[1] as QuerySnapshot<Json>).docs
            .map(GroupMember.fromDoc)
            .toList()
          ..sort(
            (a, b) => (a.drawPosition ?? 1 << 30).compareTo(
              b.drawPosition ?? 1 << 30,
            ),
          );
    return Group.fromDoc(results[0] as DocumentSnapshot<Json>)
        .copyWith(members: members);
  }

  static Future<String> createGroup({
    required Tontine tontine,
    required String name,
    required int memberCount,
    required int contributionAmount,
    required Frequency frequency,
    required DateTime startDate,
    required CommissionType commissionType,
    required double commissionValue,
  }) async {
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
        'name': name.trim(),
        'memberCount': memberCount,
        'contributionAmount': contributionAmount,
        'frequency': frequency.name,
        'startDate': dateKey(startDate),
        'commissionType': commissionType.name,
        'commissionValue': commissionValue,
        'inviteCode': code,
        'status': 'recruiting',
        'joinedCount': 0,
        'drawnCount': 0,
        'memberIds': <String>[],
        'createdAt': _now,
      },
    );
  }

  /// Le tontinier voit tous les paiements ; un membre seulement les siens.
  static Future<List<Payment>> groupPayments(Group g) async {
    Query<Json> query = _db.collection('groups/${g.id}/payments');
    if (g.ownerId != uid) query = query.where('userId', isEqualTo: uid);
    final snap = await query.get();
    return snap.docs.map(Payment.fromDoc).toList()
      ..sort((a, b) => b.declaredAt.compareTo(a.declaredAt));
  }

  /// Lance le tirage : l'ordre de passage est tiré au hasard ici, puis
  /// chaque membre découvre son numéro en « tirant ».
  static Future<void> startDraw(Group g) async {
    final positions = List.generate(g.memberCount, (i) => i + 1)
      ..shuffle(Random.secure());
    final members = await _db.collection('groups/${g.id}/members').get();
    if (members.docs.length != g.memberCount) {
      throw AppException(
        'Le groupe n\'est pas encore complet (${members.docs.length} / ${g.memberCount})',
      );
    }
    final batch = _db.batch()
      ..update(_db.doc('groups/${g.id}'), {'status': 'drawing'});
    for (var i = 0; i < members.docs.length; i++) {
      batch.set(_db.doc('groups/${g.id}/draws/${members.docs[i].id}'), {
        'position': positions[i],
      });
    }
    await batch.commit();
  }

  /// Un membre découvre son numéro.
  static Future<int> drawLot(String groupId) {
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
      tx.update(member.reference, {'drawPosition': position});
      tx.update(group.reference, {
        'drawnCount': (group['drawnCount'] as num).toInt() + 1,
      });
      return position;
    });
  }

  /// Le tontinier révèle les numéros des membres qui n'ont pas tiré.
  /// L'état est relu ici : des membres ont pu tirer depuis l'affichage.
  static Future<void> finishDraw(Group g) async {
    final members = await _db.collection('groups/${g.id}/members').get();
    final batch = _db.batch();
    for (final m in members.docs.where((d) => d['drawPosition'] == null)) {
      final draw = await _db.doc('groups/${g.id}/draws/${m.id}').get();
      batch.update(m.reference, {'drawPosition': draw['position']});
    }
    batch.update(_db.doc('groups/${g.id}'), {'drawnCount': g.memberCount});
    await batch.commit();
  }

  static Future<void> declarePayment({
    required Group group,
    required int tourNumber,
    required Uint8List proof,
    required String mime,
    required bool afterRejection,
  }) async {
    final me = await _requireMe();
    final batch = _db.batch();
    final proofId = _addProof(
      batch,
      proof,
      mime,
      'group',
      group.id,
      group.ownerId,
    );
    final ref = _db.doc('groups/${group.id}/payments/${uid}_$tourNumber');
    if (afterRejection) {
      batch.update(ref, {
        'proofId': proofId,
        'status': 'pending',
        'rejectionReason': null,
        'declaredAt': _now,
        'reviewedAt': null,
      });
    } else {
      batch.set(ref, {
        'userId': uid,
        'payerName': me.fullName,
        'payerPhone': me.phone,
        'tourNumber': tourNumber,
        'amount': group.contributionAmount,
        'proofId': proofId,
        'status': 'pending',
        'rejectionReason': null,
        'declaredAt': _now,
        'reviewedAt': null,
      });
    }
    await batch.commit();
  }

  static Future<void> reviewPayment(
    String groupId,
    String paymentId,
    bool approve,
    String? reason,
  ) {
    return _db
        .doc('groups/$groupId/payments/$paymentId')
        .update(_review(approve, reason));
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
    required Uint8List proof,
    required String mime,
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
      final proofRef = _db.collection('proofs').doc();
      tx.set(
        proofRef,
        _proofData(proof, mime, 'carnet', carnet.id, carnet.ownerId),
      );
      final payRef = carnetRef.collection('payments').doc();
      tx.set(payRef, {
        'userId': uid,
        'payerName': me.fullName,
        'payerPhone': me.phone,
        'caseCount': caseCount,
        'amount': caseCount * fresh.caseAmount,
        'proofId': proofRef.id,
        'status': 'pending',
        'rejectionReason': null,
        'declaredAt': _now,
        'reviewedAt': null,
      });
      tx.update(carnetRef, {
        'usedCases': fresh.usedCases + caseCount,
        'lastPaymentId': payRef.id,
      });
    });
  }

  /// Validation : les cases deviennent payées ; refus : elles sont libérées.
  static Future<void> reviewCarnetPayment(
    String carnetId,
    Payment p,
    bool approve,
    String? reason,
  ) {
    final carnetRef = _db.doc('carnets/$carnetId');
    return _db.runTransaction((tx) async {
      final fresh = Carnet.fromDoc(await tx.get(carnetRef));
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

  static String _addProof(
    WriteBatch batch,
    Uint8List bytes,
    String mime,
    String kind,
    String targetId,
    String reviewerId,
  ) {
    final ref = _db.collection('proofs').doc();
    batch.set(ref, _proofData(bytes, mime, kind, targetId, reviewerId));
    return ref.id;
  }

  static Future<Uint8List> proofImage(String proofId) async {
    final doc = await _db.doc('proofs/$proofId').get();
    return base64.decode(doc['data'] as String);
  }
}
