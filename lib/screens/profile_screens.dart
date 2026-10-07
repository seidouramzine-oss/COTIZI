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
import 'business_screens.dart';
import 'subscription_screens.dart';

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
                  const SizedBox(height: 4),
                  Text(_p.phone, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  StatusChip(
                    _p.isMember ? 'Client' : 'Tontinier',
                    scheme.primary,
                  ),
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
                    ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: const Text('Mon abonnement'),
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
                title: const Text('Comment fonctionne COTIZI'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HelpScreen(isMember: _p.isMember),
                  ),
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
          'Essai gratuit et abonnement',
          'Un nouveau tontinier a 30 jours d\'essai gratuit. Ensuite, un '
              'abonnement est nécessaire pour créer de nouvelles tontines, '
              'groupes et carnets (Profil → Mon abonnement). Vos groupes en '
              'cours continuent toujours.',
        ),
      (
        Icons.casino_outlined,
        'Tontine à cagnotte',
        'Le tontinier fixe la cotisation (ex. 5 000 F chaque jour), la durée de '
            'collecte (ex. 30 jours), l\'ordre des remises (tirage au sort ou '
            'ordre fixé) et la date de début. Il démarre la tontine quand '
            'l\'ordre est fixé : les dates de début et de fin sont alors '
            'figées. Pendant la collecte, tous cotisent pour la cagnotte en '
            'cours ; à la date de remise, elle est donnée au bénéficiaire, qui '
            'confirme l\'avoir reçue.',
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
            'dernière case revient au tontinier comme commission.',
      ),
      (
        Icons.receipt_long,
        'Déclarer un paiement',
        'Appuyez sur « Payer », choisissez le nombre de cotisations puis le '
            'mode : Mobile Money (les numéros du tontinier s\'affichent ; '
            'ajoutez la capture de l\'envoi) ou espèces (remises en main '
            'propre). Le paiement reste « En attente » jusqu\'à ce que le '
            'tontinier le valide. En cas de retard, des pénalités peuvent '
            's\'ajouter si le tontinier les a prévues.',
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
      appBar: AppBar(title: const Text('Comment fonctionne COTIZI')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
