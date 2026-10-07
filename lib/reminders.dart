import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'format.dart';
import 'models.dart';

/// Un rappel à afficher sur le téléphone.
class Reminder {
  const Reminder(this.at, this.title, this.body);

  final DateTime at;
  final String title;
  final String body;

  @override
  String toString() => '$at · $title · $body';
}

/// Rappels à programmer, calculés à partir des cagnottes du participant
/// ([member]) et des groupes du tontinier ([owned]) :
/// - la veille de chaque cotisation à payer, à 18 h (les 10 prochaines par
///   groupe), avec le retard éventuel ;
/// - le lendemain matin à 9 h s'il a déjà des cotisations en retard ;
/// - pour le tontinier, le matin de chaque remise à 8 h (les 3 prochaines).
List<Reminder> planReminders({
  List<MemberGroupStatus> member = const [],
  List<Group> owned = const [],
  required DateTime now,
}) {
  final out = <Reminder>[];
  final today = DateTime(now.year, now.month, now.day);
  for (final s in member) {
    final g = s.group;
    if (g.isLegacy || g.status != GroupStatus.active) continue;
    final st = s.standing;
    if (st.late > 0) {
      out.add(
        Reminder(
          today.add(const Duration(days: 1, hours: 9)),
          'Cotisations en retard · ${g.name}',
          'Vous avez ${contributionsLabel(st.late)} en retard '
              '(${money(st.late * g.contributionAmount + st.penaltyDue)}). '
              'Payez puis déclarez votre paiement dans COTIZI.',
        ),
      );
    }
    var planned = 0;
    for (var i = st.declared + 1; i <= st.total && planned < 10; i++) {
      final due = g.contributionDate(i);
      final at = due.subtract(const Duration(hours: 6)); // veille à 18 h
      if (!at.isAfter(now)) continue;
      final lateThen = i - 1 - st.declared;
      out.add(
        Reminder(
          at,
          'Cotisation demain · ${g.name}',
          '${money(g.contributionAmount)} à payer demain (${dateShort(due)})'
              '${lateThen > 0 ? '. Vous avez aussi ${contributionsLabel(lateThen)} en retard' : ''}. '
              'Payez par Mobile Money ou en espèces, puis déclarez-le dans COTIZI.',
        ),
      );
      planned++;
    }
  }
  for (final g in owned) {
    if (g.isLegacy || g.status != GroupStatus.active) continue;
    for (
      var pot = g.paidOutCount + 1;
      pot <= g.memberCount && pot <= g.paidOutCount + 3;
      pot++
    ) {
      final at = g.payoutDate(pot).add(const Duration(hours: 8));
      if (!at.isAfter(now)) continue;
      final b = g.beneficiaryOf(pot);
      out.add(
        Reminder(
          at,
          'Remise prévue aujourd\'hui · ${g.name}',
          'Cagnotte n°$pot pour ${b?.name ?? 'le bénéficiaire'} '
              '(${money(g.netPot)}). Elle peut être remise dès que la collecte '
              'est complète.',
        ),
      );
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.take(60).toList();
}

/// Rappels sur le téléphone, sans serveur : reprogrammés à chaque ouverture
/// de l'accueil. Android seulement.
class Reminders {
  Reminders._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _enabledKey = 'reminders_enabled';
  static const _askedKey = 'reminders_asked';
  static bool _ready = false;

  /// Rappels activés (réglage du profil).
  static final enabled = ValueNotifier<bool>(true);

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_enabledKey) ?? true;
    } catch (_) {}
    if (!supported) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(_localLocation());
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_cotizi'),
        ),
      );
      _ready = true;
    } catch (_) {
      // Pas de rappels si le téléphone ne les permet pas
    }
  }

  /// Fuseau du téléphone, retrouvé d'après son décalage horaire actuel
  /// (Bénin et voisins : UTC+1 toute l'année).
  static tz.Location _localLocation() {
    final offset = DateTime.now().timeZoneOffset;
    if (offset.inMinutes % 60 == 0) {
      final h = offset.inHours;
      // Les zones « Etc/GMT » ont le signe inversé : UTC+1 = Etc/GMT-1
      final name = h == 0 ? 'Etc/UTC' : 'Etc/GMT${h > 0 ? '-' : '+'}${h.abs()}';
      try {
        return tz.getLocation(name);
      } catch (_) {}
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final l in tz.timeZoneDatabase.locations.values) {
      if (l.timeZone(now).offset == offset) return l;
    }
    return tz.getLocation('Africa/Lagos');
  }

  /// Active ou désactive les rappels.
  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (_) {}
    if (!_ready) return;
    if (value) {
      await _android?.requestNotificationsPermission();
    } else {
      await _plugin.cancelAllPendingNotifications();
    }
  }

  static List<MemberGroupStatus> _member = const [];
  static List<Group> _owned = const [];

  /// Reprogramme tous les rappels (sans argument : avec les dernières
  /// données chargées, par exemple quand on réactive les rappels).
  static Future<void> update({
    List<MemberGroupStatus>? member,
    List<Group>? owned,
  }) async {
    if (member != null || owned != null) {
      _member = member ?? const [];
      _owned = owned ?? const [];
    }
    if (!_ready || !enabled.value) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_askedKey) != true) {
        await prefs.setBool(_askedKey, true);
        await _android?.requestNotificationsPermission();
      }
      await _plugin.cancelAllPendingNotifications();
      final plan = planReminders(
        member: _member,
        owned: _owned,
        now: DateTime.now(),
      );
      for (var i = 0; i < plan.length; i++) {
        final r = plan[i];
        await _plugin.zonedSchedule(
          id: i,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'rappels',
              'Rappels',
              channelDescription: 'Cotisations à payer et remises de cagnotte',
              importance: Importance.high,
              priority: Priority.high,
              color: const Color(0xFF0A6B4E),
              styleInformation: BigTextStyleInformation(r.body),
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: r.title,
          body: r.body,
        );
      }
    } catch (e) {
      debugPrint('Rappels : $e');
    }
  }
}
