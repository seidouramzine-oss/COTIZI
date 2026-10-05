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

String commissionLabel(Group g) => g.commissionType == CommissionType.percent
    ? '${NumberFormat.decimalPattern('fr').format(g.commissionValue)} % (${money(g.commission)})'
    : money(g.commission);

String groupStatusLabel(GroupStatus s) => switch (s) {
  GroupStatus.recruiting => 'Inscriptions',
  GroupStatus.drawing => 'Tirage au sort',
  GroupStatus.active => 'En cours',
};

String paymentStatusLabel(PaymentStatus s) => switch (s) {
  PaymentStatus.pending => 'En attente',
  PaymentStatus.approved => 'Validé',
  PaymentStatus.rejected => 'Refusé',
};

Color paymentStatusColor(PaymentStatus s) => switch (s) {
  PaymentStatus.pending => const Color(0xFFE08600),
  PaymentStatus.approved => const Color(0xFF1B8A4B),
  PaymentStatus.rejected => const Color(0xFFC62828),
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
