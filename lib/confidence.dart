import 'package:cloud_firestore/cloud_firestore.dart';

import 'api.dart';
import 'models.dart';

DateTime _time(Object? v) => v is Timestamp ? v.toDate() : DateTime.now();

/// Avis d'un client sur son tontinier (après une cagnotte reçue ou un
/// carnet clôturé).
class Review {
  const Review({
    required this.ownerId,
    required this.reviewerId,
    required this.reviewerName,
    required this.stars,
    required this.comment,
    required this.at,
  });

  final String ownerId;
  final String reviewerId;
  final String reviewerName;
  final int stars;
  final String comment;
  final DateTime at;

  factory Review.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Review(
      ownerId: json['ownerId'] as String? ?? '',
      reviewerId: json['reviewerId'] as String? ?? '',
      reviewerName: json['reviewerName'] as String? ?? '',
      stars: (json['stars'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String? ?? '',
      at: _time(json['at']),
    );
  }
}

/// Moyenne des avis d'un tontinier.
class ReviewSummary {
  const ReviewSummary(this.reviews);

  final List<Review> reviews;

  int get count => reviews.length;

  double get average =>
      count == 0 ? 0 : reviews.fold<int>(0, (n, r) => n + r.stars) / count;
}

/// Litige ouvert par un client contre son tontinier.
class Dispute {
  const Dispute({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.clientId,
    required this.clientName,
    required this.where,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.groupId,
    this.carnetId,
  });

  final String id;
  final String ownerId;
  final String ownerName;
  final String clientId;
  final String clientName;
  final String? groupId;
  final String? carnetId;
  final String where;
  final String reason;

  /// open, answered, resolved ou rejected
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const reasons = {
    'payment_not_validated': 'Paiement non validé',
    'payout_not_received': 'Cagnotte non reçue',
    'wrong_amount': 'Montant incorrect',
    'other': 'Autre problème',
  };

  String get reasonLabel => reasons[reason] ?? 'Autre problème';

  bool get isOpen => status == 'open' || status == 'answered';

  String get statusLabel => switch (status) {
    'answered' => 'Le tontinier a répondu',
    'resolved' => 'Réglé',
    'rejected' => 'Clos par COTIZI',
    _ => 'En cours',
  };

  factory Dispute.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Dispute(
      id: doc.id,
      ownerId: json['ownerId'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      clientId: json['clientId'] as String? ?? '',
      clientName: json['clientName'] as String? ?? '',
      groupId: json['groupId'] as String?,
      carnetId: json['carnetId'] as String?,
      where: json['where'] as String? ?? '',
      reason: json['reason'] as String? ?? 'other',
      status: json['status'] as String? ?? 'open',
      createdAt: _time(json['createdAt']),
      updatedAt: _time(json['updatedAt']),
    );
  }
}

class DisputeMessage {
  const DisputeMessage(this.authorName, this.role, this.text, this.at);

  final String authorName;

  /// client, owner ou admin
  final String role;
  final String text;
  final DateTime at;

  factory DisputeMessage.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return DisputeMessage(
      json['authorName'] as String? ?? '',
      json['role'] as String? ?? 'client',
      json['text'] as String? ?? '',
      _time(json['at']),
    );
  }
}

/// Annonce du tontinier à son groupe.
class Announcement {
  const Announcement(this.id, this.text, this.authorName, this.at);

  final String id;
  final String text;
  final String authorName;
  final DateTime at;

  factory Announcement.fromDoc(DocumentSnapshot<Json> doc) {
    final json = doc.data()!;
    return Announcement(
      doc.id,
      json['text'] as String? ?? '',
      json['authorName'] as String? ?? '',
      _time(json['at']),
    );
  }
}

/// Avis, litiges et annonces : la confiance entre le tontinier et ses
/// clients, sans que COTIZI touche l'argent.
class ConfidenceApi {
  ConfidenceApi._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String get _uid => Api.uid;
  static FieldValue get _now => FieldValue.serverTimestamp();

  // -------------------------------------------------------------- Avis

  static Future<ReviewSummary> reviews(String ownerId) async {
    final snap = await _db
        .collection('reviews')
        .where('ownerId', isEqualTo: ownerId)
        .get();
    return ReviewSummary(
      snap.docs.map(Review.fromDoc).toList()
        ..sort((a, b) => b.at.compareTo(a.at)),
    );
  }

  static Future<Review?> myReview(String ownerId) async {
    final doc = await _db.doc('reviews/${ownerId}_$_uid').get();
    return doc.exists ? Review.fromDoc(doc) : null;
  }

  /// Ce qui permet à ce client de noter ce tontinier : une cagnotte reçue
  /// et confirmée, ou un carnet clôturé (null : pas encore possible).
  static Future<String?> reviewSource(String ownerId) async {
    final carnets = await Api.myCarnets();
    for (final c in carnets) {
      if (c.ownerId == ownerId && c.isClosed) return 'carnets/${c.id}';
    }
    final groups = await Api.myGroups();
    for (final g in groups.where((g) => g.ownerId == ownerId)) {
      final payouts = await Api.payouts(g.id);
      for (final p in payouts.values) {
        if (p.beneficiaryId == _uid && p.confirmed) {
          return 'groups/${g.id}/payouts/${p.pot}';
        }
      }
    }
    return null;
  }

  static Future<void> saveReview({
    required String ownerId,
    required String source,
    required int stars,
    required String comment,
  }) async {
    final me = await Api.myProfile();
    if (me == null) throw const AppException('Profil introuvable.');
    await _db.doc('reviews/${ownerId}_$_uid').set({
      'ownerId': ownerId,
      'reviewerId': _uid,
      'reviewerName': me.fullName,
      'stars': stars,
      'comment': comment.trim(),
      'source': source,
      'at': _now,
    });
  }

  // ----------------------------------------------------------- Litiges

  static Future<List<Dispute>> disputesAbout(String ownerId) async {
    final snap = await _db
        .collection('disputes')
        .where('ownerId', isEqualTo: ownerId)
        .get();
    return snap.docs.map(Dispute.fromDoc).toList();
  }

  /// Litiges qui me concernent : ouverts par moi, ou contre moi.
  static Future<List<Dispute>> myDisputes() async {
    final results = await Future.wait([
      _db.collection('disputes').where('clientId', isEqualTo: _uid).get(),
      _db.collection('disputes').where('ownerId', isEqualTo: _uid).get(),
    ]);
    return [for (final r in results) ...r.docs.map(Dispute.fromDoc)]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Tous les litiges (administrateur : médiation).
  static Future<List<Dispute>> allDisputes() async {
    final snap = await _db.collection('disputes').get();
    return snap.docs.map(Dispute.fromDoc).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<Dispute> openDispute({
    required String ownerId,
    required String ownerName,
    required String where,
    required String reason,
    required String details,
    String? groupId,
    String? carnetId,
  }) async {
    if (details.trim().length < 2) {
      throw const AppException('Expliquez le problème en quelques mots.');
    }
    final me = await Api.myProfile();
    if (me == null) throw const AppException('Profil introuvable.');
    final ref = _db.collection('disputes').doc();
    final batch = _db.batch()
      ..set(ref, {
        'ownerId': ownerId,
        'ownerName': ownerName,
        'clientId': _uid,
        'clientName': me.fullName,
        'groupId': groupId,
        'carnetId': carnetId,
        'where': where,
        'reason': reason,
        'status': 'open',
        'createdAt': _now,
        'updatedAt': _now,
      })
      ..set(ref.collection('messages').doc('first'), {
        'authorId': _uid,
        'authorName': me.fullName,
        'role': 'client',
        'text': details.trim(),
        'at': _now,
      });
    await batch.commit();
    await Api.notify(
      to: ownerId,
      type: 'dispute',
      title: 'Problème signalé',
      body:
          '${me.fullName} signale : ${Dispute.reasons[reason]} ($where). '
          'Répondez-lui dans Profil → Litiges.',
      groupId: groupId,
      carnetId: carnetId,
    );
    return Dispute.fromDoc(await ref.get());
  }

  static Future<List<DisputeMessage>> messages(String disputeId) async {
    final snap = await _db
        .collection('disputes/$disputeId/messages')
        .orderBy('at')
        .get();
    return snap.docs.map(DisputeMessage.fromDoc).toList();
  }

  /// Ajoute un message ; [status] change l'état du litige si besoin.
  static Future<void> reply(
    Dispute d,
    String text, {
    required String role,
    String? status,
  }) async {
    if (text.trim().length < 2) {
      throw const AppException('Écrivez votre message.');
    }
    final me = await Api.myProfile();
    if (me == null) throw const AppException('Profil introuvable.');
    final ref = _db.doc('disputes/${d.id}');
    final batch = _db.batch()
      ..set(ref.collection('messages').doc(), {
        'authorId': _uid,
        'authorName': me.fullName,
        'role': role,
        'text': text.trim(),
        'at': _now,
      });
    if (status != null && status != d.status) {
      batch.update(ref, {'status': status, 'updatedAt': _now});
    }
    await batch.commit();
    final other = role == 'owner' ? d.clientId : d.ownerId;
    await Api.notify(
      to: other,
      type: 'dispute',
      title: 'Litige : nouveau message',
      body: '${me.fullName} : ${text.trim()}',
      groupId: d.groupId,
      carnetId: d.carnetId,
    );
  }

  static Future<void> setStatus(Dispute d, String status) =>
      _db.doc('disputes/${d.id}').update({'status': status, 'updatedAt': _now});

  // ---------------------------------------------------------- Annonces

  static Future<List<Announcement>> announcements(String groupId) async {
    final snap = await _db
        .collection('groups/$groupId/announcements')
        .orderBy('at', descending: true)
        .limit(20)
        .get();
    return snap.docs.map(Announcement.fromDoc).toList();
  }

  /// Publie une annonce et prévient chaque participant.
  static Future<void> announce(Group g, String text) async {
    if (text.trim().length < 2) {
      throw const AppException('Écrivez votre annonce.');
    }
    final me = await Api.myProfile();
    if (me == null) throw const AppException('Profil introuvable.');
    await _db.collection('groups/${g.id}/announcements').add({
      'text': text.trim(),
      'authorName': me.fullName,
      'at': _now,
    });
    await Future.wait([
      for (final m in g.memberIds)
        Api.notify(
          to: m,
          type: 'announcement',
          title: 'Annonce · ${g.name}',
          body: text.trim(),
          groupId: g.id,
        ),
    ]);
  }

  static Future<void> deleteAnnouncement(String groupId, String id) =>
      _db.doc('groups/$groupId/announcements/$id').delete();
}
