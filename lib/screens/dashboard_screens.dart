import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'carnet_screens.dart';
import 'group_screens.dart';
import 'home_screen.dart';
import 'payment_screens.dart';
import 'tontine_screens.dart';

String _firstName(Profile p) => p.fullName.trim().split(RegExp(r'\s+')).first;

class _Greeting extends StatelessWidget {
  const _Greeting(this.profile, this.subtitle);

  final Profile profile;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bonjour ${_firstName(profile)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Ligne d'action « à faire » : icône, texte, flèche.
class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color ?? scheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Bandeau de synthèse coloré (à jour / à faire).
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================= Accueil tontinier

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({
    super.key,
    required this.profile,
    required this.onShowTontines,
  });

  final Profile profile;
  final VoidCallback onShowTontines;

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> with Reloadable {
  late Future<OwnerOverview> _data = Api.ownerOverview();

  @override
  void reload() => setState(() => _data = Api.ownerOverview());

  void _review(PendingReview r) {
    final p = r.payment;
    final g = r.group;
    final c = r.carnet;
    open(
      ReviewPaymentScreen(
        payment: p,
        canReview: true,
        details: g != null
            ? [
                ('Groupe', g.name),
                (
                  'Tour',
                  '${p.tourNumber} · ${dateShort(g.tourDate(p.tourNumber))}',
                ),
              ]
            : [('Carnet', c!.label), ('Cases payées', '${p.caseCount}')],
        onReview: (approve, reason) => g != null
            ? Api.reviewPayment(g.id, p.id, approve, reason)
            : Api.reviewCarnetPayment(c!.id, p, approve, reason),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: _Greeting(widget.profile, 'Espace tontinier')),
      body: RefreshIndicator(
        onRefresh: () async {
          reload();
          await _data;
        },
        child: FutureView<OwnerOverview>(
          future: _data,
          onRetry: reload,
          builder: (context, o) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: o.tontineCount == 0 ? _empty() : _content(o),
          ),
        ),
      ),
    );
  }

  List<Widget> _empty() => [
    EmptyState(
      icon: Icons.savings_outlined,
      title: 'Bienvenue sur COTIZI',
      message:
          'Créez votre première tontine à cagnotte ou à carnet, puis invitez '
          'vos membres en leur envoyant le lien.',
      action: FilledButton.icon(
        onPressed: () => open(const CreateTontineScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Créer ma première tontine'),
      ),
    ),
  ];

  List<Widget> _content(OwnerOverview o) {
    final pendingColor = paymentStatusColor(PaymentStatus.pending);
    return [
      o.pending.isEmpty
          ? _Banner(
              icon: Icons.verified_outlined,
              text: 'Tout est à jour : aucun paiement à valider.',
              color: paymentStatusColor(PaymentStatus.approved),
            )
          : _Banner(
              icon: Icons.notifications_active_outlined,
              text:
                  '${o.pending.length} paiement${o.pending.length > 1 ? 's' : ''} '
                  'à valider · ${money(o.pendingAmount)}',
              color: pendingColor,
            ),
      const SizedBox(height: 4),
      _StatsRow(
        stats: [
          ('Tontines', o.tontineCount),
          ('Groupes', o.groups.length),
          ('Carnets', o.carnets.length),
          ('Membres', o.memberCount),
        ],
      ),
      if (o.pending.isNotEmpty) ...[
        SectionTitle('Paiements à valider (${o.pending.length})'),
        for (final r in o.pending)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: pendingColor.withValues(alpha: 0.15),
                foregroundColor: pendingColor,
                child: const Icon(Icons.receipt_long),
              ),
              title: Text(
                r.payment.payer.fullName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${r.group != null ? '${r.group!.name} · tour ${r.payment.tourNumber}' : '${r.carnet!.label} · ${r.payment.caseCount} case(s)'}\n'
                '${dateTime(r.payment.declaredAt)}',
              ),
              isThreeLine: true,
              trailing: Text(
                money(r.payment.amount),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onTap: () => _review(r),
            ),
          ),
      ],
      ..._todos(o),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: widget.onShowTontines,
        icon: const Icon(Icons.savings_outlined),
        label: const Text('Voir toutes mes tontines'),
      ),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        onPressed: () => open(const CreateTontineScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle tontine'),
      ),
    ];
  }

  /// Actions à mener : tirage à lancer, places libres, carnets à remettre.
  List<Widget> _todos(OwnerOverview o) {
    final items = <Widget>[];
    for (final g in o.groups) {
      if (g.status == GroupStatus.recruiting &&
          g.joinedCount >= g.memberCount) {
        items.add(
          _TodoTile(
            icon: Icons.casino_outlined,
            title: '« ${g.name} » est complet',
            subtitle: 'Lancez le tirage au sort',
            onTap: () => open(GroupScreen(groupId: g.id)),
          ),
        );
      } else if (g.status == GroupStatus.recruiting) {
        final free = g.memberCount - g.joinedCount;
        items.add(
          _TodoTile(
            icon: Icons.person_add_alt,
            title:
                '« ${g.name} » : $free place${free > 1 ? 's' : ''} libre${free > 1 ? 's' : ''}',
            subtitle: 'Partagez le lien d\'invitation',
            onTap: () => open(GroupScreen(groupId: g.id)),
          ),
        );
      } else if (g.status == GroupStatus.drawing) {
        items.add(
          _TodoTile(
            icon: Icons.shuffle,
            title: 'Tirage en cours dans « ${g.name} »',
            subtitle: '${g.drawnCount} / ${g.memberCount} membres ont tiré',
            onTap: () => open(GroupScreen(groupId: g.id)),
          ),
        );
      }
    }
    for (final c in o.carnets) {
      if (c.isComplete) {
        items.add(
          _TodoTile(
            icon: Icons.payments_outlined,
            title: '« ${c.label} » est terminé',
            subtitle:
                'Remettez ${money(c.clientPayout)} à ${c.client?.fullName ?? 'votre client'}',
            color: paymentStatusColor(PaymentStatus.approved),
            onTap: () => open(CarnetScreen(carnetId: c.id)),
          ),
        );
      } else if (c.clientId == null) {
        items.add(
          _TodoTile(
            icon: Icons.person_add_alt,
            title: '« ${c.label} » n\'a pas de client',
            subtitle: 'Partagez le lien d\'invitation',
            onTap: () => open(CarnetScreen(carnetId: c.id)),
          ),
        );
      }
    }
    if (items.isEmpty) return const [];
    return [const SectionTitle('À faire'), ...items];
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final List<(String, int)> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final (label, value) in stats)
          Expanded(
            child: Card(
              margin: const EdgeInsets.all(3),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 4,
                ),
                child: Column(
                  children: [
                    Text(
                      '$value',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      label,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ===================================================== Accueil participant

class MemberDashboard extends StatefulWidget {
  const MemberDashboard({
    super.key,
    required this.profile,
    required this.onShowTontines,
  });

  final Profile profile;
  final VoidCallback onShowTontines;

  @override
  State<MemberDashboard> createState() => _MemberDashboardState();
}

class _MemberDashboardState extends State<MemberDashboard> with Reloadable {
  late Future<MemberOverview> _data = Api.memberOverview();

  @override
  void reload() => setState(() => _data = Api.memberOverview());

  void _declare(MemberGroupStatus s, int tour) {
    final g = s.group;
    final latest = s.latestFor(tour);
    open(
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
          afterRejection: latest != null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: _Greeting(widget.profile, 'Espace participant')),
      body: RefreshIndicator(
        onRefresh: () async {
          reload();
          await _data;
        },
        child: FutureView<MemberOverview>(
          future: _data,
          onRetry: reload,
          builder: (context, o) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: o.groups.isEmpty && o.carnets.isEmpty
                ? [
                    EmptyState(
                      icon: Icons.group_add_outlined,
                      title: 'Bienvenue sur COTIZI',
                      message:
                          'Ouvrez le lien d\'invitation envoyé par votre tontinier, '
                          'ou saisissez son code pour rejoindre sa tontine.',
                      action: FilledButton.icon(
                        onPressed: () => open(const JoinScreen()),
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Rejoindre avec un code'),
                      ),
                    ),
                  ]
                : _content(o),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(MemberOverview o) {
    final uid = Api.uid;
    final today = DateUtils.dateOnly(DateTime.now());
    final late = paymentStatusColor(PaymentStatus.rejected);
    final pendingColor = paymentStatusColor(PaymentStatus.pending);
    final waiting = [
      for (final s in o.groups)
        for (final p in s.payments.where(
          (p) => p.userId == uid && p.status == PaymentStatus.pending,
        ))
          (s.group, p),
    ];
    return [
      o.dueCount > 0
          ? _Banner(
              icon: Icons.pending_actions,
              text:
                  'Vous avez ${o.dueCount} paiement${o.dueCount > 1 ? 's' : ''} à faire',
              color: pendingColor,
            )
          : _Banner(
              icon: Icons.verified_outlined,
              text: 'Vous êtes à jour dans vos cotisations.',
              color: paymentStatusColor(PaymentStatus.approved),
            ),
      // ------------------------------------------------------------ À payer
      if (o.dueCount > 0) const SectionTitle('À payer'),
      for (final s in o.groups)
        for (final tour in s.dueTours)
          Builder(
            builder: (context) {
              final g = s.group;
              final date = g.tourDate(tour);
              final overdue = date.isBefore(today);
              final rejected = s.latestFor(tour);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${g.name} · tour $tour',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            money(g.contributionAmount),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        overdue
                            ? 'En retard · prévu le ${dateLong(date)}'
                            : 'À payer aujourd\'hui',
                        style: TextStyle(color: overdue ? late : pendingColor),
                      ),
                      if (rejected?.status == PaymentStatus.rejected)
                        Text(
                          'Refusé : ${rejected!.rejectionReason ?? ''}',
                          style: TextStyle(color: late),
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _declare(s, tour),
                          icon: const Icon(Icons.upload),
                          label: Text(
                            rejected == null
                                ? 'Déclarer mon paiement'
                                : 'Déclarer à nouveau',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      for (final c in o.carnets.where((c) => c.remainingCases > 0))
        _TodoTile(
          icon: Icons.menu_book_outlined,
          title: '${c.label} : ${c.remainingCases} case(s) à payer',
          subtitle:
              '${c.approvedCases} / ${c.caseCount} cases validées · '
              '${money(c.caseAmount)} par case',
          onTap: () => open(CarnetScreen(carnetId: c.id)),
        ),
      // ------------------------------------------ En attente de validation
      if (waiting.isNotEmpty) ...[
        SectionTitle('En attente de validation (${waiting.length})'),
        for (final (g, p) in waiting)
          Card(
            child: ListTile(
              leading: Icon(Icons.hourglass_top, color: pendingColor),
              title: Text('${g.name} · tour ${p.tourNumber}'),
              subtitle: Text('Déclaré le ${dateTime(p.declaredAt)}'),
              trailing: Text(money(p.amount)),
              onTap: () => open(GroupScreen(groupId: g.id)),
            ),
          ),
      ],
      // ------------------------------------------- Groupes en préparation
      for (final s in o.groups.where(
        (s) => s.group.status != GroupStatus.active,
      ))
        _TodoTile(
          icon: s.group.status == GroupStatus.drawing
              ? Icons.casino_outlined
              : Icons.hourglass_top,
          title: s.group.name,
          subtitle: s.group.status == GroupStatus.drawing
              ? (s.myPosition(uid) == null
                    ? 'Le tirage est ouvert : tirez votre numéro'
                    : 'Vous avez le n°${s.myPosition(uid)}, tirage en cours')
              : 'En attente des autres membres (${s.group.joinedCount} / ${s.group.memberCount})',
          onTap: () => open(GroupScreen(groupId: s.group.id)),
        ),
      // ------------------------------------------------ Mes cagnottes
      if (o.groups.any((s) => s.myPosition(uid) != null)) ...[
        const SectionTitle('Ma cagnotte'),
        for (final s in o.groups.where((s) => s.myPosition(uid) != null))
          Card(
            child: ListTile(
              leading: const Icon(Icons.emoji_events_outlined),
              title: Text(
                '${money(s.group.netPot)} le ${dateLong(s.group.tourDate(s.myPosition(uid)!))}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('${s.group.name} · tour ${s.myPosition(uid)}'),
              onTap: () => open(GroupScreen(groupId: s.group.id)),
            ),
          ),
      ],
      // --------------------------------------------------- Prochains tours
      if (o.groups.any((s) => s.nextTour != null)) ...[
        const SectionTitle('Prochaines cotisations'),
        for (final s in o.groups.where((s) => s.nextTour != null))
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text('${s.group.name} · tour ${s.nextTour}'),
              subtitle: Text(dateLong(s.group.tourDate(s.nextTour!))),
              trailing: Text(money(s.group.contributionAmount)),
              onTap: () => open(GroupScreen(groupId: s.group.id)),
            ),
          ),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: widget.onShowTontines,
        icon: const Icon(Icons.groups_outlined),
        label: const Text('Voir toutes mes tontines'),
      ),
    ];
  }
}
