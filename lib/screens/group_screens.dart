import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../invite_link.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'payment_screens.dart';

// ====================================================== Création du groupe

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
  final _duration = TextEditingController(text: '30');
  final _commission = TextEditingController(text: '0');
  Frequency _frequency = Frequency.daily;
  CommissionType _commissionType = CommissionType.percent;
  DateTime _start = DateUtils.dateOnly(DateTime.now());

  /// Date de 1re remise choisie par le tontinier (sinon : fin de collecte).
  DateTime? _payout;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _members.dispose();
    _amount.dispose();
    _duration.dispose();
    _commission.dispose();
    super.dispose();
  }

  int get _memberCount => int.tryParse(_members.text) ?? 0;
  int get _contribution => parseAmount(_amount.text) ?? 0;
  int get _perPot => int.tryParse(_duration.text) ?? 0;
  double get _commissionValue =>
      double.tryParse(
        _commission.text.replaceAll(',', '.').replaceAll(' ', ''),
      ) ??
      0;

  Group _preview({DateTime? payout}) {
    final draft = Group(
      id: '',
      tontineId: widget.tontine.id,
      tontineName: widget.tontine.name,
      ownerId: '',
      ownerName: '',
      name: _name.text,
      memberCount: max(_memberCount, 1),
      contributionAmount: _contribution,
      frequency: _frequency,
      startDate: _start,
      contributionsPerPot: max(_perPot, 1),
      firstPayoutDate: payout ?? _start,
      commissionType: _commissionType,
      commissionValue: _commissionValue,
      inviteCode: '',
      status: GroupStatus.recruiting,
    );
    return payout != null
        ? draft
        : _preview(payout: _payout ?? draft.collectEnd(1));
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      helpText: 'Date de la première cotisation',
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (d != null) {
      setState(() {
        _start = d;
        _payout = null;
      });
    }
  }

  Future<void> _pickPayout() async {
    final g = _preview();
    final earliest = g.collectEnd(1);
    final d = await showDatePicker(
      context: context,
      helpText: 'Date de la 1re remise',
      initialDate: g.firstPayoutDate!,
      firstDate: earliest,
      lastDate: earliest.add(const Duration(days: 365 * 2)),
    );
    if (d != null) setState(() => _payout = d);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final g = _preview();
    setState(() => _busy = true);
    try {
      await Api.createGroup(
        tontine: widget.tontine,
        name: _name.text,
        memberCount: _memberCount,
        contributionAmount: _contribution,
        frequency: _frequency,
        startDate: _start,
        contributionsPerPot: _perPot,
        firstPayoutDate: g.firstPayoutDate!,
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
    final ready = _memberCount >= 2 && _contribution > 0 && _perPot >= 1;
    final g = _preview();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau groupe')),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const _Step(1, 'Le groupe'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nom du groupe',
                hintText: 'Ex. Groupe du marché',
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
                labelText: 'Nombre de participants',
                helperText:
                    'Chacun reçoit la cagnotte une fois : il y aura autant '
                    'de remises que de participants.',
                helperMaxLines: 2,
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '') ?? 0;
                return n < 2 || n > 100 ? 'Entre 2 et 100 participants' : null;
              },
            ),
            const _Step(2, 'Les cotisations'),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Montant d\'une cotisation',
                suffixText: 'FCFA',
              ),
              validator: (v) => (parseAmount(v ?? '') ?? 0) <= 0
                  ? 'Indiquez le montant de la cotisation'
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              'Fréquence des cotisations',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final f in Frequency.values)
                  ChoiceChip(
                    label: Text(frequencyLabel(f)),
                    selected: _frequency == f,
                    onSelected: (_) => setState(() {
                      _frequency = f;
                      _payout = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Première cotisation le',
              date: _start,
              onTap: _pickStart,
            ),
            const _Step(3, 'La remise de la cagnotte'),
            TextFormField(
              controller: _duration,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Durée de collecte avant chaque remise',
                suffixText: durationUnit(_frequency),
                helperText: _perPot >= 1
                    ? 'Soit ${contributionsLabel(_perPot)} par participant '
                          'pour chaque cagnotte'
                    : null,
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '') ?? 0;
                return n < 1 || n > 366 ? 'Entre 1 et 366' : null;
              },
              onChanged: (_) => _payout = null,
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Date de la 1re remise au bénéficiaire',
              date: g.firstPayoutDate!,
              helper: ready
                  ? 'Collecte du ${dateShort(g.collectStart(1))} au '
                        '${dateShort(g.collectEnd(1))}. Remises suivantes : '
                        'tous les ${durationLabel(_frequency, g.perPot)}.'
                  : null,
              onTap: ready ? _pickPayout : null,
            ),
            const _Step(4, 'Commission du tontinier'),
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
                labelText: 'Commission sur chaque cagnotte',
                suffixText: _commissionType == CommissionType.percent
                    ? '%'
                    : 'FCFA',
                helperText: 'Retenue sur la cagnotte remise au bénéficiaire',
              ),
              validator: (_) {
                final v = _commissionValue;
                if (v < 0) return 'Commission invalide';
                if (_commissionType == CommissionType.percent && v > 100) {
                  return 'Maximum 100 %';
                }
                if (_commissionType == CommissionType.fixed &&
                    ready &&
                    v > g.grossPot) {
                  return 'Supérieure à la cagnotte';
                }
                return null;
              },
            ),
            if (ready) ...[const SectionTitle('Résumé'), _Summary(g)],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.check),
              label: const Text('Créer le groupe'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.title);

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            child: Text(
              '$number',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    this.helper,
  });

  final String label;
  final DateTime date;
  final VoidCallback? onTap;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(dateLong(date)),
      ),
    );
  }
}

/// Résumé du groupe avant création : ce que chacun verse et reçoit.
class _Summary extends StatelessWidget {
  const _Summary(this.g);

  final Group g;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chaque participant cotise ${money(g.contributionAmount)} '
              '${frequencyLower(g.frequency)}, soit ${money(g.perMemberPerPot)} '
              'par cagnotte.',
              style: theme.textTheme.bodyMedium,
            ),
            const Divider(height: 24),
            InfoRow(
              'Cagnotte',
              '${g.memberCount} × ${money(g.perMemberPerPot)} = '
                  '${money(g.grossPot)}',
            ),
            InfoRow('Commission', commissionLabel(g)),
            InfoRow('Le bénéficiaire reçoit', money(g.netPot), bold: true),
            const Divider(height: 24),
            InfoRow('1re remise', dateLong(g.payoutDate(1))),
            InfoRow(
              'Remises suivantes',
              'tous les ${durationLabel(g.frequency, g.perPot)}',
            ),
            InfoRow('Dernière remise', dateLong(g.payoutDate(g.memberCount))),
            InfoRow(
              'Total versé par participant',
              money(g.totalContributions * g.contributionAmount),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================= Écran du groupe

/// Paiement d'un groupe ouvert par le tontinier (validation) ou par le
/// participant (consultation, reçu).
Widget groupPaymentScreen(Group g, Payment p, {required bool canReview}) =>
    ReviewPaymentScreen(
      payment: p,
      canReview: canReview,
      details: [
        ('Groupe', g.name),
        (
          'Cotisations',
          '${contributionsLabel(p.count)} × ${money(g.contributionAmount)}',
        ),
      ],
      onReview: (approve, reason) =>
          Api.reviewContributions(g.id, p, approve, reason),
      receipt: receiptText(
        p,
        tontine: g.tontineName,
        item: 'Groupe : ${g.name}',
        owner: g.ownerName,
        detail:
            '${contributionsLabel(p.count)} × ${money(g.contributionAmount)}',
      ),
    );

/// Paiement de cotisations par le participant (une ou plusieurs à la fois).
Widget payContributionsScreen(Group g, MemberStanding s) =>
    DeclarePaymentScreen(
      title: 'Payer mes cotisations',
      unitAmount: g.contributionAmount,
      maxUnits: s.remaining,
      initialUnits: max(1, s.late),
      unitsLabel: 'Nombre de cotisations payées',
      note: s.late > 0
          ? 'Vous avez ${contributionsLabel(s.late)} en retard '
                '(${money(s.late * g.contributionAmount)}).'
          : 'Vous êtes à jour. Vous pouvez aussi payer d\'avance.',
      details: [
        ('Groupe', g.name),
        (
          'Cotisation',
          '${money(g.contributionAmount)} · ${frequencyLower(g.frequency)}',
        ),
        ('Déjà payées', '${s.declared} / ${s.total}'),
      ],
      onSubmit: (proof, mime, count) => Api.declareContributions(
        group: g,
        count: count,
        proof: proof,
        mime: mime,
      ),
    );

/// Message de relance d'un participant en retard.
String reminderText(Group g, GroupMember m, MemberStanding s) =>
    'Bonjour ${m.name}, petit rappel pour le groupe « ${g.name} » '
    '(${g.tontineName}) : vous avez ${contributionsLabel(s.late)} en retard, '
    'soit ${money(s.late * g.contributionAmount)}. Merci de payer puis de '
    'déclarer votre paiement dans COTIZI. — ${g.ownerName}';

/// Détail d'un groupe, vu par le tontinier ou par un participant.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

typedef _GroupData = (Group, List<Payment>, Map<int, Payout>);

class _GroupScreenState extends State<GroupScreen> {
  late Future<_GroupData> _data = _load();
  bool _busy = false;

  Future<_GroupData> _load() async {
    final group = await Api.group(widget.groupId);
    final started =
        !group.isLegacy &&
        (group.status == GroupStatus.active ||
            group.status == GroupStatus.finished);
    final results = await Future.wait([
      Api.groupPayments(group),
      started ? Api.payouts(group.id) : Future.value(<int, Payout>{}),
    ]);
    return (group, results[0] as List<Payment>, results[1] as Map<int, Payout>);
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
          'Vous recevrez la cagnotte n°$position de ${money(g.netPot)} '
          'le ${dateLong(g.payoutDate(position))}.',
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

  void _pay(Group g, MemberStanding s) => _push(payContributionsScreen(g, s));

  Future<void> _confirmPayout(Group g) async {
    final pot = g.currentPot;
    final b = g.beneficiaryOf(pot);
    if (b == null) return;
    final collected = g.collectedFor(pot);
    if (await confirm(
      context,
      title: 'Confirmer la remise',
      message:
          'Avez-vous remis ${money(g.netPot)} à ${b.name} pour la cagnotte '
          'n°$pot ?${collected < g.grossPot ? '\n\nAttention : la collecte n\'est pas terminée (${money(collected)} validés sur ${money(g.grossPot)}).' : ''}'
          '\n\nCette confirmation est définitive et visible par les '
          'participants.',
      confirmLabel: 'Oui, c\'est remis',
    )) {
      await _run(() => Api.confirmPayout(g));
      if (mounted) showInfo(context, 'Remise de la cagnotte n°$pot confirmée');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groupe')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureView<_GroupData>(
          future: _data,
          onRetry: _reload,
          builder: (context, data) {
            final (g, payments, payouts) = data;
            final isOwner = g.ownerId == Api.uid;
            final started =
                g.status == GroupStatus.active ||
                g.status == GroupStatus.finished;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _header(g),
                if (g.isLegacy) ...[
                  _legacyNotice(),
                  ..._membersSection(g),
                ] else ...[
                  ..._statusSection(g, isOwner),
                  if (started) ...[
                    if (g.status == GroupStatus.active) _currentPot(g, isOwner),
                    if (g.status == GroupStatus.finished)
                      StatusCard(
                        icon: Icons.verified_outlined,
                        title: 'Tontine terminée',
                        message:
                            'Les ${g.memberCount} cagnottes ont été remises.',
                        color: paymentStatusColor(PaymentStatus.approved),
                      ),
                    if (!isOwner) ..._mySituation(g, payments),
                    if (isOwner) ..._pendingSection(g, payments),
                    if (isOwner) ..._trackingSection(g),
                    ..._calendarSection(g, payouts),
                  ] else
                    ..._membersSection(g),
                ],
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                StatusChip(
                  groupStatusLabel(g.status),
                  g.status == GroupStatus.finished
                      ? paymentStatusColor(PaymentStatus.approved)
                      : theme.colorScheme.primary,
                ),
              ],
            ),
            Text(
              '${g.tontineName} · Tontinier : ${g.ownerName}',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            FigureGrid([
              Figure(
                'Cotisation',
                money(g.contributionAmount),
                caption: frequencyLower(g.frequency),
              ),
              if (g.isLegacy)
                Figure('Premier tour', dateShort(g.startDate))
              else
                Figure(
                  'Collecte',
                  durationLabel(g.frequency, g.perPot),
                  caption: 'avant chaque remise',
                ),
              Figure(
                'Cagnotte',
                money(g.grossPot),
                caption: 'reçu : ${money(g.netPot)}',
              ),
              Figure(
                'Participants',
                '${g.joinedCount} / ${g.memberCount}',
                caption: 'commission ${commissionLabel(g)}',
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _legacyNotice() => const Padding(
    padding: EdgeInsets.only(top: 4),
    child: _Notice(
      icon: Icons.history,
      text:
          'Ce groupe a été créé avec une ancienne version de COTIZI. Il reste '
          'consultable, mais les paiements se font dans les nouveaux groupes.',
    ),
  );

  // --------------------------------------------- Inscriptions et tirage

  List<Widget> _statusSection(Group g, bool isOwner) {
    final joined = g.members.length;
    final me = g.memberById(Api.uid);
    switch (g.status) {
      case GroupStatus.recruiting:
        if (isOwner) {
          return [
            const SizedBox(height: 4),
            InviteCodeCard(
              code: g.inviteCode,
              hint:
                  'Appuyez sur Partager : vos participants recevront un lien '
                  'pour rejoindre le groupe.',
              shareText: inviteMessage(
                'Rejoins le groupe « ${g.name} » de ma tontine sur COTIZI. '
                'Cotisation : ${money(g.contributionAmount)} '
                '${frequencyLower(g.frequency)}, cagnotte de '
                '${money(g.netPot)} remise tous les '
                '${durationLabel(g.frequency, g.perPot)}.',
                g.inviteCode,
              ),
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
                            'Plus personne ne pourra rejoindre le groupe. '
                            'Chaque participant tirera son numéro : c\'est '
                            'l\'ordre des remises.',
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
          _Notice(
            icon: Icons.hourglass_top,
            text: joined < g.memberCount
                ? 'En attente des autres participants ($joined / '
                      '${g.memberCount}). Le tontinier lancera ensuite le '
                      'tirage au sort.'
                : 'Le groupe est complet. Le tontinier va lancer le tirage '
                      'au sort.',
          ),
        ];
      case GroupStatus.drawing:
        final drawn = g.members.where((m) => m.drawPosition != null).length;
        if (isOwner) {
          return [
            _Notice(
              icon: Icons.casino_outlined,
              text:
                  'Tirage au sort en cours : $drawn / ${g.memberCount} '
                  'participants ont tiré leur numéro.',
            ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      if (await confirm(
                        context,
                        title: 'Terminer le tirage',
                        message:
                            'Les participants qui n\'ont pas encore tiré '
                            'recevront un numéro au hasard.',
                        confirmLabel: 'Tirer pour eux',
                      )) {
                        await _run(() => Api.finishDraw(g));
                      }
                    },
              icon: const Icon(Icons.shuffle),
              label: const Text('Tirer pour les participants restants'),
            ),
          ];
        }
        if (me != null && me.drawPosition == null) {
          return [
            const SizedBox(height: 4),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.casino, size: 48),
                    const SizedBox(height: 8),
                    const Text(
                      'Le tirage au sort est ouvert ! Tirez votre numéro pour '
                      'savoir quand vous recevrez la cagnotte.',
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
          _Notice(
            icon: Icons.casino_outlined,
            text:
                'Vous avez tiré le n°${me?.drawPosition}. En attente des '
                'autres participants ($drawn / ${g.memberCount}).',
          ),
        ];
      case GroupStatus.active:
      case GroupStatus.finished:
        return const [];
    }
  }

  // ------------------------------------------------- Cagnotte en cours

  Widget _currentPot(Group g, bool isOwner) {
    final theme = Theme.of(context);
    final pot = g.currentPot;
    final b = g.beneficiaryOf(pot);
    final isMine = b?.userId == Api.uid;
    final validated = g.collectedFor(pot);
    final declared = g.collectedFor(pot, withPending: true);
    final percent = g.grossPot == 0
        ? 0
        : (100 * validated / g.grossPot).round();
    final date = g.payoutDate(pot);
    final overdue = date.isBefore(DateUtils.dateOnly(DateTime.now()));
    return Card(
      color: isMine ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.savings_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cagnotte n°$pot sur ${g.memberCount}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                StatusChip(
                  'En cours de collecte',
                  paymentStatusColor(PaymentStatus.pending),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FigureGrid([
              Figure(
                'Bénéficiaire',
                isMine ? 'Vous !' : (b?.name ?? '—'),
                caption: 'reçoit ${money(g.netPot)}',
              ),
              Figure('Remise', dateShort(date), caption: countdownLabel(date)),
            ]),
            const SizedBox(height: 16),
            ProgressLine(
              value: g.grossPot == 0 ? 0 : validated / g.grossPot,
              label:
                  '${money(validated)} validés sur ${money(g.grossPot)} '
                  '($percent %)'
                  '${declared > validated ? ' · + ${money(declared - validated)} en attente' : ''}',
            ),
            const SizedBox(height: 4),
            Text(
              'Collecte du ${dateShort(g.collectStart(pot))} au '
              '${dateShort(g.collectEnd(pot))}',
              style: theme.textTheme.bodySmall,
            ),
            if (isOwner && b != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : () => _confirmPayout(g),
                icon: const Icon(Icons.payments_outlined),
                label: Text('Confirmer la remise à ${b.name}'),
              ),
              if (overdue)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'La date de remise est passée : confirmez la remise dès '
                    'que la cagnotte est donnée.',
                    style: TextStyle(
                      color: paymentStatusColor(PaymentStatus.pending),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // --------------------------------------------- Situation du participant

  List<Widget> _mySituation(Group g, List<Payment> payments) {
    final me = g.memberById(Api.uid);
    if (me == null) return const [];
    final s = g.standingOf(me, DateTime.now());
    final good = paymentStatusColor(PaymentStatus.approved);
    final bad = paymentStatusColor(PaymentStatus.rejected);
    final mine = payments.where((p) => p.userId == Api.uid).toList();
    final pos = me.drawPosition;
    return [
      const SectionTitle('Ma situation'),
      StatusCard(
        icon: s.allPaid
            ? Icons.verified
            : s.upToDate
            ? Icons.check_circle
            : Icons.warning_amber_rounded,
        color: s.upToDate ? good : bad,
        title: s.allPaid
            ? 'Toutes vos cotisations sont payées'
            : s.upToDate
            ? 'Vous êtes à jour'
            : '${contributionsLabel(s.late)} en retard',
        message: s.upToDate
            ? [
                if (s.pending > 0)
                  '${contributionsLabel(s.pending)} en attente de validation.',
                if (s.ahead > 0)
                  'Vous avez payé ${contributionsLabel(s.ahead)} d\'avance.',
                if (s.remaining > 0)
                  'Prochaine cotisation : '
                      '${dateLong(g.contributionDate(s.declared + 1))}.',
              ].join(' ')
            : 'Montant à régulariser : ${money(s.late * g.contributionAmount)}.',
        children: [
          const SizedBox(height: 12),
          ProgressLine(
            value: s.total == 0 ? 0 : s.approved / s.total,
            color: good,
            label:
                '${s.approved} / ${s.total} cotisations validées'
                '${s.pending > 0 ? ' · ${s.pending} en attente' : ''}',
          ),
          if (s.remaining > 0 && g.status == GroupStatus.active) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _pay(g, s),
              icon: const Icon(Icons.upload),
              label: Text(
                s.late > 0 ? 'Payer mes cotisations en retard' : 'Payer',
              ),
            ),
          ],
        ],
      ),
      if (pos != null)
        Card(
          child: ListTile(
            leading: const Icon(Icons.emoji_events_outlined),
            title: Text(
              pos <= g.paidOutCount
                  ? 'Vous avez reçu la cagnotte n°$pos'
                  : 'Vous recevez la cagnotte n°$pos',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${money(g.netPot)} · ${dateLong(g.payoutDate(pos))}',
            ),
          ),
        ),
      if (mine.isNotEmpty) ...[
        SectionTitle('Mes paiements (${mine.length})'),
        for (final p in mine)
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(
                '${contributionsLabel(p.count)} · ${money(p.amount)}',
              ),
              subtitle: Text(
                p.status == PaymentStatus.rejected
                    ? 'Refusé : ${p.rejectionReason ?? ''}'
                    : 'Déclaré le ${dateTime(p.declaredAt)}',
              ),
              trailing: StatusChip.payment(p.status),
              onTap: () => _push(groupPaymentScreen(g, p, canReview: false)),
            ),
          ),
      ],
    ];
  }

  // ------------------------------------------------------- Tontinier

  List<Widget> _pendingSection(Group g, List<Payment> payments) {
    final pending = payments
        .where((p) => p.status == PaymentStatus.pending)
        .toList();
    if (pending.isEmpty) return const [];
    final color = paymentStatusColor(PaymentStatus.pending);
    return [
      SectionTitle('Paiements à valider (${pending.length})'),
      for (final p in pending)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              foregroundColor: color,
              child: const Icon(Icons.receipt_long),
            ),
            title: Text(p.payer.fullName),
            subtitle: Text(
              '${contributionsLabel(p.count)} · ${dateTime(p.declaredAt)}',
            ),
            trailing: Text(
              money(p.amount),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onTap: () => _push(groupPaymentScreen(g, p, canReview: true)),
          ),
        ),
    ];
  }

  /// Suivi des participants : à jour ou en retard, avec relance.
  List<Widget> _trackingSection(Group g) {
    final today = DateTime.now();
    final standings = [for (final m in g.members) (m, g.standingOf(m, today))];
    final lateCount = standings.where((e) => !e.$2.upToDate).length;
    final good = paymentStatusColor(PaymentStatus.approved);
    final bad = paymentStatusColor(PaymentStatus.rejected);
    return [
      SectionTitle(
        'Suivi des participants',
        trailing: Text(
          lateCount == 0 ? 'Tous à jour' : '$lateCount en retard',
          style: TextStyle(
            color: lateCount == 0 ? good : bad,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      for (final (m, s) in standings)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                m.drawPosition == null ? '?' : '${m.drawPosition}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(m.name),
            subtitle: Text(
              s.upToDate
                  ? '${s.approved} / ${s.total} validées'
                        '${s.pending > 0 ? ' · ${s.pending} en attente' : ''}'
                  : '${contributionsLabel(s.late)} en retard · '
                        '${money(s.late * g.contributionAmount)}',
              style: TextStyle(color: s.upToDate ? null : bad),
            ),
            trailing: s.upToDate
                ? StatusChip('À jour', good)
                : IconButton.filledTonal(
                    tooltip: 'Relancer ${m.name} sur WhatsApp',
                    onPressed: () => openWhatsApp(
                      context,
                      m.profile.phone,
                      reminderText(g, m, s),
                    ),
                    icon: const Icon(Icons.campaign_outlined),
                  ),
          ),
        ),
    ];
  }

  // ------------------------------------------------ Calendrier des remises

  List<Widget> _calendarSection(Group g, Map<int, Payout> payouts) {
    final theme = Theme.of(context);
    final good = paymentStatusColor(PaymentStatus.approved);
    return [
      const SectionTitle('Calendrier des remises'),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var pot = 1; pot <= g.memberCount; pot++)
              Builder(
                builder: (context) {
                  final b = g.beneficiaryOf(pot);
                  final done = payouts[pot];
                  final current =
                      g.status == GroupStatus.active && pot == g.currentPot;
                  final mine = b?.userId == Api.uid;
                  return ListTile(
                    tileColor: mine
                        ? theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.5,
                          )
                        : null,
                    leading: CircleAvatar(
                      backgroundColor: done != null
                          ? good.withValues(alpha: 0.15)
                          : null,
                      foregroundColor: done != null ? good : null,
                      child: done != null
                          ? const Icon(Icons.check)
                          : Text(
                              '$pot',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                    title: Text(
                      mine ? '${b!.name} (vous)' : (b?.name ?? 'À tirer'),
                      style: TextStyle(
                        fontWeight: current || mine
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      done != null
                          ? 'Remise le ${dateShort(done.paidAt)} · '
                                '${money(done.amount)}'
                          : 'Remise prévue le ${dateShort(g.payoutDate(pot))}',
                    ),
                    trailing: done != null
                        ? StatusChip('Remise', good)
                        : current
                        ? StatusChip(
                            'En cours',
                            paymentStatusColor(PaymentStatus.pending),
                          )
                        : const StatusChip('À venir', Colors.grey),
                  );
                },
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _membersSection(Group g) {
    return [
      SectionTitle('Participants (${g.members.length} / ${g.memberCount})'),
      if (g.members.isEmpty)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Aucun participant pour le moment.'),
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
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
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
