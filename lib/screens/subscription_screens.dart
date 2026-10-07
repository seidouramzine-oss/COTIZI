import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Accès d'un tontinier (essai, abonnement, administrateur), prêt à afficher.
class AccessStatus {
  AccessStatus(this.profile, {required this.isAdmin, DateTime? now})
    : now = now ?? DateTime.now();

  final Profile profile;
  final bool isAdmin;
  final DateTime now;

  bool get canCreate => isAdmin || profile.canCreateAt(now);

  int get daysLeft => profile.daysLeft(now);

  /// À signaler sur l'accueil : essai en cours, fin proche ou terminé.
  bool get needsAttention =>
      !isAdmin && (!canCreate || profile.isTrial || daysLeft <= 7);

  String get title {
    if (isAdmin) return 'Administrateur : accès illimité';
    if (!canCreate) {
      return profile.isTrial ? 'Essai gratuit terminé' : 'Abonnement terminé';
    }
    final d = daysLeft;
    final left = d <= 0
        ? 'dernier jour'
        : '$d jour${d > 1 ? 's' : ''} restant${d > 1 ? 's' : ''}';
    return profile.isTrial ? 'Essai gratuit : $left' : 'Abonnement : $left';
  }

  String get detail {
    if (isAdmin) return 'Vous gérez COTIZI : aucun abonnement nécessaire.';
    final end = profile.accessEnd;
    if (canCreate) return 'Jusqu\'au ${dateLong(end!)}';
    return 'Vous ne pouvez plus créer de tontine, de groupe ni de carnet. '
        'Vos groupes et carnets en cours continuent : vous pouvez toujours '
        'valider les paiements.';
  }

  IconData get icon => !canCreate
      ? Icons.lock_clock_outlined
      : profile.isTrial && !isAdmin
      ? Icons.card_giftcard_outlined
      : Icons.verified_outlined;

  Color color(ColorScheme scheme) => !canCreate
      ? scheme.error
      : !isAdmin && daysLeft <= 7
      ? paymentStatusColor(PaymentStatus.pending)
      : paymentStatusColor(PaymentStatus.approved);
}

/// Vérifie qu'un tontinier peut créer (essai ou abonnement en cours).
/// Sinon, propose de renouveler l'abonnement.
Future<bool> checkCanCreate(BuildContext context) async {
  try {
    await Api.ensureCanCreate();
    return true;
  } on SubscriptionExpired catch (e) {
    if (!context.mounted) return false;
    final renew = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_clock_outlined),
        title: const Text('Abonnement terminé'),
        content: Text(e.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Renouveler'),
          ),
        ],
      ),
    );
    if (renew == true && context.mounted) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
    }
    return false;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
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
        subtitle: Text(
          status.canCreate ? status.detail : 'Appuyez ici pour le renouveler.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ======================================================== Mon abonnement

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
      appBar: AppBar(title: const Text('Mon abonnement')),
      body: FutureView<(AccessStatus, SubscriptionSettings)>(
        future: _data,
        onRetry: () => setState(() => _data = _load()),
        builder: (context, data) {
          final (status, settings) = data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _StatusCard(status),
              const SectionTitle('Ce que comprend l\'abonnement'),
              const Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      _Feature(
                        Icons.savings_outlined,
                        'Tontines à cagnotte et à carnet sans limite',
                      ),
                      _Feature(
                        Icons.share_outlined,
                        'Invitation de vos clients par lien WhatsApp',
                      ),
                      _Feature(
                        Icons.casino_outlined,
                        'Tirage au sort des tours de cagnotte',
                      ),
                      _Feature(
                        Icons.fact_check_outlined,
                        'Paiements avec preuve, validés par vous',
                      ),
                    ],
                  ),
                ),
              ),
              if (!status.isAdmin) ...[
                SectionTitle(
                  status.canCreate
                      ? 'Prolonger mon abonnement'
                      : 'Renouveler mon abonnement',
                ),
                _RenewCard(settings: settings, profile: status.profile),
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

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(text),
    );
  }
}

class _RenewCard extends StatelessWidget {
  const _RenewCard({required this.settings, required this.profile});

  final SubscriptionSettings settings;
  final Profile profile;

  String get _digits => settings.paymentPhone.replaceAll(RegExp(r'\D'), '');

  Future<void> _open(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      showError(context, const AppException('Impossible d\'ouvrir le lien'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message =
        'Bonjour, je souhaite renouveler mon abonnement COTIZI.\n'
        'Nom : ${profile.fullName}\nNuméro COTIZI : ${profile.phone}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (settings.monthlyPrice > 0)
              InfoRow(
                'Prix',
                '${money(settings.monthlyPrice)} par mois',
                bold: true,
              ),
            if (settings.paymentPhone.isNotEmpty)
              InfoRow('Mobile Money', settings.paymentPhone, bold: true),
            if (settings.isSet) const SizedBox(height: 8),
            Text(
              settings.paymentPhone.isNotEmpty
                  ? '1. Envoyez le montant par Mobile Money au numéro '
                        'ci-dessus.\n'
                        '2. Prévenez-nous sur WhatsApp avec votre nom et votre '
                        'numéro COTIZI.\n'
                        '3. Votre abonnement est prolongé dès réception.'
                  : 'Contactez l\'équipe COTIZI pour renouveler votre '
                        'abonnement.',
              style: theme.textTheme.bodyMedium,
            ),
            if (_digits.isNotEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _open(
                  context,
                  Uri.parse(
                    'https://wa.me/$_digits?text=${Uri.encodeComponent(message)}',
                  ),
                ),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Prévenir sur WhatsApp'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _open(context, Uri.parse('tel:+$_digits')),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Appeler'),
              ),
            ],
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
  SubscriptionSettings _settings = const SubscriptionSettings();
  final _search = TextEditingController();

  Future<void> _load() async {
    final results = await Future.wait([
      Api.accounts(),
      Api.subscriptionSettings(),
    ]);
    _accounts = results[0] as List<Account>;
    _settings = results[1] as SubscriptionSettings;
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
    final action = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => _AccountSheet(account: a, status: _status(a)),
    );
    if (action == null || !mounted) return;
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
          : await Api.extendSubscription(a, action);
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
        const SectionTitle('Paiement de l\'abonnement'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Prix et numéro Mobile Money'),
            subtitle: Text(
              _settings.isSet
                  ? [
                      if (_settings.monthlyPrice > 0)
                        '${money(_settings.monthlyPrice)} par mois',
                      if (_settings.paymentPhone.isNotEmpty)
                        'Mobile Money : ${_settings.paymentPhone}',
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
                  onTap: status.isAdmin ? null : () => _manage(a),
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
          for (final months in [1, 3, 12])
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(
                'Ajouter $months mois',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Jusqu\'au ${dateLong(_newEnd(months))}'),
              onTap: () => Navigator.pop(context, months),
            ),
          if (status.canCreate)
            ListTile(
              leading: Icon(Icons.block, color: theme.colorScheme.error),
              title: Text(
                'Arrêter l\'abonnement',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, 0),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  DateTime _newEnd(int months) {
    final now = DateTime.now();
    final end = account.profile.accessEnd;
    return addMonths(end != null && end.isAfter(now) ? end : now, months);
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

  @override
  void dispose() {
    _price.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paiement de l\'abonnement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Prix par mois',
              suffixText: 'FCFA',
            ),
          ),
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
        ],
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
            ),
          ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
