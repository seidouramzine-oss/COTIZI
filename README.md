# COTIZI

Application de gestion de tontine pour les tontiniers : **tontines à cagnotte**
(groupes, tirage au sort ou ordre fixé, bouton « Démarrer », paiements Mobile Money
ou espèces, pénalités de retard, remises confirmées par le bénéficiaire) et
**tontines à carnet** (carnets de 31 cases, la dernière case revenant au tontinier),
avec profil pro, tableau des gains, historique des actions et relevés PDF.

Les règles de fonctionnement sont décrites dans [docs/REGLES_METIER.md](docs/REGLES_METIER.md).

## Technologies

- **Application mobile** : Flutter (Android ; web possible)
- **Serveur** : Firebase, offre gratuite Spark
  - Authentication (numéro de téléphone + mot de passe)
  - Cloud Firestore (données, captures de paiement compressées)
  - Règles de sécurité : [firebase/firestore.rules](firebase/firestore.rules)

## Structure

```
lib/
  main.dart              démarrage, thème, connexion / profil / accueil
  firebase_options.dart  identifiants du projet Firebase (publics)
  api.dart               toutes les lectures / écritures Firebase
  models.dart            tontines, groupes, carnets, paiements (+ calculs)
  format.dart            montants FCFA, dates, numéros, messages d'erreur
  reports.dart           relevés et bilans PDF
  screens/               écrans (connexion, accueil, tontines, groupes, carnets, paiements,
                         profil pro, gains, abonnement, administration)
  widgets/common.dart    composants partagés
assets/fonts/            police Roboto des relevés PDF
firebase/
  firestore.rules        règles de sécurité (à publier dans la console Firebase)
  tests/                 scénario de test des règles sur l'émulateur Firestore
test/                    tests des calculs (commission, dates, cases, téléphones)
```

## Mise en service de Firebase

Voir [firebase/README.md](firebase/README.md).

## Développement

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release   # APK dans build/app/outputs/flutter-apk/

# Tester avec les émulateurs Firebase locaux
cd firebase && npm install && npx firebase emulators:start --only auth,firestore --project demo-cotizi
flutter run -d chrome --dart-define=USE_EMULATOR=true

# Tester les règles de sécurité
cd firebase && npm test
```
