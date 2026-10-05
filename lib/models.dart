import 'dart:math';

enum TontineType { cagnotte, carnet }

enum Frequency { daily, weekly, biweekly, monthly }

enum CommissionType { percent, fixed }

enum GroupStatus { recruiting, drawing, active }

enum PaymentStatus { pending, approved, rejected }

T _enum<T extends Enum>(List<T> values, Object? name) =>
    values.firstWhere((v) => v.name == name);

int _int(Object? v) => (v as num).toInt();

class Profile {
  const Profile({required this.fullName, required this.phone});

  final String fullName;
  final String phone;

  static Profile? maybe(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return Profile(
      fullName: json['full_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
    );
  }
}

class Tontine {
  const Tontine({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.type,
    this.owner,
    this.itemCount = 0,
  });

  final String id;
  final String ownerId;
  final String name;
  final TontineType type;
  final Profile? owner;

  /// Nombre de groupes (cagnotte) ou de carnets (carnet).
  final int itemCount;

  factory Tontine.fromJson(Map<String, dynamic> json) {
    final type = _enum(TontineType.values, json['type']);
    final counts = json[type == TontineType.cagnotte ? 'groups' : 'carnets'];
    return Tontine(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String? ?? '',
      name: json['name'] as String,
      type: type,
      owner: Profile.maybe(json['owner']),
      itemCount: counts is List && counts.isNotEmpty
          ? _int(counts.first['count'])
          : 0,
    );
  }
}

class Group {
  const Group({
    required this.id,
    required this.tontineId,
    required this.name,
    required this.memberCount,
    required this.contributionAmount,
    required this.frequency,
    required this.startDate,
    required this.commissionType,
    required this.commissionValue,
    required this.inviteCode,
    required this.status,
    this.tontine,
    this.members = const [],
    this.joinedCount = 0,
    this.pendingCount = 0,
  });

  final String id;
  final String tontineId;
  final String name;
  final int memberCount;
  final int contributionAmount;
  final Frequency frequency;
  final DateTime startDate;
  final CommissionType commissionType;
  final double commissionValue;
  final String inviteCode;
  final GroupStatus status;
  final Tontine? tontine;
  final List<GroupMember> members;
  final int joinedCount;
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
        return startDate.add(Duration(days: n));
      case Frequency.weekly:
        return startDate.add(Duration(days: 7 * n));
      case Frequency.biweekly:
        return startDate.add(Duration(days: 14 * n));
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

  factory Group.fromJson(Map<String, dynamic> json) {
    final membersJson = json['members'];
    final countJson = json['group_members'];
    final pendingJson = json['payments'];
    return Group(
      id: json['id'] as String,
      tontineId: json['tontine_id'] as String,
      name: json['name'] as String,
      memberCount: _int(json['member_count']),
      contributionAmount: _int(json['contribution_amount']),
      frequency: _enum(Frequency.values, json['frequency']),
      startDate: DateTime.parse(json['start_date'] as String),
      commissionType: _enum(CommissionType.values, json['commission_type']),
      commissionValue: (json['commission_value'] as num).toDouble(),
      inviteCode: json['invite_code'] as String,
      status: _enum(GroupStatus.values, json['status']),
      tontine: json['tontine'] is Map<String, dynamic>
          ? Tontine.fromJson({
              'type': 'cagnotte',
              ...json['tontine'] as Map<String, dynamic>,
            })
          : null,
      members: membersJson is List
          ? (membersJson.map((m) => GroupMember.fromJson(m)).toList()..sort(
              (a, b) => (a.drawPosition ?? 1 << 30).compareTo(
                b.drawPosition ?? 1 << 30,
              ),
            ))
          : const [],
      joinedCount: membersJson is List
          ? membersJson.length
          : countJson is List && countJson.isNotEmpty
          ? _int(countJson.first['count'])
          : 0,
      pendingCount: pendingJson is List && pendingJson.isNotEmpty
          ? _int(pendingJson.first['count'])
          : 0,
    );
  }
}

class GroupMember {
  const GroupMember({
    required this.id,
    required this.userId,
    required this.drawPosition,
    required this.profile,
  });

  final String id;
  final String userId;
  final int? drawPosition;
  final Profile? profile;

  String get name => profile?.fullName ?? 'Membre';

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    drawPosition: json['draw_position'] == null
        ? null
        : _int(json['draw_position']),
    profile: Profile.maybe(json['profile']),
  );
}

class Payment {
  const Payment({
    required this.id,
    required this.userId,
    required this.amount,
    required this.proofPath,
    required this.status,
    required this.rejectionReason,
    required this.declaredAt,
    this.tourNumber = 0,
    this.caseCount = 0,
    this.profile,
  });

  final String id;
  final String userId;
  final int amount;
  final String proofPath;
  final PaymentStatus status;
  final String? rejectionReason;
  final DateTime declaredAt;

  /// Paiement de groupe (cagnotte) : tour concerné.
  final int tourNumber;

  /// Paiement de carnet : nombre de cases payées.
  final int caseCount;
  final Profile? profile;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    amount: _int(json['amount']),
    proofPath: json['proof_path'] as String,
    status: _enum(PaymentStatus.values, json['status']),
    rejectionReason: json['rejection_reason'] as String?,
    declaredAt: DateTime.parse(json['declared_at'] as String).toLocal(),
    tourNumber: json['tour_number'] == null ? 0 : _int(json['tour_number']),
    caseCount: json['case_count'] == null ? 0 : _int(json['case_count']),
    profile: Profile.maybe(json['profile']),
  );
}

class Carnet {
  const Carnet({
    required this.id,
    required this.tontineId,
    required this.label,
    required this.caseAmount,
    required this.caseCount,
    required this.clientId,
    required this.inviteCode,
    this.client,
    this.tontine,
    this.approvedCases = 0,
    this.pendingCases = 0,
  });

  final String id;
  final String tontineId;
  final String label;
  final int caseAmount;
  final int caseCount;
  final String? clientId;
  final String inviteCode;
  final Profile? client;
  final Tontine? tontine;
  final int approvedCases;
  final int pendingCases;

  int get remainingCases => caseCount - approvedCases - pendingCases;

  /// Le client récupère toutes les cases sauf la dernière (commission).
  int get clientPayout => (caseCount - 1) * caseAmount;

  bool get isComplete => approvedCases >= caseCount;

  Carnet withPayments(List<Payment> payments) =>
      _withCounts(payments.map((p) => (p.status, p.caseCount)));

  Carnet _withCounts(Iterable<(PaymentStatus, int)> payments) {
    var approved = 0;
    var pending = 0;
    for (final (status, cases) in payments) {
      if (status == PaymentStatus.approved) approved += cases;
      if (status == PaymentStatus.pending) pending += cases;
    }
    return Carnet(
      id: id,
      tontineId: tontineId,
      label: label,
      caseAmount: caseAmount,
      caseCount: caseCount,
      clientId: clientId,
      inviteCode: inviteCode,
      client: client,
      tontine: tontine,
      approvedCases: approved,
      pendingCases: pending,
    );
  }

  factory Carnet.fromJson(Map<String, dynamic> json) {
    final carnet = Carnet(
      id: json['id'] as String,
      tontineId: json['tontine_id'] as String,
      label: json['label'] as String,
      caseAmount: _int(json['case_amount']),
      caseCount: _int(json['case_count']),
      clientId: json['client_id'] as String?,
      inviteCode: json['invite_code'] as String,
      client: Profile.maybe(json['client']),
      tontine: json['tontine'] is Map<String, dynamic>
          ? Tontine.fromJson({
              'type': 'carnet',
              ...json['tontine'] as Map<String, dynamic>,
            })
          : null,
    );
    final payments = json['carnet_payments'];
    if (payments is List) {
      return carnet._withCounts(
        payments.map(
          (p) =>
              (_enum(PaymentStatus.values, p['status']), _int(p['case_count'])),
        ),
      );
    }
    return carnet;
  }
}
