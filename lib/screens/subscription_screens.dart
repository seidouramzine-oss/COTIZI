import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'pro_screens.dart';
import 'suggestion_screens.dart';

/// Plan d'un tontinier (Gratuit, essai Pro, Pro, administrateur), prêt à
/// afficher.
class AccessStatus {
  AccessStatus(this.profile, {required this.isAdmin, DateTime? now})
    : now = now ?? DateTime.now();

  final Profile profile;
  final bool isAdmin;
  final DateTime now;

  /// Plan Pro en cours (essai de 30 jours ou abonnement payé).
  bool get isPro => isAdmin || profile.isProAt(now);

  /// Plan Business en cours (comprend le plan Pro).
  bool get isBusiness => !isAdmin && profile.isBusinessAt(now);

  /// Un tontinier crée toujours : en Gratuit, dans les limites du plan.
  bool get canCreate => isAdmin || !profile.isMember;

  int get daysLeft => profile.daysLeft(now);

  /// À signaler sur l'accueil : plan Gratuit, essai, ou fin proche.
  bool get needsAttention =>
      !isAdmin && (!isPro || profile.isTrial || daysLeft <= 7);

  String get planName => isAdmin
      ? 'Administrateur'
      : !isPro
      ? 'Gratuit'
      : profile.isTrial
      ? 'Essai Pro'
      : isBusiness
      ? 'Business'
      : 'Pro';

  String get title {
    if (isAdmin) return 'Administrateur : accès illimité';
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
      : !isAdmin && daysLeft <= 7
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

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late Future<(AccessStatus, SubscriptionSettings)> _data = _load();

  static Future<(AccessStatus, SubscriptionSettings)> _load() async {
    final results = await Future.wait([
      Api.reloadProfile(),
      Api.isAdmin(),
      Api.subscriptionSettings(),
    ]);
    return (
      AccessStatus(results[0] as Profile, isAdmin: results[1] as bool),
      results[2] as SubscriptionSettings,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon plan')),
      body: FutureView<(AccessStatus, SubscriptionSettings)>(
        future: _data,
        onRetry: () => setState(() => _data = _load()),
        builder: (context, data) {
          final (status, settings) = data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _StatusCard(status),
              const SectionTitle('Les plans COTIZI'),
              _PlanCard(
                name: 'Gratuit',
                price: '0 F',
                current: !status.isPro && !status.isAdmin,
                icon: Icons.rocket_launch_outlined,
                features: [
                  '${settings.freeGroups} groupe(s) en cours',
                  '${settings.freeCarnets} carnet(s) en cours',
                  '${settings.freeClients} clients au maximum',
                  'Paiements, reçus, règlement et anti-fraude',
                ],
              ),
              _PlanCard(
                name: 'Pro',
                price: settings.monthlyPrice > 0
                    ? '${money(settings.monthlyPrice)} / mois'
                    : 'Prix sur demande',
                current: status.isPro && !status.isBusiness && !status.isAdmin,
                highlighted: true,
                icon: Icons.workspace_premium,
                features: const [
                  'Groupes, carnets et clients illimités',
                  'Comptabilité : entrées, sorties, dépenses, bénéfice',
                  'Statistiques avancées',
                  'Badge vérifié ✔',
                  'Accès aux offres d\'emploi des entreprises (bientôt)',
                ],
              ),
              _PlanCard(
                name: 'Business',
                price: settings.businessPrice > 0
                    ? '${money(settings.businessPrice)} / mois'
                    : 'Prix sur demande',
                current: status.isBusiness,
                icon: Icons.business_center_outlined,
                features: const [
                  'Pour les entreprises de tontine',
                  'Tout le plan Pro, pour vous et votre équipe',
                  'Votre équipe de tontiniers (agents)',
                  'Activité de chaque agent, mois par mois',
                  'Salaires : fixe, commission ou les deux',
                  'Recrutement de tontiniers Pro (bientôt)',
                ],
              ),
              if (!status.isAdmin) ...[
                SectionTitle(
                  status.isPro && !status.profile.isTrial
                      ? 'Prolonger ou changer de plan'
                      : 'Passer à Pro ou Business',
                ),
                _RenewCard(
                  settings: settings,
                  profile: status.profile,
                  initialPlan: status.isBusiness ? 'business' : 'pro',
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard(this.status);

  final AccessStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = status.color(theme.colorScheme);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color.withValues(alpha: 0.12),
              foregroundColor: color,
              child: Icon(status.icon, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              status.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              status.detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte d'un plan : nom, prix, avantages, plan actuel.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.current,
    required this.icon,
    required this.features,
    this.highlighted = false,
  });

  final String name;
  final String price;
  final bool current;
  final IconData icon;
  final List<String> features;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = highlighted ? scheme.primary : scheme.onSurfaceVariant;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: current || highlighted
              ? scheme.primary
              : scheme.outlineVariant,
          width: current ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                if (current) StatusChip('Votre plan', scheme.primary),
                const Spacer(),
                Text(
                  price,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final f in features)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check, size: 18, color: accent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Demande d'abonnement : on choisit la durée, on écrit à COTIZI sur
/// WhatsApp, on paie par Mobile Money, puis l'équipe active l'abonnement.
class _RenewCard extends StatefulWidget {
  const _RenewCard({
    required this.settings,
    required this.profile,
    this.initialPlan = 'pro',
  });

  final SubscriptionSettings settings;
  final Profile profile;
  final String initialPlan;

  @override
  State<_RenewCard> createState() => _RenewCardState();
}

class _RenewCardState extends State<_RenewCard> {
  int _months = 1;
  late String _plan = widget.initialPlan;
  late Future<SubscriptionRequest?> _request = Api.myRequest();
  bool _busy = false;

  bool get _business => _plan == 'business';

  String get _planName => _business ? 'Business' : 'Pro';

  int get _price =>
      _business ? widget.settings.businessPrice : widget.settings.monthlyPrice;

  int get _amount => _price * _months;

  Future<void> _ask() async {
    final phone = widget.settings.contactPhone;
    setState(() => _busy = true);
    try {
      await Api.requestSubscription(_months, _amount, plan: _plan);
      if (!mounted) return;
      setState(() => _request = Api.myRequest());
      await openWhatsApp(
        context,
        phone,
        'Bonjour, je souhaite le plan $_planName de COTIZI pour $_months mois'
        '${_amount > 0 ? ' (${money(_amount)})' : ''}.\n'
        'Nom : ${widget.profile.fullName}\n'
        'Numéro COTIZI : ${widget.profile.phone}',
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.settings;
    final phone = settings.contactPhone;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Plan',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pro', label: Text('Pro')),
                ButtonSegment(value: 'business', label: Text('Business')),
              ],
              selected: {_plan},
              onSelectionChanged: (v) => setState(() => _plan = v.first),
            ),
            const SizedBox(height: 12),
            Text(
              'Durée',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1 mois')),
                ButtonSegment(value: 3, label: Text('3 mois')),
                ButtonSegment(value: 12, label: Text('12 mois')),
              ],
              selected: {_months},
              onSelectionChanged: (v) => setState(() => _months = v.first),
            ),
            if (_price > 0) ...[
              const SizedBox(height: 12),
              InfoRow('Montant à payer', money(_amount), bold: true),
            ],
            const SizedBox(height: 12),
            for (final (n, text) in [
              (1, 'Écrivez-nous sur WhatsApp avec le bouton ci-dessous.'),
              (
                2,
                settings.paymentPhone.isNotEmpty
                    ? 'Payez par Mobile Money au ${settings.paymentPhone}.'
                    : 'Payez par Mobile Money au numéro que nous vous indiquons.',
              ),
              (
                3,
                'Dès réception du paiement, nous activons votre plan '
                    '$_planName.',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        '$n',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
            FutureBuilder<SubscriptionRequest?>(
              future: _request,
              builder: (context, snap) {
                final r = snap.data;
                if (r == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: StatusCard(
                    icon: Icons.hourglass_top,
                    title: 'Demande envoyée',
                    message:
                        'Plan ${r.planLabel}, ${r.months} mois${r.amount > 0 ? ' · ${money(r.amount)}' : ''}, '
                        'le ${dateLong(r.requestedAt)}. Votre abonnement sera '
                        'activé dès réception du paiement.',
                    color: paymentStatusColor(PaymentStatus.pending),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            if (phone.isNotEmpty) ...[
              FilledButton.icon(
                onPressed: _busy ? null : _ask,
                icon: const Icon(Icons.chat_outlined),
                label: Text('Demander le plan $_planName sur WhatsApp'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('tel:+${phone.replaceAll(RegExp(r'\D'), '')}'),
                ),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Appeler COTIZI'),
              ),
            ] else
              const Text('Contactez l\'équipe COTIZI pour vous abonner.'),
          ],
        ),
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
