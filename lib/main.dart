import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'firebase_options.dart';
import 'invite_link.dart';
import 'models.dart';
import 'screens/auth_screens.dart';
import 'screens/home_screen.dart';
import 'settings.dart';
import 'widgets/common.dart';
import 'reminders.dart';

/// --dart-define=USE_EMULATOR=true : utilise les émulateurs Firebase locaux.
const _useEmulator = bool.fromEnvironment('USE_EMULATOR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr';
  await initializeDateFormatting('fr');
  await loadSettings();
  await Reminders.init();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (_useEmulator) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  }
  // Liens d'invitation (cotizi://join?c=CODE) : traités après connexion
  listenToInviteLinks();
  runApp(const CotiziApp());
}

class CotiziApp extends StatelessWidget {
  const CotiziApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'COTIZI',
        debugShowCheckedModeBanner: false,
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        home: const AuthGate(),
      ),
    );
  }
}

/// Affiche l'écran de connexion, la création du profil ou l'accueil.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: Api.authChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data == null) return const LoginScreen();
        return _ProfileGate(key: ValueKey(snap.data!.uid));
      },
    );
  }
}

class _ProfileGate extends StatefulWidget {
  const _ProfileGate({super.key});

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  late Future<Profile?> _profile = Api.myProfile();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureView<Profile?>(
        future: _profile,
        onRetry: () => setState(() => _profile = Api.myProfile()),
        builder: (context, profile) => profile == null
            ? CompleteProfileScreen(
                onDone: () => setState(() => _profile = Api.myProfile()),
              )
            : HomeScreen(profile: profile),
      ),
    );
  }
}
