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
}
