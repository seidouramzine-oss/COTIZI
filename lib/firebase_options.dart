import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Configuration du projet Firebase de COTIZI.
/// Les valeurs viennent de google-services.json (Android) et du bloc
/// firebaseConfig (Web) de la console Firebase. Ce ne sont pas des secrets :
/// les données sont protégées par firebase/firestore.rules.
///
/// Tant que le projet n'est pas configuré, le projet « demo-cotizi » permet
/// de tester l'application avec les émulateurs Firebase
/// (flutter run --dart-define=USE_EMULATOR=true).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => kIsWeb ? web : android;

  static const android = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-cotizi',
  );

  static const web = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-cotizi',
    authDomain: 'demo-cotizi.firebaseapp.com',
  );
}
