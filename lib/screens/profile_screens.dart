import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../invite_link.dart';
import '../models.dart';
import '../settings.dart';
import '../widgets/common.dart';
import '../reminders.dart';
import 'business_screens.dart';
import 'company_screens.dart';
import 'recruit_screens.dart';
import 'pro_screens.dart';
import 'subscription_screens.dart';
import 'suggestion_screens.dart';

/// Onglet « Profil » : informations du compte et paramètres.
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.profile,
    required this.onChanged,
  });

  final Profile profile;
  final ValueChanged<Profile> onChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Profile get _p => widget.profile;
  final Future<bool> _isAdmin = Api.isAdmin();

  // Mode test de l'administrateur : le plan affiché change aussitôt
  void _onPlanView() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    adminPlanView.addListener(_onPlanView);
  }

  @override
  void dispose() {
    adminPlanView.removeListener(_onPlanView);
    super.dispose();
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _editName() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: _p.fullName),
    );
    if (name == null || name == _p.fullName || !mounted) return;
    try {
      widget.onChanged(await Api.updateName(name));
      if (mounted) showInfo(context, 'Nom mis à jour');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _chooseTheme() async {
    final mode = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Apparence'),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: themeMode.value,
            onChanged: (m) => Navigator.pop(context, m),
            child: Column(
              children: [
                for (final m in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: m,
                    title: Text(themeModeLabel(m)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (mode != null) await setThemeMode(mode);
  }

  Future<void> _about() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'COTIZI',
      applicationVersion: 'Version ${info.version}',
      applicationIcon: const _AppIcon(size: 48),
      children: const [
        Text(
          'Gestion des tontines à cagnotte et à carnet : cotisations, tirage '
          'au sort, paiements avec preuve validés par le tontinier.',
        ),
      ],
    );
  }

  Future<void> _logout() async {
    if (await confirm(
      context,
      title: 'Déconnexion',
      message: 'Voulez-vous vous déconnecter de COTIZI ?',
      confirmLabel: 'Se déconnecter',
    )) {
      await Api.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: Text(
                      _initials(_p.fullName),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _p.fullName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!_p.isMember)
                    VerifiedBadge(ownerId: Api.uid, large: true),
                  const SizedBox(height: 4),
                  Text(_p.phone, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  StatusChip(
                    _p.isMember ? 'Client' : 'Tontinier',
                    scheme.primary,
                  ),
                  if (_p.isMember) ...[
                    const SizedBox(height: 8),
                    Text(
                      'COTIZI est gratuit pour vous : vous n\'avez jamais de '
                      'plan à prendre.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (_p.createdAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Inscrit le ${dateLong(_p.createdAt!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SectionTitle('Mon compte'),
          _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Modifier mon nom'),
                subtitle: Text(_p.fullName),
                trailing: const Icon(Icons.chevron_right),
                onTap: _editName,
              ),
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: const Text('Numéro de téléphone'),
                subtitle: Text(
                  '${_p.phone} · sert à vous connecter, ne peut pas être modifié',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Changer le mot de passe'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                ),
              ),
            ],
          ),
          if (!_p.isMember) ...[
            const SectionTitle('Mon activité'),
            FutureBuilder<bool>(
              future: _isAdmin,
              builder: (context, snap) {
                final status = AccessStatus(_p, isAdmin: snap.data ?? false);
                return _Group(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: const Text('Mon profil pro'),
                      subtitle: const Text(
                        'Nom de l\'activité, logo, numéros de paiement',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(const BusinessProfileScreen()),
                    ),
                    ListTile(
                      leading: const Icon(Icons.insights_outlined),
                      title: const Text('Mes gains'),
                      subtitle: const Text(
                        'Encaissements, commissions, pénalités, retards',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(const GainsScreen()),
                    ),
                    for (final (icon, title, sub, screen) in [
                      (
                        Icons.account_balance_wallet_outlined,
                        'Comptabilité',
                        'Entrées, sorties, dépenses et bénéfice du mois',
                        const AccountingScreen(),
                      ),
                      (
                        Icons.bar_chart_rounded,
                        'Statistiques',
                        'Évolution, clients réguliers et en retard',
                        const StatsScreen(),
                      ),
                      (
                        Icons.verified_outlined,
                        'Badge vérifié',
                        'Faites vérifier votre identité par COTIZI',
                        const VerificationScreen(),
                      ),
                    ])
                      ListTile(
                        leading: Icon(icon),
                        title: Row(
                          children: [
                            Text(title),
                            if (!status.isPro) ...[
                              const SizedBox(width: 8),
                              StatusChip('PRO', scheme.primary),
                            ],
                          ],
                        ),
                        subtitle: Text(sub),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openPro(context, screen),
                      ),
                    ListTile(
                      leading: const Icon(Icons.business_center_outlined),
                      title: const Text('Mon entreprise'),
                      subtitle: Text(
                        status.isBusiness
                            ? 'Votre équipe de tontiniers et leurs salaires'
                            : 'Rejoindre l\'équipe d\'une entreprise, ou créer '
                                  'la vôtre (plan Business)',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(const EnterpriseScreen()),
                    ),
                    ListTile(
                      leading: const Icon(Icons.work_outline),
                      title: Row(
                        children: [
                          const Text('Espace recrutement'),
                          if (!status.isPro) ...[
                            const SizedBox(width: 8),
                            StatusChip('PRO', scheme.primary),
                          ],
                        ],
                      ),
                      subtitle: const Text(
                        'Offres d\'emploi des entreprises de tontine',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(const RecruitmentScreen()),
                    ),
                    ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: const Text('Mon plan'),
                      subtitle: Text(
                        status.title,
                        style: TextStyle(color: status.color(scheme)),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(const SubscriptionScreen()),
                    ),
                    if (snap.data == true)
                      ListTile(
                        leading: const Icon(
                          Icons.admin_panel_settings_outlined,
                        ),
                        title: const Text('Administration'),
                        subtitle: const Text(
                          'Abonnements des tontiniers, prix et paiement',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _push(const AdminScreen()),
                      ),
                  ],
                );
              },
            ),
          ],
          const SectionTitle('Paramètres'),
          _Group(
            children: [
              if (Reminders.supported)
                ValueListenableBuilder<bool>(
                  valueListenable: Reminders.enabled,
                  builder: (context, on, _) => SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Rappels'),
                    subtitle: Text(
                      _p.isMember
                          ? 'La veille de chaque cotisation à payer'
                          : 'Jours de remise et cotisations à payer',
                    ),
                    value: on,
                    onChanged: (v) async {
                      await Reminders.setEnabled(v);
                      if (v) Reminders.update();
                    },
                  ),
                ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeMode,
                builder: (context, mode, _) => ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Apparence'),
                  subtitle: Text(themeModeLabel(mode)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _chooseTheme,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Aide et assistance'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HelpScreen(isMember: _p.isMember),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: const Text('Suggestions'),
                subtitle: const Text('Aidez-nous à améliorer COTIZI'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SuggestionsScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Partager l\'application'),
                subtitle: const Text('Envoyer le lien de téléchargement'),
                onTap: () => SharePlus.instance.share(
                  ShareParams(
                    text:
                        'Je gère mes tontines avec COTIZI. Télécharge '
                        'l\'application ici : $siteUrl',
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('À propos'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _about,
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              minimumSize: const Size(64, 48),
            ),
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

/// Bloc de lignes de paramètres dans une seule carte.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Icon(
        Icons.savings_outlined,
        color: scheme.onPrimary,
        size: size * 0.6,
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid {
    final n = _name.text.trim().length;
    return n >= 2 && n <= 60;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier mon nom'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nom et prénom'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            'Le nouveau nom s\'affichera sur vos prochaines déclarations.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(context, _name.text.trim())
              : null,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Api.changePassword(_current.text, _next.text);
      if (!mounted) return;
      showInfo(context, 'Mot de passe modifié');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Changer le mot de passe')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: 'Mot de passe actuel',
              ),
              validator: (v) =>
                  (v ?? '').isEmpty ? 'Entrez votre mot de passe actuel' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _next,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'Nouveau mot de passe',
                helperText: 'Au moins 6 caractères',
              ),
              validator: (v) =>
                  (v ?? '').length < 6 ? 'Au moins 6 caractères' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirmer le nouveau mot de passe',
              ),
              validator: (v) => v != _next.text
                  ? 'Les mots de passe ne correspondent pas'
                  : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explications simples, adaptées au rôle.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.isMember});

  final bool isMember;

  @override
  Widget build(BuildContext context) {
    final sections = <(IconData, String, String)>[
      if (!isMember)
        (
          Icons.add_circle_outline,
          'Créer une tontine',
          'Onglet « Mes tontines » → « Nouvelle tontine ». Choisissez une tontine '
              'à cagnotte (avec des groupes) ou à carnet (carnets de 31 cases).',
        ),
      if (!isMember)
        (
          Icons.share_outlined,
          'Inviter des membres',
          'Ouvrez un groupe ou un carnet et appuyez sur « Partager ». Vos membres '
              'reçoivent un lien : en appuyant dessus, ils installent COTIZI et '
              'rejoignent directement votre tontine. S\'ils ouvrent COTIZI sans '
              'le lien, ils choisissent « Client » à l\'inscription et entrent '
              'le code d\'invitation. Un participant sans téléphone ? Dans un '
              'groupe, « Ajouter un participant sans application » lui réserve '
              'une place : vous encaissez pour lui, et il pourra la récupérer '
              'plus tard avec son numéro.',
        ),
      if (!isMember)
        (
          Icons.workspace_premium_outlined,
          'Les plans : Gratuit, Pro, Business',
          'Plan Gratuit : sans limite de temps, avec un nombre limité de '
              'groupes, carnets et clients. Plan Pro : tout illimité ; un '
              'nouveau tontinier a 30 jours d\'essai Pro gratuit. Pour passer '
              'à Pro : Profil → Mon plan → choisissez la durée et écrivez-nous '
              'sur WhatsApp ; vous payez par Mobile Money, puis nous activons '
              'votre plan. S\'il se termine, vous revenez au plan Gratuit : '
              'rien n\'est bloqué, vos groupes et carnets en cours continuent. '
              'Vos clients n\'ont jamais de plan à prendre.',
        ),
      if (!isMember)
        (
          Icons.gavel_outlined,
          'Règlement du groupe',
          'Vous fixez les conditions (cotisation, pénalités…) et vos règles. '
              'Chaque participant avec l\'application doit accepter ce '
              'règlement avant le démarrage ; vous vous portez garant de ceux '
              'qui n\'ont pas l\'application. Si vous modifiez le règlement, '
              'chacun doit l\'accepter de nouveau.',
        ),
      (
        Icons.casino_outlined,
        'Tontine à cagnotte',
        'Le tontinier fixe la cotisation (ex. 5 000 F chaque jour) et quand la '
            'cagnotte est remise : à chaque cotisation (tontine tournante : '
            'avec 15 participants, 15 jours et chacun reçoit une fois) ou après '
            'plusieurs cotisations (ex. 30 jours), l\'ordre des remises (tirage au sort ou '
            'ordre fixé) et la date de début. Il démarre la tontine quand '
            'l\'ordre est fixé : les dates de début et de fin sont alors '
            'figées. Pendant la collecte, tous cotisent pour la cagnotte en '
            'cours. Elle n\'est remise au bénéficiaire que lorsque toute sa '
            'collecte est payée ; le bénéficiaire confirme l\'avoir reçue.',
      ),
      (
        Icons.notifications_active_outlined,
        'Rappels',
        'COTIZI vous prévient la veille de chaque cotisation à payer et, pour '
            'le tontinier, le matin de chaque remise. Vous pouvez les couper '
            'dans Profil → Paramètres → Rappels.',
      ),
      (
        Icons.verified_user_outlined,
        'Contre la fraude',
        'COTIZI ne touche jamais l\'argent. Une capture d\'écran ne peut '
            'servir qu\'à un seul paiement : la même capture ne peut pas être '
            'déclarée deux fois. Un paiement validé ou une remise ne '
            'peuvent plus être modifiés ni supprimés, et chaque reçu porte un '
            'numéro unique (CZ-…). La note de confiance du tontinier '
            '(cagnottes remises, confirmées par les bénéficiaires, problèmes '
            'signalés) est tenue par COTIZI : il ne peut pas la changer.',
      ),
      (
        Icons.notifications_none,
        'La cloche',
        'La cloche en haut de l\'accueil vous signale les opérations : '
            'paiements déclarés ou validés, nouveaux participants, règlement '
            'accepté, cagnotte remise. Touchez une notification pour ouvrir le '
            'groupe concerné.',
      ),
      (
        Icons.check_circle_outline,
        'Être à jour',
        'Votre accueil indique « Vous êtes à jour » quand toutes les cotisations '
            'arrivées à échéance sont payées, ou le nombre de cotisations en '
            'retard. Vous pouvez payer plusieurs cotisations en une fois, et '
            'même payer d\'avance.',
      ),
      (
        Icons.menu_book_outlined,
        'Tontine à carnet',
        'Le client paie les 31 cases de son carnet. Il récupère 30 cases ; la '
            'dernière case revient au tontinier comme commission. Il peut '
            'aussi arrêter avant la fin avec « Demander le remboursement » : '
            'il récupère ses cases payées moins une (ex. 20 cases payées, 19 '
            'rendues). Le tontinier remet l\'argent puis clôture le carnet.',
      ),
      (
        Icons.receipt_long,
        'Déclarer un paiement',
        'Appuyez sur « Payer », choisissez le nombre de cotisations puis le '
            'mode : Mobile Money (les numéros du tontinier s\'affichent ; '
            'ajoutez la capture de l\'envoi, obligatoire) ou espèces '
            '(remises en main '
            'propre). Le paiement reste « En attente » jusqu\'à ce que le '
            'tontinier le valide. En cas de retard, des pénalités peuvent '
            's\'ajouter si le règlement les prévoit (montant fixe ou '
            'pourcentage du montant dû, après quelques jours de retard).',
      ),
      if (isMember)
        (
          Icons.gavel_outlined,
          'Règlement du groupe',
          'Avant le démarrage, lisez le règlement du tontinier (cotisations, '
              'pénalités, règles) et acceptez-le : la tontine ne démarre '
              'qu\'avec l\'accord de tous. Il reste consultable avec le bouton '
              '« Règlement » en haut de la page du groupe.',
        ),
      (
        Icons.rule,
        'Validation par le tontinier',
        'Le tontinier regarde la preuve puis valide ou refuse. En cas de refus, '
            'la raison s\'affiche et le paiement est à refaire. Un paiement '
            'validé donne un reçu à partager.',
      ),
    ];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Aide et assistance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SupportCard(isMember: isMember),
          const SectionTitle('Comment fonctionne COTIZI'),
          for (final (icon, title, text) in sections)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(text),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(siteUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Site de COTIZI'),
          ),
        ],
      ),
    );
  }
}

/// « Aide et support » : WhatsApp ou e-mail de l'assistance COTIZI.
class SupportCard extends StatelessWidget {
  const SupportCard({super.key, required this.isMember});

  final bool isMember;

  static const _whatsappGreen = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FutureBuilder<(SubscriptionSettings, Profile?)>(
      future: Future.wait([Api.subscriptionSettings(), Api.myProfile()])
          .then((r) => (r[0] as SubscriptionSettings, r[1] as Profile?)),
      builder: (context, snap) {
        final settings = snap.data?.$1 ?? const SubscriptionSettings();
        final me = snap.data?.$2;
        final phone = settings.contactPhone;
        final email = settings.supportEmail;
        final hello =
            'Bonjour, j\'ai besoin d\'aide sur COTIZI.'
            '${me == null ? '' : '\nNom : ${me.fullName}\nNuméro : ${me.phone}'}';
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primaryContainer.withValues(alpha: 0.7),
                scheme.primaryContainer,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                  child: Text(
                    'AIDE ET SUPPORT',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Besoin d\'assistance ?',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Nous sommes à un clic !',
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF13906A), Color(0xFF075A41)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.question_mark_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  isMember
                      ? 'Une question sur vos cotisations ? Écrivez d\'abord à '
                            'votre tontinier. Pour un problème avec '
                            'l\'application, contactez COTIZI.'
                      : 'Utilisation de l\'application, abonnement, groupe ou '
                            'paiement : notre équipe vous répond.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: phone.isEmpty
                            ? null
                            : () => openWhatsApp(context, phone, hello),
                        style: FilledButton.styleFrom(
                          backgroundColor: _whatsappGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        icon: const Icon(Icons.chat),
                        label: const Text('WhatsApp'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: email.isEmpty
                            ? (phone.isEmpty
                                  ? null
                                  : () => launchUrl(
                                      Uri.parse(
                                        'tel:+${phone.replaceAll(RegExp(r'\D'), '')}',
                                      ),
                                    ))
                            : () => launchUrl(
                                Uri(
                                  scheme: 'mailto',
                                  path: email,
                                  query:
                                      'subject=${Uri.encodeComponent('Assistance COTIZI')}'
                                      '&body=${Uri.encodeComponent(hello)}',
                                ),
                              ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: scheme.surface,
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        icon: Icon(
                          email.isEmpty
                              ? Icons.call_outlined
                              : Icons.mail_outline,
                        ),
                        label: Text(email.isEmpty ? 'Appeler' : 'E-mail'),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                color: const Color(0xFFFFE9A8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  'Contactez-nous ${settings.hoursLabel}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF7A3B00),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
