import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../invite_link.dart';
import '../models.dart';

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.savings_outlined,
            size: 40,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'COTIZI',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          'Vos tontines, simplement',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Indicatif pays + numéro.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.dialCode,
    required this.onDialCodeChanged,
    required this.controller,
  });

  final String dialCode;
  final ValueChanged<String> onDialCodeChanged;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: DropdownButtonFormField<String>(
            initialValue: dialCode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Pays'),
            items: [
              for (final (code, country) in dialCodes)
                DropdownMenuItem(
                  value: code,
                  child: Text(
                    '$code $country',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            selectedItemBuilder: (context) => [
              for (final (code, _) in dialCodes) Text(code),
            ],
            onChanged: (v) => onDialCodeChanged(v ?? dialCode),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(
              labelText: 'Numéro de téléphone',
              hintText: '01 97 00 00 00',
            ),
            validator: (v) => isValidPhone(normalizePhone(dialCode, v ?? ''))
                ? null
                : 'Numéro invalide',
          ),
        ),
      ],
    );
  }
}

/// Invitation reçue par lien, avant d'avoir un compte.
class _InviteBanner extends StatelessWidget {
  const _InviteBanner({required this.code, required this.onRegister});

  final String code;
  final VoidCallback? onRegister;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Vous êtes invité à rejoindre une tontine',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Code d\'invitation : $code. Créez votre compte : vous rejoindrez '
              'la tontine automatiquement. Déjà inscrit ? Connectez-vous plus bas.',
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRegister,
              child: const Text('Créer mon compte'),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _dialCode = dialCodes.first.$1;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Api.signIn(
        phone: normalizePhone(_dialCode, _phone.text),
        password: _password.text,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Logo(),
                      ValueListenableBuilder<String?>(
                        valueListenable: pendingInvite,
                        builder: (context, code, _) => code == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: _InviteBanner(
                                  code: code,
                                  onRegister: _busy
                                      ? null
                                      : () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const RegisterScreen(
                                                  asMember: true,
                                                ),
                                          ),
                                        ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 32),
                      PhoneField(
                        dialCode: _dialCode,
                        onDialCodeChanged: (v) => setState(() => _dialCode = v),
                        controller: _phone,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => (v ?? '').isEmpty
                            ? 'Entrez votre mot de passe'
                            : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Se connecter'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RegisterScreen(
                                    asMember: pendingInvite.value != null,
                                  ),
                                ),
                              ),
                        child: const Text('Pas encore de compte ? S\'inscrire'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// « Vous êtes : tontinier ou client ? » à l'inscription.
class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.role, required this.onChanged});

  final Role? role;
  final ValueChanged<Role> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Vous êtes :',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        RadioGroup<Role>(
          groupValue: role,
          onChanged: (r) {
            if (r != null) onChanged(r);
          },
          child: Column(
            children: [
              _RoleOption(
                value: Role.tontinier,
                selected: role == Role.tontinier,
                icon: Icons.storefront_outlined,
                title: 'Tontinier',
                subtitle:
                    'Je crée et je gère des tontines. Essai gratuit de '
                    '${Profile.trialDays} jours.',
              ),
              const SizedBox(height: 8),
              _RoleOption(
                value: Role.membre,
                selected: role == Role.membre,
                icon: Icons.person_outline,
                title: 'Client',
                subtitle:
                    'Je rejoins la tontine de mon tontinier avec son code '
                    'd\'invitation.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.value,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final Role value;
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: RadioListTile<Role>(
        value: value,
        controlAffinity: ListTileControlAffinity.trailing,
        secondary: Icon(icon, color: scheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
      ),
    );
  }
}

/// Code d'invitation obligatoire pour un client.
class _InviteCodeField extends StatelessWidget {
  const _InviteCodeField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: 'Code d\'invitation',
        hintText: 'Exemple : PAJ8R3',
        helperText: 'Le code à 6 caractères envoyé par votre tontinier',
        prefixIcon: Icon(Icons.key_outlined),
      ),
      validator: (v) => Api.normalizeCode(v ?? '').length != 6
          ? 'Entrez le code à 6 caractères envoyé par votre tontinier'
          : null,
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.asMember = false});

  /// Inscription depuis un lien d'invitation : « Client » déjà choisi.
  final bool asMember;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final _code = TextEditingController(text: pendingInvite.value ?? '');
  String _dialCode = dialCodes.first.$1;
  late Role? _role = widget.asMember || pendingInvite.value != null
      ? Role.membre
      : null;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final role = _role;
    if (role == null) {
      showError(
        context,
        const AppException('Choisissez d\'abord : tontinier ou client'),
      );
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    // Client : la tontine est rejointe dès l'arrivée sur l'accueil
    final previousInvite = pendingInvite.value;
    final code = role == Role.membre ? Api.normalizeCode(_code.text) : null;
    if (code != null) pendingInvite.value = code;
    try {
      await Api.signUp(
        phone: normalizePhone(_dialCode, _phone.text),
        password: _password.text,
        fullName: _name.text.trim(),
        role: role,
        inviteCode: code,
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (code != null) pendingInvite.value = previousInvite;
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RolePicker(
                      role: _role,
                      onChanged: (r) => setState(() => _role = r),
                    ),
                    if (_role == Role.membre) ...[
                      const SizedBox(height: 16),
                      _InviteCodeField(controller: _code),
                    ],
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Nom et prénom',
                      ),
                      validator: (v) {
                        final n = (v ?? '').trim().length;
                        return n < 2 || n > 60 ? 'Indiquez votre nom' : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    PhoneField(
                      dialCode: _dialCode,
                      onDialCodeChanged: (v) => setState(() => _dialCode = v),
                      controller: _phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(
                        labelText: 'Mot de passe',
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
                        labelText: 'Confirmer le mot de passe',
                      ),
                      validator: (v) => v != _password.text
                          ? 'Les mots de passe ne correspondent pas'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _role == Role.membre
                                  ? 'Créer mon compte et rejoindre'
                                  : 'Créer mon compte',
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Profil manquant (inscription interrompue) : demander le nom.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _code = TextEditingController(text: pendingInvite.value ?? '');
  Role? _role = pendingInvite.value != null ? Role.membre : null;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final role = _role;
    if (role == null) {
      showError(
        context,
        const AppException('Choisissez d\'abord : tontinier ou client'),
      );
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (role == Role.membre) {
        final code = await Api.verifyInviteCode(_code.text);
        await Api.createProfile(_name.text, role: role);
        pendingInvite.value = code;
      } else {
        await Api.createProfile(_name.text, role: role);
      }
      widget.onDone();
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Votre profil'),
        actions: [
          TextButton(
            onPressed: Api.signOut,
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Terminez votre inscription.'),
            const SizedBox(height: 16),
            _RolePicker(
              role: _role,
              onChanged: (r) => setState(() => _role = r),
            ),
            if (_role == Role.membre) ...[
              const SizedBox(height: 16),
              _InviteCodeField(controller: _code),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nom et prénom'),
              validator: (v) {
                final n = (v ?? '').trim().length;
                return n < 2 || n > 60 ? 'Indiquez votre nom' : null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Continuer'),
            ),
          ],
        ),
      ),
    );
  }
}
