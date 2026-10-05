import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Site public de COTIZI (GitHub Pages) : page d'invitation et téléchargement.
const siteUrl = 'https://zidane123-web.github.io';

/// Lien à partager : la page web ouvre COTIZI (cotizi://join?c=CODE)
/// ou propose de télécharger l'application.
String inviteUrl(String code) => '$siteUrl/j/?c=$code';

String inviteMessage(String intro, String code) =>
    '$intro\n\nAppuie sur ce lien pour rejoindre :\n${inviteUrl(code)}\n\n'
    '(Code d\'invitation : $code)';

/// Code contenu dans un lien d'invitation, ou null.
/// Accepte cotizi://join?c=CODE et toute page web /j/?c=CODE (site public,
/// version web de l'application).
String? inviteCodeFrom(Uri uri) {
  final isApp = uri.scheme == 'cotizi' && uri.host == 'join';
  final isWeb =
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.path.startsWith('/j');
  if (!isApp && !isWeb) return null;
  final code = (uri.queryParameters['c'] ?? '').toUpperCase().replaceAll(
    RegExp(r'[^A-Z0-9]'),
    '',
  );
  return code.isEmpty ? null : code;
}

/// Invitation reçue par lien, en attente d'être traitée (après connexion
/// si nécessaire).
final pendingInvite = ValueNotifier<String?>(null);

/// Écoute les liens d'invitation : celui qui a lancé l'application et
/// ceux reçus pendant qu'elle est ouverte.
Future<void> listenToInviteLinks() async {
  final links = AppLinks();
  try {
    final initial = await links.getInitialLink();
    if (initial != null) pendingInvite.value = inviteCodeFrom(initial);
  } catch (_) {
    // Pas de lien au démarrage (ou plateforme sans liens profonds)
  }
  links.uriLinkStream.listen((uri) {
    final code = inviteCodeFrom(uri);
    if (code != null) pendingInvite.value = code;
  }, onError: (_) {});
}
