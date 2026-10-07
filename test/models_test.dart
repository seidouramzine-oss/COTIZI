import 'package:cotizi/format.dart';
import 'package:cotizi/models.dart';
import 'package:flutter_test/flutter_test.dart';

Group _group({
  int members = 10,
  int contribution = 5000,
  Frequency frequency = Frequency.monthly,
  DateTime? start,
  CommissionType commissionType = CommissionType.percent,
  double commissionValue = 5,
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
  commissionType: commissionType,
  commissionValue: commissionValue,
  inviteCode: 'ABC123',
  status: GroupStatus.active,
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

    test(
      'tours à payer : passés sans paiement, refus à refaire, puis le prochain',
      () {
        final g = _group(
          members: 5,
          frequency: Frequency.weekly,
          start: DateTime(2026, 10, 1),
        );
        Payment pay(int tour, PaymentStatus status, [String user = 'u']) =>
            Payment(
              id: '${user}_$tour',
              userId: user,
              amount: 5000,
              proofId: 'p',
              status: status,
              rejectionReason: null,
              declaredAt: DateTime(2026, 10, 1),
              payer: const Profile(fullName: 'U', phone: '+229'),
              tourNumber: tour,
            );
        // Tours : 1/10, 8/10, 15/10, 22/10, 29/10 ; on est le 15/10
        final (due, next) = g.unpaidTours('u', [
          pay(1, PaymentStatus.approved),
          pay(2, PaymentStatus.rejected),
          pay(3, PaymentStatus.approved, 'autre'),
        ], DateTime(2026, 10, 15, 18));
        expect(due, [2, 3]);
        expect(next, 4);

        final (allPaid, upcoming) = g.unpaidTours('u', [
          pay(1, PaymentStatus.approved),
          pay(2, PaymentStatus.pending),
          pay(3, PaymentStatus.pending),
        ], DateTime(2026, 10, 15));
        expect(allPaid, isEmpty);
        expect(upcoming, 4);
      },
    );

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
}
