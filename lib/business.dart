import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'api.dart';
import 'models.dart';
import 'pro.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

DateTime _time(Object? v) => v is Timestamp ? v.toDate() : DateTime.now();

/// Mois au format « 2026-10 » (identifiant des salaires).
String monthKey(DateTime m) =>
    '${m.year}-${m.month.toString().padLeft(2, '0')}';

/// Entreprise de tontine (plan Business).
class Company {
  const Company({
    required this.bossId,
    required this.name,
    required this.city,
    required this.phone,
    required this.inviteCode,
  });

  final String bossId;
  final String name;
  final String city;
  final String phone;
  final String inviteCode;

  factory Company.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Company(
      bossId: doc.id,
      name: json['name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      inviteCode: json['inviteCode'] as String? ?? '',
    );
  }
}

/// Tontinier de l'équipe et son salaire.
class Agent {
  const Agent({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.salaryType,
    required this.fixed,
    required this.percent,
    required this.joinedAt,
  });

  final String id;
  final String fullName;
  final String phone;

  /// none, fixed, commission ou mixed
  final String salaryType;

  /// Salaire fixe par mois.
  final int fixed;

  /// Part des commissions gagnées par l'agent (en %).
  final double percent;
  final DateTime joinedAt;

  static const salaryTypes = {
    'none': 'Pas encore réglé',
    'fixed': 'Salaire fixe',
    'commission': 'Commission',
    'mixed': 'Fixe + commission',
  };

  String get salaryLabel {
    final p = percent == percent.roundToDouble()
        ? '${percent.round()}'
        : percent.toStringAsFixed(1);
    return switch (salaryType) {
      'fixed' => 'Fixe : $fixed F / mois',
      'commission' => '$p % des commissions',
      'mixed' => '$fixed F + $p % des commissions',
      _ => 'Salaire pas encore réglé',
    };
  }

  /// Salaire du mois : (fixe, part des commissions).
  (int, int) salaryFor(int commissions) {
    final f = salaryType == 'fixed' || salaryType == 'mixed' ? fixed : 0;
    final c = salaryType == 'commission' || salaryType == 'mixed'
        ? (commissions * percent / 100).round()
        : 0;
    return (f, c);
  }

  factory Agent.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Agent(
      id: doc.id,
      fullName: json['fullName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      salaryType: json['salaryType'] as String? ?? 'none',
      fixed: _int(json['fixed']),
      percent: (json['percent'] as num?)?.toDouble() ?? 0,
      joinedAt: _time(json['joinedAt']),
    );
  }
}

/// Salaire payé à un agent pour un mois.
class Salary {
  const Salary({
    required this.agentId,
    required this.agentName,
    required this.month,
    required this.fixed,
    required this.commission,
    required this.amount,
    required this.paidAt,
  });

  final String agentId;
  final String agentName;

  /// « 2026-10 »
  final String month;
  final int fixed;
  final int commission;
  final int amount;
  final DateTime paidAt;

  DateTime get monthDate {
    final p = month.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]));
  }

  factory Salary.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Salary(
      agentId: json['agentId'] as String? ?? '',
      agentName: json['agentName'] as String? ?? '',
      month: json['month'] as String? ?? '',
      fixed: _int(json['fixed']),
      commission: _int(json['commission']),
      amount: _int(json['amount']),
      paidAt: _time(json['paidAt']),
    );
  }
}

/// Activité d'un agent pour un mois, et son salaire.
class AgentReport {
  const AgentReport({
    required this.agent,
    required this.month,
    required this.stats,
    this.paid,
  });

  final Agent agent;
  final Accounting month;
  final ProStats stats;

  /// Salaire déjà payé pour ce mois.
  final Salary? paid;

  (int, int) get salary => agent.salaryFor(month.commissions);

  int get salaryTotal => salary.$1 + salary.$2;
}

/// Tableau de bord de l'entreprise pour un mois.
class CompanyMonth {
  const CompanyMonth(this.month, this.reports);

  final DateTime month;
  final List<AgentReport> reports;

  int get received => reports.fold(0, (n, r) => n + r.month.received);
  int get commissions => reports.fold(0, (n, r) => n + r.month.commissions);
  int get penalties => reports.fold(0, (n, r) => n + r.month.penalties);
  int get clients => reports.fold(0, (n, r) => n + r.stats.clients);

  /// Salaires du mois (payés, sinon calculés).
  int get salaries =>
      reports.fold(0, (n, r) => n + (r.paid?.amount ?? r.salaryTotal));

  /// Ce que gagne l'entreprise : commissions et pénalités moins salaires.
  int get profit => commissions + penalties - salaries;
}

/// Fonctions du plan Business : entreprise, équipe, salaires.
class BusinessApi {
  BusinessApi._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String get _uid => Api.uid;
  static FieldValue get _now => FieldValue.serverTimestamp();

  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static String _code() {
    final r = Random.secure();
    return List.generate(
      6,
      (_) => _alphabet[r.nextInt(_alphabet.length)],
    ).join();
  }

  // ------------------------------------------------------------ Patron

  static Future<Company?> myCompany() async {
    final doc = await _db.doc('companies/$_uid').get();
    return doc.exists ? Company.fromDoc(doc) : null;
  }

  /// Crée l'entreprise (ou change ses informations) avec un code
  /// d'invitation pour l'équipe.
  static Future<Company> saveCompany({
    required String name,
    required String city,
    required String phone,
    bool newCode = false,
  }) async {
    if (name.trim().length < 2) {
      throw const AppException('Écrivez le nom de votre entreprise.');
    }
    final current = await myCompany();
    var code = current?.inviteCode ?? '';
    final batch = _db.batch();
    if (current == null || newCode) {
      do {
        code = _code();
      } while ((await _db.doc('companyCodes/$code').get()).exists);
      batch.set(_db.doc('companyCodes/$code'), {'bossId': _uid});
      if (current != null) {
        batch.delete(_db.doc('companyCodes/${current.inviteCode}'));
      }
    }
    batch.set(_db.doc('companies/$_uid'), {
      'name': name.trim(),
      'city': city.trim(),
      'phone': phone.trim(),
      'inviteCode': code,
      'updatedAt': _now,
    });
    await batch.commit();
    return Company(
      bossId: _uid,
      name: name.trim(),
      city: city.trim(),
      phone: phone.trim(),
      inviteCode: code,
    );
  }

  static Future<List<Agent>> agents() async {
    final snap = await _db.collection('companies/$_uid/agents').get();
    return snap.docs.map(Agent.fromDoc).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  static Future<List<Salary>> salaries() async {
    final snap = await _db.collection('companies/$_uid/salaries').get();
    return snap.docs.map(Salary.fromDoc).toList()
      ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
  }

  /// Activité de toute l'équipe pour un mois.
  static Future<CompanyMonth> month(DateTime month) async {
    final results = await Future.wait([agents(), salaries()]);
    final team = results[0] as List<Agent>;
    final paid = results[1] as List<Salary>;
    final key = monthKey(month);
    final data = await Future.wait([
      for (final a in team) ProApi.load(ownerId: a.id),
    ]);
    return CompanyMonth(month, [
      for (var i = 0; i < team.length; i++)
        AgentReport(
          agent: team[i],
          month: data[i].month(month),
          stats: ProStats.of(data[i]),
          paid: paid
              .where((s) => s.agentId == team[i].id && s.month == key)
              .firstOrNull,
        ),
    ]);
  }

  static Future<void> setSalary(
    Agent a, {
    required String type,
    required int fixed,
    required double percent,
  }) async {
    if (fixed < 0 || percent < 0 || percent > 100) {
      throw const AppException('Montant ou pourcentage invalide.');
    }
    await _db.doc('companies/$_uid/agents/${a.id}').update({
      'salaryType': type,
      'fixed': type == 'fixed' || type == 'mixed' ? fixed : 0,
      'percent': type == 'commission' || type == 'mixed' ? percent : 0,
    });
  }

  /// Le patron note le salaire du mois comme payé.
  static Future<void> paySalary(AgentReport r) async {
    final (fixed, commission) = r.salary;
    if (fixed + commission <= 0) {
      throw const AppException(
        'Le salaire de ce mois est de 0 F. Réglez d\'abord son salaire.',
      );
    }
    final key = monthKey(r.month.month);
    await _db.doc('companies/$_uid/salaries/${r.agent.id}_$key').set({
      'agentId': r.agent.id,
      'agentName': r.agent.fullName,
      'month': key,
      'fixed': fixed,
      'commission': commission,
      'amount': fixed + commission,
      'paidAt': _now,
    });
  }

  static Future<void> removeAgent(Agent a) async {
    final batch = _db.batch()
      ..delete(_db.doc('companies/$_uid/agents/${a.id}'))
      ..delete(_db.doc('agentOf/${a.id}'));
    await batch.commit();
  }

  // ------------------------------------------------------------- Agent

  /// Entreprise du tontinier connecté (s'il est agent) et sa fiche.
  static Future<(Company, Agent)?> myEmployer() async {
    final link = await _db.doc('agentOf/$_uid').get();
    if (!link.exists) return null;
    final bossId = link['bossId'] as String;
    final results = await Future.wait([
      _db.doc('companies/$bossId').get(),
      _db.doc('companies/$bossId/agents/$_uid').get(),
    ]);
    if (!results[0].exists || !results[1].exists) return null;
    return (Company.fromDoc(results[0]), Agent.fromDoc(results[1]));
  }

  static Future<List<Salary>> mySalaries(String bossId) async {
    final snap = await _db
        .collection('companies/$bossId/salaries')
        .where('agentId', isEqualTo: _uid)
        .get();
    return snap.docs.map(Salary.fromDoc).toList()
      ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
  }

  /// Rejoint l'équipe d'une entreprise avec son code.
  static Future<Company> join(String input) async {
    final code = input.trim().toUpperCase();
    final link = await _db.doc('companyCodes/$code').get();
    if (!link.exists) {
      throw const AppException('Code d\'entreprise introuvable.');
    }
    final bossId = link['bossId'] as String;
    if (bossId == _uid) {
      throw const AppException('C\'est le code de votre propre entreprise.');
    }
    if ((await _db.doc('agentOf/$_uid').get()).exists) {
      throw const AppException(
        'Vous êtes déjà dans une entreprise. Quittez-la d\'abord.',
      );
    }
    final me = await Api.myProfile();
    if (me == null) throw const AppException('Profil introuvable.');
    final batch = _db.batch()
      ..set(_db.doc('companies/$bossId/agents/$_uid'), {
        'fullName': me.fullName,
        'phone': me.phone,
        'code': code,
        'salaryType': 'none',
        'fixed': 0,
        'percent': 0,
        'joinedAt': _now,
      })
      ..set(_db.doc('agentOf/$_uid'), {'bossId': bossId, 'joinedAt': _now});
    await batch.commit();
    final company = await _db.doc('companies/$bossId').get();
    return Company.fromDoc(company);
  }

  static Future<void> leave(String bossId) async {
    final batch = _db.batch()
      ..delete(_db.doc('companies/$bossId/agents/$_uid'))
      ..delete(_db.doc('agentOf/$_uid'));
    await batch.commit();
  }
}
