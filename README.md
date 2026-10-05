# COTIZI

Application de gestion de tontine : **tontines à cagnotte** (groupes, tirage au sort,
déclaration des paiements avec preuve, validation par le tontinier) et
**tontines à carnet** (carnets de 31 cases, la dernière case revenant au tontinier).

Les règles de fonctionnement sont décrites dans [docs/REGLES_METIER.md](docs/REGLES_METIER.md).

## Technologies

- **Application mobile** : Flutter (Android ; iOS et web possibles)
- **Serveur** : Supabase (base PostgreSQL, comptes, stockage des captures, fonction d'inscription)

## Structure

```
lib/
  main.dart              démarrage, thème, connexion/accueil
  config.dart            adresse et clé publique du projet Supabase
  api.dart               toutes les requêtes vers Supabase
  models.dart            tontines, groupes, carnets, paiements (+ calculs)
  format.dart            montants FCFA, dates, numéros, messages d'erreur
  screens/               écrans (connexion, accueil, tontines, groupes, carnets, paiements)
  widgets/common.dart    composants partagés
supabase/
  migrations/            schéma de la base, règles d'accès, actions (tirage, validations...)
  functions/signup/      inscription par numéro de téléphone
  tests/                 scénario de test de la base sur PostgreSQL local
test/                    tests des calculs (commission, dates, cases, téléphones)
```

## Mise en service du serveur (Supabase)

1. Créer un projet Supabase (ex. « cotizi », région Paris `eu-west-3`).
2. Appliquer `supabase/migrations/20261005000000_init.sql`.
3. Déployer la fonction `supabase/functions/signup` en mode public
   (`verify_jwt = false`) : c'est le point d'inscription de l'application.
4. Renseigner l'URL du projet et sa clé publique (`sb_publishable_...`) dans
   `lib/config.dart`, ou à la compilation :

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<projet>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

## Développement

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release   # APK dans build/app/outputs/flutter-apk/
```
