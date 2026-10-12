import 'package:flutter/material.dart';

import '../api.dart';
import '../confidence.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

const _star = Color(0xFFF2A900);

/// Étoiles (de 1 à 5), éventuellement cliquables.
class Stars extends StatelessWidget {
  const Stars(this.value, {super.key, this.size = 18, this.onChanged});

  final double value;
  final double size;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${value.toStringAsFixed(1)} sur 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            GestureDetector(
              onTap: onChanged == null ? null : () => onChanged!(i),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: onChanged == null ? 0 : 4,
                ),
                child: Icon(
                  value >= i
                      ? Icons.star_rounded
                      : value >= i - 0.5
                      ? Icons.star_half_rounded
                      : Icons.star_outline_rounded,
                  color: _star,
                  size: size,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ================================================================== Avis

/// Avis des clients sur un tontinier, et le mien si je peux noter.
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({
    super.key,
    required this.ownerId,
    required this.ownerName,
  });

  final String ownerId;
  final String ownerName;

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

typedef _ReviewsData = (ReviewSummary, String?, Review?);

class _ReviewsScreenState extends State<ReviewsScreen> {
  late Future<_ReviewsData> _data = _load();

  Future<_ReviewsData> _load() async {
    final mine = widget.ownerId == Api.uid;
    final r = await Future.wait([
      ConfidenceApi.reviews(widget.ownerId),
      mine
          ? Future<String?>.value(null)
          : ConfidenceApi.reviewSource(widget.ownerId),
      mine
          ? Future<Review?>.value(null)
          : ConfidenceApi.myReview(widget.ownerId),
    ]);
    return (r[0] as ReviewSummary, r[1] as String?, r[2] as Review?);
  }

  Future<void> _rate(String source, Review? current) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ReviewDialog(
        ownerId: widget.ownerId,
        ownerName: widget.ownerName,
        source: source,
        current: current,
      ),
    );
    if (saved == true) setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Avis des clients')),
      body: FutureView<_ReviewsData>(
        future: _data,
        onRetry: () => setState(() => _data = _load()),
        builder: (context, data) {
          final (summary, source, mine) = data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        widget.ownerName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        summary.count == 0
                            ? '—'
                            : summary.average.toStringAsFixed(1),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Stars(summary.average, size: 28),
                      const SizedBox(height: 4),
                      Text(
                        summary.count == 0
                            ? 'Pas encore d\'avis'
                            : '${summary.count} avis de clients vérifiés',
                      ),
                    ],
                  ),
                ),
              ),
              if (source != null)
                FilledButton.icon(
                  onPressed: () => _rate(source, mine),
                  icon: const Icon(Icons.star_outline),
                  label: Text(
                    mine == null ? 'Donner mon avis' : 'Modifier mon avis',
                  ),
                )
              else if (widget.ownerId != Api.uid)
                Text(
                  'Vous pourrez donner votre avis après avoir reçu votre '
                  'cagnotte ou à la clôture de votre carnet.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Seuls les clients qui ont reçu leur cagnotte ou fini '
                      'leur carnet peuvent noter : pas de faux avis.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              SectionTitle('Avis (${summary.count})'),
              for (final r in summary.reviews)
                Card(
                  child: ListTile(
                    title: Row(
                      children: [
                        Expanded(child: Text(r.reviewerName)),
                        Stars(r.stars.toDouble(), size: 16),
                      ],
                    ),
                    subtitle: Text(
                      [
                        if (r.comment.isNotEmpty) '« ${r.comment} »',
                        dateShort(r.at),
                      ].join('\n'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.ownerId,
    required this.ownerName,
    required this.source,
    this.current,
  });

  final String ownerId;
  final String ownerName;
  final String source;
  final Review? current;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late int _stars = widget.current?.stars ?? 5;
  late final _comment = TextEditingController(text: widget.current?.comment);
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ConfidenceApi.saveReview(
        ownerId: widget.ownerId,
        source: widget.source,
        stars: _stars,
        comment: _comment.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Votre avis sur ${widget.ownerName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stars(
              _stars.toDouble(),
              size: 36,
              onChanged: (v) => setState(() => _stars = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _comment,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Votre commentaire (facultatif)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Publier mon avis'),
        ),
      ],
    );
  }
}

// =============================================================== Litiges

/// Signaler un problème à son tontinier (litige). COTIZI peut arbitrer.
class DisputeFormScreen extends StatefulWidget {
  const DisputeFormScreen({
    super.key,
    required this.ownerId,
    required this.ownerName,
    required this.where,
    this.groupId,
    this.carnetId,
    this.reason = 'payment_not_validated',
  });

  final String ownerId;
  final String ownerName;
  final String where;
  final String? groupId;
  final String? carnetId;
  final String reason;

  @override
  State<DisputeFormScreen> createState() => _DisputeFormScreenState();
}

class _DisputeFormScreenState extends State<DisputeFormScreen> {
  late String _reason = widget.reason;
  final _details = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final d = await ConfidenceApi.openDispute(
        ownerId: widget.ownerId,
        ownerName: widget.ownerName,
        where: widget.where,
        reason: _reason,
        details: _details.text,
        groupId: widget.groupId,
        carnetId: widget.carnetId,
      );
      if (!mounted) return;
      showInfo(context, 'Problème signalé à ${widget.ownerName}.');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DisputeScreen(dispute: d, role: 'client'),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signaler un problème')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Votre tontinier ${widget.ownerName} est prévenu et peut vous '
            'répondre. Si le problème n\'est pas réglé, l\'équipe COTIZI '
            'examine le litige.',
          ),
          const SectionTitle('Quel est le problème ?'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in Dispute.reasons.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _reason == e.key,
                  onSelected: (_) => setState(() => _reason = e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _details,
            maxLength: 1000,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Expliquez ce qui s\'est passé',
              hintText:
                  'Ex. J\'ai payé 5 000 F le 3 octobre, toujours pas validé',
              alignLabelWithHint: true,
            ),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Envoyer le signalement'),
          ),
        ],
      ),
    );
  }
}

Color _disputeColor(Dispute d) => d.isOpen
    ? paymentStatusColor(PaymentStatus.pending)
    : d.status == 'resolved'
    ? paymentStatusColor(PaymentStatus.approved)
    : Colors.blueGrey;

/// Liste des litiges : les miens, ou tous (administrateur, médiation).
class DisputesScreen extends StatefulWidget {
  const DisputesScreen({super.key, this.admin = false});

  final bool admin;

  @override
  State<DisputesScreen> createState() => _DisputesScreenState();
}

class _DisputesScreenState extends State<DisputesScreen> {
  late Future<List<Dispute>> _data = _load();

  Future<List<Dispute>> _load() =>
      widget.admin ? ConfidenceApi.allDisputes() : ConfidenceApi.myDisputes();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.admin ? 'Médiation des litiges' : 'Litiges'),
      ),
      body: FutureView<List<Dispute>>(
        future: _data,
        onRetry: () => setState(() => _data = _load()),
        builder: (context, list) {
          final open = list.where((d) => d.isOpen).toList();
          final closed = list.where((d) => !d.isOpen).toList();
          Widget tile(Dispute d) {
            final role = widget.admin
                ? 'admin'
                : d.ownerId == Api.uid
                ? 'owner'
                : 'client';
            return Card(
              child: ListTile(
                leading: Icon(Icons.flag_outlined, color: _disputeColor(d)),
                title: Text(d.reasonLabel),
                subtitle: Text(
                  '${role == 'client'
                      ? 'Contre ${d.ownerName}'
                      : role == 'owner'
                      ? 'Par ${d.clientName}'
                      : '${d.clientName} → ${d.ownerName}'}'
                  ' · ${d.where}\n${dateShort(d.updatedAt)}',
                ),
                isThreeLine: true,
                trailing: StatusChip(d.statusLabel, _disputeColor(d)),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DisputeScreen(dispute: d, role: role),
                    ),
                  );
                  setState(() => _data = _load());
                },
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Aucun litige.', textAlign: TextAlign.center),
                ),
              if (open.isNotEmpty) ...[
                SectionTitle('En cours (${open.length})'),
                for (final d in open) tile(d),
              ],
              if (closed.isNotEmpty) ...[
                SectionTitle('Terminés (${closed.length})'),
                for (final d in closed) tile(d),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Un litige : messages entre le client, le tontinier et COTIZI.
class DisputeScreen extends StatefulWidget {
  const DisputeScreen({super.key, required this.dispute, required this.role});

  final Dispute dispute;

  /// client, owner ou admin
  final String role;

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> {
  late Dispute _d = widget.dispute;
  late Future<List<DisputeMessage>> _messages = ConfidenceApi.messages(_d.id);
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send({String? status}) async {
    setState(() => _busy = true);
    try {
      final newStatus =
          status ??
          (widget.role == 'owner' && _d.status == 'open' ? 'answered' : null);
      await ConfidenceApi.reply(
        _d,
        _text.text,
        role: widget.role,
        status: newStatus,
      );
      _text.clear();
      if (!mounted) return;
      setState(() {
        if (newStatus != null) _d = _copy(newStatus);
        _messages = ConfidenceApi.messages(_d.id);
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Dispute _copy(String status) => Dispute(
    id: _d.id,
    ownerId: _d.ownerId,
    ownerName: _d.ownerName,
    clientId: _d.clientId,
    clientName: _d.clientName,
    groupId: _d.groupId,
    carnetId: _d.carnetId,
    where: _d.where,
    reason: _d.reason,
    status: status,
    createdAt: _d.createdAt,
    updatedAt: DateTime.now(),
  );

  Future<void> _setStatus(String status, String message) async {
    if (!await confirm(
      context,
      title: 'Confirmer',
      message: message,
      confirmLabel: 'Confirmer',
    )) {
      return;
    }
    try {
      await ConfidenceApi.setStatus(_d, status);
      if (mounted) setState(() => _d = _copy(status));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: Text(d.reasonLabel)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                StatusCard(
                  icon: Icons.flag_outlined,
                  color: _disputeColor(d),
                  title: d.statusLabel,
                  message:
                      '${d.clientName} → ${d.ownerName} · ${d.where}\n'
                      'Ouvert le ${dateLong(d.createdAt)}',
                ),
                FutureView<List<DisputeMessage>>(
                  future: _messages,
                  onRetry: () =>
                      setState(() => _messages = ConfidenceApi.messages(d.id)),
                  builder: (context, list) => Column(
                    children: [
                      for (final m in list)
                        Align(
                          alignment: m.role == widget.role
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(maxWidth: 300),
                            decoration: BoxDecoration(
                              color: m.role == 'admin'
                                  ? const Color(0xFFFFF3E0)
                                  : m.role == widget.role
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.role == 'admin'
                                      ? 'Équipe COTIZI'
                                      : m.authorName,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(m.text),
                                Text(
                                  dateTime(m.at),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.role == 'client' && d.isOpen)
                  OutlinedButton.icon(
                    onPressed: () => _setStatus(
                      'resolved',
                      'Le problème est réglé ? Le litige sera fermé.',
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Le problème est réglé'),
                  ),
                if (widget.role == 'client' && !d.isOpen)
                  TextButton(
                    onPressed: () => _setStatus(
                      'open',
                      'Rouvrir le litige ? Votre tontinier et COTIZI seront '
                          'prévenus.',
                    ),
                    child: const Text('Rouvrir le litige'),
                  ),
                if (widget.role == 'admin') ...[
                  FilledButton(
                    onPressed: () => _setStatus(
                      'resolved',
                      'Clore le litige : le problème est réglé ?',
                    ),
                    child: const Text('Clore : problème réglé'),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton(
                    onPressed: () => _setStatus(
                      'rejected',
                      'Clore le litige comme non fondé ?',
                    ),
                    child: const Text('Clore : signalement non fondé'),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: widget.role == 'admin'
                            ? 'Message de COTIZI aux deux'
                            : 'Votre message',
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Envoyer',
                    onPressed: _busy ? null : () => _send(),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================== Annonces

/// Annonces du tontinier à son groupe (vues par tous les participants).
class AnnouncementsCard extends StatefulWidget {
  const AnnouncementsCard({
    super.key,
    required this.group,
    required this.isOwner,
  });

  final Group group;
  final bool isOwner;

  @override
  State<AnnouncementsCard> createState() => _AnnouncementsCardState();
}

class _AnnouncementsCardState extends State<AnnouncementsCard> {
  late Future<List<Announcement>> _data = ConfidenceApi.announcements(
    widget.group.id,
  );

  void _reload() =>
      setState(() => _data = ConfidenceApi.announcements(widget.group.id));

  Future<void> _publish() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annonce au groupe'),
        content: TextField(
          controller: c,
          maxLength: 500,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Votre annonce',
            hintText: 'Ex. Réunion samedi à 10 h chez moi',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Publier'),
          ),
        ],
      ),
    );
    if (text == null || !mounted) return;
    try {
      await ConfidenceApi.announce(widget.group, text);
      if (mounted) showInfo(context, 'Annonce envoyée aux participants.');
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Announcement>>(
      future: _data,
      builder: (context, snap) {
        final list = snap.data ?? const <Announcement>[];
        if (list.isEmpty && !widget.isOwner) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.campaign_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Annonces',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (widget.isOwner)
                      TextButton.icon(
                        onPressed: _publish,
                        icon: const Icon(Icons.add),
                        label: const Text('Publier'),
                      ),
                  ],
                ),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Prévenez tout le groupe d\'un coup : réunion, '
                      'changement de date, rappel…',
                    ),
                  ),
                for (final a in list.take(3))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.text),
                    subtitle: Text(dateTime(a.at)),
                    trailing: widget.isOwner
                        ? IconButton(
                            tooltip: 'Supprimer l\'annonce',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await ConfidenceApi.deleteAnnouncement(
                                widget.group.id,
                                a.id,
                              );
                              _reload();
                            },
                          )
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
