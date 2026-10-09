import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show appFlavor;

/// Version de test (« COTIZI Test », flavor staging) : projet « cotizi-test »,
/// séparé des vraies données. Construite avec --flavor staging.
bool get isTestBuild => appFlavor == 'staging';

/// Configuration du projet Firebase de COTIZI.
/// Les valeurs viennent de google-services.json (Android) et du bloc
/// firebaseConfig (Web) de la console Firebase. Ce ne sont pas des secrets :
/// les données sont protégées par firebase/firestore.rules.
///
/// Tant que le projet n'est pas configuré, le projet « demo-cotizi » permet
/// de tester l'application avec les émulateurs Firebase
/// (flutter run --dart-define=USE_EMULATOR=true).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      kIsWeb ? web : (isTestBuild ? androidTest : android);

  // Projet Firebase « cotizi » (application Android com.cotizi.app)
  static const android = FirebaseOptions(
    apiKey: 'AIzaSyCp0pdbylXUx9C5-3VWrvTDp-fOrHaqaVA',
    appId: '1:357292235465:android:518da13a256af7fa118b18',
    messagingSenderId: '357292235465',
    projectId: 'cotizi',
  );

  // Projet Firebase « cotizi-test » (application Android com.cotizi.app.test)
  static const androidTest = FirebaseOptions(
    apiKey: 'AIzaSyBSFV7yTnLESTb9larhLE9hnxyv9M5hkeU',
    appId: '1:163157055197:android:21fbee981eda43ab44ed34',
    messagingSenderId: '163157055197',
    projectId: 'cotizi-test',
  );

  static const web = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-cotizi',
    authDomain: 'demo-cotizi.firebaseapp.com',
  );
}
