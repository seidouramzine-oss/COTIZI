# Firebase — mise en service

COTIZI utilise l'**offre gratuite Spark** : Authentication + Cloud Firestore.
Pas de Cloud Functions ni de Cloud Storage (payants) : les règles de
`firestore.rules` font les vérifications, et les captures de paiement sont
compressées et enregistrées dans Firestore.

## 1. Créer le projet (console.firebase.google.com)

1. **Ajouter un projet** : `cotizi` (Google Analytics facultatif).
2. **Authentication → Commencer → Adresse e-mail/Mot de passe → Activer**.
   Le numéro de téléphone sert d'identifiant : l'application crée des comptes
   avec un email technique `<numéro>@phone.cotizi.app` (aucun email envoyé).
3. **Firestore Database → Créer une base de données** : emplacement `eur3`,
   mode production.
4. **Paramètres du projet → Vos applications → Android** :
   package `com.cotizi.app`, puis récupérer `google-services.json`.
   (Facultatif : ajouter aussi une application **Web** pour tester dans un navigateur.)

## 2. Publier les règles de sécurité

**Firestore Database → Règles** : remplacer tout le contenu par celui de
[`firestore.rules`](firestore.rules), puis **Publier**.

Ou avec la ligne de commande :

```bash
npx firebase login
npx firebase deploy --only firestore:rules --project <id-du-projet>
```

## 3. Brancher l'application

Reporter les valeurs de `google-services.json` dans `lib/firebase_options.dart` :

| `google-services.json`                              | `FirebaseOptions`   |
|-----------------------------------------------------|---------------------|
| `client[0].api_key[0].current_key`                  | `apiKey`            |
| `client[0].client_info.mobilesdk_app_id`            | `appId`             |
| `project_info.project_number`                       | `messagingSenderId` |
| `project_info.project_id`                           | `projectId`         |
| `project_info.storage_bucket`                       | `storageBucket`     |

Ces identifiants ne sont pas secrets : la sécurité repose sur les règles.

## Tester les règles

```bash
npm install
npm test   # lance l'émulateur Firestore et le scénario tests/rules.test.mjs
```

Le scénario couvre : inscription, création de groupe, invitations, groupe complet,
tirage au sort (impossible de choisir son numéro), déclarations avec preuve,
refus motivé, validation, carnet de 31 cases, confidentialité des données.
