import 'package:flutter/material.dart';

/// Couleur des boutons d'action mis en avant (jaune doré).
const homeAccent = Color(0xFFF2B705);

/// Dégradé des grandes cartes de l'accueil (vert COTIZI).
const homeGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF075A41), Color(0xFF0A6B4E), Color(0xFF13906A)],
);

/// « Bonjour », « Bon après-midi » ou « Bonsoir » selon l'heure.
String greetingFor(DateTime now) {
  if (now.hour >= 5 && now.hour < 12) return 'Bonjour';
  if (now.hour >= 12 && now.hour < 18) return 'Bon après-midi';
  return 'Bonsoir';
}

/// En-tête de l'accueil : grand bonjour, résumé, cloche et aide.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.name,
    required this.subtitle,
    required this.bell,
    required this.onHelp,
  });

  final String name;
  final String subtitle;
  final Widget bell;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${greetingFor(DateTime.now())} $name 👋',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _RoundButton(child: bell),
          const SizedBox(width: 8),
          _RoundButton(
            child: IconButton(
              tooltip: 'Aide',
              icon: const Icon(Icons.help_outline),
              onPressed: onHelp,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// « Reprenez là où vous vous êtes arrêté » : la prochaine chose à faire.
class ResumeCard extends StatelessWidget {
  const ResumeCard({
    super.key,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = color ?? scheme.primary;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: c.withValues(alpha: 0.12),
                child: Icon(icon, color: c),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grande carte en dégradé : étiquette, pastille, titre, ligne de
/// confiance, contenu libre et bouton blanc.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.label,
    required this.headline,
    this.caption,
    this.chip,
    this.reassurance,
    this.children = const [],
    this.buttonLabel,
    this.buttonIcon,
    this.onButton,
  });

  final String label;
  final String headline;
  final String? caption;

  /// Pastille en haut à droite (ex. bouton « masquer les chiffres »).
  final Widget? chip;

  /// Ligne avec coche (ex. « L'argent ne passe jamais par COTIZI »).
  final String? reassurance;
  final List<Widget> children;
  final String? buttonLabel;
  final IconData? buttonIcon;
  final VoidCallback? onButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const on = Colors.white;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        gradient: homeGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A6B4E).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: on.withValues(alpha: 0.85),
                  ),
                ),
              ),
              ?chip,
            ],
          ),
          const SizedBox(height: 6),
          Text(
            headline,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: on,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: on.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ],
          if (reassurance != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.verified_user, color: on, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reassurance!,
                    style: theme.textTheme.bodySmall?.copyWith(color: on),
                  ),
                ),
              ],
            ),
          ],
          ...children,
          if (buttonLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onButton,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0A6B4E),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              icon: Icon(buttonIcon ?? Icons.arrow_forward),
              label: Text(buttonLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pastille blanche transparente pour la grande carte (ex. « Masquer »).
class HeroChip extends StatelessWidget {
  const HeroChip({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: Colors.white.withValues(alpha: 0.16),
          shape: StadiumBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chiffre clé dans la grande carte.
class HeroStat extends StatelessWidget {
  const HeroStat({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte d'action : icône, titre, texte et bouton jaune arrondi.
class PromoCard extends StatelessWidget {
  const PromoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.buttonLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String text;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: homeAccent, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: homeAccent,
                      foregroundColor: const Color(0xFF1F1A00),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(buttonLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une action rapide : tuile carrée avec icône ronde et libellé.
class QuickTile extends StatelessWidget {
  const QuickTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(icon, color: scheme.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
