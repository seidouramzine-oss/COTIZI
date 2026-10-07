import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

enum TontineType { cagnotte, carnet }

enum Frequency { daily, weekly, biweekly, monthly }

enum CommissionType { percent, fixed }

enum GroupStatus { recruiting, drawing, active, finished }

enum PaymentStatus { pending, approved, rejected }

typedef Json = Map<String, dynamic>;

/// Même jour [months] mois plus tard ; le 31 devient le dernier jour des
/// mois plus courts.
DateTime addMonths(DateTime d, int months) {
  final lastDay = DateTime(d.year, d.month + months + 1, 0).day;
  return DateTime(
    d.year,
    d.month + months,
    min(d.day, lastDay),
    d.hour,
    d.minute,
    d.second,
  );
}

T _enum<T extends Enum>(List<T> values, Object? name) =>
    values.firstWhere((v) => v.name == name);

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// Horodatage serveur ; encore nul juste après une écriture locale.
DateTime _time(Object? v) => v is Timestamp ? v.toDate() : DateTime.now();

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Rôle du compte : le tontinier gère des tontines ; le membre, inscrit
/// par un lien d'invitation, ne voit que les tontines auxquelles il participe.
enum Role { tontinier, membre }

class Profile {
  const Profile({
    required this.fullName,
    required this.phone,
    this.role = Role.tontinier,
    this.createdAt,
    this.subscriptionEnd,
  });

  /// Essai gratuit d'un nouveau tontinier (même durée dans les règles).
  static const trialDays = 30;

  final String fullName;
  final String phone;
  final Role role;
  final DateTime? createdAt;

  /// Fin d'abonnement fixée par l'administrateur (null : période d'essai).
  final DateTime? subscriptionEnd;

  bool get isMember => role == Role.membre;

  /// Pendant l'essai : aucune date fixée par l'administrateur.
  bool get isTrial => subscriptionEnd == null;

  /// Fin de l'essai ou de l'abonnement.
  DateTime? get accessEnd =>
      subscriptionEnd ?? createdAt?.add(const Duration(days: trialDays));

  bool canCreateAt(DateTime now) =>
      !isMember && (accessEnd?.isAfter(now) ?? false);

  /// Jours restants (0 le dernier jour, négatif une fois expiré).
  int daysLeft(DateTime now) {
    final end = accessEnd;
    if (end == null) return -1;
    return end.difference(now).inHours ~/ 24;
  }

  factory Profile.fromJson(Json json) => Profile(
    fullName: json['fullName'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    role: json['role'] == 'membre' ? Role.membre : Role.tontinier,
    createdAt: _date(json['createdAt']),
    subscriptionEnd: _date(json['subscriptionEnd']),
  );

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

  Profile withName(String name) => Profile(
    fullName: name,
    phone: phone,
    role: role,
    createdAt: createdAt,
    subscriptionEnd: subscriptionEnd,
  );

  Profile withSubscriptionEnd(DateTime end) => Profile(
    fullName: fullName,
    phone: phone,
    role: role,
    createdAt: createdAt,
    subscriptionEnd: end,
  );
}

/// Compte vu par l'administrateur.
class Account {
  const Account({required this.id, required this.profile});

  final String id;
  final Profile profile;
}

/// Prix et numéro de paiement de l'abonnement (réglés par l'administrateur).
class SubscriptionSettings {
  const SubscriptionSettings({this.monthlyPrice = 0, this.paymentPhone = ''});

  final int monthlyPrice;
  final String paymentPhone;

  bool get isSet => monthlyPrice > 0 || paymentPhone.isNotEmpty;

  factory SubscriptionSettings.fromJson(Json? json) => SubscriptionSettings(
    monthlyPrice: (json?['monthlyPrice'] as num?)?.toInt() ?? 0,
    paymentPhone: json?['paymentPhone'] as String? ?? '',
  );
}

class Tontine {
  const Tontine({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.type,
    this.itemCount = 0,
  });

  final String id;
  final String ownerId;
  final String name;
  final TontineType type;

  /// Nombre de groupes (cagnotte) ou de carnets (carnet).
  final int itemCount;

  Tontine withCount(int count) => Tontine(
    id: id,
    ownerId: ownerId,
    name: name,
    type: type,
    itemCount: count,
  );

  factory Tontine.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Tontine(
      id: doc.id,
      ownerId: json['ownerId'] as String,
      name: json['name'] as String,
      type: _enum(TontineType.values, json['type']),
    );
  }
}

class Group {
  const Group({
    required this.id,
    required this.tontineId,
    required this.tontineName,
    required this.ownerId,
    required this.ownerName,
    required this.name,
    required this.memberCount,
    required this.contributionAmount,
    required this.frequency,
    required this.startDate,
    required this.commissionType,
    required this.commissionValue,
    required this.inviteCode,
    required this.status,
    this.contributionsPerPot,
    this.firstPayoutDate,
    this.paidOutCount = 0,
    this.joinedCount = 0,
    this.drawnCount = 0,
    this.memberIds = const [],
    this.members = const [],
    this.pendingCount = 0,
  });

  final String id;
  final String tontineId;
  final String tontineName;
  final String ownerId;
  final String ownerName;
  final String name;

  /// Nombre de participants, et donc de cagnottes (chacun reçoit une fois).
  final int memberCount;

  /// Montant d'une cotisation.
  final int contributionAmount;

  /// Fréquence des cotisations.
  final Frequency frequency;

  /// Date de la première cotisation.
  final DateTime startDate;
  final CommissionType commissionType;

  /// Commission retenue sur chaque cagnotte (% ou montant fixe).
  final double commissionValue;
  final String inviteCode;
  final GroupStatus status;

  /// Cotisations de chaque participant avant chaque remise (durée de
  /// collecte). Null : groupe créé avant la version 1.4 (lecture seule).
  final int? contributionsPerPot;

  /// Date de remise de la première cagnotte.
  final DateTime? firstPayoutDate;

  /// Cagnottes déjà remises à leur bénéficiaire.
  final int paidOutCount;
  final int joinedCount;
  final int drawnCount;
  final List<String> memberIds;
  final List<GroupMember> members;
  final int pendingCount;

  /// Groupe de l'ancienne version (une cotisation par tour) : consultation.
  bool get isLegacy => contributionsPerPot == null;

  int get perPot => contributionsPerPot ?? 1;

  /// Cotisations que chaque participant verse en tout.
  int get totalContributions => memberCount * perPot;

  /// Ce que chaque participant verse pour une cagnotte.
  int get perMemberPerPot => perPot * contributionAmount;

  /// Montant total d'une cagnotte.
  int get grossPot => memberCount * perMemberPerPot;

  int get commission => commissionType == CommissionType.percent
      ? (grossPot * commissionValue / 100).round()
      : commissionValue.round();

  /// Ce que reçoit le bénéficiaire.
  int get netPot => grossPot - commission;

  DateTime _step(DateTime from, int n) => switch (frequency) {
    Frequency.daily => DateTime(from.year, from.month, from.day + n),
    Frequency.weekly => DateTime(from.year, from.month, from.day + 7 * n),
    Frequency.biweekly => DateTime(from.year, from.month, from.day + 14 * n),
    Frequency.monthly => addMonths(from, n),
  };

  /// Date de la cotisation n°[index] (à partir de 1).
  DateTime contributionDate(int index) => _step(startDate, index - 1);

  /// Ancienne version : date du tour.
  DateTime tourDate(int tour) => contributionDate(tour);

  /// Date de remise de la cagnotte n°[pot] au bénéficiaire.
  DateTime payoutDate(int pot) => isLegacy
      ? contributionDate(pot)
      : _step(firstPayoutDate!, (pot - 1) * perPot);

  /// Période de collecte de la cagnotte n°[pot].
  DateTime collectStart(int pot) => contributionDate((pot - 1) * perPot + 1);

  DateTime collectEnd(int pot) => contributionDate(pot * perPot);

  /// Cotisations dont la date est passée ou aujourd'hui.
  int dueCount(DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    if (day.isBefore(startDate)) return 0;
    if (frequency == Frequency.monthly) {
      var n = 0;
      while (n < totalContributions && !contributionDate(n + 1).isAfter(day)) {
        n++;
      }
      return n;
    }
    final stepDays = switch (frequency) {
      Frequency.weekly => 7,
      Frequency.biweekly => 14,
      _ => 1,
    };
    // Écart en jours calendaires (sans effet des changements d'heure)
    final days = DateTime.utc(day.year, day.month, day.day)
        .difference(
          DateTime.utc(startDate.year, startDate.month, startDate.day),
        )
        .inDays;
    return min(days ~/ stepDays + 1, totalContributions);
  }

  /// Situation d'un participant à la date [today].
  MemberStanding standingOf(GroupMember m, DateTime today) => MemberStanding(
    due: status == GroupStatus.active || status == GroupStatus.finished
        ? dueCount(today)
        : 0,
    declared: m.declaredCount,
    approved: m.approvedCount,
    total: totalContributions,
  );

  /// Cagnotte en cours de collecte (la première pas encore remise).
  int get currentPot => min(paidOutCount + 1, memberCount);

  /// Montant validé (ou déclaré, avec [withPending]) pour la cagnotte [pot].
  int collectedFor(int pot, {bool withPending = false}) {
    final from = (pot - 1) * perPot;
    var units = 0;
    for (final m in members) {
      final paid = withPending ? m.declaredCount : m.approvedCount;
      units += (paid - from).clamp(0, perPot);
    }
    return units * contributionAmount;
  }

  GroupMember? beneficiaryOf(int pot) {
    for (final m in members) {
      if (m.drawPosition == pot) return m;
    }
    return null;
  }

  GroupMember? memberById(String userId) {
    for (final m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  Group copyWith({List<GroupMember>? members, int? pendingCount}) => Group(
    id: id,
    tontineId: tontineId,
    tontineName: tontineName,
    ownerId: ownerId,
    ownerName: ownerName,
    name: name,
    memberCount: memberCount,
    contributionAmount: contributionAmount,
    frequency: frequency,
    startDate: startDate,
    commissionType: commissionType,
    commissionValue: commissionValue,
    inviteCode: inviteCode,
    status: status,
    contributionsPerPot: contributionsPerPot,
    firstPayoutDate: firstPayoutDate,
    paidOutCount: paidOutCount,
    joinedCount: joinedCount,
    drawnCount: drawnCount,
    memberIds: memberIds,
    members: members ?? this.members,
    pendingCount: pendingCount ?? this.pendingCount,
  );

  factory Group.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    final memberCount = _int(json['memberCount']);
    final drawnCount = _int(json['drawnCount']);
    final perPot = json['contributionsPerPot'] == null
        ? null
        : _int(json['contributionsPerPot']);
    final paidOut = _int(json['paidOutCount']);
    final status = json['status'] == 'recruiting'
        ? GroupStatus.recruiting
        : drawnCount < memberCount
        ? GroupStatus.drawing
        : perPot != null && paidOut >= memberCount
        ? GroupStatus.finished
        : GroupStatus.active;
    return Group(
      id: doc.id,
      tontineId: json['tontineId'] as String,
      tontineName: json['tontineName'] as String? ?? '',
      ownerId: json['ownerId'] as String,
      ownerName: json['ownerName'] as String? ?? '',
      name: json['name'] as String,
      memberCount: memberCount,
      contributionAmount: _int(json['contributionAmount']),
      frequency: _enum(Frequency.values, json['frequency']),
      startDate: DateTime.parse(json['startDate'] as String),
      commissionType: _enum(CommissionType.values, json['commissionType']),
      commissionValue: (json['commissionValue'] as num).toDouble(),
      inviteCode: json['inviteCode'] as String,
      status: status,
      contributionsPerPot: perPot,
      firstPayoutDate: json['firstPayoutDate'] is String
          ? DateTime.parse(json['firstPayoutDate'] as String)
          : null,
      paidOutCount: paidOut,
      joinedCount: _int(json['joinedCount']),
      drawnCount: drawnCount,
      memberIds: List<String>.from(json['memberIds'] as List? ?? const []),
    );
  }
}

/// Situation d'un participant : cotisations dues, déclarées et validées.
class MemberStanding {
  const MemberStanding({
    required this.due,
    required this.declared,
    required this.approved,
    required this.total,
  });

  /// Cotisations dont la date est arrivée.
  final int due;

  /// Cotisations déclarées (validées ou en attente).
  final int declared;
  final int approved;
  final int total;

  int get late => max(0, due - declared);
  int get pending => max(0, declared - approved);
  int get ahead => max(0, declared - due);
  int get remaining => max(0, total - declared);
  bool get upToDate => late == 0;
  bool get allPaid => approved >= total;
}

class GroupMember {
  const GroupMember({
    required this.userId,
    required this.drawPosition,
    required this.profile,
    this.declaredCount = 0,
    this.approvedCount = 0,
  });

  final String userId;
  final int? drawPosition;
  final Profile profile;

  /// Cotisations déclarées (validées ou en attente de validation).
  final int declaredCount;

  /// Cotisations validées par le tontinier.
  final int approvedCount;

  String get name => profile.fullName;

  factory GroupMember.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return GroupMember(
      userId: doc.id,
      drawPosition: json['drawPosition'] == null
          ? null
          : _int(json['drawPosition']),
      profile: Profile.fromJson(json),
      declaredCount: _int(json['declaredCount']),
      approvedCount: _int(json['approvedCount']),
    );
  }
}

/// Remise d'une cagnotte à son bénéficiaire, confirmée par le tontinier.
class Payout {
  const Payout({
    required this.pot,
    required this.beneficiaryName,
    required this.amount,
    required this.paidAt,
  });

  final int pot;
  final String beneficiaryName;
  final int amount;
  final DateTime paidAt;

  factory Payout.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Payout(
      pot: _int(json['tour']),
      beneficiaryName: json['beneficiaryName'] as String? ?? '',
      amount: _int(json['amount']),
      paidAt: _time(json['paidAt']),
    );
  }
}

class Payment {
  const Payment({
    required this.id,
    required this.userId,
    required this.amount,
    required this.proofId,
    required this.status,
    required this.rejectionReason,
    required this.declaredAt,
    required this.payer,
    this.reviewedAt,
    this.tourNumber = 0,
    this.count = 0,
    this.caseCount = 0,
  });

  final String id;
  final String userId;
  final int amount;
  final String proofId;
  final PaymentStatus status;
  final String? rejectionReason;
  final DateTime declaredAt;
  final DateTime? reviewedAt;
  final Profile payer;

  /// Ancienne version de la cagnotte : tour concerné.
  final int tourNumber;

  /// Cagnotte : nombre de cotisations payées.
  final int count;

  /// Carnet : nombre de cases payées.
  final int caseCount;

  /// Numéro court affiché sur le reçu.
  String get receiptNumber => id.substring(0, min(8, id.length)).toUpperCase();

  factory Payment.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Payment(
      id: doc.id,
      userId: json['userId'] as String,
      amount: _int(json['amount']),
      proofId: json['proofId'] as String,
      status: _enum(PaymentStatus.values, json['status']),
      rejectionReason: json['rejectionReason'] as String?,
      declaredAt: _time(json['declaredAt']),
      reviewedAt: json['reviewedAt'] is Timestamp
          ? (json['reviewedAt'] as Timestamp).toDate()
          : null,
      payer: Profile(
        fullName: json['payerName'] as String? ?? '',
        phone: json['payerPhone'] as String? ?? '',
      ),
      tourNumber: _int(json['tourNumber']),
      count: _int(json['count']),
      caseCount: _int(json['caseCount']),
    );
  }
}

class Carnet {
  const Carnet({
    required this.id,
    required this.tontineId,
    required this.tontineName,
    required this.ownerId,
    required this.ownerName,
    required this.label,
    required this.caseAmount,
    required this.caseCount,
    required this.clientId,
    required this.client,
    required this.inviteCode,
    required this.usedCases,
    required this.approvedCases,
  });

  final String id;
  final String tontineId;
  final String tontineName;
  final String ownerId;
  final String ownerName;
  final String label;
  final int caseAmount;
  final int caseCount;
  final String? clientId;
  final Profile? client;
  final String inviteCode;

  /// Cases déclarées (en attente + validées).
  final int usedCases;
  final int approvedCases;

  int get pendingCases => usedCases - approvedCases;

  int get remainingCases => caseCount - usedCases;

  /// Le client récupère toutes les cases sauf la dernière (commission).
  int get clientPayout => (caseCount - 1) * caseAmount;

  bool get isComplete => approvedCases >= caseCount;

  factory Carnet.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Carnet(
      id: doc.id,
      tontineId: json['tontineId'] as String,
      tontineName: json['tontineName'] as String? ?? '',
      ownerId: json['ownerId'] as String,
      ownerName: json['ownerName'] as String? ?? '',
      label: json['label'] as String,
      caseAmount: _int(json['caseAmount']),
      caseCount: _int(json['caseCount']),
      clientId: json['clientId'] as String?,
      client: json['clientId'] == null
          ? null
          : Profile(
              fullName: json['clientName'] as String? ?? '',
              phone: json['clientPhone'] as String? ?? '',
            ),
      inviteCode: json['inviteCode'] as String,
      usedCases: _int(json['usedCases']),
      approvedCases: _int(json['approvedCases']),
    );
  }
}

/// Paiement en attente de validation, avec son groupe ou son carnet.
class PendingReview {
  const PendingReview({required this.payment, this.group, this.carnet});

  final Payment payment;
  final Group? group;
  final Carnet? carnet;
}

/// Vue d'ensemble du tontinier (accueil).
class OwnerOverview {
  const OwnerOverview({
    required this.tontineCount,
    required this.groups,
    required this.carnets,
    required this.pending,
  });

  final int tontineCount;
  final List<Group> groups;
  final List<Carnet> carnets;
  final List<PendingReview> pending;

  int get memberCount =>
      groups.fold(0, (n, g) => n + g.joinedCount) +
      carnets.where((c) => c.clientId != null).length;

  /// Montant total en attente de validation.
  int get pendingAmount => pending.fold(0, (n, p) => n + p.payment.amount);
}

/// Situation d'un participant dans un groupe (accueil du participant).
class MemberGroupStatus {
  const MemberGroupStatus({
    required this.group,
    required this.payments,
    required this.standing,
  });

  final Group group;

  /// Ses paiements dans ce groupe (les plus récents d'abord).
  final List<Payment> payments;
  final MemberStanding standing;

  int? myPosition(String userId) => group.memberById(userId)?.drawPosition;
}

/// Vue d'ensemble d'un participant (accueil).
class MemberOverview {
  const MemberOverview({required this.groups, required this.carnets});

  final List<MemberGroupStatus> groups;
  final List<Carnet> carnets;

  /// Cotisations en retard dans les cagnottes en cours.
  int get lateCount => active.fold(0, (n, s) => n + s.standing.late);

  /// Montant total des cotisations en retard.
  int get lateAmount => active.fold(
    0,
    (n, s) => n + s.standing.late * s.group.contributionAmount,
  );

  /// Cagnottes en cours (nouvelle version).
  List<MemberGroupStatus> get active => groups
      .where((s) => !s.group.isLegacy && s.group.status == GroupStatus.active)
      .toList();
}
