import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../reminders.dart';
import '../widgets/common.dart';
import 'carnet_screens.dart';
import 'group_screens.dart';
import 'home_screen.dart';
import 'profile_screens.dart' show HelpScreen;
import 'business_screens.dart';
import 'subscription_screens.dart';
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
    final c = color ?? scheme.primary;
    return Card(
      child: ListTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: c, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Chiffre clé de l'accueil.
class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.caption, {this.color, this.onTap});

  final String label;
  final String value;
  final String caption;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Montant court : 2 340 000 → « 2,34 M », 85 000 → « 85 000 ».
String _short(int amount) => amount >= 1000000
    ? '${(amount / 1000000).toStringAsFixed(2).replaceAll('.', ',')} M'
    : money(amount).replaceAll(' FCFA', '');

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
  late Future<OwnerOverview> _data = _loadOverview();

  /// Charge l'accueil puis reprogramme les rappels (remises du tontinier et
  /// cotisations des tontines auxquelles il participe).
  static Future<OwnerOverview> _loadOverview() async {
    final o = await Api.ownerOverview();
    Api.memberOverview()
        .then((m) => Reminders.update(owned: o.groups, member: m.groups))
        .catchError((_) => Reminders.update(owned: o.groups));
    return o;
  }

  late Future<AccessStatus> _access = _loadAccess();
  late Future<Gains> _gains = Api.gains();
  late final Future<Business?> _business = Api.business(Api.uid);

  static Future<AccessStatus> _loadAccess() async {
    final results = await Future.wait([Api.reloadProfile(), Api.isAdmin()]);
    return AccessStatus(results[0] as Profile, isAdmin: results[1] as bool);
  }

  @override
  void reload() => setState(() {
    _data = _loadOverview();
    _access = _loadAccess();
    _gains = Api.gains();
  });

  /// Essai gratuit, fin d'abonnement proche ou terminée.
  Widget _accessBanner() => FutureBuilder<AccessStatus>(
    future: _access,
    builder: (context, snap) {
      final status = snap.data;
      if (status == null || !status.needsAttention) {
        return const SizedBox.shrink();
      }
      return AccessBanner(
        status,
        onTap: () => open(const SubscriptionScreen()),
      );
    },
  );

  Future<void> _review(PendingReview r) async {
    final b = await Api.business(Api.uid);
    await open(
      r.group != null
          ? groupPaymentScreen(
              r.group!,
              r.payment,
              canReview: true,
              business: b,
            )
          : carnetPaymentScreen(
              r.carnet!,
              r.payment,
              canReview: true,
              business: b,
            ),
    );
  }

  /// Accès au tableau de bord des gains et au profil pro.
  Widget _shortcuts() => Row(
    children: [
      Expanded(
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text(
              'Mes gains',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => open(const GainsScreen()),
          ),
        ),
      ),
      Expanded(
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text(
              'Profil pro',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => open(const BusinessProfileScreen()),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<Business?>(
          future: _business,
          builder: (context, snap) =>
              _Greeting(widget.profile, snap.data?.name ?? 'Espace tontinier'),
        ),
        actions: [
          IconButton(
            tooltip: 'Aide',
            icon: const Icon(Icons.help_outline),
            onPressed: () => open(const HelpScreen(isMember: false)),
          ),
        ],
      ),
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
    _accessBanner(),
    EmptyState(
      icon: Icons.savings_outlined,
      title: 'Bienvenue sur COTIZI',
      message:
          'Créez votre première tontine à cagnotte ou à carnet, puis invitez '
          'vos membres en leur envoyant le lien.',
      action: FilledButton.icon(
        onPressed: () => openIfCanCreate(const CreateTontineScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Créer ma première tontine'),
      ),
    ),
  ];

  List<Widget> _content(OwnerOverview o) {
    final pendingColor = paymentStatusColor(PaymentStatus.pending);
    final bad = paymentStatusColor(PaymentStatus.rejected);
    final today = DateUtils.dateOnly(DateTime.now());
    final active = o.groups
        .where((g) => g.status == GroupStatus.active && !g.isLegacy)
        .toList();
    final lateMembers = active.fold(
      0,
      (n, g) =>
          n + g.members.where((m) => !g.standingOf(m, today).upToDate).length,
    );
    return [
      _accessBanner(),
      Row(
        children: [
          Expanded(
            child: FutureBuilder<Gains>(
              future: _gains,
              builder: (context, snap) => _Kpi(
                'Encaissé',
                snap.hasData ? _short(snap.data!.collectedThisMonth) : '…',
                'FCFA ce mois',
                onTap: () => open(const GainsScreen()),
              ),
            ),
          ),
          Expanded(
            child: _Kpi(
              'À valider',
              '${o.pending.length}',
              o.pending.isEmpty ? 'paiement' : money(o.pendingAmount),
              color: o.pending.isEmpty ? null : pendingColor,
            ),
          ),
          Expanded(
            child: _Kpi(
              'En retard',
              '$lateMembers',
              'participant${lateMembers > 1 ? 's' : ''}',
              color: lateMembers == 0 ? null : bad,
            ),
          ),
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
                child: Icon(
                  r.payment.isCash
                      ? Icons.payments_outlined
                      : Icons.receipt_long,
                ),
              ),
              title: Text(
                r.payment.payer.fullName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${r.group != null ? '${r.group!.name} · ${contributionsLabel(r.payment.count)}' : '${r.carnet!.label} · ${r.payment.caseCount} case(s)'}\n'
                '${methodLabel(r.payment.method)} · ${dateTime(r.payment.declaredAt)}',
              ),
              isThreeLine: true,
              trailing: Text(
                money(r.payment.amount),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onTap: () => _review(r),
            ),
          ),
      ] else
        _Banner(
          icon: Icons.verified_outlined,
          text: 'Aucun paiement à valider.',
          color: paymentStatusColor(PaymentStatus.approved),
        ),
      ..._todos(o),
      if (active.isNotEmpty) ...[
        SectionTitle(
          'Mes groupes en cours',
          trailing: TextButton(
            onPressed: widget.onShowTontines,
            child: const Text('Tout voir'),
          ),
        ),
        for (final g in active) _groupProgress(g, today),
      ],
      const SizedBox(height: 8),
      _shortcuts(),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: widget.onShowTontines,
        icon: const Icon(Icons.savings_outlined),
        label: const Text('Voir toutes mes tontines'),
      ),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        onPressed: () => openIfCanCreate(const CreateTontineScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle tontine'),
      ),
    ];
  }

  /// Avancée de la cagnotte en cours d'un groupe.
  Widget _groupProgress(Group g, DateTime today) {
    final theme = Theme.of(context);
    final pot = g.currentPot;
    final complete = g.isPotComplete(pot);
    final date = g.payoutDate(pot);
    final reached = !date.isAfter(today);
    final validated = g.collectedFor(pot);
    final percent = g.grossPot == 0
        ? 0
        : (100 * validated / g.grossPot).floor();
    final (label, color) = complete
        ? ('Prête', paymentStatusColor(PaymentStatus.approved))
        : reached
        ? ('Bloquée', paymentStatusColor(PaymentStatus.rejected))
        : ('En collecte', paymentStatusColor(PaymentStatus.pending));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(GroupScreen(groupId: g.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${money(g.contributionAmount)} ${frequencyLower(g.frequency)} · '
                          '${g.memberCount} participants',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  StatusChip(label, color),
                ],
              ),
              const SizedBox(height: 10),
              ProgressLine(
                value: g.grossPot == 0 ? 0 : validated / g.grossPot,
                label:
                    'Cagnotte n°$pot sur ${g.memberCount} · $percent % collectés · '
                    'remise ${reached ? countdownLabel(date) : 'le ${dateShort(date)}'}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Actions à mener : remises, retards, tirage à lancer, places libres,
  /// carnets à remettre.
  List<Widget> _todos(OwnerOverview o) {
    final items = <Widget>[];
    final today = DateUtils.dateOnly(DateTime.now());
    for (final g in o.groups.where(
      (g) => g.status == GroupStatus.active && !g.isLegacy,
    )) {
      final pot = g.currentPot;
      final date = g.payoutDate(pot);
      final b = g.beneficiaryOf(pot);
      if (b != null && g.isPotComplete(pot)) {
        items.add(
          _TodoTile(
            icon: Icons.payments_outlined,
            title: 'Cagnotte prête · ${g.name}',
            subtitle:
                'Collecte complète · à remettre à ${b.name} '
                '(${money(g.netPot)})',
            color: paymentStatusColor(PaymentStatus.approved),
            onTap: () => open(GroupScreen(groupId: g.id)),
          ),
        );
      } else if (b != null && !date.isAfter(today)) {
        final late = g.lateFor(pot).length;
        items.add(
          _TodoTile(
            icon: Icons.lock_outline,
            title: 'Remise bloquée · ${g.name}',
            subtitle:
                'Il manque ${money(g.missingFor(pot))}'
                '${late > 0 ? ' · $late en retard' : ' · paiements à valider'}',
            color: paymentStatusColor(PaymentStatus.rejected),
            onTap: () => open(GroupScreen(groupId: g.id)),
          ),
        );
      }
      final late = g.members
          .where((m) => !g.standingOf(m, today).upToDate)
          .length;
      if (late > 0) {
        items.add(
          _TodoTile(
            icon: Icons.campaign_outlined,
            title:
                '« ${g.name} » : $late participant${late > 1 ? 's' : ''} en retard',
            subtitle: 'Voir le suivi et relancer sur WhatsApp',
            color: paymentStatusColor(PaymentStatus.rejected),
            onTap: () => open(GroupScreen(groupId: g.id)),
          ),
        );
      }
    }
    for (final g in o.groups) {
      if (!g.isStarted && g.pendingAcceptanceCount > 0 && g.joinedCount > 0) {
        final n = g.pendingAcceptanceCount;
        items.add(
          _TodoTile(
            icon: Icons.gavel_outlined,
            title: '« ${g.name} » : règlement à accepter',
            subtitle:
                '$n participant${n > 1 ? 's' : ''} n\'${n > 1 ? 'ont' : 'a'} pas encore '
                'accepté le règlement',
            color: paymentStatusColor(PaymentStatus.pending),
            onTap: () => open(GroupScreen(groupId: g.id)),
          ),
        );
      }
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
    return [const SectionTitle('À faire aujourd\'hui'), ...items];
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
  late Future<MemberOverview> _data = _loadOverview();

  /// Charge l'accueil puis reprogramme les rappels de cotisation.
  static Future<MemberOverview> _loadOverview() async {
    final o = await Api.memberOverview();
    Reminders.update(member: o.groups);
    return o;
  }

  @override
  void reload() => setState(() => _data = _loadOverview());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _Greeting(widget.profile, 'Espace participant'),
        actions: [
          IconButton(
            tooltip: 'Aide',
            icon: const Icon(Icons.help_outline),
            onPressed: () => open(const HelpScreen(isMember: true)),
          ),
        ],
      ),
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

  Future<void> _pay(MemberGroupStatus s) async {
    final me = s.group.memberById(Api.uid);
    if (me == null) return;
    final b = await Api.business(s.group.ownerId);
    await open(payContributionsScreen(s.group, me, s.standing, business: b));
  }

  List<Widget> _content(MemberOverview o) {
    final uid = Api.uid;
    final good = paymentStatusColor(PaymentStatus.approved);
    final bad = paymentStatusColor(PaymentStatus.rejected);
    final pendingColor = paymentStatusColor(PaymentStatus.pending);
    final current = o.groups
        .where(
          (s) =>
              !s.group.isLegacy &&
              (s.group.status == GroupStatus.active ||
                  s.group.status == GroupStatus.finished),
        )
        .toList();
    final waiting = [
      for (final s in current)
        for (final p in s.payments.where(
          (p) => p.userId == uid && p.status == PaymentStatus.pending,
        ))
          (s.group, p),
    ];
    return [
      // ------------------------------------------- Cagnottes à confirmer
      for (final s in o.groups.where((s) => s.payoutToConfirm != null))
        StatusCard(
          icon: Icons.savings,
          color: pendingColor,
          title: 'Avez-vous reçu votre cagnotte ?',
          message:
              '${s.group.name} : le tontinier indique vous avoir remis '
              '${money(s.payoutToConfirm!.amount)}. Confirmez la réception.',
          onTap: () => open(GroupScreen(groupId: s.group.id)),
        ),
      // ------------------------------------------------- Situation générale
      if (o.active.isNotEmpty)
        o.lateCount > 0
            ? StatusCard(
                icon: Icons.warning_amber_rounded,
                color: bad,
                title: '${contributionsLabel(o.lateCount)} en retard',
                message:
                    'Montant à régulariser : ${money(o.lateAmount)}'
                    '${o.latePenalty > 0 ? ' (dont ${money(o.latePenalty)} de pénalités)' : ''}. Payez par '
                    'Mobile Money ou en espèces, puis déclarez votre paiement.',
                children: [
                  if (o.active.length == 1) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _pay(o.active.first),
                      icon: const Icon(Icons.upload),
                      label: Text('Payer ${money(o.lateAmount)}'),
                    ),
                  ],
                ],
              )
            : _upToDateCard(o),
      // ------------------------------------------------------ Ma cagnotte
      for (final s in o.active)
        if (s.myPosition(uid) == s.group.currentPot &&
            s.group.paidOutCount < s.group.currentPot)
          _myPotCard(s),
      // ------------------------------------------------------ Mes cagnottes
      if (current.isNotEmpty) const SectionTitle('Mes cagnottes'),
      for (final s in current) _groupCard(s, good, bad),
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
              title: Text('${g.name} · ${contributionsLabel(p.count)}'),
              subtitle: Text('Déclaré le ${dateTime(p.declaredAt)}'),
              trailing: Text(money(p.amount)),
              onTap: () => open(GroupScreen(groupId: g.id)),
            ),
          ),
      ],
      // ------------------------------------------------ Règlements à accepter
      for (final s in o.groups.where(
        (s) =>
            !s.group.isStarted &&
            !s.group.isLegacy &&
            !s.group.hasAccepted(uid),
      ))
        StatusCard(
          icon: Icons.gavel_outlined,
          color: pendingColor,
          title: 'Règlement à accepter · ${s.group.name}',
          message:
              'Lisez les conditions du tontinier et acceptez-les pour que la '
              'tontine puisse démarrer.',
          onTap: () => open(GroupScreen(groupId: s.group.id)),
        ),
      // ------------------------------------------- Groupes en préparation
      for (final s in o.groups.where(
        (s) =>
            s.group.status == GroupStatus.recruiting ||
            s.group.status == GroupStatus.drawing,
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
              : 'En attente des autres participants '
                    '(${s.group.joinedCount} / ${s.group.memberCount})',
          onTap: () => open(GroupScreen(groupId: s.group.id)),
        ),
      // ------------------------------------------------- Anciens groupes
      for (final s in o.groups.where(
        (s) => s.group.isLegacy && s.group.status != GroupStatus.recruiting,
      ))
        _TodoTile(
          icon: Icons.history,
          title: s.group.name,
          subtitle: 'Ancienne version · consultation seulement',
          color: Colors.grey,
          onTap: () => open(GroupScreen(groupId: s.group.id)),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: widget.onShowTontines,
        icon: const Icon(Icons.groups_outlined),
        label: const Text('Voir toutes mes tontines'),
      ),
    ];
  }

  /// « Vous êtes à jour » avec la prochaine cotisation.
  Widget _upToDateCard(MemberOverview o) {
    final theme = Theme.of(context);
    MemberGroupStatus? next;
    DateTime? nextDate;
    for (final s in o.active) {
      if (s.standing.remaining == 0) continue;
      final d = s.group.contributionDate(s.standing.declared + 1);
      if (nextDate == null || d.isBefore(nextDate)) {
        nextDate = d;
        next = s;
      }
    }
    final onPrimary = theme.colorScheme.onPrimary;
    return Card(
      color: theme.colorScheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: onPrimary.withValues(alpha: 0.18),
                  child: Icon(Icons.check, color: onPrimary),
                ),
                const SizedBox(width: 10),
                Text(
                  'Vous êtes à jour',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              next == null
                  ? 'Toutes vos cotisations sont payées.'
                  : 'Prochaine cotisation : ${money(next.group.contributionAmount)} '
                        '${countdownLabel(nextDate!)} (${dateShort(nextDate)})'
                        '${o.active.length > 1 ? ' · ${next.group.name}' : ''}. '
                        'Vous pouvez aussi payer d\'avance.',
              style: TextStyle(color: onPrimary, height: 1.4),
            ),
            if (next != null && o.active.length == 1) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _pay(next!),
                style: FilledButton.styleFrom(
                  backgroundColor: onPrimary,
                  foregroundColor: theme.colorScheme.primary,
                ),
                child: const Text('Payer d\'avance'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// La cagnotte du participant est celle en cours de collecte.
  Widget _myPotCard(MemberGroupStatus s) {
    final g = s.group;
    final theme = Theme.of(context);
    final pot = g.currentPot;
    final validated = g.collectedFor(pot);
    final complete = g.isPotComplete(pot);
    final percent = g.grossPot == 0
        ? 0
        : (100 * validated / g.grossPot).floor();
    final good = paymentStatusColor(PaymentStatus.approved);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(GroupScreen(groupId: g.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ma cagnotte · n°$pot',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  StatusChip(
                    complete ? 'Collecte complète' : 'Collecte à $percent %',
                    complete ? good : paymentStatusColor(PaymentStatus.pending),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                money(g.netPot),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              ProgressLine(
                value: g.grossPot == 0 ? 0 : validated / g.grossPot,
                color: complete ? good : null,
                label: '${g.name} · prévue le ${dateShort(g.payoutDate(pot))}',
              ),
              const SizedBox(height: 6),
              Text(
                complete
                    ? 'La collecte est complète : votre tontinier peut vous '
                          'remettre la cagnotte.'
                    : 'Elle vous sera remise dès que toute la collecte est '
                          'payée : il manque encore ${money(g.missingFor(pot))} '
                          'd\'autres participants.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Une cagnotte du participant : sa situation, la remise en cours et la
  /// sienne.
  Widget _groupCard(MemberGroupStatus s, Color good, Color bad) {
    final g = s.group;
    final st = s.standing;
    final theme = Theme.of(context);
    final pos = s.myPosition(Api.uid);
    final finished = g.status == GroupStatus.finished;
    final pot = g.currentPot;
    final beneficiary = g.beneficiaryOf(pot);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(GroupScreen(groupId: g.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${money(g.contributionAmount)} ${frequencyLower(g.frequency)}'
                          ' · ${g.tontineName}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  finished
                      ? StatusChip('Terminée', good)
                      : st.upToDate
                      ? StatusChip('À jour', good)
                      : StatusChip('${st.late} en retard', bad),
                ],
              ),
              const SizedBox(height: 12),
              ProgressLine(
                value: st.total == 0 ? 0 : st.approved / st.total,
                color: good,
                label:
                    '${st.approved} / ${st.total} cotisations validées'
                    '${st.pending > 0 ? ' · ${st.pending} en attente' : ''}',
              ),
              if (!finished) ...[
                const SizedBox(height: 10),
                InfoRow(
                  'Cagnotte en cours',
                  'n°$pot · ${beneficiary?.userId == Api.uid ? 'pour vous' : 'pour ${beneficiary?.name ?? '—'}'}'
                      ' · ${dateShort(g.payoutDate(pot))}',
                ),
              ],
              if (pos != null)
                InfoRow(
                  'Ma cagnotte',
                  pos <= g.paidOutCount
                      ? 'reçue (n°$pos)'
                      : 'n°$pos · ${money(g.netPot)} le ${dateShort(g.payoutDate(pos))}',
                  bold: true,
                ),
              if (!finished && st.remaining > 0) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: st.upToDate
                      ? OutlinedButton.icon(
                          onPressed: () => _pay(s),
                          icon: const Icon(Icons.upload),
                          label: const Text('Payer d\'avance'),
                        )
                      : FilledButton.icon(
                          onPressed: () => _pay(s),
                          icon: const Icon(Icons.upload),
                          label: Text(
                            'Payer ${money(st.late * g.contributionAmount + st.penaltyDue)}',
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
