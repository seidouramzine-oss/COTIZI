import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

enum TontineType { cagnotte, carnet }

enum Frequency { daily, weekly, biweekly, monthly }

enum CommissionType { percent, fixed }

enum GroupStatus { recruiting, drawing, active }

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
  final int memberCount;
  final int contributionAmount;
  final Frequency frequency;
  final DateTime startDate;
  final CommissionType commissionType;
  final double commissionValue;
  final String inviteCode;
  final GroupStatus status;
  final int joinedCount;
  final int drawnCount;
  final List<String> memberIds;
  final List<GroupMember> members;
  final int pendingCount;

  /// Total collecté à chaque tour.
  int get grossPot => memberCount * contributionAmount;

  int get commission => commissionType == CommissionType.percent
      ? (grossPot * commissionValue / 100).round()
      : commissionValue.round();

  /// Ce que reçoit le bénéficiaire du tour.
  int get netPot => grossPot - commission;

  DateTime tourDate(int tour) {
    final n = tour - 1;
    switch (frequency) {
      case Frequency.daily:
        return DateTime(startDate.year, startDate.month, startDate.day + n);
      case Frequency.weekly:
        return DateTime(startDate.year, startDate.month, startDate.day + 7 * n);
      case Frequency.biweekly:
        return DateTime(
          startDate.year,
          startDate.month,
          startDate.day + 14 * n,
        );
      case Frequency.monthly:
        return addMonths(startDate, n);
    }
  }

  /// Tours que [userId] doit encore payer : ceux dont la date est passée
  /// (ou aujourd'hui) sans paiement validé ni en attente, puis le prochain tour
  /// à venir. Un paiement refusé est à refaire.
  (List<int> due, int? next) unpaidTours(
    String userId,
    List<Payment> payments,
    DateTime today,
  ) {
    final day = DateTime(today.year, today.month, today.day);
    final covered = {
      for (final p in payments)
        if (p.userId == userId && p.status != PaymentStatus.rejected)
          p.tourNumber,
    };
    final due = <int>[];
    int? next;
    for (var tour = 1; tour <= memberCount; tour++) {
      if (covered.contains(tour)) continue;
      if (!tourDate(tour).isAfter(day)) {
        due.add(tour);
      } else {
        next = tour;
        break;
      }
    }
    return (due, next);
  }

  GroupMember? beneficiaryOf(int tour) {
    for (final m in members) {
      if (m.drawPosition == tour) return m;
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
    final status = json['status'] == 'recruiting'
        ? GroupStatus.recruiting
        : drawnCount >= memberCount
        ? GroupStatus.active
        : GroupStatus.drawing;
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
      joinedCount: _int(json['joinedCount']),
      drawnCount: drawnCount,
      memberIds: List<String>.from(json['memberIds'] as List? ?? const []),
    );
  }
}

class GroupMember {
  const GroupMember({
    required this.userId,
    required this.drawPosition,
    required this.profile,
  });

  final String userId;
  final int? drawPosition;
  final Profile profile;

  String get name => profile.fullName;

  factory GroupMember.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return GroupMember(
      userId: doc.id,
      drawPosition: json['drawPosition'] == null
          ? null
          : _int(json['drawPosition']),
      profile: Profile.fromJson(json),
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
    this.tourNumber = 0,
    this.caseCount = 0,
  });

  final String id;
  final String userId;
  final int amount;
  final String proofId;
  final PaymentStatus status;
  final String? rejectionReason;
  final DateTime declaredAt;
  final Profile payer;

  /// Paiement de groupe (cagnotte) : tour concerné.
  final int tourNumber;

  /// Paiement de carnet : nombre de cases payées.
  final int caseCount;

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
      payer: Profile(
        fullName: json['payerName'] as String? ?? '',
        phone: json['payerPhone'] as String? ?? '',
      ),
      tourNumber: _int(json['tourNumber']),
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

/// Situation d'un membre dans un groupe (accueil du participant).
class MemberGroupStatus {
  const MemberGroupStatus({
    required this.group,
    required this.payments,
    required this.dueTours,
    required this.nextTour,
  });

  final Group group;
  final List<Payment> payments;
  final List<int> dueTours;
  final int? nextTour;

  int? myPosition(String userId) => group.members
      .where((m) => m.userId == userId)
      .map((m) => m.drawPosition)
      .firstOrNull;

  Payment? latestFor(int tour) =>
      payments.where((p) => p.tourNumber == tour).firstOrNull;
}

/// Vue d'ensemble d'un participant (accueil).
class MemberOverview {
  const MemberOverview({required this.groups, required this.carnets});

  final List<MemberGroupStatus> groups;
  final List<Carnet> carnets;

  int get dueCount =>
      groups.fold(0, (n, g) => n + g.dueTours.length) +
      carnets.where((c) => c.remainingCases > 0 && !c.isComplete).length;
}
