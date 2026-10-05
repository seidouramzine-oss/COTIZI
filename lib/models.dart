import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

enum TontineType { cagnotte, carnet }

enum Frequency { daily, weekly, biweekly, monthly }

enum CommissionType { percent, fixed }

enum GroupStatus { recruiting, drawing, active }

enum PaymentStatus { pending, approved, rejected }

typedef Json = Map<String, dynamic>;

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
  });

  final String fullName;
  final String phone;
  final Role role;

  bool get isMember => role == Role.membre;

  factory Profile.fromJson(Json json) => Profile(
    fullName: json['fullName'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    role: json['role'] == 'membre' ? Role.membre : Role.tontinier,
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
        final lastDay = DateTime(
          startDate.year,
          startDate.month + n + 1,
          0,
        ).day;
        return DateTime(
          startDate.year,
          startDate.month + n,
          min(startDate.day, lastDay),
        );
    }
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
