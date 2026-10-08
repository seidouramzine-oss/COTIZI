import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

enum TontineType { cagnotte, carnet }

enum Frequency { daily, weekly, biweekly, monthly }

enum CommissionType { percent, fixed }

/// Déroulé d'un groupe : inscriptions, ordre des remises (tirage ou ordre
/// fixé), prêt à démarrer, en cours, terminé.
enum GroupStatus { recruiting, drawing, ready, active, finished }

/// Ordre des remises : tirage au sort ou fixé par le tontinier.
enum OrderMode { draw, manual }

/// Mode de paiement d'une cotisation ou d'une case.
enum PaymentMethod { mobileMoney, cash }

/// Pénalité de retard : montant fixe, ou pourcentage de la cotisation due.
enum PenaltyType { fixed, percent }

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
  const SubscriptionSettings({
    this.monthlyPrice = 0,
    this.paymentPhone = '',
    this.supportPhone = '',
  });

  final int monthlyPrice;
  final String paymentPhone;

  /// Numéro WhatsApp de l'assistance COTIZI.
  final String supportPhone;

  /// Numéro à contacter sur WhatsApp (assistance, sinon paiement).
  String get contactPhone =>
      supportPhone.isNotEmpty ? supportPhone : paymentPhone;

  bool get isSet => monthlyPrice > 0 || paymentPhone.isNotEmpty;

  factory SubscriptionSettings.fromJson(Json? json) => SubscriptionSettings(
    monthlyPrice: (json?['monthlyPrice'] as num?)?.toInt() ?? 0,
    paymentPhone: json?['paymentPhone'] as String? ?? '',
    supportPhone: json?['supportPhone'] as String? ?? '',
  );
}

/// Demande d'abonnement d'un tontinier (Administration).
class SubscriptionRequest {
  const SubscriptionRequest({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.months,
    required this.amount,
    required this.requestedAt,
  });

  final String userId;
  final String fullName;
  final String phone;
  final int months;
  final int amount;
  final DateTime requestedAt;

  factory SubscriptionRequest.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return SubscriptionRequest(
      userId: doc.id,
      fullName: json['fullName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      months: _int(json['months']),
      amount: _int(json['amount']),
      requestedAt: _time(json['requestedAt']),
    );
  }
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
    this.orderMode,
    this.penaltyAmount = 0,
    this.penaltyGraceDays = 0,
    this.startedAt,
    this.joinedCount = 0,
    this.drawnCount = 0,
    this.memberIds = const [],
    this.members = const [],
    this.pendingCount = 0,
    this.levels,
    this.penaltyType = PenaltyType.fixed,
    this.rulesText = '',
    this.termsVersion,
    this.accepted = const {},
    this.closedAt,
  });

  /// Clôture par le tontinier, une fois toutes les cagnottes remises.
  final DateTime? closedAt;

  bool get isClosed => closedAt != null;

  /// Toutes les cagnottes sont remises : le tontinier peut clôturer.
  bool get canClose => !isLegacy && !isClosed && status == GroupStatus.finished;

  /// Pénalité en montant fixe ([penaltyAmount] FCFA) ou en pourcentage
  /// ([penaltyAmount] % de la cotisation due).
  final PenaltyType penaltyType;

  /// Règles propres au groupe, écrites par le tontinier.
  final String rulesText;

  /// Version du règlement (conditions + règles) que chaque participant doit
  /// accepter avant le démarrage. Null : groupe créé avant la version 2.2.
  final int? termsVersion;

  /// Version du règlement acceptée par chaque participant (identifiant).
  final Map<String, int> accepted;

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

  /// Ordre des remises (null : groupe d'une version précédente).
  final OrderMode? orderMode;

  /// Pénalité par cotisation payée en retard (0 : pas de pénalité), au-delà
  /// de [penaltyGraceDays] jours de tolérance. Elle revient au tontinier.
  final int penaltyAmount;
  final int penaltyGraceDays;

  /// Démarrage par le tontinier : les dates sont alors figées.
  final DateTime? startedAt;
  final int joinedCount;
  final int drawnCount;
  final List<String> memberIds;
  final List<GroupMember> members;
  final int pendingCount;

  /// Nombre de participants par niveau (cagnottes entièrement payées),
  /// tenu à jour pour que le serveur bloque une remise avant la fin de la
  /// collecte. Null : groupe démarré avant la version 2.1.
  final Map<String, int>? levels;

  /// Groupe d'une version précédente : consultation seulement.
  bool get isLegacy => orderMode == null;

  bool get isStarted =>
      status == GroupStatus.active || status == GroupStatus.finished;

  bool get hasPenalty => penaltyAmount > 0;

  /// Pénalité pour une cotisation payée en retard.
  int get penaltyPerContribution => penaltyType == PenaltyType.percent
      ? (contributionAmount * penaltyAmount / 100).round()
      : penaltyAmount;

  /// Le règlement doit être accepté par les participants (groupes 2.2).
  bool get needsAcceptance => termsVersion != null;

  /// [userId] a accepté le règlement en vigueur (ou n'a pas à le faire).
  bool hasAccepted(String userId) =>
      termsVersion == null || accepted[userId] == termsVersion;

  /// Participants avec l'application (comptes de [memberIds]) qui n'ont pas
  /// encore accepté le règlement en vigueur. Ceux sans application : le
  /// tontinier s'en porte garant.
  int get pendingAcceptanceCount => termsVersion == null
      ? 0
      : memberIds.where((id) => accepted[id] != termsVersion).length;

  /// Les mêmes, avec leur nom (participants chargés).
  List<GroupMember> get pendingAcceptance => [
    for (final m in members)
      if (memberIds.contains(m.userId) && !hasAccepted(m.userId)) m,
  ];

  bool get allAccepted => pendingAcceptanceCount == 0;

  /// Date de fin : dernière remise.
  DateTime get endDate => payoutDate(memberCount);

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
  MemberStanding standingOf(GroupMember m, DateTime today) {
    final due = isStarted && !isLegacy ? dueCount(today) : 0;
    final late = max(0, due - m.declaredCount);
    return MemberStanding(
      due: due,
      declared: m.declaredCount,
      approved: m.approvedCount,
      total: totalContributions,
      penaltyDue: late > 0 ? penaltyFor(m.declaredCount + 1, late, today) : 0,
      penaltyPaid: m.penaltyPaid,
    );
  }

  /// Pénalités pour les cotisations n°[from] à n°[from] + [count] - 1
  /// payées à la date [today] : une par cotisation dont l'échéance est
  /// dépassée de plus de [penaltyGraceDays] jours.
  int penaltyFor(int from, int count, DateTime today) {
    if (!hasPenalty || isLegacy) return 0;
    final day = DateTime(today.year, today.month, today.day);
    var n = 0;
    for (var i = from; i < from + count && i <= totalContributions; i++) {
      final limit = contributionDate(i).add(Duration(days: penaltyGraceDays));
      if (day.isAfter(DateTime(limit.year, limit.month, limit.day))) n++;
    }
    return n * penaltyPerContribution;
  }

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

  /// Collecte de la cagnotte [pot] complète : la remise est possible.
  bool isPotComplete(int pot) => collectedFor(pot) >= grossPot;

  /// Montant qui manque pour compléter la cagnotte [pot].
  int missingFor(int pot) => max(0, grossPot - collectedFor(pot));

  /// Participants qui n'ont pas encore tout payé (validé) pour la cagnotte
  /// [pot] : cotisations manquantes, dont celles en attente de validation
  /// et celles déjà dues à la date [today] mais pas déclarées (retard).
  List<PotShortfall> shortfallsFor(int pot, [DateTime? today]) {
    final from = (pot - 1) * perPot;
    final due = (dueCount(today ?? DateTime.now()) - from).clamp(0, perPot);
    return [
      for (final m in members)
        if ((m.approvedCount - from).clamp(0, perPot) < perPot)
          PotShortfall(
            member: m,
            missing: perPot - (m.approvedCount - from).clamp(0, perPot),
            pending:
                (m.declaredCount - from).clamp(0, perPot) -
                (m.approvedCount - from).clamp(0, perPot),
            late: max(0, due - (m.declaredCount - from).clamp(0, perPot)),
            amount:
                (perPot - (m.approvedCount - from).clamp(0, perPot)) *
                contributionAmount,
          ),
    ]..sort((a, b) => b.late.compareTo(a.late));
  }

  /// Participants en retard pour la cagnotte [pot] : des cotisations déjà
  /// dues (aujourd'hui compris) ne sont pas encore déclarées.
  List<PotShortfall> lateFor(int pot, [DateTime? today]) => [
    for (final f in shortfallsFor(pot, today))
      if (f.late > 0) f,
  ];

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
    orderMode: orderMode,
    penaltyAmount: penaltyAmount,
    penaltyGraceDays: penaltyGraceDays,
    startedAt: startedAt,
    joinedCount: joinedCount,
    drawnCount: drawnCount,
    memberIds: memberIds,
    members: members ?? this.members,
    pendingCount: pendingCount ?? this.pendingCount,
    levels: levels,
    penaltyType: penaltyType,
    rulesText: rulesText,
    termsVersion: termsVersion,
    accepted: accepted,
    closedAt: closedAt,
  );

  factory Group.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    final memberCount = _int(json['memberCount']);
    final drawnCount = _int(json['drawnCount']);
    final perPot = json['contributionsPerPot'] == null
        ? null
        : _int(json['contributionsPerPot']);
    final paidOut = _int(json['paidOutCount']);
    final orderMode = switch (json['orderMode']) {
      'draw' => OrderMode.draw,
      'manual' => OrderMode.manual,
      _ => null,
    };
    final raw = json['status'];
    final GroupStatus status;
    if (raw == 'recruiting') {
      status = GroupStatus.recruiting;
    } else if (orderMode == null) {
      // Versions précédentes : en cours dès que tout le monde a son numéro
      status = drawnCount < memberCount
          ? GroupStatus.drawing
          : GroupStatus.active;
    } else if (raw == 'closed') {
      status = GroupStatus.finished;
    } else if (raw == 'active') {
      status = paidOut >= memberCount
          ? GroupStatus.finished
          : GroupStatus.active;
    } else {
      status = drawnCount < memberCount
          ? GroupStatus.drawing
          : GroupStatus.ready;
    }
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
      orderMode: orderMode,
      penaltyAmount: _int(json['penaltyAmount']),
      penaltyGraceDays: _int(json['penaltyGraceDays']),
      startedAt: json['startedAt'] is Timestamp
          ? (json['startedAt'] as Timestamp).toDate()
          : null,
      joinedCount: _int(json['joinedCount']),
      drawnCount: drawnCount,
      memberIds: List<String>.from(json['memberIds'] as List? ?? const []),
      levels: json['levels'] is Map
          ? {
              for (final e in (json['levels'] as Map).entries)
                e.key as String: _int(e.value),
            }
          : null,
      penaltyType: json['penaltyType'] == 'percent'
          ? PenaltyType.percent
          : PenaltyType.fixed,
      rulesText: json['rulesText'] as String? ?? '',
      termsVersion: json['termsVersion'] == null
          ? null
          : _int(json['termsVersion']),
      accepted: json['accepted'] is Map
          ? {
              for (final e in (json['accepted'] as Map).entries)
                e.key as String: _int(e.value),
            }
          : const {},
      closedAt: json['closedAt'] is Timestamp
          ? (json['closedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

/// Ce qui manque à un participant pour une cagnotte.
class PotShortfall {
  const PotShortfall({
    required this.member,
    required this.missing,
    required this.pending,
    required this.amount,
    this.late = 0,
  });

  /// Cotisations déjà dues mais pas encore déclarées (retard).
  final int late;

  final GroupMember member;

  /// Cotisations pas encore validées pour cette cagnotte.
  final int missing;

  /// Parmi elles, cotisations déclarées en attente de validation.
  final int pending;

  /// Montant des cotisations manquantes.
  final int amount;
}

/// Situation d'un participant : cotisations dues, déclarées et validées.
class MemberStanding {
  const MemberStanding({
    required this.due,
    required this.declared,
    required this.approved,
    required this.total,
    this.penaltyDue = 0,
    this.penaltyPaid = 0,
  });

  /// Pénalités si les cotisations en retard étaient payées aujourd'hui.
  final int penaltyDue;

  /// Pénalités déjà payées (validées).
  final int penaltyPaid;

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
    this.penaltyPaid = 0,
    this.managed = false,
    this.claimedBy,
    this.claimedFrom,
  });

  /// Pénalités payées (validées).
  final int penaltyPaid;

  /// Participant sans application, géré par le tontinier.
  final bool managed;

  /// Place réservée reprise par son titulaire (compte [claimedBy]).
  final String? claimedBy;

  /// Compte qui a repris une place réservée (identifiant de la place).
  final String? claimedFrom;

  /// Identifiants de ses paiements : son compte et sa place réservée.
  List<String> get paymentIds => [userId, ?claimedFrom];

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
      penaltyPaid: _int(json['penaltyPaid']),
      managed: json['managed'] == true,
      claimedBy: json['claimedBy'] as String?,
      claimedFrom: json['claimedFrom'] as String?,
    );
  }
}

/// Remise d'une cagnotte à son bénéficiaire, confirmée par le tontinier.
/// Numéro de reçu lisible tiré d'un identifiant Firestore : CZ-XXXX-XXXX.
String receiptCode(String id) {
  final c = id.toUpperCase().padRight(8, '0').substring(0, 8);
  return 'CZ-${c.substring(0, 4)}-${c.substring(4)}';
}

/// Note de confiance d'un tontinier, tenue par le serveur : chaque compteur
/// n'avance qu'avec la remise, la confirmation ou le signalement réel.
class TrustStats {
  const TrustStats({
    this.payoutsDone = 0,
    this.payoutsConfirmed = 0,
    this.payoutsDisputed = 0,
  });

  /// Cagnottes remises par le tontinier.
  final int payoutsDone;

  /// Réceptions confirmées par les bénéficiaires.
  final int payoutsConfirmed;

  /// Problèmes signalés par des bénéficiaires.
  final int payoutsDisputed;

  bool get isNew => payoutsDone == 0;

  /// Part des remises confirmées (0 à 100).
  int get confirmedPercent => payoutsDone == 0
      ? 0
      : (min(payoutsConfirmed, payoutsDone) * 100 / payoutsDone).round();

  factory TrustStats.fromJson(Json? json) => TrustStats(
    payoutsDone: _int(json?['payoutsDone']),
    payoutsConfirmed: _int(json?['payoutsConfirmed']),
    payoutsDisputed: _int(json?['payoutsDisputed']),
  );
}

class Payout {
  const Payout({
    required this.pot,
    required this.beneficiaryId,
    required this.beneficiaryName,
    required this.amount,
    required this.paidAt,
    this.receivedAt,
    this.problem,
    this.method,
  });

  /// Mode de remise (null : remise enregistrée avant la version 2.1).
  final PaymentMethod? method;

  final int pot;
  final String beneficiaryId;
  final String beneficiaryName;
  final int amount;
  final DateTime paidAt;

  /// Réception confirmée par le bénéficiaire.
  final DateTime? receivedAt;

  /// Problème signalé par le bénéficiaire.
  final String? problem;

  bool get confirmed => receivedAt != null;

  /// Numéro du reçu de remise, propre au groupe et à la cagnotte.
  String receiptNumberIn(String groupId) => '${receiptCode(groupId)}-$pot';

  /// Remise pas encore confirmée par le bénéficiaire après [days] jours.
  bool unconfirmedSince(int days, [DateTime? now]) =>
      receivedAt == null &&
      (now ?? DateTime.now()).difference(paidAt).inDays >= days;

  factory Payout.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Payout(
      pot: _int(json['tour']),
      beneficiaryId: json['beneficiaryId'] as String? ?? '',
      beneficiaryName: json['beneficiaryName'] as String? ?? '',
      amount: _int(json['amount']),
      paidAt: _time(json['paidAt']),
      receivedAt: json['receivedAt'] is Timestamp
          ? (json['receivedAt'] as Timestamp).toDate()
          : null,
      problem: json['problem'] as String?,
      method: switch (json['method']) {
        'cash' => PaymentMethod.cash,
        'mobile_money' => PaymentMethod.mobileMoney,
        _ => null,
      },
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
    this.penalty = 0,
    this.method = PaymentMethod.mobileMoney,
    this.note,
    this.recordedByOwner = false,
    this.reference,
    this.proofHash,
  });

  /// Empreinte de la capture d'écran (unique : une même capture ne peut pas
  /// servir à deux paiements).
  final String? proofHash;

  /// Référence de la transaction Mobile Money (unique : une même référence
  /// ne peut pas servir à deux paiements).
  final String? reference;

  /// Pénalités de retard comprises dans [amount].
  final int penalty;
  final PaymentMethod method;
  final String? note;

  /// Encaissé directement par le tontinier (validé d'office).
  final bool recordedByOwner;

  bool get isCash => method == PaymentMethod.cash;

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

  /// Numéro du reçu : identifiant unique du paiement (CZ-XXXX-XXXX).
  String get receiptNumber => receiptCode(id);

  factory Payment.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Payment(
      id: doc.id,
      userId: json['userId'] as String,
      amount: _int(json['amount']),
      proofId: json['proofId'] as String? ?? '',
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
      penalty: _int(json['penalty']),
      method: json['method'] == 'cash'
          ? PaymentMethod.cash
          : PaymentMethod.mobileMoney,
      note: json['note'] as String?,
      recordedByOwner: json['recordedBy'] == 'owner',
      reference: json['reference'] as String?,
      proofHash: json['proofHash'] as String?,
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
    this.status = 'active',
    this.refundRequestedAt,
    this.closedAt,
    this.refundAmount = 0,
  });

  /// active, refund_requested (remboursement demandé) ou closed (clôturé).
  final String status;
  final DateTime? refundRequestedAt;
  final DateTime? closedAt;

  /// Montant rendu au client à la clôture.
  final int refundAmount;

  bool get isActive => status == 'active';
  bool get refundRequested => status == 'refund_requested';
  bool get isClosed => status == 'closed';

  /// Remboursement : les cases payées moins une (la commission).
  int get refundDue => max(0, approvedCases - 1) * caseAmount;

  /// Le client peut demander le remboursement avant la fin du carnet.
  bool get canRequestRefund =>
      isActive &&
      clientId != null &&
      approvedCases >= 1 &&
      !isComplete &&
      pendingCases == 0;

  /// Le tontinier peut rembourser (ou remettre le carnet complet) et clôturer.
  bool get canClose =>
      clientId != null &&
      pendingCases == 0 &&
      (refundRequested || (isActive && isComplete));

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
      status: json['status'] as String? ?? 'active',
      refundRequestedAt: json['refundRequestedAt'] is Timestamp
          ? (json['refundRequestedAt'] as Timestamp).toDate()
          : null,
      closedAt: json['closedAt'] is Timestamp
          ? (json['closedAt'] as Timestamp).toDate()
          : null,
      refundAmount: _int(json['refundAmount']),
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
/// Remise d'une cagnotte pas encore confirmée par son bénéficiaire.
class OpenPayout {
  const OpenPayout(this.group, this.payout);

  final Group group;
  final Payout payout;

  /// Bénéficiaire sans application : il ne peut pas confirmer lui-même.
  bool get managed => RegExp(r'^p\d+$').hasMatch(payout.beneficiaryId);
}

class OwnerOverview {
  const OwnerOverview({
    required this.tontineCount,
    required this.groups,
    required this.carnets,
    required this.pending,
    this.openPayouts = const [],
  });

  /// Remises non confirmées (ou contestées) par les bénéficiaires.
  final List<OpenPayout> openPayouts;

  /// Au moins un paiement validé (guide de démarrage).
  bool get hasApprovedPayment =>
      groups.any((g) => g.members.any((m) => m.approvedCount > 0)) ||
      carnets.any((c) => c.approvedCases > 0);

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
    this.payoutToConfirm,
  });

  final Group group;

  /// Cagnotte remise par le tontinier, à confirmer par le participant.
  final Payout? payoutToConfirm;

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

  /// Montant total à régulariser : cotisations en retard et pénalités.
  int get lateAmount => active.fold(
    0,
    (n, s) =>
        n +
        s.standing.late * s.group.contributionAmount +
        s.standing.penaltyDue,
  );

  /// Pénalités comprises dans [lateAmount].
  int get latePenalty => active.fold(0, (n, s) => n + s.standing.penaltyDue);

  /// Cagnottes en cours (nouvelle version).
  List<MemberGroupStatus> get active => groups
      .where((s) => !s.group.isLegacy && s.group.status == GroupStatus.active)
      .toList();
}

/// Numéro de paiement du tontinier (Mobile Money).
class PaymentAccount {
  const PaymentAccount({
    required this.operator,
    required this.number,
    this.holder = '',
  });

  final String operator;
  final String number;
  final String holder;

  Json toJson() => {'operator': operator, 'number': number, 'holder': holder};

  factory PaymentAccount.fromJson(Map<dynamic, dynamic> json) => PaymentAccount(
    operator: json['operator'] as String? ?? '',
    number: json['number'] as String? ?? '',
    holder: json['holder'] as String? ?? '',
  );
}

/// Profil pro du tontinier : affiché à ses clients, sur les reçus et les
/// relevés.
class Business {
  const Business({
    required this.ownerId,
    required this.name,
    this.city = '',
    this.contactPhone = '',
    this.logo,
    this.logoMime,
    this.accounts = const [],
  });

  final String ownerId;
  final String name;
  final String city;
  final String contactPhone;

  /// Logo compressé (base64).
  final String? logo;
  final String? logoMime;
  final List<PaymentAccount> accounts;

  factory Business.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Business(
      ownerId: doc.id,
      name: json['name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      contactPhone: json['contactPhone'] as String? ?? '',
      logo: json['logo'] as String?,
      logoMime: json['logoMime'] as String?,
      accounts: [
        for (final a in json['accounts'] as List? ?? const [])
          PaymentAccount.fromJson(a as Map),
      ],
    );
  }
}

/// Ligne du journal d'un groupe.
class GroupEvent {
  const GroupEvent({
    required this.type,
    required this.text,
    required this.actorName,
    required this.at,
  });

  final String type;
  final String text;
  final String actorName;
  final DateTime at;

  factory GroupEvent.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return GroupEvent(
      type: json['type'] as String? ?? '',
      text: json['text'] as String? ?? '',
      actorName: json['actorName'] as String? ?? '',
      at: _time(json['at']),
    );
  }
}

/// Conditions d'un groupe saisies par le tontinier (création, modification).
class GroupTerms {
  const GroupTerms({
    required this.name,
    required this.memberCount,
    required this.contributionAmount,
    required this.frequency,
    required this.startDate,
    required this.contributionsPerPot,
    required this.firstPayoutDate,
    required this.orderMode,
    required this.penaltyAmount,
    required this.penaltyGraceDays,
    required this.commissionType,
    required this.commissionValue,
    this.penaltyType = PenaltyType.fixed,
    this.rulesText = '',
  });

  final PenaltyType penaltyType;
  final String rulesText;
  final String name;
  final int memberCount;
  final int contributionAmount;
  final Frequency frequency;
  final DateTime startDate;
  final int contributionsPerPot;
  final DateTime firstPayoutDate;
  final OrderMode orderMode;
  final int penaltyAmount;
  final int penaltyGraceDays;
  final CommissionType commissionType;
  final double commissionValue;
}

/// Tableau de bord des gains du tontinier.
class Gains {
  const Gains({
    required this.collectedThisMonth,
    required this.commissionsEarned,
    required this.commissionsUpcoming,
    required this.penaltiesCollected,
    required this.lateAmount,
    required this.lateMembers,
    required this.upcomingPayouts,
    required this.activeGroups,
    required this.activeCarnets,
  });

  final int collectedThisMonth;
  final int commissionsEarned;
  final int commissionsUpcoming;
  final int penaltiesCollected;
  final int lateAmount;
  final int lateMembers;

  /// Remises des 7 prochains jours : (groupe, n°, date).
  final List<(Group, int, DateTime)> upcomingPayouts;
  final int activeGroups;
  final int activeCarnets;
}

/// Notification de la cloche : opération faite par un client (pour le
/// tontinier) ou par le tontinier (pour le client).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.at,
    required this.read,
    this.groupId,
    this.carnetId,
    this.actorName = '',
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime at;
  final bool read;
  final String? groupId;
  final String? carnetId;
  final String actorName;

  factory AppNotification.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return AppNotification(
      id: doc.id,
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      at: _time(json['at']),
      read: json['read'] == true,
      groupId: json['groupId'] as String?,
      carnetId: json['carnetId'] as String?,
      actorName: json['actorName'] as String? ?? '',
    );
  }
}
