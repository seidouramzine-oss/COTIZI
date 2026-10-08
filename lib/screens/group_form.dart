import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Création (ou modification pendant les inscriptions) d'un groupe à
/// cagnotte, en 4 étapes, avec le montant de la cagnotte toujours visible
/// et un résumé final : dates de début et de fin, montants, remises.
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
  late final _duration = TextEditingController(text: '${_g?.perPot ?? 1}');

  /// Tontine tournante : une remise à chaque cotisation (collecte d'une
  /// seule cotisation par participant).
  late bool _rotating = (_g?.perPot ?? 1) == 1;
  late final _commission = TextEditingController(
    text: _g == null ? '0' : _formatNumber(_g.commissionValue),
  );
  late final _penalty = TextEditingController(
    text: _g == null || _g.penaltyAmount == 0 ? '' : '${_g.penaltyAmount}',
  );
  late final _grace = TextEditingController(
    text: '${_g?.penaltyGraceDays ?? 1}',
  );
  late final _rules = TextEditingController(text: _g?.rulesText ?? '');
  late PenaltyType _penaltyType = _g?.penaltyType ?? PenaltyType.fixed;
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
      _rules,
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
      penaltyType: _penaltyType,
      rulesText: _rules.text.trim(),
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
      penaltyType: _penaltyType,
      rulesText: _rules.text,
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

  static const _steps = ['Le groupe', 'Cotisations', 'Règles', 'Dates'];

  /// Étape affichée (0 à 3). Seuls ses champs sont vérifiés pour continuer.
  int _step = 0;

  void _next() {
    if (!_form.currentState!.validate()) return;
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  List<Widget> _groupStep() => [
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
    const SizedBox(height: 16),
    TextFormField(
      controller: _members,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(
        labelText: 'Nombre de participants',
        helperText:
            'Chacun reçoit la cagnotte une fois : il y aura autant de remises '
            'que de participants.',
        helperMaxLines: 2,
      ),
      validator: (v) {
        final n = int.tryParse(v ?? '') ?? 0;
        if (n < 2 || n > 100) return 'Entre 2 et 100 participants';
        final joined = widget.group?.joinedCount ?? 0;
        return n < joined ? 'Déjà $joined inscrits' : null;
      },
    ),
  ];

  List<Widget> _contributionStep(ThemeData theme) => [
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
    const SizedBox(height: 16),
    Text(
      'Fréquence',
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
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
    const SizedBox(height: 20),
    Text(
      'Quand la cagnotte est-elle remise ?',
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    _ModeCard(
      selected: _rotating,
      title: 'À chaque cotisation (tontine tournante)',
      text:
          '${_capitalize(frequencyLower(_frequency))}, tout le monde cotise et '
          'un participant reçoit la cagnotte. Avec '
          '${_memberCount >= 2 ? _memberCount : 'N'} participants, la tontine '
          'dure ${_memberCount >= 2 ? durationLabel(_frequency, _memberCount) : 'N ${durationUnit(_frequency)}'} '
          'et chacun reçoit une fois.',
      onTap: () => setState(() {
        _rotating = true;
        _duration.text = '1';
        _payout = null;
      }),
    ),
    const SizedBox(height: 8),
    _ModeCard(
      selected: !_rotating,
      title: 'Après plusieurs cotisations',
      text:
          'La cagnotte est remise après une période de collecte (ex. 30 jours '
          'de cotisations), puis la suivante commence.',
      onTap: () => setState(() {
        _rotating = false;
        if (_perPot <= 1) _duration.text = '';
        _payout = null;
      }),
    ),
    if (!_rotating) ...[
      const SizedBox(height: 16),
      TextFormField(
        controller: _duration,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: 'Durée de collecte avant chaque remise',
          suffixText: durationUnit(_frequency),
          helperText: _perPot >= 1
              ? 'Soit ${contributionsLabel(_perPot)} par participant pour '
                    'chaque cagnotte'
              : null,
        ),
        validator: (v) {
          final n = int.tryParse(v ?? '') ?? 0;
          return n < 2 || n > 366 ? 'Entre 2 et 366' : null;
        },
        onChanged: (_) => _payout = null,
      ),
    ],
    if (_ready) ...[
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Durée totale : ${durationLabel(_frequency, _memberCount * _perPot)} · '
          '$_memberCount remises, une tous les '
          '${durationLabel(_frequency, _perPot)}. Chaque participant verse '
          '${money(_perPot * _contribution)} par cagnotte.',
          style: theme.textTheme.bodySmall,
        ),
      ),
    ],
  ];

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  List<Widget> _payoutStep(ThemeData theme, Group g) => [
    Text(
      'Ordre des remises',
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
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
    const SizedBox(height: 20),
    Text(
      'Votre commission',
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    SegmentedButton<CommissionType>(
      segments: const [
        ButtonSegment(
          value: CommissionType.percent,
          label: Text('Pourcentage'),
        ),
        ButtonSegment(value: CommissionType.fixed, label: Text('Montant fixe')),
      ],
      selected: {_commissionType},
      onSelectionChanged: (s) => setState(() => _commissionType = s.first),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _commission,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Commission sur chaque cagnotte',
        suffixText: _commissionType == CommissionType.percent ? '%' : 'FCFA',
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
      SegmentedButton<PenaltyType>(
        segments: const [
          ButtonSegment(value: PenaltyType.percent, label: Text('Pourcentage')),
          ButtonSegment(value: PenaltyType.fixed, label: Text('Montant fixe')),
        ],
        selected: {_penaltyType},
        onSelectionChanged: (s) => setState(() => _penaltyType = s.first),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _penalty,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: _penaltyType == PenaltyType.percent
              ? 'Pénalité (% du montant dû)'
              : 'Pénalité par cotisation en retard',
          suffixText: _penaltyType == PenaltyType.percent ? '%' : 'FCFA',
          helperText:
              _penaltyType == PenaltyType.percent &&
                  _contribution > 0 &&
                  _penaltyAmount > 0
              ? 'Soit ${money(g.penaltyPerContribution)} par cotisation de '
                    '${money(_contribution)} payée en retard'
              : null,
        ),
        validator: (v) {
          final n = parseAmount(v ?? '') ?? 0;
          if (_penaltyType == PenaltyType.percent) {
            return n <= 0 || n > 100 ? 'Entre 1 et 100 %' : null;
          }
          return n <= 0 || n > 1000000 ? 'Indiquez un montant' : null;
        },
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _grace,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Appliquée après combien de jours de retard ?',
          suffixText: 'jours',
          helperText:
              'Ex. 2 : pas de pénalité si la cotisation est payée dans les '
              '2 jours qui suivent sa date.',
          helperMaxLines: 2,
        ),
        validator: (v) {
          final n = int.tryParse(v ?? '') ?? -1;
          return n < 0 || n > 30 ? 'Entre 0 et 30 jours' : null;
        },
      ),
    ],
    const SizedBox(height: 20),
    Text(
      'Vos règles (facultatif)',
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    TextFormField(
      controller: _rules,
      minLines: 3,
      maxLines: 8,
      maxLength: 2000,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText:
            'Ex. Les cotisations se paient avant 18 h. En cas d\'abandon, '
            'les sommes versées sont rendues à la fin de la tontine.',
        helperText:
            'Avec les conditions ci-dessus, elles forment le règlement que '
            'chaque participant devra accepter avant le démarrage.',
        helperMaxLines: 3,
      ),
    ),
  ];

  List<Widget> _datesStep(Group g) => [
    _DateField(
      label: 'Date de début prévue (1re cotisation)',
      date: _start,
      helper:
          'Vous la confirmerez en démarrant la tontine, après l\'ordre des '
          'remises.',
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
  ];

  @override
  Widget build(BuildContext context) {
    final g = _preview();
    final theme = Theme.of(context);
    final editing = widget.group != null;
    final last = _step == _steps.length - 1;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(editing ? 'Modifier le groupe' : 'Nouveau groupe'),
              Text(
                'Étape ${_step + 1} sur ${_steps.length} · ${_steps[_step]}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        body: Form(
          key: _form,
          onChanged: () => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _StepBar(steps: _steps, current: _step),
              const SizedBox(height: 20),
              ...switch (_step) {
                0 => _groupStep(),
                1 => _contributionStep(theme),
                2 => _payoutStep(theme, g),
                _ => _datesStep(g),
              },
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_ready) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Chaque cagnotte',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        Text(
                          money(g.grossPot),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    if (_step > 0) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _step--),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                          ),
                          child: const Text('Retour'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _next,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 50),
                        ),
                        child: Text(
                          !last
                              ? 'Continuer'
                              : editing
                              ? 'Enregistrer'
                              : 'Créer le groupe',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre d'avancement des étapes.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < steps.length - 1 ? 6 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= current
                          ? scheme.primary
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    steps[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == current
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: i <= current
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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
            if (g.hasPenalty) InfoRow('Pénalité de retard', penaltyLabel(g)),
            if (!g.hasPenalty) const InfoRow('Pénalité de retard', 'aucune'),
            InfoRow(
              'Ordre des remises',
              g.orderMode == OrderMode.manual
                  ? 'fixé par le tontinier'
                  : 'tirage au sort',
            ),
            InfoRow(
              'Remise de la cagnotte',
              'quand toute sa collecte est payée',
            ),
            if (g.rulesText.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Règles du tontinier',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(g.rulesText, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

/// Choix d'un mode (carte sélectionnable avec explication).
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.title,
    required this.text,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(text, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
