import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'models.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

DateTime? _timeOrNull(Object? v) => v is Timestamp ? v.toDate() : null;

DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

bool _inMonth(DateTime d, DateTime month) =>
    d.year == month.year && d.month == month.month;

// ============================================================== Dépenses

/// Dépense du tontinier (transport, crédit téléphone…), notée dans sa
/// comptabilité.
class Expense {
  const Expense({
    required this.id,
    required this.label,
    required this.amount,
    required this.category,
    required this.date,
  });

  final String id;
  final String label;
  final int amount;
  final String category;
  final DateTime date;

  static const categories = {
    'transport': 'Transport',
    'communication': 'Crédit et internet',
    'materiel': 'Carnets et matériel',
    'personnel': 'Aide et personnel',
    'autre': 'Autre',
  };

  String get categoryLabel => categories[category] ?? 'Autre';

  factory Expense.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Expense(
      id: doc.id,
      label: json['label'] as String? ?? '',
      amount: _int(json['amount']),
      category: json['category'] as String? ?? 'autre',
      date: _timeOrNull(json['date']) ?? DateTime.now(),
    );
  }
}

// =========================================================== Comptabilité

/// Une ligne du journal : entrée (+) ou sortie (−) d'argent.
class LedgerLine {
  const LedgerLine({
    required this.date,
    required this.label,
    required this.detail,
    required this.amount,
    required this.kind,
    this.expenseId,
  });

  /// Dépense (supprimable) : son identifiant.
  final String? expenseId;

  final DateTime date;
  final String label;
  final String detail;

  /// Positif : argent reçu ; négatif : argent sorti.
  final int amount;

  /// cotisation, remise, carnet, depense
  final String kind;
}

/// Toutes les opérations du tontinier, chargées une fois pour la
/// comptabilité et les statistiques.
class ProData {
  ProData({
    required this.groups,
    required this.groupPayments,
    required this.payouts,
    required this.carnets,
    required this.carnetPayments,
    required this.expenses,
  });

  final List<Group> groups;
  final Map<String, List<Payment>> groupPayments;
  final Map<String, List<Payout>> payouts;
  final List<Carnet> carnets;
  final Map<String, List<Payment>> carnetPayments;
  final List<Expense> expenses;

  static DateTime paidOn(Payment p) => p.reviewedAt ?? p.declaredAt;

  /// Commission gagnée sur un carnet clôturé (la case gardée).
  static int carnetCommission(Carnet c) =>
      c.isClosed && c.approvedCases >= 1 ? c.caseAmount : 0;

  /// Mois où il y a eu au moins une opération (le plus récent d'abord).
  List<DateTime> get months {
    final set = <DateTime>{_monthOf(DateTime.now())};
    for (final l in groupPayments.values.expand((l) => l)) {
      set.add(_monthOf(paidOn(l)));
    }
    for (final l in carnetPayments.values.expand((l) => l)) {
      set.add(_monthOf(paidOn(l)));
    }
    for (final p in payouts.values.expand((l) => l)) {
      set.add(_monthOf(p.paidAt));
    }
    for (final e in expenses) {
      set.add(_monthOf(e.date));
    }
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  Accounting month(DateTime month) => Accounting.of(this, _monthOf(month));
}

/// Comptabilité d'un mois.
class Accounting {
  const Accounting({
    required this.month,
    required this.received,
    required this.penalties,
    required this.paidOut,
    required this.carnetsPaid,
    required this.expenses,
    required this.commissions,
    required this.lines,
  });

  final DateTime month;

  /// Cotisations et cases reçues (pénalités comprises).
  final int received;

  /// Pénalités de retard comprises dans [received].
  final int penalties;

  /// Cagnottes remises aux bénéficiaires.
  final int paidOut;

  /// Carnets remis ou remboursés aux clients.
  final int carnetsPaid;

  /// Dépenses notées par le tontinier.
  final int expenses;

  /// Commissions gagnées (remises faites et carnets clôturés).
  final int commissions;

  final List<LedgerLine> lines;

  /// Argent entré moins argent sorti dans le mois.
  int get balance => received - paidOut - carnetsPaid - expenses;

  /// Ce que le tontinier a gagné : commissions et pénalités, moins ses
  /// dépenses.
  int get profit => commissions + penalties - expenses;

  factory Accounting.of(ProData d, DateTime month) {
    final lines = <LedgerLine>[];
    var received = 0;
    var penalties = 0;
    var paidOut = 0;
    var carnetsPaid = 0;
    var expenses = 0;
    var commissions = 0;
    for (final g in d.groups) {
      for (final p in d.groupPayments[g.id] ?? const <Payment>[]) {
        final at = ProData.paidOn(p);
        if (!_inMonth(at, month)) continue;
        received += p.amount;
        penalties += p.penalty;
        lines.add(
          LedgerLine(
            date: at,
            label: p.payer.fullName,
            detail: p.penalty > 0
                ? '${g.name} · dont pénalité ${p.penalty} F'
                : g.name,
            amount: p.amount,
            kind: 'cotisation',
          ),
        );
      }
      for (final o in d.payouts[g.id] ?? const <Payout>[]) {
        if (!_inMonth(o.paidAt, month)) continue;
        paidOut += o.amount;
        commissions += g.commission;
        lines.add(
          LedgerLine(
            date: o.paidAt,
            label: 'Remise à ${o.beneficiaryName}',
            detail: '${g.name} · cagnotte n°${o.pot}',
            amount: -o.amount,
            kind: 'remise',
          ),
        );
      }
    }
    for (final c in d.carnets) {
      final client = c.client?.fullName ?? c.label;
      for (final p in d.carnetPayments[c.id] ?? const <Payment>[]) {
        final at = ProData.paidOn(p);
        if (!_inMonth(at, month)) continue;
        received += p.amount;
        lines.add(
          LedgerLine(
            date: at,
            label: client,
            detail: '${c.label} · ${p.caseCount} case(s)',
            amount: p.amount,
            kind: 'cotisation',
          ),
        );
      }
      final closed = c.closedAt;
      if (c.isClosed && closed != null && _inMonth(closed, month)) {
        carnetsPaid += c.refundAmount;
        commissions += ProData.carnetCommission(c);
        lines.add(
          LedgerLine(
            date: closed,
            label: 'Carnet remis à $client',
            detail: c.label,
            amount: -c.refundAmount,
            kind: 'carnet',
          ),
        );
      }
    }
    for (final e in d.expenses) {
      if (!_inMonth(e.date, month)) continue;
      expenses += e.amount;
      lines.add(
        LedgerLine(
          date: e.date,
          label: e.label,
          detail: 'Dépense · ${e.categoryLabel}',
          amount: -e.amount,
          kind: 'depense',
          expenseId: e.id,
        ),
      );
    }
    lines.sort((a, b) => b.date.compareTo(a.date));
    return Accounting(
      month: month,
      received: received,
      penalties: penalties,
      paidOut: paidOut,
      carnetsPaid: carnetsPaid,
      expenses: expenses,
      commissions: commissions,
      lines: lines,
    );
  }
}

// ============================================================ Statistiques

/// Un client et sa régularité.
class ClientStat {
  const ClientStat(this.name, this.where, this.paid, this.late);

  final String name;
  final String where;

  /// Paiements validés.
  final int paid;

  /// Cotisations en retard aujourd'hui.
  final int late;
}

/// Statistiques avancées sur les 6 derniers mois.
class ProStats {
  const ProStats({
    required this.months,
    required this.totalReceived,
    required this.totalCommissions,
    required this.clients,
    required this.upToDate,
    required this.activeGroups,
    required this.activeCarnets,
    required this.regular,
    required this.watch,
  });

  /// Les 6 derniers mois (le plus ancien d'abord).
  final List<Accounting> months;
  final int totalReceived;
  final int totalCommissions;

  /// Clients en cours (groupes actifs et carnets ouverts).
  final int clients;

  /// Clients à jour aujourd'hui.
  final int upToDate;
  final int activeGroups;
  final int activeCarnets;

  /// Les plus réguliers (aucun retard, le plus de paiements).
  final List<ClientStat> regular;

  /// Clients en retard aujourd'hui (le plus de retards d'abord).
  final List<ClientStat> watch;

  int get upToDatePercent => clients == 0 ? 100 : (upToDate * 100 ~/ clients);

  /// Variation des encaissements par rapport au mois précédent (en %).
  int? get trend {
    if (months.length < 2) return null;
    final prev = months[months.length - 2].received;
    if (prev == 0) return null;
    return ((months.last.received - prev) * 100 / prev).round();
  }

  factory ProStats.of(ProData d, [DateTime? now]) {
    now ??= DateTime.now();
    final months = [
      for (var i = 5; i >= 0; i--) d.month(DateTime(now.year, now.month - i)),
    ];
    var totalReceived = 0;
    var totalCommissions = 0;
    for (final l in d.groupPayments.values.expand((l) => l)) {
      totalReceived += l.amount;
    }
    for (final l in d.carnetPayments.values.expand((l) => l)) {
      totalReceived += l.amount;
    }
    for (final g in d.groups) {
      totalCommissions += (d.payouts[g.id]?.length ?? 0) * g.commission;
    }
    for (final c in d.carnets) {
      totalCommissions += ProData.carnetCommission(c);
    }

    final all = <ClientStat>[];
    var activeGroups = 0;
    for (final g in d.groups.where((g) => g.status == GroupStatus.active)) {
      activeGroups++;
      final payments = d.groupPayments[g.id] ?? const <Payment>[];
      for (final m in g.members) {
        final paid = payments.where((p) => p.userId == m.userId).length;
        all.add(ClientStat(m.name, g.name, paid, g.standingOf(m, now).late));
      }
    }
    var activeCarnets = 0;
    for (final c in d.carnets.where(
      (c) => c.isActive && c.clientId != null && !c.isComplete,
    )) {
      activeCarnets++;
      all.add(
        ClientStat(
          c.client?.fullName ?? c.label,
          c.label,
          d.carnetPayments[c.id]?.length ?? 0,
          0,
        ),
      );
    }
    final regular = all.where((s) => s.late == 0 && s.paid > 0).toList()
      ..sort((a, b) => b.paid.compareTo(a.paid));
    final watch = all.where((s) => s.late > 0).toList()
      ..sort((a, b) => b.late.compareTo(a.late));
    return ProStats(
      months: months,
      totalReceived: totalReceived,
      totalCommissions: totalCommissions,
      clients: all.length,
      upToDate: all.where((s) => s.late == 0).length,
      activeGroups: activeGroups,
      activeCarnets: activeCarnets,
      regular: regular.take(5).toList(),
      watch: watch.take(5).toList(),
    );
  }
}

// ========================================================== Badge vérifié

/// Demande de badge vérifié : pièce d'identité et selfie, examinés par
/// l'administrateur de COTIZI.
class Verification {
  const Verification({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.idType,
    required this.status,
    required this.submittedAt,
    this.reason,
  });

  final String userId;
  final String fullName;
  final String phone;
  final String idType;

  /// pending, approved ou rejected
  final String status;
  final DateTime submittedAt;
  final String? reason;

  bool get pending => status == 'pending';
  bool get approved => status == 'approved';
  bool get rejected => status == 'rejected';

  static const idTypes = {
    'cni': 'Carte d\'identité',
    'passeport': 'Passeport',
    'permis': 'Permis de conduire',
    'autre': 'Autre pièce officielle',
  };

  String get idTypeLabel => idTypes[idType] ?? 'Pièce d\'identité';

  factory Verification.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Verification(
      userId: doc.id,
      fullName: json['fullName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      idType: json['idType'] as String? ?? 'autre',
      status: json['status'] as String? ?? 'pending',
      submittedAt: _timeOrNull(json['submittedAt']) ?? DateTime.now(),
      reason: json['reason'] as String?,
    );
  }
}

// ==================================================================== API

/// Fonctions du plan Pro : comptabilité, statistiques, badge vérifié.
class ProApi {
  ProApi._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String get _uid => Api.uid;
  static FieldValue get _now => FieldValue.serverTimestamp();

  /// Toutes les opérations du tontinier connecté.
  static Future<ProData> load() async {
    final results = await Future.wait([
      _db.collection('groups').where('ownerId', isEqualTo: _uid).get(),
      _db.collection('carnets').where('ownerId', isEqualTo: _uid).get(),
      _db.collection('expenses').where('ownerId', isEqualTo: _uid).get(),
    ]);
    final groupIds = results[0].docs
        .map(Group.fromDoc)
        .where((g) => !g.isLegacy)
        .map((g) => g.id)
        .toList();
    final carnets = results[1].docs.map(Carnet.fromDoc).toList();
    final expenses = results[2].docs.map(Expense.fromDoc).toList();
    final groups = await Future.wait(groupIds.map(Api.group));

    Future<List<Payment>> approved(String path) async {
      final snap = await _db
          .collection(path)
          .where('status', isEqualTo: 'approved')
          .get();
      return snap.docs.map(Payment.fromDoc).toList();
    }

    final gp = await Future.wait([
      for (final g in groups) approved('groups/${g.id}/payments'),
    ]);
    final po = await Future.wait([
      for (final g in groups) Api.payouts(g.id).then((m) => m.values.toList()),
    ]);
    final withClient = carnets.where((c) => c.clientId != null).toList();
    final cp = await Future.wait([
      for (final c in withClient) approved('carnets/${c.id}/payments'),
    ]);
    return ProData(
      groups: groups,
      groupPayments: {
        for (var i = 0; i < groups.length; i++) groups[i].id: gp[i],
      },
      payouts: {for (var i = 0; i < groups.length; i++) groups[i].id: po[i]},
      carnets: carnets,
      carnetPayments: {
        for (var i = 0; i < withClient.length; i++) withClient[i].id: cp[i],
      },
      expenses: expenses,
    );
  }

  static Future<void> addExpense({
    required String label,
    required int amount,
    required String category,
    required DateTime date,
  }) async {
    if (label.trim().length < 2) {
      throw const AppException('Écrivez à quoi a servi la dépense.');
    }
    if (amount <= 0) throw const AppException('Montant invalide.');
    await _db.collection('expenses').add({
      'ownerId': _uid,
      'label': label.trim(),
      'amount': amount,
      'category': category,
      'date': Timestamp.fromDate(date),
      'createdAt': _now,
    });
  }

  static Future<void> deleteExpense(String id) =>
      _db.doc('expenses/$id').delete();

  // ---------------------------------------------------------- Badge

  /// Demande de vérification du tontinier connecté.
  static Future<Verification?> myVerification() async {
    final doc = await _db.doc('verifications/$_uid').get();
    return doc.exists ? Verification.fromDoc(doc) : null;
  }

  /// Taille maximale d'une photo encodée (limite d'un document Firestore).
  static const _maxPhotoChars = 900000;

  static Future<(Uint8List, String)> readPhoto(XFile file) async {
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final mime = name.endsWith('.png')
        ? 'image/png'
        : name.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    if (base64.encode(bytes).length > _maxPhotoChars) {
      throw const AppException('Photo trop lourde. Reprenez-la.');
    }
    return (bytes, mime);
  }

  /// Envoie la pièce d'identité et le selfie à COTIZI.
  static Future<void> submitVerification({
    required String idType,
    required (Uint8List, String) idPhoto,
    required (Uint8List, String) selfie,
  }) async {
    final me = await Api.myProfile();
    if (me == null) throw const AppException('Profil introuvable.');
    final ref = _db.doc('verifications/$_uid');
    // Les photos d'abord : la demande n'apparaît qu'une fois complète.
    await ref.collection('photos').doc('id').set({
      'data': base64.encode(idPhoto.$1),
      'mime': idPhoto.$2,
    });
    await ref.collection('photos').doc('selfie').set({
      'data': base64.encode(selfie.$1),
      'mime': selfie.$2,
    });
    await ref.set({
      'fullName': me.fullName,
      'phone': me.phone,
      'idType': idType,
      'status': 'pending',
      'submittedAt': _now,
    });
  }

  /// Demandes en attente (administrateur).
  static Future<List<Verification>> pendingVerifications() async {
    final snap = await _db
        .collection('verifications')
        .where('status', isEqualTo: 'pending')
        .get();
    return snap.docs.map(Verification.fromDoc).toList()
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
  }

  static Future<Uint8List?> verificationPhoto(
    String userId,
    String kind,
  ) async {
    final doc = await _db.doc('verifications/$userId/photos/$kind').get();
    if (!doc.exists) return null;
    return base64.decode(doc['data'] as String);
  }

  /// L'administrateur accepte : badge donné, photos supprimées.
  static Future<void> approveVerification(Verification v) async {
    final batch = _db.batch()
      ..update(_db.doc('verifications/${v.userId}'), {
        'status': 'approved',
        'decidedAt': _now,
      })
      ..set(_db.doc('badges/${v.userId}'), {
        'fullName': v.fullName,
        'verifiedAt': _now,
      })
      ..delete(_db.doc('verifications/${v.userId}/photos/id'))
      ..delete(_db.doc('verifications/${v.userId}/photos/selfie'));
    await batch.commit();
  }

  /// L'administrateur refuse avec une raison : photos supprimées.
  static Future<void> rejectVerification(Verification v, String reason) async {
    final batch = _db.batch()
      ..update(_db.doc('verifications/${v.userId}'), {
        'status': 'rejected',
        'reason': reason.trim(),
        'decidedAt': _now,
      })
      ..delete(_db.doc('verifications/${v.userId}/photos/id'))
      ..delete(_db.doc('verifications/${v.userId}/photos/selfie'));
    await batch.commit();
  }

  /// L'administrateur retire un badge.
  static Future<void> revokeBadge(String userId) =>
      _db.doc('badges/$userId').delete();

  /// Badge visible : identité vérifiée et plan Pro en cours.
  static Future<bool> isVerified(String ownerId) async {
    try {
      final results = await Future.wait([
        _db.doc('badges/$ownerId').get(),
        _db.doc('users/$ownerId').get(),
      ]);
      if (!results[0].exists || !results[1].exists) return false;
      return Profile.fromJson(results[1].data()!).isProAt(DateTime.now());
    } on FirebaseException {
      return false;
    }
  }
}
