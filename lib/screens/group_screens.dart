import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'payment_screens.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key, required this.tontine});

  final Tontine tontine;

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _members = TextEditingController();
  final _amount = TextEditingController();
  final _commission = TextEditingController(text: '0');
  Frequency _frequency = Frequency.monthly;
  CommissionType _commissionType = CommissionType.percent;
  DateTime _start = DateUtils.dateOnly(DateTime.now());
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _members.dispose();
    _amount.dispose();
    _commission.dispose();
    super.dispose();
  }

  int get _memberCount => int.tryParse(_members.text) ?? 0;
  int get _contribution => parseAmount(_amount.text) ?? 0;
  double get _commissionValue =>
      double.tryParse(
        _commission.text.replaceAll(',', '.').replaceAll(' ', ''),
      ) ??
      0;

  Group get _preview => Group(
    id: '',
    tontineId: widget.tontine.id,
    tontineName: widget.tontine.name,
    ownerId: '',
    ownerName: '',
    name: _name.text,
    memberCount: _memberCount,
    contributionAmount: _contribution,
    frequency: _frequency,
    startDate: _start,
    commissionType: _commissionType,
    commissionValue: _commissionValue,
    inviteCode: '',
    status: GroupStatus.recruiting,
  );

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (d != null) setState(() => _start = d);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Api.createGroup(
        tontine: widget.tontine,
        name: _name.text,
        memberCount: _memberCount,
        contributionAmount: _contribution,
        frequency: _frequency,
        startDate: _start,
        commissionType: _commissionType,
        commissionValue: _commissionValue,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final ready = _memberCount >= 2 && _contribution > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau groupe')),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nom du groupe',
                hintText: 'Ex. Groupe A',
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Donnez un nom au groupe' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _members,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Nombre de membres',
                helperText: 'C\'est aussi le nombre de tours',
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '') ?? 0;
                return n < 2 || n > 100 ? 'Entre 2 et 100 membres' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Cotisation par membre et par tour',
                suffixText: 'FCFA',
              ),
              validator: (v) => (parseAmount(v ?? '') ?? 0) <= 0
                  ? 'Indiquez le montant de la cotisation'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Frequency>(
              initialValue: _frequency,
              decoration: const InputDecoration(
                labelText: 'Fréquence des paiements',
              ),
              items: [
                for (final f in Frequency.values)
                  DropdownMenuItem(value: f, child: Text(frequencyLabel(f))),
              ],
              onChanged: (f) => setState(() => _frequency = f ?? _frequency),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date du premier tour',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(dateLong(_start)),
              ),
            ),
            const SectionTitle('Commission du tontinier'),
            SegmentedButton<CommissionType>(
              segments: const [
                ButtonSegment(
                  value: CommissionType.percent,
                  label: Text('Pourcentage'),
                ),
                ButtonSegment(
                  value: CommissionType.fixed,
                  label: Text('Montant fixe'),
                ),
              ],
              selected: {_commissionType},
              onSelectionChanged: (s) =>
                  setState(() => _commissionType = s.first),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _commission,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Commission par tour',
                suffixText: _commissionType == CommissionType.percent
                    ? '%'
                    : 'FCFA',
                helperText: 'Retenue sur la cagnotte du bénéficiaire',
              ),
              validator: (_) {
                final v = _commissionValue;
                if (v < 0) return 'Commission invalide';
                if (_commissionType == CommissionType.percent && v > 100) {
                  return 'Maximum 100 %';
                }
                if (_commissionType == CommissionType.fixed &&
                    ready &&
                    v > preview.grossPot) {
                  return 'Supérieure à la cagnotte';
                }
                return null;
              },
            ),
            if (ready) ...[
              const SectionTitle('Résumé'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      InfoRow('Cagnotte par tour', money(preview.grossPot)),
                      InfoRow('Commission', money(preview.commission)),
                      InfoRow(
                        'Le bénéficiaire reçoit',
                        money(preview.netPot),
                        bold: true,
                      ),
                      InfoRow(
                        'Dernier tour',
                        dateLong(preview.tourDate(preview.memberCount)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Créer le groupe'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Détail d'un groupe, vu par le tontinier ou par un membre.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  late Future<(Group, List<Payment>)> _data = _load();
  bool _busy = false;

  Future<(Group, List<Payment>)> _load() async {
    final group = await Api.group(widget.groupId);
    return (group, await Api.groupPayments(group));
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  Future<void> _push(Widget screen) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (changed == true && mounted) _reload();
  }

  Future<void> _drawLot(Group g) => _run(() async {
    final position = await Api.drawLot(g.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.celebration, size: 40),
        title: Text('Vous avez tiré le n°$position'),
        content: Text(
          'Vous recevrez la cagnotte de ${money(g.netPot)} au tour $position, '
          'prévu le ${dateLong(g.tourDate(position))}.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  });

  void _openPayment(Group g, Payment p, bool isOwner) => _push(
    ReviewPaymentScreen(
      payment: p,
      canReview: isOwner,
      details: [
        ('Groupe', g.name),
        ('Tour', '${p.tourNumber} · ${dateShort(g.tourDate(p.tourNumber))}'),
      ],
      onReview: (approve, reason) =>
          Api.reviewPayment(g.id, p.id, approve, reason),
    ),
  );

  void _declare(Group g, int tour, {required bool afterRejection}) => _push(
    DeclarePaymentScreen(
      title: 'Déclarer un paiement',
      fixedAmount: g.contributionAmount,
      details: [
        ('Groupe', g.name),
        ('Tour', '$tour · ${dateLong(g.tourDate(tour))}'),
        ('Bénéficiaire', g.beneficiaryOf(tour)?.name ?? '—'),
      ],
      onSubmit: (proof, mime, _) => Api.declarePayment(
        group: g,
        tourNumber: tour,
        proof: proof,
        mime: mime,
        afterRejection: afterRejection,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groupe')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureView<(Group, List<Payment>)>(
          future: _data,
          onRetry: _reload,
          builder: (context, data) {
            final (g, payments) = data;
            final isOwner = g.ownerId == Api.uid;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _header(g),
                ..._statusSection(g, isOwner),
                if (isOwner) ..._pendingSection(g, payments),
                if (g.status != GroupStatus.recruiting)
                  ..._toursSection(g, payments, isOwner),
                ..._membersSection(g),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(Group g) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    g.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                StatusChip(
                  groupStatusLabel(g.status),
                  theme.colorScheme.primary,
                ),
              ],
            ),
            Text(
              '${g.tontineName} · Tontinier : ${g.ownerName}',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            InfoRow(
              'Cotisation',
              '${money(g.contributionAmount)} · ${frequencyLabel(g.frequency).toLowerCase()}',
            ),
            InfoRow('Premier tour', dateLong(g.startDate)),
            InfoRow('Membres', '${g.members.length} / ${g.memberCount}'),
            InfoRow('Cagnotte par tour', money(g.grossPot)),
            InfoRow('Commission', commissionLabel(g)),
            InfoRow('Le bénéficiaire reçoit', money(g.netPot), bold: true),
          ],
        ),
      ),
    );
  }

  List<Widget> _statusSection(Group g, bool isOwner) {
    final joined = g.members.length;
    final me = g.members.where((m) => m.userId == Api.uid).firstOrNull;
    switch (g.status) {
      case GroupStatus.recruiting:
        if (isOwner) {
          return [
            const SizedBox(height: 8),
            InviteCodeCard(
              code: g.inviteCode,
              hint: 'Partagez ce code avec vos membres pour qu\'ils rejoignent le groupe.',
              shareText:
                  'Rejoins le groupe « ${g.name} » de ma tontine sur COTIZI. '
                  'Cotisation : ${money(g.contributionAmount)} ${frequencyLabel(g.frequency).toLowerCase()}. '
                  'Code d\'invitation : ${g.inviteCode}',
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: joined < g.memberCount || _busy
                  ? null
                  : () async {
                      if (await confirm(
                        context,
                        title: 'Lancer le tirage au sort',
                        message:
                            'Les membres ne pourront plus rejoindre le groupe. '
                            'Chaque membre tirera son numéro de passage.',
                        confirmLabel: 'Lancer',
                      )) {
                        await _run(() => Api.startDraw(g));
                      }
                    },
              icon: const Icon(Icons.casino_outlined),
              label: Text(
                joined < g.memberCount
                    ? 'Tirage possible quand le groupe est complet ($joined / ${g.memberCount})'
                    : 'Lancer le tirage au sort',
              ),
            ),
          ];
        }
        return [
          _infoBanner(
            Icons.hourglass_top,
            joined < g.memberCount
                ? 'En attente des autres membres ($joined / ${g.memberCount}). '
                      'Le tontinier lancera ensuite le tirage au sort.'
                : 'Le groupe est complet. Le tontinier va lancer le tirage au sort.',
          ),
        ];
      case GroupStatus.drawing:
        final drawn = g.members.where((m) => m.drawPosition != null).length;
        if (isOwner) {
          return [
            _infoBanner(
              Icons.casino_outlined,
              'Tirage au sort en cours : $drawn / ${g.memberCount} membres ont tiré leur numéro.',
            ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      if (await confirm(
                        context,
                        title: 'Terminer le tirage',
                        message: 'Les membres qui n\'ont pas encore tiré recevront un numéro au hasard.',
                        confirmLabel: 'Tirer pour eux',
                      )) {
                        await _run(() => Api.finishDraw(g));
                      }
                    },
              icon: const Icon(Icons.shuffle),
              label: const Text('Tirer pour les membres restants'),
            ),
          ];
        }
        if (me != null && me.drawPosition == null) {
          return [
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.casino, size: 48),
                    const SizedBox(height: 8),
                    const Text(
                      'Le tirage au sort est ouvert ! Tirez votre numéro pour savoir '
                      'à quel tour vous recevrez la cagnotte.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _drawLot(g),
                      icon: const Icon(Icons.casino_outlined),
                      label: const Text('Tirer mon numéro'),
                    ),
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          _infoBanner(
            Icons.casino_outlined,
            'Vous avez tiré le n°${me?.drawPosition}. En attente des autres membres ($drawn / ${g.memberCount}).',
          ),
        ];
      case GroupStatus.active:
        if (me?.drawPosition != null) {
          final pos = me!.drawPosition!;
          return [
            _infoBanner(
              Icons.emoji_events_outlined,
              'Vous recevez la cagnotte au tour $pos, le ${dateLong(g.tourDate(pos))}.',
            ),
          ];
        }
        return const [];
    }
  }

  List<Widget> _pendingSection(Group g, List<Payment> payments) {
    final pending = payments
        .where((p) => p.status == PaymentStatus.pending)
        .toList();
    if (pending.isEmpty) return const [];
    return [
      SectionTitle('Paiements à valider (${pending.length})'),
      for (final p in pending)
        Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long),
            title: Text(p.payer.fullName),
            subtitle: Text(
              'Tour ${p.tourNumber} · ${money(p.amount)} · ${dateTime(p.declaredAt)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPayment(g, p, true),
          ),
        ),
    ];
  }

  List<Widget> _toursSection(Group g, List<Payment> payments, bool isOwner) {
    return [
      const SectionTitle('Calendrier des tours'),
      for (var tour = 1; tour <= g.memberCount; tour++)
        isOwner
            ? _ownerTourCard(g, tour, payments)
            : _memberTourCard(g, tour, payments),
    ];
  }

  Widget _tourLeading(int tour) => CircleAvatar(
    radius: 18,
    child: Text('$tour', style: const TextStyle(fontWeight: FontWeight.w700)),
  );

  String _tourSubtitle(Group g, int tour) {
    final b = g.beneficiaryOf(tour);
    return '${dateLong(g.tourDate(tour))} · ${b == null ? 'bénéficiaire à tirer' : 'pour ${b.name}'}';
  }

  Widget _ownerTourCard(Group g, int tour, List<Payment> payments) {
    final tourPayments = payments.where((p) => p.tourNumber == tour).toList();
    final approved = tourPayments
        .where((p) => p.status == PaymentStatus.approved)
        .length;
    final pending = tourPayments
        .where((p) => p.status == PaymentStatus.pending)
        .length;
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        leading: _tourLeading(tour),
        title: Text('Tour $tour'),
        subtitle: Text(
          pending > 0
              ? '${_tourSubtitle(g, tour)}\n$pending paiement(s) à valider'
              : _tourSubtitle(g, tour),
        ),
        trailing: StatusChip(
          '$approved / ${g.memberCount} payé${approved > 1 ? 's' : ''}',
          approved == g.memberCount
              ? paymentStatusColor(PaymentStatus.approved)
              : Theme.of(context).colorScheme.primary,
        ),
        children: [
          for (final m in g.members)
            Builder(
              builder: (context) {
                final p = tourPayments
                    .where((p) => p.userId == m.userId)
                    .firstOrNull; // le plus récent (tri par date décroissante)
                return ListTile(
                  dense: true,
                  title: Text(m.name),
                  trailing: p == null
                      ? const StatusChip('Non payé', Colors.grey)
                      : StatusChip.payment(p.status),
                  onTap: p == null ? null : () => _openPayment(g, p, true),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _memberTourCard(Group g, int tour, List<Payment> payments) {
    final mine = payments
        .where((p) => p.tourNumber == tour && p.userId == Api.uid)
        .firstOrNull; // le plus récent
    final canDeclare =
        g.status == GroupStatus.active &&
        (mine == null || mine.status == PaymentStatus.rejected);
    final isMyTour = g.beneficiaryOf(tour)?.userId == Api.uid;
    return Card(
      color: isMyTour
          ? Theme.of(context).colorScheme.primaryContainer
                .withValues(alpha: 0.5)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            ListTile(
              leading: _tourLeading(tour),
              title: Text(
                isMyTour ? 'Tour $tour · votre tour !' : 'Tour $tour',
              ),
              subtitle: Text(_tourSubtitle(g, tour)),
              trailing: mine == null ? null : StatusChip.payment(mine.status),
              onTap: mine == null ? null : () => _openPayment(g, mine, false),
            ),
            if (mine?.status == PaymentStatus.rejected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Refusé : ${mine!.rejectionReason ?? ''}',
                  style: TextStyle(
                    color: paymentStatusColor(PaymentStatus.rejected),
                  ),
                ),
              ),
            if (canDeclare)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        _declare(g, tour, afterRejection: mine != null),
                    icon: const Icon(Icons.upload),
                    label: Text(
                      mine == null
                          ? 'Déclarer mon paiement'
                          : 'Déclarer à nouveau',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _membersSection(Group g) {
    return [
      SectionTitle('Membres (${g.members.length} / ${g.memberCount})'),
      if (g.members.isEmpty)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Aucun membre pour le moment.'),
        ),
      for (final m in g.members)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(m.name.isEmpty ? '?' : m.name[0].toUpperCase()),
            ),
            title: Text(m.userId == Api.uid ? '${m.name} (vous)' : m.name),
            subtitle: Text(m.profile.phone),
            trailing: m.drawPosition == null
                ? null
                : StatusChip(
                    'N° ${m.drawPosition}',
                    Theme.of(context).colorScheme.primary,
                  ),
          ),
        ),
    ];
  }

  Widget _infoBanner(IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
