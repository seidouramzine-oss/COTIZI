import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Création (ou modification pendant les inscriptions) d'un groupe à
/// cagnotte, en 5 étapes, avec un résumé : dates de début et de fin,
/// montants, remises.
class GroupFormScreen extends StatefulWidget {
  const GroupFormScreen({super.key, required this.tontine, this.group});

  final Tontine tontine;

  /// Groupe à modifier (sinon : création).
  final Group? group;

  @override
  State<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends State<GroupFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Group? _g = widget.group;
  late final _name = TextEditingController(text: _g?.name ?? '');
  late final _members = TextEditingController(
    text: _g == null ? '' : '${_g.memberCount}',
  );
  late final _amount = TextEditingController(
    text: _g == null ? '' : '${_g.contributionAmount}',
  );
  late final _duration = TextEditingController(text: '${_g?.perPot ?? 30}');
  late final _commission = TextEditingController(
    text: _g == null ? '0' : _formatNumber(_g.commissionValue),
  );
  late final _penalty = TextEditingController(
    text: _g == null || _g.penaltyAmount == 0 ? '' : '${_g.penaltyAmount}',
  );
  late final _grace = TextEditingController(
    text: '${_g?.penaltyGraceDays ?? 1}',
  );
  late Frequency _frequency = _g?.frequency ?? Frequency.daily;
  late CommissionType _commissionType =
      _g?.commissionType ?? CommissionType.percent;
  late OrderMode _orderMode = _g?.orderMode ?? OrderMode.draw;
  late bool _withPenalty = (_g?.penaltyAmount ?? 0) > 0;
  late DateTime _start = _g?.startDate ?? DateUtils.dateOnly(DateTime.now());

  /// 1re remise choisie par le tontinier (sinon : dernier jour de collecte).
  late DateTime? _payout = _g?.firstPayoutDate;
  bool _busy = false;

  static String _formatNumber(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';

  @override
  void dispose() {
    for (final c in [
      _name,
      _members,
      _amount,
      _duration,
      _commission,
      _penalty,
      _grace,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _memberCount => int.tryParse(_members.text) ?? 0;
  int get _contribution => parseAmount(_amount.text) ?? 0;
  int get _perPot => int.tryParse(_duration.text) ?? 0;
  int get _penaltyAmount =>
      _withPenalty ? (parseAmount(_penalty.text) ?? 0) : 0;
  int get _graceDays => _withPenalty ? (int.tryParse(_grace.text) ?? 0) : 0;
  double get _commissionValue =>
      double.tryParse(
        _commission.text.replaceAll(',', '.').replaceAll(' ', ''),
      ) ??
      0;

  bool get _ready => _memberCount >= 2 && _contribution > 0 && _perPot >= 1;

  Group _preview() {
    Group draft(DateTime payout) => Group(
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
      firstPayoutDate: payout,
      orderMode: _orderMode,
      penaltyAmount: _penaltyAmount,
      penaltyGraceDays: _graceDays,
      commissionType: _commissionType,
      commissionValue: _commissionValue,
      inviteCode: '',
      status: GroupStatus.recruiting,
    );
    final end = draft(_start).collectEnd(1);
    final payout = _payout;
    return draft(payout != null && !payout.isBefore(end) ? payout : end);
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      helpText: 'Date de début prévue',
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
    final terms = GroupTerms(
      name: _name.text,
      memberCount: _memberCount,
      contributionAmount: _contribution,
      frequency: _frequency,
      startDate: _start,
      contributionsPerPot: _perPot,
      firstPayoutDate: g.firstPayoutDate!,
      orderMode: _orderMode,
      penaltyAmount: _penaltyAmount,
      penaltyGraceDays: _graceDays,
      commissionType: _commissionType,
      commissionValue: _commissionValue,
    );
    setState(() => _busy = true);
    try {
      final edit = widget.group;
      if (edit == null) {
        await Api.createGroup(widget.tontine, terms);
      } else {
        await Api.updateGroup(edit, terms);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _preview();
    final theme = Theme.of(context);
    final editing = widget.group != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Modifier le groupe' : 'Nouveau groupe'),
      ),
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
                if (n < 2 || n > 100) return 'Entre 2 et 100 participants';
                final joined = widget.group?.joinedCount ?? 0;
                return n < joined ? 'Déjà $joined inscrits' : null;
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
            const _Step(3, 'Les remises'),
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
            Text('Ordre des remises', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            SegmentedButton<OrderMode>(
              segments: const [
                ButtonSegment(
                  value: OrderMode.draw,
                  icon: Icon(Icons.casino_outlined),
                  label: Text('Tirage au sort'),
                ),
                ButtonSegment(
                  value: OrderMode.manual,
                  icon: Icon(Icons.format_list_numbered),
                  label: Text('Fixé par moi'),
                ),
              ],
              selected: {_orderMode},
              onSelectionChanged: (s) => setState(() => _orderMode = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              _orderMode == OrderMode.draw
                  ? 'Chaque participant tire son numéro quand le groupe est complet.'
                  : 'Vous classez vous-même les participants quand le groupe est complet.',
              style: theme.textTheme.bodySmall,
            ),
            const _Step(4, 'Commission et pénalités'),
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
                    _ready &&
                    v > g.grossPot) {
                  return 'Supérieure à la cagnotte';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pénalités de retard'),
              subtitle: const Text(
                'Ajoutées aux cotisations payées en retard. Elles vous reviennent.',
              ),
              value: _withPenalty,
              onChanged: (v) => setState(() => _withPenalty = v),
            ),
            if (_withPenalty) ...[
              TextFormField(
                controller: _penalty,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Pénalité par cotisation en retard',
                  suffixText: 'FCFA',
                ),
                validator: (v) {
                  final n = parseAmount(v ?? '') ?? 0;
                  return n <= 0 || n > 1000000 ? 'Indiquez un montant' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _grace,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Jours de tolérance',
                  suffixText: 'jours',
                  helperText: 'Pas de pénalité si la cotisation est payée dans ce délai.',
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '') ?? -1;
                  return n < 0 || n > 30 ? 'Entre 0 et 30 jours' : null;
                },
              ),
            ],
            const _Step(5, 'Les dates'),
            _DateField(
              label: 'Date de début prévue (1re cotisation)',
              date: _start,
              helper:
                  'Vous la confirmerez en démarrant la tontine, après '
                  'l\'ordre des remises.',
              onTap: _pickStart,
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Date de la 1re remise',
              date: g.firstPayoutDate!,
              helper: _ready
                  ? 'Collecte ${periodLabel(g.collectStart(1), g.collectEnd(1))}. '
                        'Remises suivantes : tous les '
                        '${durationLabel(_frequency, g.perPot)}.'
                  : null,
              onTap: _ready ? _pickPayout : null,
            ),
            if (_ready) ...[const SectionTitle('Résumé'), GroupSummary(g)],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.check),
              label: Text(editing ? 'Enregistrer' : 'Créer le groupe'),
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

/// Résumé d'un groupe : ce que chacun verse et reçoit, début et fin.
class GroupSummary extends StatelessWidget {
  const GroupSummary(this.g, {super.key});

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
            InfoRow('Début', dateLong(g.startDate), bold: true),
            InfoRow('Fin (dernière remise)', dateLong(g.endDate), bold: true),
            InfoRow('Nombre de cagnottes', '${g.memberCount}'),
            const Divider(height: 24),
            InfoRow(
              'Cagnotte',
              '${g.memberCount} × ${money(g.perMemberPerPot)} = '
                  '${money(g.grossPot)}',
            ),
            InfoRow('Commission', commissionLabel(g)),
            InfoRow('Le bénéficiaire reçoit', money(g.netPot), bold: true),
            InfoRow(
              'Remises',
              'à partir du ${dateShort(g.payoutDate(1))}, tous les '
                  '${durationLabel(g.frequency, g.perPot)}',
            ),
            InfoRow(
              'Total versé par participant',
              money(g.totalContributions * g.contributionAmount),
            ),
            if (g.hasPenalty)
              InfoRow(
                'Pénalité de retard',
                g.penaltyGraceDays == 0
                    ? '${money(g.penaltyAmount)} par cotisation, dès le '
                          'lendemain de l\'échéance'
                    : '${money(g.penaltyAmount)} par cotisation, après '
                          '${g.penaltyGraceDays} jour${g.penaltyGraceDays > 1 ? 's' : ''} '
                          'de tolérance',
              ),
            InfoRow(
              'Ordre des remises',
              g.orderMode == OrderMode.manual
                  ? 'fixé par le tontinier'
                  : 'tirage au sort',
            ),
          ],
        ),
      ),
    );
  }
}
