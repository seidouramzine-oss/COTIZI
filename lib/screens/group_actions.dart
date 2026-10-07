import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'auth_screens.dart' show PhoneField;
import 'business_screens.dart';
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
  late Future<Business?> _business = Api.business(Api.uid);

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
      penaltyType: g.penaltyType,
      rulesText: g.rulesText,
      termsVersion: g.termsVersion,
      accepted: g.accepted,
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

  Widget _check(bool ok, String title, String subtitle, {Widget? action}) {
    final color = ok
        ? paymentStatusColor(PaymentStatus.approved)
        : paymentStatusColor(PaymentStatus.pending);
    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: ok ? color : color.withValues(alpha: 0.15),
        child: Icon(
          ok ? Icons.check : Icons.priority_high,
          size: 16,
          color: ok ? Colors.white : color,
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _preview;
    final managed = g.members.where((m) => m.managed).length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Démarrer la tontine'),
            Text(
              '${g.name} · ${g.memberCount} participants',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionTitle('Avant de démarrer'),
          Card(
            child: FutureBuilder<Business?>(
              future: _business,
              builder: (context, snap) {
                final accounts = snap.data?.accounts ?? const [];
                return Column(
                  children: [
                    _check(
                      true,
                      'Groupe complet',
                      '${g.memberCount} / ${g.memberCount} participants'
                          '${managed > 0 ? ', dont $managed sans appli' : ''}',
                    ),
                    if (g.needsAcceptance)
                      _check(
                        g.allAccepted,
                        'Règlement accepté par tous',
                        g.allAccepted
                            ? '${g.memberIds.length} / ${g.memberIds.length} '
                                  'participants avec l\'application'
                            : 'En attente : '
                                  '${g.pendingAcceptance.map((m) => m.name).join(', ')}',
                      ),
                    _check(
                      true,
                      'Ordre des remises fixé',
                      g.orderMode == OrderMode.manual
                          ? 'Fixé par vous'
                          : 'Par tirage au sort',
                    ),
                    _check(
                      accounts.isNotEmpty,
                      'Numéros de paiement',
                      accounts.isNotEmpty
                          ? [for (final a in accounts) a.operator].join(' et ')
                          : 'Ajoutez vos numéros Mobile Money pour que vos '
                                'clients sachent où payer',
                      action: accounts.isNotEmpty
                          ? null
                          : TextButton(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<bool>(
                                    builder: (_) =>
                                        const BusinessProfileScreen(),
                                  ),
                                );
                                if (mounted) {
                                  setState(
                                    () => _business = Api.business(Api.uid),
                                  );
                                }
                              },
                              child: const Text('Ajouter'),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SectionTitle('Les dates'),
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
          const SizedBox(height: 12),
          StatusCard(
            icon: Icons.warning_amber_rounded,
            title: 'À savoir',
            message:
                'Après le démarrage, les dates, montants et participants ne '
                'peuvent plus être modifiés. Chaque remise ne sera possible '
                'qu\'une fois sa collecte complète.',
            color: paymentStatusColor(PaymentStatus.pending),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || !g.allAccepted ? null : _launch,
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

/// Confirmation de la remise de la cagnotte en cours (collecte complète) :
/// montant, commission, mode de remise. Renvoie le mode choisi.
class PayoutSheet extends StatefulWidget {
  const PayoutSheet({
    super.key,
    required this.group,
    required this.beneficiary,
  });

  final Group group;
  final GroupMember beneficiary;

  @override
  State<PayoutSheet> createState() => _PayoutSheetState();
}

class _PayoutSheetState extends State<PayoutSheet> {
  PaymentMethod _method = PaymentMethod.cash;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final b = widget.beneficiary;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Confirmer la remise',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Cagnotte n°${g.currentPot} · ${b.name} · ${b.profile.phone}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  InfoRow('Collecte validée', money(g.grossPot)),
                  InfoRow('Votre commission', '− ${money(g.commission)}'),
                  const Divider(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'À remettre à ${b.name.split(' ').first}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        money(g.netPot),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Comment remettez-vous l\'argent ?',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<PaymentMethod>(
              segments: const [
                ButtonSegment(
                  value: PaymentMethod.cash,
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Espèces'),
                ),
                ButtonSegment(
                  value: PaymentMethod.mobileMoney,
                  icon: Icon(Icons.phone_android),
                  label: Text('Mobile Money'),
                ),
              ],
              selected: {_method},
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    b.managed
                        ? 'Cette remise est définitive et ne pourra pas être '
                              'annulée.'
                        : '${b.name} recevra une demande pour confirmer qu\'il '
                              'a bien reçu l\'argent. Cette remise ne pourra pas '
                              'être annulée.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _method),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 50),
                    ),
                    child: const Text('Confirmer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Règlement du groupe : conditions fixées par le tontinier et ses règles.
/// Chaque participant l'accepte avant le démarrage.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key, required this.group});

  final Group group;

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  bool _read = false;
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await Api.acceptRules(widget.group);
      if (!mounted) return;
      showInfo(context, 'Règlement accepté');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final theme = Theme.of(context);
    final isOwner = g.ownerId == Api.uid;
    final canAccept =
        !isOwner &&
        g.needsAcceptance &&
        g.memberIds.contains(Api.uid) &&
        !g.isStarted;
    final accepted = g.hasAccepted(Api.uid);
    final good = paymentStatusColor(PaymentStatus.approved);
    final wait = paymentStatusColor(PaymentStatus.pending);
    return Scaffold(
      appBar: AppBar(title: const Text('Règlement du groupe')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            isOwner
                ? 'Voici le règlement que chaque participant doit accepter '
                      'avant le démarrage. Si vous le modifiez, chacun devra '
                      'l\'accepter de nouveau.'
                : 'Voici les conditions fixées par ${g.ownerName} pour le '
                      'groupe « ${g.name} ». Lisez-les avant d\'accepter.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          GroupSummary(g),
          if (isOwner && g.needsAcceptance) ...[
            SectionTitle(
              'Acceptation (${g.memberIds.length - g.pendingAcceptanceCount} / '
              '${g.memberIds.length})',
            ),
            Card(
              child: Column(
                children: [
                  for (final m in g.members)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        m.managed || g.hasAccepted(m.userId)
                            ? Icons.check_circle
                            : Icons.schedule,
                        color: m.managed || g.hasAccepted(m.userId)
                            ? good
                            : wait,
                      ),
                      title: Text(m.name),
                      subtitle: Text(
                        m.managed
                            ? 'Sans application : vous vous en portez garant'
                            : g.hasAccepted(m.userId)
                            ? 'A accepté'
                            : 'Pas encore accepté',
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (canAccept) ...[
            const SizedBox(height: 12),
            if (accepted)
              StatusCard(
                icon: Icons.verified_outlined,
                title: 'Vous avez accepté ce règlement',
                color: good,
              )
            else ...[
              CheckboxListTile(
                value: _read,
                onChanged: (v) => setState(() => _read = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'J\'ai lu le règlement et je l\'accepte',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: !_read || _busy ? null : _accept,
                icon: const Icon(Icons.how_to_reg_outlined),
                label: const Text('Accepter le règlement'),
              ),
            ],
          ] else if (!isOwner && g.needsAcceptance && accepted) ...[
            const SizedBox(height: 12),
            StatusCard(
              icon: Icons.verified_outlined,
              title: 'Vous avez accepté ce règlement',
              color: good,
            ),
          ],
        ],
      ),
    );
  }
}
