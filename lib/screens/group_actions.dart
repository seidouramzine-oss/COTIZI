import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'auth_screens.dart' show PhoneField;
import 'group_form.dart';

/// Ajout d'un participant sans application : nom et numéro.
/// Renvoie (nom, numéro au format +229…).
class AddManagedMemberDialog extends StatefulWidget {
  const AddManagedMemberDialog({super.key});

  @override
  State<AddManagedMemberDialog> createState() => _AddManagedMemberDialogState();
}

class _AddManagedMemberDialogState extends State<AddManagedMemberDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _dialCode = dialCodes.first.$1;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Participant sans application'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Vous gérez ses paiements. S\'il s\'inscrit un jour comme '
                'client avec ce numéro et le lien du groupe, il retrouve sa '
                'place.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom et prénom'),
                validator: (v) {
                  final n = (v ?? '').trim().length;
                  return n < 2 || n > 60 ? 'Indiquez son nom' : null;
                },
              ),
              const SizedBox(height: 12),
              PhoneField(
                dialCode: _dialCode,
                onDialCodeChanged: (v) => setState(() => _dialCode = v),
                controller: _phone,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, (
              _name.text.trim(),
              normalizePhone(_dialCode, _phone.text),
            ));
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

/// Ordre des remises fixé par le tontinier : glisser pour classer.
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.group});

  final Group group;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late final List<GroupMember> _order = [...widget.group.members];
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await Api.setManualOrder(widget.group, _order);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Scaffold(
      appBar: AppBar(title: const Text('Ordre des remises')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Enregistrer l\'ordre'),
          ),
        ),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Maintenez un participant puis faites-le glisser. Le premier '
              'reçoit la première cagnotte.',
            ),
          ),
          Expanded(
            child: ReorderableListView(
              padding: const EdgeInsets.all(16),
              onReorderItem: (from, to) => setState(() {
                _order.insert(to, _order.removeAt(from));
              }),
              children: [
                for (var i = 0; i < _order.length; i++)
                  Card(
                    key: ValueKey(_order[i].userId),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(_order[i].name),
                      subtitle: Text(
                        'Remise prévue le ${dateShort(g.payoutDate(i + 1))}',
                      ),
                      trailing: const Icon(Icons.drag_handle),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Démarrage de la tontine : le tontinier confirme les dates, qui sont
/// ensuite figées.
class StartGroupScreen extends StatefulWidget {
  const StartGroupScreen({super.key, required this.group});

  final Group group;

  @override
  State<StartGroupScreen> createState() => _StartGroupScreenState();
}

class _StartGroupScreenState extends State<StartGroupScreen> {
  late DateTime _start = _defaultStart();
  DateTime? _payout;
  bool _busy = false;

  DateTime _defaultStart() {
    final today = DateUtils.dateOnly(DateTime.now());
    final planned = widget.group.startDate;
    return planned.isBefore(today) ? today : planned;
  }

  Group get _preview {
    final g = widget.group;
    Group withDates(DateTime payout) => Group(
      id: g.id,
      tontineId: g.tontineId,
      tontineName: g.tontineName,
      ownerId: g.ownerId,
      ownerName: g.ownerName,
      name: g.name,
      memberCount: g.memberCount,
      contributionAmount: g.contributionAmount,
      frequency: g.frequency,
      startDate: _start,
      contributionsPerPot: g.contributionsPerPot,
      firstPayoutDate: payout,
      orderMode: g.orderMode,
      penaltyAmount: g.penaltyAmount,
      penaltyGraceDays: g.penaltyGraceDays,
      commissionType: g.commissionType,
      commissionValue: g.commissionValue,
      inviteCode: g.inviteCode,
      status: GroupStatus.ready,
      members: g.members,
    );
    final end = withDates(_start).collectEnd(1);
    final payout = _payout;
    return withDates(payout != null && !payout.isBefore(end) ? payout : end);
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      helpText: 'Date de la 1re cotisation',
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() {
        _start = d;
        _payout = null;
      });
    }
  }

  Future<void> _pickPayout() async {
    final g = _preview;
    final earliest = g.collectEnd(1);
    final d = await showDatePicker(
      context: context,
      helpText: 'Date de la 1re remise',
      initialDate: g.firstPayoutDate!,
      firstDate: earliest,
      lastDate: earliest.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _payout = d);
  }

  Future<void> _launch() async {
    final g = _preview;
    if (!await confirm(
      context,
      title: 'Démarrer la tontine',
      message:
          'La tontine se déroulera ${periodLabel(g.startDate, g.endDate)}. '
          'Les dates ne pourront plus être changées.',
      confirmLabel: 'Démarrer',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.startGroup(
        widget.group,
        g.startDate,
        g.firstPayoutDate!,
        periodLabel(g.startDate, g.endDate),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Démarrer la tontine')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Confirmez les dates. Dès le démarrage, les participants peuvent '
            'payer et les retards sont comptés.',
          ),
          const SizedBox(height: 16),
          _DateTile(
            label: 'Date de la 1re cotisation',
            date: g.startDate,
            onTap: _pickStart,
          ),
          const SizedBox(height: 12),
          _DateTile(
            label: 'Date de la 1re remise',
            date: g.firstPayoutDate!,
            helper:
                'Collecte ${periodLabel(g.collectStart(1), g.collectEnd(1))}',
            onTap: _pickPayout,
          ),
          const SectionTitle('Résumé'),
          GroupSummary(g),
          const SectionTitle('Calendrier des remises'),
          Card(
            child: Column(
              children: [
                for (var pot = 1; pot <= g.memberCount; pot++)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 14, child: Text('$pot')),
                    title: Text(g.beneficiaryOf(pot)?.name ?? '—'),
                    trailing: Text(dateShort(g.payoutDate(pot))),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _launch,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Démarrer la tontine'),
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.date,
    required this.onTap,
    this.helper,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;
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
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(dateLong(date)),
      ),
    );
  }
}

/// Journal du groupe.
class GroupEventsScreen extends StatelessWidget {
  const GroupEventsScreen({super.key, required this.group});

  final Group group;

  static IconData _icon(String type) => switch (type) {
    'created' || 'edited' => Icons.edit_note,
    'joined' || 'managed_added' => Icons.person_add_alt,
    'member_removed' => Icons.person_remove_outlined,
    'draw_started' ||
    'number_drawn' ||
    'draw_finished' => Icons.casino_outlined,
    'order_set' => Icons.format_list_numbered,
    'started' => Icons.play_circle_outline,
    'payment_declared' => Icons.upload,
    'payment_approved' || 'payment_recorded' => Icons.check_circle_outline,
    'payment_rejected' => Icons.cancel_outlined,
    'payout_confirmed' => Icons.payments_outlined,
    'payout_received' => Icons.done_all,
    'payout_problem' => Icons.report_problem_outlined,
    _ => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: FutureBuilder<List<GroupEvent>>(
        future: Api.events(group),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(errorMessage(snap.error!)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final events = snap.data!;
          if (events.isEmpty) {
            return const EmptyState(
              icon: Icons.history,
              title: 'Aucune action',
              message: 'Les actions du groupe apparaîtront ici.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = events[i];
              return ListTile(
                leading: Icon(
                  _icon(e.type),
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(e.text),
                subtitle: Text('${e.actorName} · ${dateTime(e.at)}'),
              );
            },
          );
        },
      ),
    );
  }
}
