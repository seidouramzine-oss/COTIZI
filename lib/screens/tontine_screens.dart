import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'carnet_screens.dart';
import 'group_screens.dart';
import 'subscription_screens.dart';

class CreateTontineScreen extends StatefulWidget {
  const CreateTontineScreen({super.key});

  @override
  State<CreateTontineScreen> createState() => _CreateTontineScreenState();
}

class _CreateTontineScreenState extends State<CreateTontineScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  TontineType _type = TontineType.cagnotte;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final tontine = await Api.createTontine(_name.text, _type);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TontineScreen(tontine: tontine)),
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
      appBar: AppBar(title: const Text('Nouvelle tontine')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nom de la tontine',
                hintText: 'Ex. Tontine des commerçantes',
              ),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'Donnez un nom à la tontine'
                  : null,
            ),
            const SectionTitle('Type de tontine'),
            _TypeCard(
              selected: _type == TontineType.cagnotte,
              icon: Icons.savings_outlined,
              title: 'Tontine à cagnotte',
              description:
                  'Vous créez des groupes. Les participants cotisent (chaque '
                  'jour, semaine ou mois) et la cagnotte est remise à chacun à '
                  'son tour, selon le tirage au sort.',
              onTap: () => setState(() => _type = TontineType.cagnotte),
            ),
            _TypeCard(
              selected: _type == TontineType.carnet,
              icon: Icons.menu_book_outlined,
              title: 'Tontine à carnet',
              description:
                  'Vous créez des carnets de 31 cases. Le client paie ses 31 cases, '
                  'récupère 30 cases et la dernière case est votre commission.',
              onTap: () => setState(() => _type = TontineType.carnet),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Créer la tontine'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: scheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(description),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: scheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Détail d'une tontine gérée : ses groupes (cagnotte) ou ses carnets.
class TontineScreen extends StatefulWidget {
  const TontineScreen({super.key, required this.tontine});

  final Tontine tontine;

  @override
  State<TontineScreen> createState() => _TontineScreenState();
}

class _TontineScreenState extends State<TontineScreen> {
  bool get _isCagnotte => widget.tontine.type == TontineType.cagnotte;
  late Future<List<Group>> _groups = Api.groupsOf(widget.tontine.id);
  late Future<List<Carnet>> _carnets = Api.carnetsOf(widget.tontine.id);

  void _reload() => setState(() {
    if (_isCagnotte) {
      _groups = Api.groupsOf(widget.tontine.id);
    } else {
      _carnets = Api.carnetsOf(widget.tontine.id);
    }
  });

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  Future<void> _createGroup() async {
    if (await checkCanCreate(context) && mounted) {
      await _open(CreateGroupScreen(tontine: widget.tontine));
    }
  }

  Future<void> _createCarnet(int existing) async {
    if (!await checkCanCreate(context) || !mounted) return;
    final carnetId = await showDialog<String>(
      context: context,
      builder: (_) => _CreateCarnetDialog(
        tontine: widget.tontine,
        defaultLabel: 'Carnet n°${existing + 1}',
      ),
    );
    if (carnetId != null && mounted) {
      await _open(CarnetScreen(carnetId: carnetId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.tontine.name),
            Text(
              _isCagnotte ? 'Tontine à cagnotte' : 'Tontine à carnet',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      floatingActionButton: _isCagnotte
          ? FloatingActionButton.extended(
              onPressed: _createGroup,
              icon: const Icon(Icons.group_add),
              label: const Text('Nouveau groupe'),
            )
          : FutureBuilder<List<Carnet>>(
              future: _carnets,
              builder: (context, snap) => FloatingActionButton.extended(
                onPressed: () => _createCarnet(snap.data?.length ?? 0),
                icon: const Icon(Icons.add),
                label: const Text('Nouveau carnet'),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: _isCagnotte ? _groupList() : _carnetList(),
      ),
    );
  }

  Widget _groupList() {
    return FutureView<List<Group>>(
      future: _groups,
      onRetry: _reload,
      builder: (context, groups) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (groups.isEmpty)
            const EmptyState(
              icon: Icons.groups_outlined,
              title: 'Aucun groupe',
              message:
                  'Créez un groupe : nombre de membres, cotisation, fréquence et commission. '
                  'Vous pourrez ensuite inviter vos membres.',
            ),
          for (final g in groups)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                title: Text(
                  g.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${g.joinedCount} / ${g.memberCount} participants · '
                  '${money(g.contributionAmount)} ${frequencyLower(g.frequency)}'
                  '${g.isLegacy ? '' : '\nCagnotte de ${money(g.netPot)} tous les ${durationLabel(g.frequency, g.perPot)}'}',
                ),
                isThreeLine: !g.isLegacy,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusChip(
                      groupStatusLabel(g.status),
                      Theme.of(context).colorScheme.primary,
                    ),
                    if (g.pendingCount > 0) ...[
                      const SizedBox(height: 4),
                      StatusChip(
                        '${g.pendingCount} à valider',
                        paymentStatusColor(PaymentStatus.pending),
                      ),
                    ],
                  ],
                ),
                onTap: () => _open(GroupScreen(groupId: g.id)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _carnetList() {
    return FutureView<List<Carnet>>(
      future: _carnets,
      onRetry: _reload,
      builder: (context, carnets) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (carnets.isEmpty)
            const EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'Aucun carnet',
              message: 'Créez un carnet de 31 cases et partagez son code avec votre client.',
            ),
          for (final c in carnets)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                title: Text(
                  c.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.client != null
                          ? '${c.client!.fullName} · ${money(c.caseAmount)} / case'
                          : 'Sans client · code ${c.inviteCode}',
                    ),
                    const SizedBox(height: 6),
                    // Le texte « x / 31 cases payées » suffit aux lecteurs d'écran
                    ExcludeSemantics(
                      child: LinearProgressIndicator(
                        value: c.approvedCases / c.caseCount,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('${c.approvedCases} / ${c.caseCount} cases payées'),
                  ],
                ),
                trailing: c.pendingCases > 0
                    ? StatusChip(
                        'À valider',
                        paymentStatusColor(PaymentStatus.pending),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () => _open(CarnetScreen(carnetId: c.id)),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateCarnetDialog extends StatefulWidget {
  const _CreateCarnetDialog({
    required this.tontine,
    required this.defaultLabel,
  });

  final Tontine tontine;
  final String defaultLabel;

  @override
  State<_CreateCarnetDialog> createState() => _CreateCarnetDialogState();
}

class _CreateCarnetDialogState extends State<_CreateCarnetDialog> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.defaultLabel);
  final _amount = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final carnetId = await Api.createCarnet(
        tontine: widget.tontine,
        label: _label.text,
        caseAmount: parseAmount(_amount.text)!,
      );
      if (mounted) Navigator.pop(context, carnetId);
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseAmount(_amount.text) ?? 0;
    return AlertDialog(
      title: const Text('Nouveau carnet'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Nom du carnet'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Donnez un nom au carnet' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Montant par case',
                suffixText: 'FCFA',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) => (parseAmount(v ?? '') ?? 0) <= 0
                  ? 'Indiquez le montant d\'une case'
                  : null,
            ),
            if (amount > 0) ...[
              const SizedBox(height: 12),
              Text('31 cases · total payé ${money(amount * 31)}'),
              Text('Le client reçoit ${money(amount * 30)}'),
              Text('Votre commission : ${money(amount)}'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
