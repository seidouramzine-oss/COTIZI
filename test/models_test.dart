import 'package:cotizi/format.dart';
import 'package:cotizi/models.dart';
import 'package:flutter_test/flutter_test.dart';

Group _group({
  int members = 10,
  int contribution = 5000,
  Frequency frequency = Frequency.monthly,
  DateTime? start,
  int perPot = 1,
  DateTime? firstPayout,
  CommissionType commissionType = CommissionType.percent,
  double commissionValue = 5,
  GroupStatus status = GroupStatus.active,
  int penalty = 0,
  int grace = 0,
  List<GroupMember> members_ = const [],
}) => Group(
  id: 'g',
  tontineId: 't',
  tontineName: 'Tontine',
  ownerId: 'o',
  ownerName: 'Tontinier',
  name: 'Groupe',
  memberCount: members,
  contributionAmount: contribution,
  frequency: frequency,
  startDate: start ?? DateTime(2026, 1, 31),
  contributionsPerPot: perPot,
  firstPayoutDate: firstPayout ?? start ?? DateTime(2026, 1, 31),
  orderMode: OrderMode.draw,
  penaltyAmount: penalty,
  penaltyGraceDays: grace,
  commissionType: commissionType,
  commissionValue: commissionValue,
  inviteCode: 'ABC123',
  status: status,
  members: members_,
);

GroupMember _member(
  String id, {
  int? pos,
  int declared = 0,
  int approved = 0,
}) => GroupMember(
  userId: id,
  drawPosition: pos,
  profile: Profile(fullName: id, phone: '+22901000000'),
  declaredCount: declared,
  approvedCount: approved,
);

void main() {
  group('Cagnotte', () {
    test('commission en pourcentage retenue sur la cagnotte', () {
      final g = _group();
      expect(g.grossPot, 50000);
      expect(g.commission, 2500);
      expect(g.netPot, 47500);
    });

    test('commission en montant fixe', () {
      final g = _group(
        commissionType: CommissionType.fixed,
        commissionValue: 1000,
      );
      expect(g.commission, 1000);
      expect(g.netPot, 49000);
    });

    test('dates des tours selon la fréquence', () {
      final start = DateTime(2026, 3, 2);
      expect(
        _group(frequency: Frequency.daily, start: start).tourDate(3),
        DateTime(2026, 3, 4),
      );
      expect(
        _group(frequency: Frequency.weekly, start: start).tourDate(2),
        DateTime(2026, 3, 9),
      );
      expect(
        _group(frequency: Frequency.biweekly, start: start).tourDate(2),
        DateTime(2026, 3, 16),
      );
    });

    test('cagnotte : 5 000 F par jour pendant 30 jours, 10 participants', () {
      final g = _group(
        frequency: Frequency.daily,
        start: DateTime(2026, 10, 7),
        perPot: 30,
        firstPayout: DateTime(2026, 11, 5),
      );
      expect(g.perMemberPerPot, 150000);
      expect(g.grossPot, 1500000);
      expect(g.netPot, 1425000);
      expect(g.totalContributions, 300);
      expect(g.collectStart(1), DateTime(2026, 10, 7));
      expect(g.collectEnd(1), DateTime(2026, 11, 5));
      expect(g.collectStart(2), DateTime(2026, 11, 6));
      expect(g.payoutDate(1), DateTime(2026, 11, 5));
      expect(g.payoutDate(2), DateTime(2026, 12, 5));
    });

    test('cotisations dues à une date (jour, semaine, mois)', () {
      final daily = _group(
        frequency: Frequency.daily,
        start: DateTime(2026, 10, 7),
        perPot: 30,
      );
      expect(daily.dueCount(DateTime(2026, 10, 6, 23)), 0);
      expect(daily.dueCount(DateTime(2026, 10, 7, 8)), 1);
      expect(daily.dueCount(DateTime(2026, 10, 18, 20)), 12);
      expect(daily.dueCount(DateTime(2030, 1, 1)), 300);
      final weekly = _group(
        frequency: Frequency.weekly,
        start: DateTime(2026, 10, 7),
        perPot: 4,
      );
      expect(weekly.dueCount(DateTime(2026, 10, 20)), 2);
      final monthly = _group(start: DateTime(2026, 1, 31), perPot: 1);
      expect(monthly.dueCount(DateTime(2026, 3, 30)), 2);
      expect(monthly.dueCount(DateTime(2026, 3, 31)), 3);
    });

    test('« vous êtes à jour », retard, avance et attente', () {
      final today = DateTime(2026, 10, 18);
      final g = _group(
        frequency: Frequency.daily,
        start: DateTime(2026, 10, 7),
        perPot: 30,
      );
      final late = g.standingOf(_member('a', declared: 9, approved: 9), today);
      expect(late.due, 12);
      expect(late.late, 3);
      expect(late.upToDate, isFalse);
      final ok = g.standingOf(_member('b', declared: 14, approved: 10), today);
      expect(ok.upToDate, isTrue);
      expect(ok.pending, 4);
      expect(ok.ahead, 2);
      expect(ok.remaining, 286);
      final waiting = _group(
        frequency: Frequency.daily,
        start: DateTime(2026, 10, 7),
        status: GroupStatus.recruiting,
      );
      expect(waiting.standingOf(_member('c'), today).upToDate, isTrue);
    });

    test('montant collecté pour la cagnotte en cours', () {
      final g = _group(
        members: 3,
        contribution: 1000,
        frequency: Frequency.daily,
        start: DateTime(2026, 10, 7),
        perPot: 5,
        members_: [
          _member('a', pos: 1, declared: 7, approved: 6),
          _member('b', pos: 2, declared: 3, approved: 3),
          _member('c', pos: 3),
        ],
      );
      expect(g.collectedFor(1), (5 + 3) * 1000);
      expect(g.collectedFor(1, withPending: true), (5 + 3) * 1000);
      expect(g.collectedFor(2), 1 * 1000);
      expect(g.collectedFor(2, withPending: true), 2 * 1000);
      expect(g.beneficiaryOf(2)?.userId, 'b');
    });

    test('tours mensuels : le 31 devient le dernier jour du mois', () {
      final g = _group(start: DateTime(2026, 1, 31));
      expect(g.tourDate(1), DateTime(2026, 1, 31));
      expect(g.tourDate(2), DateTime(2026, 2, 28));
      expect(g.tourDate(3), DateTime(2026, 3, 31));
      expect(g.tourDate(4), DateTime(2026, 4, 30));
      expect(g.tourDate(13), DateTime(2027, 1, 31));
    });
  });

  group('Carnet', () {
    Carnet carnet({int used = 0, int approved = 0}) => Carnet(
      id: 'c',
      tontineId: 't',
      tontineName: 'Carnets',
      ownerId: 'o',
      ownerName: 'Tontinier',
      label: 'Carnet n°1',
      caseAmount: 500,
      caseCount: 31,
      clientId: 'u',
      client: const Profile(fullName: 'Client', phone: '+22901000000'),
      inviteCode: 'XYZ789',
      usedCases: used,
      approvedCases: approved,
    );

    test('le client reçoit 30 cases, la 31e est la commission', () {
      expect(carnet().clientPayout, 15000);
    });

    test('cases validées, en attente et restantes', () {
      final c = carnet(used: 13, approved: 10);
      expect(c.pendingCases, 3);
      expect(c.remainingCases, 18);
      expect(c.isComplete, isFalse);
      expect(carnet(used: 31, approved: 31).isComplete, isTrue);
    });
  });

  group('Téléphone', () {
    test('ajoute l\'indicatif et ignore les espaces', () {
      expect(normalizePhone('+229', '01 97 12 34 56'), '+2290197123456');
    });

    test('garde un indicatif saisi avec + ou 00', () {
      expect(normalizePhone('+229', '+228 90 12 34 56'), '+22890123456');
      expect(normalizePhone('+229', '0022890123456'), '+22890123456');
    });

    test('validation du format international', () {
      expect(isValidPhone('+2290197123456'), isTrue);
      expect(isValidPhone('+229'), isFalse);
    });

    test('montant saisi avec espaces', () {
      expect(parseAmount('25 000'), 25000);
      expect(parseAmount(''), isNull);
    });
  });

  group('Abonnement', () {
    final now = DateTime(2026, 10, 7, 12);
    Profile tontinier({
      DateTime? created,
      DateTime? end,
      Role role = Role.tontinier,
    }) => Profile(
      fullName: 'T',
      phone: '+22901000000',
      role: role,
      createdAt: created,
      subscriptionEnd: end,
    );

    test('essai gratuit de 30 jours après l\'inscription', () {
      final p = tontinier(created: DateTime(2026, 9, 20, 12));
      expect(p.isTrial, isTrue);
      expect(p.accessEnd, DateTime(2026, 10, 20, 12));
      expect(p.canCreateAt(now), isTrue);
      expect(p.daysLeft(now), 13);
    });

    test('essai terminé', () {
      final p = tontinier(created: DateTime(2026, 9, 1));
      expect(p.canCreateAt(now), isFalse);
      expect(p.daysLeft(now), isNegative);
    });

    test('la date fixée par l\'administrateur remplace l\'essai', () {
      final paid = tontinier(
        created: DateTime(2026, 1, 1),
        end: DateTime(2026, 12, 31),
      );
      expect(paid.isTrial, isFalse);
      expect(paid.canCreateAt(now), isTrue);
      final stopped = tontinier(created: DateTime(2026, 10, 1), end: now);
      expect(stopped.canCreateAt(now), isFalse);
    });

    test('un client ne crée jamais, un ancien compte sans date non plus', () {
      expect(
        tontinier(created: now, role: Role.membre).canCreateAt(now),
        isFalse,
      );
      expect(tontinier().canCreateAt(now), isFalse);
    });

    test('ajout de mois : le 31 devient le dernier jour du mois', () {
      expect(addMonths(DateTime(2026, 1, 31, 9), 1), DateTime(2026, 2, 28, 9));
      expect(addMonths(DateTime(2026, 10, 7), 12), DateTime(2027, 10, 7));
    });
  });

  group('Version 2', () {
    test('dates de début et de fin de la tontine', () {
      final g = _group(
        members: 10,
        frequency: Frequency.daily,
        start: DateTime(2026, 11, 1),
        perPot: 30,
        firstPayout: DateTime(2026, 11, 30),
      );
      expect(g.startDate, DateTime(2026, 11, 1));
      expect(g.endDate, DateTime(2027, 8, 27));
    });

    test('pénalités : au-delà des jours de tolérance', () {
      final g = _group(
        frequency: Frequency.daily,
        start: DateTime(2026, 10, 1),
        perPot: 30,
        penalty: 500,
        grace: 2,
      );
      final today = DateTime(2026, 10, 10, 15);
      // Cotisations du 1 au 7 octobre : plus de 2 jours de retard
      expect(g.penaltyFor(1, 7, today), 7 * 500);
      // 8 octobre (2 jours) et 9, 10 octobre : dans la tolérance
      expect(g.penaltyFor(8, 3, today), 0);
      expect(g.penaltyFor(6, 4, today), 2 * 500);
      final s = g.standingOf(
        GroupMember(
          userId: 'a',
          drawPosition: 1,
          profile: const Profile(fullName: 'A', phone: '+22901000000'),
          declaredCount: 5,
          approvedCount: 5,
        ),
        today,
      );
      expect(s.late, 5);
      expect(s.penaltyDue, 2 * 500);
    });

    test('sans pénalité : rien à payer en plus', () {
      final g = _group(
        frequency: Frequency.daily,
        start: DateTime(2026, 10, 1),
      );
      expect(g.penaltyFor(1, 5, DateTime(2026, 12, 1)), 0);
    });

    test('place reprise : paiements des deux identifiants', () {
      const m = GroupMember(
        userId: 'uid1',
        drawPosition: 2,
        profile: Profile(fullName: 'Zoé', phone: '+22997000099'),
        claimedFrom: 'p22997000099',
      );
      expect(m.paymentIds, ['uid1', 'p22997000099']);
    });
  });
}
