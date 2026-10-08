import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'carnet_screens.dart';
import 'group_screens.dart';

/// Icône et couleur d'une notification selon l'opération.
(IconData, Color) notificationStyle(String type) => switch (type) {
  'payment_declared' => (
    Icons.receipt_long,
    paymentStatusColor(PaymentStatus.pending),
  ),
  'payment_approved' || 'payment_recorded' || 'payout_received' => (
    Icons.check_circle_outline,
    paymentStatusColor(PaymentStatus.approved),
  ),
  'payment_rejected' || 'payout_problem' => (
    Icons.error_outline,
    paymentStatusColor(PaymentStatus.rejected),
  ),
  'payout_confirmed' => (
    Icons.savings_outlined,
    paymentStatusColor(PaymentStatus.approved),
  ),
  'joined' => (Icons.person_add_alt, const Color(0xFF1D4E89)),
  'rules_accepted' => (Icons.gavel_outlined, const Color(0xFF1D4E89)),
  'started' => (Icons.play_circle_outline, const Color(0xFF1D4E89)),
  'refund_requested' => (Icons.undo, paymentStatusColor(PaymentStatus.pending)),
  'carnet_closed' || 'group_closed' => (
    Icons.task_alt,
    paymentStatusColor(PaymentStatus.approved),
  ),
  _ => (Icons.notifications_none, Colors.grey),
};

/// « il y a 5 min », « hier à 14:02 »…
String agoLabel(DateTime at, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final d = n.difference(at);
  if (d.inMinutes < 1) return 'à l\'instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24 && at.day == n.day) return 'il y a ${d.inHours} h';
  return dateTime(at);
}

/// Une ligne de notification (cloche, activité récente de l'accueil).
class NotificationTile extends StatelessWidget {
  const NotificationTile(this.n, {super.key, this.onTap});

  final AppNotification n;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = notificationStyle(n.type);
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              n.title,
              style: TextStyle(
                fontWeight: n.read ? FontWeight.w600 : FontWeight.w800,
              ),
            ),
          ),
          if (!n.read)
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      subtitle: Text('${n.body}\n${agoLabel(n.at)}'),
      isThreeLine: true,
    );
  }
}

/// Ouvre le groupe ou le carnet concerné par une notification.
void openNotificationTarget(BuildContext context, AppNotification n) {
  final screen = n.groupId != null
      ? GroupScreen(groupId: n.groupId!)
      : n.carnetId != null
      ? CarnetScreen(carnetId: n.carnetId!)
      : null;
  if (screen == null) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

/// Toutes les notifications ; elles sont marquées comme lues à l'ouverture.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<AppNotification>> _data = _load();

  static Future<List<AppNotification>> _load() async {
    final list = await Api.notifications();
    // Affichées comme non lues cette fois-ci, enregistrées comme lues
    Api.markAllRead(list).catchError((_) {});
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _data = _load());
          await _data;
        },
        child: FutureView<List<AppNotification>>(
          future: _data,
          onRetry: () => setState(() => _data = _load()),
          builder: (context, list) {
            if (list.isEmpty) {
              return ListView(
                children: const [
                  EmptyState(
                    icon: Icons.notifications_none,
                    title: 'Aucune notification',
                    message:
                        'Vous serez prévenu ici des paiements déclarés, des '
                        'nouveaux participants, des remises et des validations.',
                  ),
                ],
              );
            }
            final today = DateUtils.dateOnly(DateTime.now());
            final recent = list.where((n) => !n.at.isBefore(today)).toList();
            final older = list.where((n) => n.at.isBefore(today)).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                for (final (title, items) in [
                  ('Aujourd\'hui', recent),
                  ('Plus tôt', older),
                ])
                  if (items.isNotEmpty) ...[
                    SectionTitle(title),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final n in items)
                            NotificationTile(
                              n,
                              onTap: () => openNotificationTarget(context, n),
                            ),
                        ],
                      ),
                    ),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Cloche avec le nombre de notifications non lues.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.unread,
    required this.onTap,
  });

  final Future<int> unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: unread,
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return IconButton(
          tooltip: n == 0 ? 'Notifications' : 'Notifications : $n nouvelles',
          onPressed: onTap,
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n > 9 ? '9+' : '$n'),
            child: Icon(
              n > 0 ? Icons.notifications_active : Icons.notifications_none,
            ),
          ),
        );
      },
    );
  }
}
