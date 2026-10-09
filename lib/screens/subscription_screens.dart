import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../settings.dart';
import '../widgets/common.dart';
import 'pro_screens.dart';
import 'suggestion_screens.dart';

/// Plan d'un tontinier (Gratuit, essai Pro, Pro, administrateur), prêt à
/// afficher.
class AccessStatus {
  AccessStatus(this.profile, {required bool isAdmin, DateTime? now})
    : now = now ?? DateTime.now(),
      realAdmin = isAdmin,
      simulated = isAdmin && adminPlanView.value != 'admin'
          ? adminPlanView.value
          : null;

  final Profile profile;
  final DateTime now;

  /// Compte administrateur de COTIZI (même en mode test).
  final bool realAdmin;

  /// Mode test de l'administrateur : plan essayé (free, pro, business).
  final String? simulated;

  /// Accès illimité d'administrateur (hors mode test).
  bool get isAdmin => realAdmin && simulated == null;

  /// Plan Pro en cours (essai de 30 jours ou abonnement payé).
  bool get isPro =>
      isAdmin ||
      (simulated != null ? simulated != 'free' : profile.isProAt(now));

  /// Plan Business en cours (comprend le plan Pro).
  bool get isBusiness => simulated != null
      ? simulated == 'business'
      : !isAdmin && profile.isBusinessAt(now);

  /// Un tontinier crée toujours : en Gratuit, dans les limites du plan.
  bool get canCreate => isAdmin || !profile.isMember;

  int get daysLeft => profile.daysLeft(now);

  /// À signaler sur l'accueil : plan Gratuit, essai, ou fin proche.
  bool get needsAttention => simulated != null
      ? simulated == 'free'
      : !isAdmin && (!isPro || profile.isTrial || daysLeft <= 7);

  String get planName => isAdmin
      ? 'Administrateur'
      : simulated != null
      ? (isBusiness
            ? 'Business'
            : isPro
            ? 'Pro'
            : 'Gratuit')
      : !isPro
      ? 'Gratuit'
      : profile.isTrial
      ? 'Essai Pro'
      : isBusiness
      ? 'Business'
      : 'Pro';

  String get title {
    if (isAdmin) return 'Administrateur : accès illimité';
    if (simulated != null) return 'Mode test : plan $planName';
    if (!isPro) return 'Plan Gratuit';
    final d = daysLeft;
    final left = d <= 0
        ? 'dernier jour'
        : '$d jour${d > 1 ? 's' : ''} restant${d > 1 ? 's' : ''}';
    return profile.isTrial
        ? 'Essai Pro gratuit : $left'
        : isBusiness
        ? 'Plan Business : $left'
        : 'Plan Pro : $left';
  }

  String get detail {
    if (isAdmin) return 'Vous gérez COTIZI : aucun plan nécessaire.';
    if (simulated != null) {
      return 'Vous voyez COTIZI comme un tontinier au plan $planName. '
          'Changez de plan d\'essai dans Mon plan.';
    }
    if (isPro) {
      return 'Jusqu\'au ${dateLong(profile.accessEnd!)}'
          '${profile.isTrial ? ', puis plan Gratuit si vous ne passez pas à Pro' : ''}.';
    }
    return 'Groupes, carnets et clients limités. Passez à Pro pour tout '
        'débloquer. Vos groupes en cours continuent toujours.';
  }

  IconData get icon => !isPro
      ? Icons.rocket_launch_outlined
      : profile.isTrial && !isAdmin
      ? Icons.card_giftcard_outlined
      : isBusiness
      ? Icons.business_center
      : Icons.workspace_premium;

  Color color(ColorScheme scheme) => !isPro
      ? scheme.primary
      : !isAdmin && simulated == null && daysLeft <= 7
      ? paymentStatusColor(PaymentStatus.pending)
      : paymentStatusColor(PaymentStatus.approved);
}

/// Vérifie qu'un tontinier peut créer un groupe ([kind] = 'group') ou un
/// carnet ([kind] = 'carnet') : en Gratuit, dans les limites du plan. Sinon,
/// propose de passer à Pro.
Future<bool> checkCanCreate(BuildContext context, {String? kind}) async {
  try {
    await Api.ensureCanCreate(kind: kind);
    return true;
  } on PlanLimitReached catch (e) {
    if (!context.mounted) return false;
    await showPlanLimit(context, e.message);
    return false;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

/// « Limite du plan Gratuit » : propose de passer à Pro.
Future<void> showPlanLimit(BuildContext context, String message) async {
  final upgrade = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.rocket_launch_outlined),
      title: const Text('Limite du plan Gratuit'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Passer à Pro'),
        ),
      ],
    ),
  );
  if (upgrade == true && context.mounted) {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
  }
}

/// Bandeau d'état de l'abonnement (accueil du tontinier).
class AccessBanner extends StatelessWidget {
  const AccessBanner(this.status, {super.key, required this.onTap});

  final AccessStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = status.color(Theme.of(context).colorScheme);
    return Card(
      color: color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(status.icon, color: color),
        title: Text(
          status.title,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(status.detail),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ============================================================ Mon plan

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

typedef _PlanData = (AccessStatus, SubscriptionSettings, SubscriptionRequest?);

/// « Mon plan » : un plan à la fois (Gratuit, Pro, Business), prix au mois
/// ou à l'année (2 mois offerts), puis « Contactez-nous » pour l'activer.
class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late Future<_PlanData> _data = _load();
  String? _plan;
  bool _yearly = false;
  bool _busy = false;

  static Future<_PlanData> _load() async {
    final results = await Future.wait([
      Api.reloadProfile(),
      Api.isAdmin(),
      Api.subscriptionSettings(),
      Api.myRequest(),
    ]);
    return (
      AccessStatus(results[0] as Profile, isAdmin: results[1] as bool),
      results[2] as SubscriptionSettings,
      results[3] as SubscriptionRequest?,
    );
  }

  void _reload() => setState(() => _data = _load());

  /// Annuel : 12 mois pour le prix de 10.
  static const yearMonthsPaid = 10;

  int _monthly(SubscriptionSettings s, String plan) =>
      plan == 'business' ? s.businessPrice : s.monthlyPrice;

  int _amount(SubscriptionSettings s, String plan) =>
      _monthly(s, plan) * (_yearly ? yearMonthsPaid : 1);

  String _planTitle(String plan) => switch (plan) {
    'business' => 'COTIZI Business',
    'pro' => 'COTIZI Pro',
    _ => 'COTIZI Gratuit',
  };

  Future<void> _contact(AccessStatus status, SubscriptionSettings s) async {
    final plan = _plan!;
    final months = _yearly ? 12 : 1;
    final amount = _amount(s, plan);
    final name = plan == 'business' ? 'Business' : 'Pro';
    setState(() => _busy = true);
    try {
      await Api.requestSubscription(months, amount, plan: plan);
      if (!mounted) return;
      _reload();
      await openWhatsApp(
        context,
        s.contactPhone,
        'Bonjour, je souhaite activer le plan $name de COTIZI '
        '(${_yearly ? 'annuel, 12 mois' : 'mensuel, 1 mois'})'
        '${amount > 0 ? ' : ${money(amount)}' : ''}.\n'
        'Nom : ${status.profile.fullName}\n'
        'Numéro COTIZI : ${status.profile.phone}',
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _howTo(SubscriptionSettings s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comment activer mon abonnement ?',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                for (final (n, text) in [
                  (
                    1,
                    'Choisissez votre plan (Pro ou Business) et la durée : '
                        'mensuel, ou annuel avec 2 mois offerts.',
                  ),
                  (
                    2,
                    'Appuyez sur « Contactez-nous pour activer l\'abonnement » : '
                        'WhatsApp s\'ouvre vers l\'équipe COTIZI.',
                  ),
                  (
                    3,
                    s.paymentPhone.isNotEmpty
                        ? 'Payez par Mobile Money au ${s.paymentPhone}.'
                        : 'Payez par Mobile Money au numéro que nous vous '
                              'indiquons.',
                  ),
                  (
                    4,
                    'Dès réception du paiement, nous activons votre plan. '
                        'Fermez et rouvrez COTIZI pour le voir.',
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            '$n',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(text)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon plan')),
      body: FutureView<_PlanData>(
        future: _data,
        onRetry: _reload,
        builder: (context, data) {
          final (status, s, request) = data;
          final plan = _plan ??= status.isBusiness ? 'business' : 'pro';
          final current = switch (plan) {
            'business' => status.isBusiness,
            'pro' =>
              status.isPro &&
                  !status.isBusiness &&
                  !status.isAdmin &&
                  !status.profile.isTrial,
            _ => !status.isPro && !status.isAdmin,
          };
          final canAsk =
              plan != 'free' && !status.isAdmin && s.contactPhone.isNotEmpty;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (status.realAdmin) _AdminTestCard(onChanged: _reload),
                    _CurrentPlan(status),
                    const SizedBox(height: 16),
                    _Pills(
                      options: const [
                        ('free', 'Gratuit'),
                        ('pro', 'Pro'),
                        ('business', 'Business'),
                      ],
                      selected: plan,
                      onChanged: (v) => setState(() => _plan = v),
                    ),
                    if (plan != 'free') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _Pills(
                              options: const [
                                ('month', 'Mensuel'),
                                ('year', 'Annuel'),
                              ],
                              selected: _yearly ? 'year' : 'month',
                              onChanged: (v) =>
                                  setState(() => _yearly = v == 'year'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: paymentStatusColor(PaymentStatus.approved)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '2 mois offerts',
                              style: TextStyle(
                                color: paymentStatusColor(
                                  PaymentStatus.approved,
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    _PlanCard(
                      title: _planTitle(plan),
                      price: plan == 'free'
                          ? '0 FCFA'
                          : _monthly(s, plan) > 0
                          ? money(_amount(s, plan))
                          : 'Prix sur demande',
                      unit: plan == 'free'
                          ? 'pour toujours'
                          : '${plan == 'business' ? 'par entreprise' : 'par tontinier'}'
                                '/${_yearly ? 'an' : 'mois'}',
                      note: plan != 'free' && _yearly && _monthly(s, plan) > 0
                          ? '12 mois pour le prix de 10, soit '
                                '${money((_amount(s, plan) / 12).round())} / mois'
                          : null,
                      current: current,
                      sections: switch (plan) {
                        'business' => const [
                          [
                            'Tout le plan Pro, pour vous et votre équipe',
                            'Tontiniers (agents) illimités',
                          ],
                          [
                            'Activité de chaque agent, mois par mois',
                            'Salaires : fixe, commission ou les deux',
                            'Fiches de paie pour vos agents',
                            'Bénéfice de l\'entreprise',
                            'Recrutement de tontiniers Pro (bientôt)',
                          ],
                        ],
                        'pro' => const [
                          [
                            'Toutes les fonctionnalités incluses',
                            'Groupes, carnets et clients illimités',
                          ],
                          [
                            'Comptabilité : entrées, sorties, dépenses, bénéfice',
                            'Statistiques avancées',
                            'Badge « Vérifié » visible de vos clients',
                            'Relevés PDF pour vous et vos clients',
                            'Offres d\'emploi des entreprises (bientôt)',
                          ],
                        ],
                        _ => [
                          const [
                            'Sans limite de temps',
                            'Paiements, reçus, règlement et anti-fraude',
                          ],
                          [
                            '${s.freeGroups} groupe(s) en cours',
                            '${s.freeCarnets} carnet(s) en cours',
                            '${s.freeClients} clients au maximum',
                            'Note de confiance et rappels',
                          ],
                        ],
                      },
                    ),
                    if (plan != 'free')
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => _howTo(s),
                          child: const Text(
                            'Comment activer mon abonnement ?',
                            style: TextStyle(
                              decoration: TextDecoration.underline,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    if (request != null)
                      StatusCard(
                        icon: Icons.hourglass_top,
                        title: 'Demande envoyée',
                        message:
                            'Plan ${request.planLabel}, ${request.months} mois'
                            '${request.amount > 0 ? ' · ${money(request.amount)}' : ''}, '
                            'le ${dateLong(request.requestedAt)}. Votre plan sera '
                            'activé dès réception du paiement.',
                        color: paymentStatusColor(PaymentStatus.pending),
                      ),
                  ],
                ),
              ),
              if (canAsk)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: _busy ? null : () => _contact(status, s),
                        icon: const Icon(Icons.support_agent),
                        label: const Text(
                          'Contactez-nous pour activer l\'abonnement',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Mode test de l'administrateur : essayer COTIZI dans chaque plan.
class _AdminTestCard extends StatelessWidget {
  const _AdminTestCard({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: const Color(0xFFFFF3E0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.science_outlined, color: Color(0xFFE07B00)),
                const SizedBox(width: 8),
                Text(
                  'Mode test administrateur',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF7A4300),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Voir et utiliser COTIZI comme un tontinier de ce plan. '
              'L\'Administration reste toujours accessible.',
              style: TextStyle(color: Color(0xFF7A4300)),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<String>(
              valueListenable: adminPlanView,
              builder: (context, view, _) => SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'admin', label: Text('Admin')),
                  ButtonSegment(value: 'free', label: Text('Gratuit')),
                  ButtonSegment(value: 'pro', label: Text('Pro')),
                  ButtonSegment(value: 'business', label: Text('Business')),
                ],
                selected: {view},
                onSelectionChanged: (v) async {
                  await setAdminPlanView(v.first);
                  onChanged();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plan actuel, en une ligne.
class _CurrentPlan extends StatelessWidget {
  const _CurrentPlan(this.status);

  final AccessStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = status.color(theme.colorScheme);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(status.icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(status.detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Choix en pastilles (comme un interrupteur) : la pastille choisie est
/// blanche sur fond gris.
class _Pills extends StatelessWidget {
  const _Pills({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          for (final (value, label) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == selected,
                label: label,
                excludeSemantics: true,
                onTap: () => onChanged(value),
                child: GestureDetector(
                  onTap: () => onChanged(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: value == selected
                          ? scheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(26),
                      border: value == selected
                          ? Border.all(color: scheme.outlineVariant)
                          : null,
                      boxShadow: value == selected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: value == selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: value == selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Carte d'un plan : nom, grand prix, avantages cochés.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.unit,
    required this.sections,
    required this.current,
    this.note,
  });

  final String title;
  final String price;
  final String unit;
  final String? note;
  final List<List<String>> sections;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: current ? scheme.primary : scheme.outlineVariant,
          width: current ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        children: [
          if (current) ...[
            StatusChip('Votre plan actuel', scheme.primary),
            const SizedBox(height: 8),
          ],
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              price,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ),
          Text(
            unit,
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: paymentStatusColor(PaymentStatus.approved),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          for (final section in sections) ...[
            const Divider(height: 32),
            for (final f in section)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check, size: 22, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(f, style: theme.textTheme.bodyLarge)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ========================================================= Administration

/// Réservé au propriétaire de COTIZI : abonnements des tontiniers.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late Future<void> _loading = _load();
  List<Account> _accounts = [];
  List<SubscriptionRequest> _requests = [];
  SubscriptionSettings _settings = const SubscriptionSettings();
  final _search = TextEditingController();

  Future<void> _load() async {
    final results = await Future.wait([
      Api.accounts(),
      Api.subscriptionSettings(),
      Api.subscriptionRequests(),
    ]);
    _accounts = results[0] as List<Account>;
    _settings = results[1] as SubscriptionSettings;
    _requests = results[2] as List<SubscriptionRequest>;
  }

  /// Paiement reçu : active l'abonnement demandé et clôt la demande.
  Future<void> _activate(SubscriptionRequest r) async {
    final account = _accounts.where((a) => a.id == r.userId).firstOrNull;
    if (account == null) return;
    if (!await confirm(
      context,
      title: 'Activer l\'abonnement',
      message:
          'Avez-vous reçu le paiement de ${r.fullName}'
          '${r.amount > 0 ? ' (${money(r.amount)})' : ''} ? Son abonnement '
          'Plan ${r.planLabel} pour ${r.months} mois.',
      confirmLabel: 'Activer',
    )) {
      return;
    }
    try {
      final updated = await Api.extendSubscription(
        account,
        r.months,
        plan: r.plan,
      );
      await Api.closeSubscriptionRequest(r.userId);
      setState(() {
        _accounts = [for (final x in _accounts) x.id == r.userId ? updated : x];
        _requests = [
          for (final x in _requests)
            if (x.userId != r.userId) x,
        ];
      });
      if (mounted) {
        showInfo(
          context,
          'Abonnement activé jusqu\'au ${dateLong(updated.profile.accessEnd!)}',
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _dismiss(SubscriptionRequest r) async {
    try {
      await Api.closeSubscriptionRequest(r.userId);
      setState(
        () => _requests = [
          for (final x in _requests)
            if (x.userId != r.userId) x,
        ],
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _reload() => setState(() => _loading = _load());

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AccessStatus _status(Account a) =>
      AccessStatus(a.profile, isAdmin: a.id == Api.uid);

  Future<void> _editSettings() async {
    final settings = await showDialog<SubscriptionSettings>(
      context: context,
      builder: (_) => _SettingsDialog(initial: _settings),
    );
    if (settings == null || !mounted) return;
    try {
      await Api.saveSubscriptionSettings(settings);
      setState(() => _settings = settings);
      if (mounted) showInfo(context, 'Réglages enregistrés');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _manage(Account a) async {
    final choice = await showModalBottomSheet<(int, String)>(
      context: context,
      showDragHandle: true,
      builder: (_) => _AccountSheet(account: a, status: _status(a)),
    );
    if (choice == null || !mounted) return;
    final (action, plan) = choice;
    if (action == 0 &&
        !await confirm(
          context,
          title: 'Arrêter l\'abonnement',
          message:
              '${a.profile.fullName} ne pourra plus créer de tontine, de '
              'groupe ni de carnet. Ses groupes en cours continuent.',
          confirmLabel: 'Arrêter',
        )) {
      return;
    }
    try {
      final updated = action == 0
          ? await Api.stopSubscription(a)
          : await Api.extendSubscription(a, action, plan: plan);
      setState(() {
        _accounts = [for (final x in _accounts) x.id == a.id ? updated : x];
      });
      if (mounted) {
        showInfo(
          context,
          action == 0
              ? 'Abonnement arrêté'
              : 'Abonnement prolongé jusqu\'au '
                    '${dateLong(updated.profile.accessEnd!)}',
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      body: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _loading;
        },
        child: FutureView<void>(
          future: _loading,
          onRetry: _reload,
          builder: (context, _) => _content(),
        ),
      ),
    );
  }

  Widget _content() {
    final tontiniers = _accounts.where((a) => !a.profile.isMember).toList();
    final clients = _accounts.length - tontiniers.length;
    final active = tontiniers.where((a) => _status(a).canCreate).length;
    final query = _search.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? tontiniers
        : tontiniers
              .where(
                (a) =>
                    a.profile.fullName.toLowerCase().contains(query) ||
                    a.profile.phone.contains(query.replaceAll(' ', '')),
              )
              .toList();
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            for (final (label, value) in [
              ('Tontiniers', tontiniers.length),
              ('Actifs', active),
              ('Clients', clients),
            ])
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      children: [
                        Text(
                          '$value',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text(label, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('Suggestions reçues'),
            subtitle: const Text(
              'Idées et problèmes envoyés par les utilisateurs',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminSuggestionsScreen()),
            ),
          ),
        ),
        if (_requests.isNotEmpty) ...[
          SectionTitle('Demandes d\'abonnement (${_requests.length})'),
          for (final r in _requests)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      r.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${r.phone} · ${r.planLabel} · ${r.months} mois'
                      '${r.amount > 0 ? ' · ${money(r.amount)}' : ''} · '
                      '${dateTime(r.requestedAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => _activate(r),
                          child: Text(
                            'Paiement reçu : activer ${r.planLabel} '
                            '${r.months} mois',
                          ),
                        ),
                        IconButton(
                          tooltip: 'Écrire sur WhatsApp',
                          icon: const Icon(Icons.chat_outlined),
                          onPressed: () => openWhatsApp(
                            context,
                            r.phone,
                            'Bonjour ${r.fullName}, merci pour votre demande '
                            'd\'abonnement COTIZI (${r.months} mois).',
                          ),
                        ),
                        IconButton(
                          tooltip: 'Supprimer la demande',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _dismiss(r),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SectionTitle('Badges vérifiés'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: const Text('Demandes de badge'),
            subtitle: const Text(
              'Vérifier la pièce d\'identité et le selfie des tontiniers Pro',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const VerificationRequestsScreen(),
              ),
            ),
          ),
        ),
        const SectionTitle('Plans, paiement et assistance'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text(
              'Prix des plans, limites, Mobile Money et assistance',
            ),
            subtitle: Text(
              _settings.isSet
                  ? [
                      'Pro : ${_settings.monthlyPrice > 0 ? '${money(_settings.monthlyPrice)} / mois' : 'prix non réglé'}',
                      'Business : ${_settings.businessPrice > 0 ? '${money(_settings.businessPrice)} / mois' : 'prix non réglé'}',
                      'Gratuit : ${_settings.freeGroups} groupe(s), ${_settings.freeCarnets} carnet(s), ${_settings.freeClients} clients',
                      if (_settings.paymentPhone.isNotEmpty)
                        'Mobile Money : ${_settings.paymentPhone}',
                      if (_settings.supportPhone.isNotEmpty)
                        'Assistance WhatsApp : ${_settings.supportPhone}',
                      if (_settings.supportEmail.isNotEmpty)
                        'E-mail : ${_settings.supportEmail}',
                      'Horaires : ${_settings.hoursLabel}',
                    ].join('\n')
                  : 'Pas encore réglé : les tontiniers ne savent pas comment payer',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editSettings,
          ),
        ),
        SectionTitle('Tontiniers (${tontiniers.length})'),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Rechercher un nom ou un numéro',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Aucun tontinier trouvé', textAlign: TextAlign.center),
          ),
        for (final a in shown)
          Builder(
            builder: (context) {
              final status = _status(a);
              final color = status.color(theme.colorScheme);
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    foregroundColor: color,
                    child: Icon(status.icon),
                  ),
                  title: Text(
                    a.profile.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${a.profile.phone}\n${status.title}',
                    style: TextStyle(color: color),
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _manage(a),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Actions sur un tontinier : renvoie le nombre de mois à ajouter, ou 0
/// pour arrêter l'abonnement.
class _AccountSheet extends StatelessWidget {
  const _AccountSheet({required this.account, required this.status});

  final Account account;
  final AccessStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = account.profile.accessEnd;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.profile.fullName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(account.profile.phone),
                const SizedBox(height: 4),
                Text(
                  end == null
                      ? status.title
                      : '${status.title} · fin le ${dateShort(end)}',
                  style: TextStyle(color: status.color(theme.colorScheme)),
                ),
              ],
            ),
          ),
          const Divider(),
          for (final plan in ['pro', 'business'])
            for (final months in [1, 3, 12])
              ListTile(
                leading: Icon(
                  plan == 'business'
                      ? Icons.business_center_outlined
                      : Icons.workspace_premium_outlined,
                ),
                title: Text(
                  '${plan == 'business' ? 'Business' : 'Pro'} : '
                  'ajouter $months mois',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('Jusqu\'au ${dateLong(_newEnd(months, plan))}'),
                onTap: () => Navigator.pop(context, (months, plan)),
              ),
          if (status.canCreate)
            ListTile(
              leading: Icon(Icons.block, color: theme.colorScheme.error),
              title: Text(
                'Arrêter l\'abonnement',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, (0, 'pro')),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  DateTime _newEnd(int months, String plan) {
    final now = DateTime.now();
    final end = account.profile.accessEnd;
    final keep =
        end != null && end.isAfter(now) && account.profile.plan == plan;
    return addMonths(keep ? end : now, months);
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.initial});

  final SubscriptionSettings initial;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _price = TextEditingController(
    text: widget.initial.monthlyPrice > 0
        ? '${widget.initial.monthlyPrice}'
        : '',
  );
  late final _phone = TextEditingController(text: widget.initial.paymentPhone);
  late final _support = TextEditingController(
    text: widget.initial.supportPhone,
  );
  late final _email = TextEditingController(text: widget.initial.supportEmail);
  late final _business = TextEditingController(
    text: widget.initial.businessPrice > 0
        ? '${widget.initial.businessPrice}'
        : '',
  );
  late final _freeGroups = TextEditingController(
    text: '${widget.initial.freeGroups}',
  );
  late final _freeCarnets = TextEditingController(
    text: '${widget.initial.freeCarnets}',
  );
  late final _freeClients = TextEditingController(
    text: '${widget.initial.freeClients}',
  );
  late final _hours = TextEditingController(text: widget.initial.supportHours);

  @override
  void dispose() {
    _price.dispose();
    _phone.dispose();
    _support.dispose();
    _email.dispose();
    _business.dispose();
    _freeGroups.dispose();
    _freeCarnets.dispose();
    _freeClients.dispose();
    _hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Plans, paiement et assistance'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Prix du plan Pro par mois',
                suffixText: 'FCFA',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _business,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Prix du plan Business par mois',
                suffixText: 'FCFA',
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Limites du plan Gratuit',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _freeGroups,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Groupes'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _freeCarnets,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Carnets'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _freeClients,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Clients'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: 'Numéro Mobile Money et WhatsApp',
                hintText: '+229 01 97 00 00 00',
              ),
            ),
            TextField(
              controller: _support,
              keyboardType: TextInputType.phone,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: 'WhatsApp de l\'assistance (facultatif)',
                helperText: 'Sinon, le numéro ci-dessus est utilisé',
              ),
            ),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'E-mail de l\'assistance (facultatif)',
                hintText: 'assistance@exemple.com',
              ),
            ),
            TextField(
              controller: _hours,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Horaires de l\'assistance',
                hintText: SubscriptionSettings.defaultHours,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            SubscriptionSettings(
              monthlyPrice: (parseAmount(_price.text) ?? 0).clamp(0, 10000000),
              paymentPhone: _phone.text.trim(),
              supportPhone: _support.text.trim(),
              supportEmail: _email.text.trim(),
              supportHours: _hours.text.trim(),
              businessPrice: (parseAmount(_business.text) ?? 0).clamp(
                0,
                10000000,
              ),
              freeGroups: (parseAmount(_freeGroups.text) ?? 0).clamp(0, 1000),
              freeCarnets: (parseAmount(_freeCarnets.text) ?? 0).clamp(0, 1000),
              freeClients: (parseAmount(_freeClients.text) ?? 0).clamp(
                0,
                100000,
              ),
            ),
          ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
