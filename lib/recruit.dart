import 'package:cloud_firestore/cloud_firestore.dart';

import 'api.dart';
import 'business.dart';
import 'models.dart';

DateTime _time(Object? v) => v is Timestamp ? v.toDate() : DateTime.now();

/// Offre d'emploi d'une entreprise (plan Business).
class Job {
  const Job({
    required this.id,
    required this.bossId,
    required this.companyName,
    required this.title,
    required this.city,
    required this.salary,
    required this.description,
    required this.open,
    required this.createdAt,
  });

  final String id;
  final String bossId;
  final String companyName;
  final String title;
  final String city;
  final String salary;
  final String description;
  final bool open;
  final DateTime createdAt;

  factory Job.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Job(
      id: doc.id,
      bossId: json['bossId'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      city: json['city'] as String? ?? '',
      salary: json['salary'] as String? ?? '',
      description: json['description'] as String? ?? '',
      open: json['status'] == 'open',
      createdAt: _time(json['createdAt']),
    );
  }
}

/// Candidature d'un tontinier Pro à une offre.
class JobApplication {
  const JobApplication({
    required this.id,
    required this.jobId,
    required this.jobTitle,
    required this.bossId,
    required this.companyName,
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String jobId;
  final String jobTitle;
  final String bossId;
  final String companyName;
  final String userId;
  final String fullName;
  final String phone;
  final String message;

  /// sent, accepted ou rejected
  final String status;
  final DateTime createdAt;

  String get statusLabel => switch (status) {
    'accepted' => 'Acceptée',
    'rejected' => 'Non retenue',
    _ => 'Envoyée',
  };

  factory JobApplication.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return JobApplication(
      id: doc.id,
      jobId: json['jobId'] as String? ?? '',
      jobTitle: json['jobTitle'] as String? ?? '',
      bossId: json['bossId'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      message: json['message'] as String? ?? '',
      status: json['status'] as String? ?? 'sent',
      createdAt: _time(json['createdAt']),
    );
  }
}

/// Espace recrutement : offres des entreprises, candidatures des tontiniers
/// Pro.
class RecruitApi {
  RecruitApi._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String get _uid => Api.uid;
  static FieldValue get _now => FieldValue.serverTimestamp();

  /// Offres ouvertes (tontiniers Pro), les plus récentes d'abord.
  static Future<List<Job>> openJobs() async {
    final snap = await _db
        .collection('jobs')
        .where('status', isEqualTo: 'open')
        .get();
    return snap.docs.map(Job.fromDoc).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<List<JobApplication>> myApplications() async {
    final snap = await _db
        .collection('applications')
        .where('userId', isEqualTo: _uid)
        .get();
    return snap.docs.map(JobApplication.fromDoc).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> apply(Job job, String message) async {
    final me = await Api.myProfile();
    if (me == null) throw const AppException('Profil introuvable.');
    if (job.bossId == _uid) {
      throw const AppException('C\'est votre propre offre.');
    }
    await _db.doc('applications/${job.id}_$_uid').set({
      'jobId': job.id,
      'jobTitle': job.title,
      'bossId': job.bossId,
      'companyName': job.companyName,
      'userId': _uid,
      'fullName': me.fullName,
      'phone': me.phone,
      'message': message.trim(),
      'status': 'sent',
      'createdAt': _now,
    });
  }

  static Future<void> withdraw(JobApplication a) =>
      _db.doc('applications/${a.id}').delete();

  // ---------------------------------------------------------- Entreprise

  static Future<List<Job>> myJobs() async {
    final snap = await _db
        .collection('jobs')
        .where('bossId', isEqualTo: _uid)
        .get();
    return snap.docs.map(Job.fromDoc).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<List<JobApplication>> receivedApplications() async {
    final snap = await _db
        .collection('applications')
        .where('bossId', isEqualTo: _uid)
        .get();
    return snap.docs.map(JobApplication.fromDoc).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> publish({
    required Company company,
    required String title,
    required String city,
    required String salary,
    required String description,
  }) async {
    if (title.trim().length < 3) {
      throw const AppException('Écrivez le poste proposé.');
    }
    if (description.trim().length < 10) {
      throw const AppException('Décrivez le travail en quelques mots.');
    }
    await _db.collection('jobs').add({
      'bossId': _uid,
      'companyName': company.name,
      'title': title.trim(),
      'city': city.trim(),
      'salary': salary.trim(),
      'description': description.trim(),
      'status': 'open',
      'createdAt': _now,
    });
  }

  static Future<void> setOpen(Job job, bool open) =>
      _db.doc('jobs/${job.id}').update({'status': open ? 'open' : 'closed'});

  static Future<void> answer(JobApplication a, bool accept) => _db
      .doc('applications/${a.id}')
      .update({'status': accept ? 'accepted' : 'rejected'});
}
