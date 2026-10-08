import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';

/// « Votre argent reste chez vous » : COTIZI ne touche jamais l'argent.
class MoneySafetyCard extends StatelessWidget {
  const MoneySafetyCard({super.key, required this.isMember});

  final bool isMember;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_user_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Votre argent reste chez vous',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isMember
                        ? 'COTIZI ne touche jamais votre argent. Vous payez '
                              'votre tontinier comme d\'habitude (Mobile Money '
                              'ou espèces), vous déclarez le paiement et il le '
                              'valide. Chaque opération est enregistrée : elle '
                              'ne peut être ni modifiée ni supprimée.'
                        : 'COTIZI ne touche jamais l\'argent. Vos clients vous '
                              'paient comme d\'habitude (Mobile Money ou '
                              'espèces), déclarent le paiement et vous le '
                              'validez. Chaque opération est enregistrée : elle '
                              'ne peut être ni modifiée ni supprimée.',
                    style: TextStyle(color: scheme.onPrimaryContainer),
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

/// « Besoin d'aide ? » : ouvre l'aide et l'assistance.
class HelpCard extends StatelessWidget {
  const HelpCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          foregroundColor: theme.colorScheme.onSecondaryContainer,
          child: const Icon(Icons.support_agent),
        ),
        title: const Text(
          'Besoin d\'aide ?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Explications pas à pas et assistance COTIZI sur WhatsApp.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Niveau affiché d'après la note de confiance.
(String, IconData, Color) trustLevel(TrustStats t) {
  if (t.isNew) {
    return ('Nouveau sur COTIZI', Icons.fiber_new_outlined, Colors.blueGrey);
  }
  if (t.payoutsDisputed > 0) {
    return (
      '${t.payoutsDisputed} problème${t.payoutsDisputed > 1 ? 's' : ''} '
          'signalé${t.payoutsDisputed > 1 ? 's' : ''}',
      Icons.report_gmailerrorred,
      paymentStatusColor(PaymentStatus.pending),
    );
  }
  if (t.confirmedPercent >= 80) {
    return (
      'Tontinier fiable',
      Icons.verified,
      paymentStatusColor(PaymentStatus.approved),
    );
  }
  return (
    'Remises en cours de confirmation',
    Icons.hourglass_bottom,
    paymentStatusColor(PaymentStatus.pending),
  );
}

/// Note de confiance d'un tontinier : cagnottes remises, réceptions
/// confirmées par les bénéficiaires, problèmes signalés. Les chiffres sont
/// tenus par COTIZI et le tontinier ne peut pas les modifier.
class TrustCard extends StatefulWidget {
  const TrustCard({
    super.key,
    required this.ownerId,
    this.ownerName,
    this.own = false,
  });

  final String ownerId;
  final String? ownerName;

  /// Vue du tontinier lui-même (« Ma note de confiance »).
  final bool own;

  @override
  State<TrustCard> createState() => _TrustCardState();
}

class _TrustCardState extends State<TrustCard> {
  late final Future<(TrustStats, Business?)> _data = Future.wait([
    Api.trust(widget.ownerId),
    Api.business(widget.ownerId),
  ]).then((r) => (r[0] as TrustStats, r[1] as Business?));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<(TrustStats, Business?)>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final (t, b) = snap.data!;
        final (label, icon, color) = trustLevel(t);
        final name = b?.name ?? widget.ownerName ?? 'Tontinier';
        Widget stat(String value, String caption, [Color? c]) => Expanded(
          child: Column(
            children: [
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: c,
                ),
              ),
              Text(
                caption,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.own
                      ? 'Ma note de confiance'
                      : 'Note de confiance du tontinier',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((b?.city ?? '').isNotEmpty)
                            Text(b!.city, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Chip(
                      avatar: Icon(icon, size: 18, color: color),
                      label: Text(label),
                      side: BorderSide(color: color.withValues(alpha: 0.4)),
                      backgroundColor: color.withValues(alpha: 0.08),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (t.isNew)
                  Text(
                    widget.own
                        ? 'Votre note se construit à chaque cagnotte remise et '
                              'confirmée par son bénéficiaire.'
                        : 'Ce tontinier n\'a pas encore remis de cagnotte avec '
                              'COTIZI.',
                  )
                else
                  Row(
                    children: [
                      stat('${t.payoutsDone}', 'cagnottes\nremises'),
                      stat(
                        '${t.confirmedPercent} %',
                        'confirmées par les\nbénéficiaires',
                        paymentStatusColor(PaymentStatus.approved),
                      ),
                      stat(
                        '${t.payoutsDisputed}',
                        'problèmes\nsignalés',
                        t.payoutsDisputed > 0
                            ? paymentStatusColor(PaymentStatus.rejected)
                            : null,
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Chiffres tenus par COTIZI : le tontinier ne peut pas '
                        'les modifier.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Une étape du guide de démarrage.
class StartStep {
  const StartStep(this.icon, this.label, this.done, this.onTap);

  final IconData icon;
  final String label;
  final bool done;
  final VoidCallback onTap;
}

/// Guide « Démarrer avec COTIZI » : étapes cochées au fur et à mesure.
class GettingStartedCard extends StatelessWidget {
  const GettingStartedCard({
    super.key,
    required this.steps,
    required this.onClose,
  });

  final List<StartStep> steps;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = steps.where((s) => s.done).length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.primary,
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Démarrer avec COTIZI',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '$done / ${steps.length} étapes faites',
                        style: TextStyle(color: scheme.onPrimary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Masquer le guide',
                  onPressed: onClose,
                  icon: Icon(Icons.close, color: scheme.onPrimary),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: done / steps.length,
            minHeight: 4,
            backgroundColor: scheme.primaryContainer,
          ),
          for (final s in steps)
            ListTile(
              leading: Icon(
                s.done ? Icons.check_circle : s.icon,
                color: s.done
                    ? paymentStatusColor(PaymentStatus.approved)
                    : scheme.primary,
              ),
              title: Text(
                s.label,
                style: TextStyle(
                  decoration: s.done ? TextDecoration.lineThrough : null,
                  color: s.done ? scheme.onSurfaceVariant : null,
                ),
              ),
              trailing: s.done ? null : const Icon(Icons.chevron_right),
              onTap: s.done ? null : s.onTap,
            ),
        ],
      ),
    );
  }
}
