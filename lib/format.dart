import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'api.dart';
import 'models.dart';

final _money = NumberFormat.decimalPattern('fr');

String money(num amount) => '${_money.format(amount)} FCFA';

String dateLong(DateTime d) => DateFormat('d MMMM yyyy', 'fr').format(d);

String dateShort(DateTime d) => DateFormat('d MMM yyyy', 'fr').format(d);

String dateTime(DateTime d) =>
    DateFormat("d MMM yyyy 'à' HH:mm", 'fr').format(d);

String frequencyLabel(Frequency f) => switch (f) {
  Frequency.daily => 'Chaque jour',
  Frequency.weekly => 'Chaque semaine',
  Frequency.biweekly => 'Toutes les 2 semaines',
  Frequency.monthly => 'Chaque mois',
};

/// « chaque jour », « chaque semaine »…
String frequencyLower(Frequency f) => frequencyLabel(f).toLowerCase();

/// Durée couverte par [n] cotisations : « 30 jours », « 4 semaines »…
String durationLabel(Frequency f, int n) => switch (f) {
  Frequency.daily => '$n jour${n > 1 ? 's' : ''}',
  Frequency.weekly => '$n semaine${n > 1 ? 's' : ''}',
  Frequency.biweekly => '${2 * n} semaines',
  Frequency.monthly => '$n mois',
};

/// Unité de la durée de collecte saisie par le tontinier.
String durationUnit(Frequency f) => switch (f) {
  Frequency.daily => 'jours',
  Frequency.weekly => 'semaines',
  Frequency.biweekly => 'quinzaines',
  Frequency.monthly => 'mois',
};

/// « 3 cotisations »
String contributionsLabel(int n) => '$n cotisation${n > 1 ? 's' : ''}';

/// Échéance par rapport à aujourd'hui : « aujourd'hui », « dans 12 jours »…
String countdownLabel(DateTime date, [DateTime? now]) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final days = DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  return switch (days) {
    0 => 'aujourd\'hui',
    1 => 'demain',
    -1 => 'hier',
    > 1 => 'dans $days jours',
    _ => 'il y a ${-days} jours',
  };
}

String commissionLabel(Group g) => g.commissionType == CommissionType.percent
    ? '${NumberFormat.decimalPattern('fr').format(g.commissionValue)} % (${money(g.commission)})'
    : money(g.commission);

String groupStatusLabel(GroupStatus s) => switch (s) {
  GroupStatus.recruiting => 'Inscriptions',
  GroupStatus.drawing => 'Tirage au sort',
  GroupStatus.ready => 'Prête à démarrer',
  GroupStatus.active => 'En cours',
  GroupStatus.finished => 'Terminée',
};

String methodLabel(PaymentMethod m) => switch (m) {
  PaymentMethod.mobileMoney => 'Mobile Money',
  PaymentMethod.cash => 'Espèces',
};

/// « du 1 nov. 2026 au 28 août 2027 »
String periodLabel(DateTime from, DateTime to) =>
    'du ${dateShort(from)} au ${dateShort(to)}';

/// Opérateurs Mobile Money proposés pour les numéros de paiement.
const mobileOperators = [
  'MTN MoMo',
  'Moov Money',
  'Celtiis Cash',
  'Wave',
  'Orange Money',
  'Autre',
];

String paymentStatusLabel(PaymentStatus s) => switch (s) {
  PaymentStatus.pending => 'En attente',
  PaymentStatus.approved => 'Validé',
  PaymentStatus.rejected => 'Refusé',
};

/// Pénalité de retard : « 10 % du montant dû (500 FCFA par cotisation),
/// après 2 jours de retard ».
String penaltyLabel(Group g) {
  final amount = g.penaltyType == PenaltyType.percent
      ? '${g.penaltyAmount} % du montant dû '
            '(${money(g.penaltyPerContribution)} par cotisation)'
      : '${money(g.penaltyAmount)} par cotisation';
  final when = g.penaltyGraceDays == 0
      ? 'dès le lendemain de l\'échéance'
      : 'après ${g.penaltyGraceDays} jour${g.penaltyGraceDays > 1 ? 's' : ''} '
            'de retard';
  return '$amount, $when';
}

/// Montant court de la pénalité (« 10 % » ou « 500 FCFA »).
String penaltyShort(Group g) => g.penaltyType == PenaltyType.percent
    ? '${g.penaltyAmount} %'
    : money(g.penaltyAmount);

/// Couleurs d'état (lisibles en texte sur fond clair) : orange = en
/// attente, vert = validé / à jour, rouge = refusé / bloqué.
Color paymentStatusColor(PaymentStatus s) => switch (s) {
  PaymentStatus.pending => const Color(0xFFA85A00),
  PaymentStatus.approved => const Color(0xFF177A45),
  PaymentStatus.rejected => const Color(0xFFB3261E),
};

/// Indicatifs proposés à l'inscription et à la connexion.
const dialCodes = <(String, String)>[
  ('+229', 'Bénin'),
  ('+228', 'Togo'),
  ('+225', 'Côte d\'Ivoire'),
  ('+226', 'Burkina Faso'),
  ('+227', 'Niger'),
  ('+223', 'Mali'),
  ('+221', 'Sénégal'),
  ('+224', 'Guinée'),
  ('+237', 'Cameroun'),
  ('+241', 'Gabon'),
  ('+242', 'Congo'),
  ('+243', 'RD Congo'),
  ('+234', 'Nigeria'),
  ('+233', 'Ghana'),
  ('+33', 'France'),
];

/// Numéro au format international (+229...). Les espaces et tirets sont
/// ignorés ; un numéro commençant par + ou 00 garde son propre indicatif.
String normalizePhone(String dialCode, String input) {
  final raw = input.trim();
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (raw.startsWith('+')) return '+$digits';
  if (digits.startsWith('00')) return '+${digits.substring(2)}';
  return '$dialCode$digits';
}

bool isValidPhone(String e164) => RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(e164);

/// Montant saisi (« 25 000 ») -> 25000.
int? parseAmount(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}

/// Message d'erreur lisible pour l'utilisateur.
String errorMessage(Object e) {
  if (e is AppException) return e.message;
  if (e is FirebaseAuthException) {
    return switch (e.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'invalid-email' => 'Numéro ou mot de passe incorrect',
      'email-already-in-use' => 'Ce numéro est déjà inscrit. Connectez-vous.',
      'weak-password' => 'Mot de passe trop faible (6 caractères minimum)',
      'too-many-requests' =>
        'Trop de tentatives. Réessayez dans quelques minutes.',
      'network-request-failed' => 'Pas de connexion internet',
      'operation-not-allowed' =>
        'La connexion par mot de passe n\'est pas activée sur le serveur',
      _ => 'Connexion impossible (${e.code})',
    };
  }
  if (e is FirebaseException) {
    return switch (e.code) {
      'permission-denied' => 'Action non autorisée',
      'unavailable' || 'deadline-exceeded' => 'Pas de connexion internet',
      'not-found' => 'Élément introuvable',
      _ => 'Une erreur est survenue (${e.code})',
    };
  }
  return 'Une erreur est survenue';
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(errorMessage(e))));
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
