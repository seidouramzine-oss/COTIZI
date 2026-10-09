import 'dart:typed_data';

import 'package:cotizi/api.dart';
import 'package:cotizi/format.dart';
import 'package:cotizi/models.dart';
import 'package:cotizi/reminders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

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
      expect(p.isProAt(now), isTrue);
      expect(p.daysLeft(now), 13);
    });

    test('essai terminé : plan Gratuit, il crée toujours', () {
      final p = tontinier(created: DateTime(2026, 9, 1));
      expect(p.isProAt(now), isFalse);
      expect(p.canCreateAt(now), isTrue);
      expect(p.daysLeft(now), isNegative);
    });

    test('la date fixée par l\'administrateur remplace l\'essai', () {
      final paid = tontinier(
        created: DateTime(2026, 1, 1),
        end: DateTime(2026, 12, 31),
      );
      expect(paid.isTrial, isFalse);
      expect(paid.isProAt(now), isTrue);
      final stopped = tontinier(created: DateTime(2026, 10, 1), end: now);
      expect(stopped.isProAt(now), isFalse);
      expect(stopped.canCreateAt(now), isTrue);
    });

    test('un client ne crée jamais et n\'est jamais Pro', () {
      final c = tontinier(created: now, role: Role.membre);
      expect(c.canCreateAt(now), isFalse);
      expect(c.isProAt(now), isFalse);
      expect(tontinier().isProAt(now), isFalse);
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

  group('Version 2.1 : remise seulement quand la collecte est complète', () {
    // 3 participants, 2 cotisations de 1 000 F par cagnotte
    Group g(List<GroupMember> m) => _group(
      members: 3,
      contribution: 1000,
      frequency: Frequency.daily,
      start: DateTime(2026, 10, 1),
      perPot: 2,
      firstPayout: DateTime(2026, 10, 2),
      members_: m,
    );

    test('collecte incomplète : il manque des cotisations', () {
      final grp = g([
        _member('a', pos: 1, declared: 2, approved: 2),
        _member('b', pos: 2, declared: 2, approved: 1),
        _member('c', pos: 3),
      ]);
      expect(grp.isPotComplete(1), isFalse);
      expect(grp.missingFor(1), 3000);
      final short = grp.shortfallsFor(1);
      expect(short.map((f) => f.member.userId), ['c', 'b']);
      expect(short.first.missing, 2);
      expect(short.first.amount, 2000);
      expect(short.last.pending, 1);
    });

    test('collecte complète : remise possible', () {
      final grp = g([
        _member('a', pos: 1, declared: 4, approved: 4),
        _member('b', pos: 2, declared: 2, approved: 2),
        _member('c', pos: 3, declared: 2, approved: 2),
      ]);
      expect(grp.isPotComplete(1), isTrue);
      expect(grp.shortfallsFor(1), isEmpty);
      // Cagnotte 2 : seul A a payé d'avance
      expect(grp.isPotComplete(2), isFalse);
      expect(grp.missingFor(2), 4000);
    });
  });

  group('Rappels', () {
    setUpAll(() => initializeDateFormatting('fr'));
    final g = _group(
      members: 2,
      contribution: 1000,
      frequency: Frequency.daily,
      start: DateTime(2026, 10, 1),
      perPot: 30,
      firstPayout: DateTime(2026, 10, 30),
      members_: [
        _member('me', pos: 1, declared: 5, approved: 5),
        _member('b', pos: 2),
      ],
    );
    final status = MemberGroupStatus(
      group: g,
      payments: const [],
      standing: g.standingOf(g.members.first, DateTime(2026, 10, 7)),
    );

    test('la veille de chaque cotisation à payer, avec le retard', () {
      final plan = planReminders(
        member: [status],
        now: DateTime(2026, 10, 7, 10),
      );
      // 2 cotisations en retard (6 et 7 oct.) : rappel le lendemain à 9 h
      final late = plan.firstWhere((r) => r.title.contains('en retard'));
      expect(late.at, DateTime(2026, 10, 8, 9));
      expect(late.body, contains('2 cotisations en retard'));
      // Cotisation du 8 oct. : rappel le 7 à 18 h
      final eve = plan.firstWhere(
        (r) => r.title.startsWith('Cotisation demain'),
      );
      expect(eve.at, DateTime(2026, 10, 7, 18));
      expect(eve.body, contains('aussi 2 cotisations en retard'));
      expect(
        plan.where((r) => r.title.startsWith('Cotisation demain')).length,
        10,
      );
    });

    test('le tontinier : matin de chaque remise', () {
      final plan = planReminders(owned: [g], now: DateTime(2026, 10, 7));
      expect(plan.map((r) => r.at), [
        DateTime(2026, 10, 30, 8),
        DateTime(2026, 11, 29, 8),
      ]);
      expect(plan.first.body, contains('collecte est complète'));
    });
  });

  group('Version 2.2', () {
    test('pénalité en pourcentage du montant dû, après 2 jours', () {
      final g = Group(
        id: 'g',
        tontineId: 't',
        tontineName: 'T',
        ownerId: 'o',
        ownerName: 'O',
        name: 'G',
        memberCount: 3,
        contributionAmount: 5000,
        frequency: Frequency.daily,
        startDate: DateTime(2026, 10, 1),
        contributionsPerPot: 10,
        firstPayoutDate: DateTime(2026, 10, 10),
        orderMode: OrderMode.draw,
        penaltyType: PenaltyType.percent,
        penaltyAmount: 10,
        penaltyGraceDays: 2,
        commissionType: CommissionType.percent,
        commissionValue: 0,
        inviteCode: 'ABC234',
        status: GroupStatus.active,
      );
      expect(g.penaltyPerContribution, 500);
      // Le 5 oct. : cotisations des 1er et 2 oct. en retard de plus de 2 jours
      expect(g.penaltyFor(1, 5, DateTime(2026, 10, 5)), 1000);
      expect(g.penaltyFor(3, 1, DateTime(2026, 10, 5)), 0);
    });

    test('retards de la cagnotte : seulement les cotisations déjà dues', () {
      final g = _group(
        members: 3,
        contribution: 5000,
        frequency: Frequency.daily,
        start: DateTime(2026, 10, 1),
        perPot: 30,
        firstPayout: DateTime(2026, 10, 30),
        members_: [
          _member('a', pos: 1, declared: 5, approved: 5),
          _member('b', pos: 2, declared: 4, approved: 4),
          _member('c', pos: 3),
        ],
      );
      final today = DateTime(2026, 10, 5); // 5 cotisations dues
      expect(g.isPotComplete(1), isFalse);
      final late = g.lateFor(1, today);
      expect(late.map((f) => f.member.userId), ['c', 'b']);
      expect(late.first.late, 5);
      expect(late.last.late, 1);
    });
  });

  group('Version 2.4 anti-fraude', () {
    test('référence Mobile Money normalisée', () {
      expect(Api.normalizeReference(' mp240101.1234 a56 '), 'MP240101.1234A56');
      expect(Api.normalizeReference('ab'), isNull);
      expect(Api.normalizeReference('MP#12345'), isNull);
      expect(Api.normalizeReference(null), isNull);
    });

    test('empreinte de capture : identique pour la même image', () {
      final a = Api.proofHash(Uint8List.fromList([1, 2, 3]));
      expect(a, Api.proofHash(Uint8List.fromList([1, 2, 3])));
      expect(a, isNot(Api.proofHash(Uint8List.fromList([1, 2, 4]))));
      expect(RegExp(r'^IMG[0-9A-F]{32}$').hasMatch(a), isTrue);
    });

    test('numéros de reçu', () {
      expect(receiptCode('abcd1234xyz'), 'CZ-ABCD-1234');
      expect(receiptCode('ab'), 'CZ-AB00-0000');
    });

    test('note de confiance', () {
      expect(const TrustStats().isNew, isTrue);
      const t = TrustStats(payoutsDone: 4, payoutsConfirmed: 3);
      expect(t.confirmedPercent, 75);
      // Confirmations d'anciennes remises : jamais plus de 100 %
      const old = TrustStats(payoutsDone: 1, payoutsConfirmed: 3);
      expect(old.confirmedPercent, 100);
    });

    test('remise non confirmée après 2 jours', () {
      final p = Payout(
        pot: 1,
        beneficiaryId: 'a',
        beneficiaryName: 'Awa',
        amount: 1000,
        paidAt: DateTime(2026, 10, 1, 10),
      );
      expect(p.unconfirmedSince(2, DateTime(2026, 10, 2, 12)), isFalse);
      expect(p.unconfirmedSince(2, DateTime(2026, 10, 3, 11)), isTrue);
    });
  });

  group('Version 2.5 remboursement du carnet', () {
    Carnet carnet(int approved, {int used = -1, String status = 'active'}) =>
        Carnet(
          id: 'c',
          tontineId: 't',
          tontineName: 'Carnets',
          ownerId: 'o',
          ownerName: 'Tontinier',
          label: 'Carnet n°1',
          caseAmount: 300,
          caseCount: 31,
          clientId: 'a',
          client: const Profile(fullName: 'Awa', phone: '+229'),
          inviteCode: 'ABC234',
          usedCases: used < 0 ? approved : used,
          approvedCases: approved,
          status: status,
        );

    test('20 cases payées : 19 rendues', () {
      final c = carnet(20);
      expect(c.refundDue, 19 * 300);
      expect(c.canRequestRefund, isTrue);
      expect(c.canClose, isFalse);
    });

    test('paiement en attente : demande impossible', () {
      expect(carnet(20, used: 21).canRequestRefund, isFalse);
    });

    test('demande faite : le tontinier peut clôturer', () {
      final c = carnet(20, status: 'refund_requested');
      expect(c.canRequestRefund, isFalse);
      expect(c.canClose, isTrue);
    });

    test('carnet complet : 30 cases rendues, clôture possible', () {
      final c = carnet(31);
      expect(c.refundDue, 30 * 300);
      expect(c.canRequestRefund, isFalse);
      expect(c.canClose, isTrue);
      expect(carnet(31, status: 'closed').canClose, isFalse);
    });
  });

  group('Version 3.0 plans', () {
    test(
      'utilisation du plan Gratuit : groupes, carnets et clients en cours',
      () {
        final g = _group(members: 5);
        final c = Carnet(
          id: 'c',
          tontineId: 't',
          tontineName: 'Carnets',
          ownerId: 'o',
          ownerName: 'T',
          label: 'Carnet',
          caseAmount: 300,
          caseCount: 31,
          clientId: 'a',
          client: const Profile(fullName: 'A', phone: '+229'),
          inviteCode: 'ABC234',
          usedCases: 0,
          approvedCases: 0,
        );
        final closed = Carnet(
          id: 'd',
          tontineId: 't',
          tontineName: 'Carnets',
          ownerId: 'o',
          ownerName: 'T',
          label: 'Carnet 2',
          caseAmount: 300,
          caseCount: 31,
          clientId: 'b',
          client: const Profile(fullName: 'B', phone: '+229'),
          inviteCode: 'ABC235',
          usedCases: 31,
          approvedCases: 31,
          status: 'closed',
        );
        final u = PlanUsage.of([g], [c, closed]);
        expect(u.groups, 1);
        expect(u.carnets, 1);
        expect(u.clients, 6);
      },
    );

    test('limites par défaut du plan Gratuit', () {
      const s = SubscriptionSettings();
      expect(s.freeGroups, 2);
      expect(s.freeCarnets, 3);
      expect(s.freeClients, 30);
      final custom = SubscriptionSettings.fromJson({
        'freeGroups': 5,
        'businessPrice': 15000,
      });
      expect(custom.freeGroups, 5);
      expect(custom.businessPrice, 15000);
    });
  });
}
