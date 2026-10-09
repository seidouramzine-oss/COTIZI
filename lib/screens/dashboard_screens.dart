import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../reminders.dart';
import '../widgets/common.dart';
import '../widgets/home_cards.dart';
import '../widgets/trust.dart';
import 'carnet_screens.dart';
import 'group_screens.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';
import 'profile_screens.dart' show HelpScreen;
import 'business_screens.dart';
import 'pro_screens.dart';
import 'subscription_screens.dart';
import 'tontine_screens.dart';
import 'suggestion_screens.dart';

String _firstName(Profile p) => p.fullName.trim().split(RegExp(r'\s+')).first;

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
  late Future<int> _unread = Api.unreadCount();
  late Future<List<AppNotification>> _recent = Api.notifications(limit: 4);
  bool _guideHidden = true;

  /// Chiffres masqués sur l'accueil (bouton œil), mémorisé sur le téléphone.
  bool _hideAmounts = false;

  static const _hideKey = 'chiffres_masques';

  String _m(int amount) => _hideAmounts ? '••••• FCFA' : money(amount);

  Future<void> _toggleAmounts() async {
    setState(() => _hideAmounts = !_hideAmounts);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_hideKey, _hideAmounts);
    } catch (_) {}
  }

  static const _guideKey = 'guide_demarrage_masque';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance()
        .then((p) {
          if (mounted) {
            setState(() {
              _guideHidden = p.getBool(_guideKey) ?? false;
              _hideAmounts = p.getBool(_hideKey) ?? false;
            });
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _guideHidden = false);
        });
  }

  Future<void> _hideGuide() async {
    setState(() => _guideHidden = true);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_guideKey, true);
    } catch (_) {}
  }

  /// Guide « Démarrer avec COTIZI » : 4 étapes, masqué une fois fini.
  Widget _guide(OwnerOverview o) => FutureBuilder<Business?>(
    future: _business,
    builder: (context, snap) {
      if (_guideHidden || snap.connectionState != ConnectionState.done) {
        return const SizedBox.shrink();
      }
      final steps = [
        StartStep(
          Icons.storefront_outlined,
          'Compléter mon profil pro et mes numéros Mobile Money',
          (snap.data?.accounts ?? const []).isNotEmpty,
          () => open(const BusinessProfileScreen()),
        ),
        StartStep(
          Icons.group_add_outlined,
          'Créer ma première tontine',
          o.groups.isNotEmpty || o.carnets.isNotEmpty,
          () => openIfCanCreate(const CreateTontineScreen()),
        ),
        StartStep(
          Icons.share_outlined,
          'Inviter mes clients avec le lien',
          o.memberCount > 0,
          widget.onShowTontines,
        ),
        StartStep(
          Icons.fact_check_outlined,
          'Valider mon premier paiement',
          o.hasApprovedPayment,
          widget.onShowTontines,
        ),
      ];
      if (steps.every((s) => s.done)) return const SizedBox.shrink();
      return GettingStartedCard(steps: steps, onClose: _hideGuide);
    },
  );

  static Future<AccessStatus> _loadAccess() async {
    final results = await Future.wait([Api.reloadProfile(), Api.isAdmin()]);
    return AccessStatus(results[0] as Profile, isAdmin: results[1] as bool);
  }

  @override
  void reload() => setState(() {
    _data = _loadOverview();
    _access = _loadAccess();
    _gains = Api.gains();
    _unread = Api.unreadCount();
    _recent = Api.notifications(limit: 4);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            reload();
            await _data;
          },
          child: FutureView<OwnerOverview>(
            future: _data,
            onRetry: reload,
            builder: (context, o) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: o.tontineCount == 0 ? _empty(o) : _content(o),
            ),
          ),
        ),
      ),
    );
  }

  /// En-tête : grand bonjour, nom de l'activité, cloche et aide.
  Widget _header() => FutureBuilder<Business?>(
    future: _business,
    builder: (context, snap) => HomeHeader(
      name: _firstName(widget.profile),
      subtitle: snap.data?.name != null
          ? '${snap.data!.name} · voici le résumé de votre activité'
          : 'Voici le résumé de votre activité',
      bell: NotificationBell(
        unread: _unread,
        onTap: () => open(const NotificationsScreen()),
      ),
      onHelp: () => open(const HelpScreen(isMember: false)),
    ),
  );

  /// « Reprenez là où vous vous êtes arrêté » : la chose la plus urgente.
  Widget _resume(OwnerOverview o) {
    if (o.tontineCount == 0) {
      return ResumeCard(
        icon: Icons.savings_outlined,
        title: 'Votre première tontine vous attend',
        subtitle:
            'Reprenez là où vous vous êtes arrêté : 2 minutes pour la créer.',
        color: const Color(0xFFB07D00),
        onTap: () => openIfCanCreate(const CreateTontineScreen()),
      );
    }
    if (o.pending.isEmpty) return const SizedBox.shrink();
    final n = o.pending.length;
    return ResumeCard(
      icon: Icons.receipt_long,
      title: '$n paiement${n > 1 ? 's' : ''} à valider',
      subtitle:
          'Reprenez là où vous vous êtes arrêté : vérifiez la preuve et '
          'validez.',
      color: paymentStatusColor(PaymentStatus.pending),
      onTap: () => _review(o.pending.first),
    );
  }

  /// Carte d'action : créer sa première tontine, ou inviter ses clients.
  Widget _promo(OwnerOverview o) => o.tontineCount == 0
      ? PromoCard(
          icon: Icons.rocket_launch_outlined,
          title: 'Créez votre première tontine',
          text:
              'Cagnotte tournante ou carnet de 31 cases : prête en 2 minutes, '
              'puis invitez vos clients par WhatsApp.',
          buttonLabel: 'Commencer',
          onTap: () => openIfCanCreate(const CreateTontineScreen()),
        )
      : PromoCard(
          icon: Icons.group_add_outlined,
          title: 'Invitez vos clients',
          text:
              'Partagez le lien d\'invitation de vos groupes sur WhatsApp : '
              'vos clients rejoignent en un clic, gratuitement.',
          buttonLabel: 'Partager un lien',
          onTap: widget.onShowTontines,
        );

  List<Widget> _empty(OwnerOverview o) => [
    _header(),
    _accessBanner(),
    _resume(o),
    _hero(o, 0, 0),
    _promo(o),
    const SectionTitle('Actions rapides'),
    _quickActions(),
    _guide(o),
    HelpCard(onTap: () => open(const HelpScreen(isMember: false))),
  ];

  List<Widget> _content(OwnerOverview o) {
    final pendingColor = paymentStatusColor(PaymentStatus.pending);
    final today = DateUtils.dateOnly(DateTime.now());
    final active = o.groups
        .where((g) => g.status == GroupStatus.active && !g.isLegacy)
        .toList();
    final lateMembers = active.fold(
      0,
      (n, g) =>
          n + g.members.where((m) => !g.standingOf(m, today).upToDate).length,
    );
    final todos = _todos(o);
    return [
      _header(),
      _accessBanner(),
      _resume(o),
      _hero(o, active.length, lateMembers),
      _promo(o),
      const SectionTitle('Actions rapides'),
      _quickActions(),
      _guide(o),
      // --------------------------------------------- Paiements à valider
      if (o.pending.isNotEmpty) ...[
        SectionTitle(
          'Paiements à valider',
          trailing: StatusChip('${o.pending.length}', pendingColor),
        ),
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
                _m(r.payment.amount),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onTap: () => _review(r),
            ),
          ),
      ],
      // ------------------------------------------------- À faire
      const SectionTitle('À faire aujourd\'hui'),
      if (todos.isEmpty && o.pending.isEmpty)
        Card(
          child: ListTile(
            leading: Icon(
              Icons.check_circle,
              color: paymentStatusColor(PaymentStatus.approved),
            ),
            title: const Text(
              'Rien d\'urgent',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Aucun paiement à valider, aucun retard, aucune remise à faire.',
            ),
          ),
        )
      else if (todos.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.arrow_upward),
            title: Text('Validez les paiements ci-dessus'),
          ),
        )
      else
        ...todos,
      // ------------------------------------------------- Groupes
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
      // ------------------------------------------------- Activité récente
      FutureBuilder<List<AppNotification>>(
        future: _recent,
        builder: (context, snap) {
          final list = snap.data ?? const <AppNotification>[];
          if (list.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                'Activité récente',
                trailing: TextButton(
                  onPressed: () => open(const NotificationsScreen()),
                  child: const Text('Tout voir'),
                ),
              ),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final n in list)
                      NotificationTile(
                        n,
                        onTap: () => openNotificationTarget(context, n),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      // ------------------------------------------------- Confiance
      const SectionTitle('Confiance'),
      TrustCard(ownerId: Api.uid, own: true),
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFFFF3C4),
            foregroundColor: Color(0xFF7A5A00),
            child: Icon(Icons.lightbulb_outline),
          ),
          title: const Text(
            'Suggestions',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('Aidez-nous à améliorer COTIZI'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => open(const SuggestionsScreen()),
        ),
      ),
      HelpCard(onTap: () => open(const HelpScreen(isMember: false))),
    ];
  }

  /// Bandeau principal : encaissé ce mois et chiffres clés.
  Widget _hero(OwnerOverview o, int activeGroups, int lateMembers) {
    final n = o.pending.length;
    return FutureBuilder<Gains>(
      future: _gains,
      builder: (context, snap) => HeroCard(
        label: 'Bienvenue sur COTIZI',
        chip: HeroChip(
          icon: _hideAmounts
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          label: _hideAmounts ? 'Afficher' : 'Masquer',
          tooltip: _hideAmounts
              ? 'Afficher les chiffres'
              : 'Masquer les chiffres',
          onTap: _toggleAmounts,
        ),
        headline: 'Vos tontines, enfin claires',
        reassurance:
            "L'argent ne passe jamais par COTIZI : vos clients vous paient "
            'directement.',
        buttonLabel: n > 0
            ? 'Valider $n paiement${n > 1 ? 's' : ''}'
            : o.tontineCount == 0
            ? 'Créer ma première tontine'
            : 'Nouvelle tontine',
        buttonIcon: n > 0 ? Icons.fact_check_outlined : Icons.add,
        onButton: n > 0
            ? () => _review(o.pending.first)
            : () => openIfCanCreate(const CreateTontineScreen()),
        children: [
          const SizedBox(height: 14),
          Text(
            'Encaissé ce mois-ci',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
          ),
          Text(
            snap.hasData ? _m(snap.data!.collectedThisMonth) : '…',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              HeroStat(value: '$n', label: 'à valider'),
              const SizedBox(width: 8),
              HeroStat(value: '$lateMembers', label: 'en retard'),
              const SizedBox(width: 8),
              HeroStat(
                value: '$activeGroups',
                label: activeGroups > 1 ? 'groupes actifs' : 'groupe actif',
                onTap: widget.onShowTontines,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Raccourcis : nouvelle tontine, tontines, gains, comptabilité.
  Widget _quickActions() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      QuickTile(
        icon: Icons.add,
        label: 'Nouvelle tontine',
        onTap: () => openIfCanCreate(const CreateTontineScreen()),
      ),
      QuickTile(
        icon: Icons.savings_outlined,
        label: 'Mes tontines',
        onTap: widget.onShowTontines,
      ),
      QuickTile(
        icon: Icons.insights_outlined,
        label: 'Mes gains',
        onTap: () => open(const GainsScreen()),
      ),
      QuickTile(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Comptabilité',
        onTap: () => openPro(context, const AccountingScreen()),
      ),
    ],
  );

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
                          '${_m(g.contributionAmount)} ${frequencyLower(g.frequency)} · '
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
    // Remises contestées, puis remises non confirmées depuis 2 jours
    for (final r in o.openPayouts) {
      final p = r.payout;
      if (p.problem != null) {
        items.add(
          _TodoTile(
            icon: Icons.report_gmailerrorred,
            title: 'Problème signalé · ${r.group.name}',
            subtitle:
                '${p.beneficiaryName} (cagnotte n°${p.pot}) : ${p.problem}',
            color: paymentStatusColor(PaymentStatus.rejected),
            onTap: () => open(GroupScreen(groupId: r.group.id)),
          ),
        );
      } else if (!r.managed && p.unconfirmedSince(2)) {
        items.add(
          _TodoTile(
            icon: Icons.hourglass_bottom,
            title: 'Remise non confirmée · ${r.group.name}',
            subtitle:
                '${p.beneficiaryName} n\'a pas confirmé avoir reçu '
                '${_m(p.amount)} (remise le ${dateShort(p.paidAt)}). '
                'Demandez-lui de confirmer dans COTIZI.',
            color: paymentStatusColor(PaymentStatus.pending),
            onTap: () => open(GroupScreen(groupId: r.group.id)),
          ),
        );
      }
    }
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
                '(${_m(g.netPot)})',
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
                'Il manque ${_m(g.missingFor(pot))}'
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
            title: '$late participant${late > 1 ? 's' : ''} en retard',
            subtitle: '${g.name} · relancez-les sur WhatsApp',
            color: paymentStatusColor(PaymentStatus.rejected),
            onTap: () => open(GroupScreen(groupId: g.id)),
          ),
        );
      }
    }
    for (final g in o.groups) {
      if (g.canClose) {
        items.add(
          _TodoTile(
            icon: Icons.task_alt,
            title: '« ${g.name} » : toutes les cagnottes sont remises',
            subtitle: 'Clôturez le groupe',
            color: paymentStatusColor(PaymentStatus.approved),
            onTap: () => open(GroupScreen(groupId: g.id)),
          ),
        );
      }
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
      if (c.isClosed) continue;
      if (c.refundRequested) {
        items.add(
          _TodoTile(
            icon: Icons.undo,
            title: 'Remboursement demandé · ${c.label}',
            subtitle:
                '${c.client?.fullName ?? 'Le client'} : remettez '
                '${_m(c.refundDue)} (${c.approvedCases - 1} cases) puis '
                'clôturez le carnet',
            color: paymentStatusColor(PaymentStatus.pending),
            onTap: () => open(CarnetScreen(carnetId: c.id)),
          ),
        );
      } else if (c.isComplete) {
        items.add(
          _TodoTile(
            icon: Icons.payments_outlined,
            title: '« ${c.label} » est terminé',
            subtitle:
                'Remettez ${_m(c.clientPayout)} à ${c.client?.fullName ?? 'votre client'}',
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
    return items;
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

  late Future<int> _unread = Api.unreadCount();

  @override
  void reload() => setState(() {
    _data = _loadOverview();
    _unread = Api.unreadCount();
  });

  @override
  Widget build(BuildContext context) {
    final header = HomeHeader(
      name: _firstName(widget.profile),
      subtitle: 'Voici le résumé de vos cotisations',
      bell: NotificationBell(
        unread: _unread,
        onTap: () => open(const NotificationsScreen()),
      ),
      onHelp: () => open(const HelpScreen(isMember: true)),
    );
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
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
                      header,
                      HeroCard(
                        label: 'Bienvenue sur COTIZI',
                        headline: 'Votre tontine, enfin claire',
                        caption:
                            'Rejoignez votre tontinier : ouvrez le lien d\'invitation envoyé par votre '
                            'tontinier, ou saisissez son code.',
                        reassurance:
                            'Votre argent ne passe jamais par COTIZI : vous '
                            'payez votre tontinier directement.',
                        buttonLabel: 'Rejoindre avec un code',
                        buttonIcon: Icons.qr_code_2,
                        onButton: () => open(const JoinScreen()),
                      ),
                      HelpCard(
                        onTap: () => open(const HelpScreen(isMember: true)),
                      ),
                    ]
                  : [header, ..._content(o)],
            ),
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
      for (final c in o.carnets.where((c) => c.refundRequested))
        _TodoTile(
          icon: Icons.undo,
          title: '${c.label} : remboursement demandé',
          subtitle:
              'Votre tontinier doit vous remettre ${money(c.refundDue)} '
              '(${c.approvedCases - 1} cases)',
          color: paymentStatusColor(PaymentStatus.pending),
          onTap: () => open(CarnetScreen(carnetId: c.id)),
        ),
      for (final c in o.carnets.where(
        (c) => c.isActive && c.remainingCases > 0,
      ))
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
      const SizedBox(height: 12),
      const MoneySafetyCard(isMember: true),
      HelpCard(onTap: () => open(const HelpScreen(isMember: true))),
    ];
  }

  /// « Vous êtes à jour » avec la prochaine cotisation.
  Widget _upToDateCard(MemberOverview o) {
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
    final canPay = next != null && o.active.length == 1;
    return HeroCard(
      label: 'Bienvenue sur COTIZI',
      headline: 'Votre tontine, enfin claire',
      caption: next == null
          ? 'Vous êtes à jour : toutes vos cotisations sont payées.'
          : 'Vous êtes à jour. Prochaine cotisation : ${money(next.group.contributionAmount)} '
                '${countdownLabel(nextDate!)} (${dateShort(nextDate)})'
                '${o.active.length > 1 ? ' · ${next.group.name}' : ''}. '
                'Vous pouvez aussi payer d\'avance.',
      reassurance:
          'Votre argent ne passe jamais par COTIZI : vous payez votre '
          'tontinier directement.',
      buttonLabel: canPay ? 'Payer d\'avance' : null,
      buttonIcon: Icons.upload,
      onButton: canPay ? () => _pay(next!) : null,
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
