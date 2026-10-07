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

### Devenir administrateur (une seule fois)

L'écran **Administration** (abonnements des tontiniers, prix, numéro de
paiement) est réservé aux comptes listés dans la collection `admins` :

1. **Authentication → Utilisateurs** : copier l'**UID** de votre compte
   (la ligne `<votre numéro>@phone.cotizi.app`).
2. **Firestore Database → Données → Commencer une collection** :
   ID de la collection `admins`, ID du document = l'UID copié, un champ
   `note` (chaîne) = `propriétaire`, puis **Enregistrer**.
3. Dans l'application : **Profil → Administration**.

Personne ne peut se déclarer administrateur depuis l'application : les règles
refusent toute écriture dans `admins`.

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
tirage au sort (impossible de choisir son numéro) ou ordre fixé par le tontinier,
modification et suppression avant le démarrage, règlement accepté par chaque
participant avant le démarrage, bouton « Démarrer », paiement de
plusieurs cotisations (Mobile Money avec preuve ou espèces) avec pénalités de
retard (montant fixe ou pourcentage), refus motivé, validation, encaissement par le tontinier, participants
sans application et récupération de leur place, remise refusée tant que la collecte
n'est pas complète (niveaux des participants tenus à jour par le groupe),
remises confirmées par le bénéficiaire, historique des actions, profil pro, anciens groupes en lecture
seule, carnet de 31 cases, confidentialité des données, essai gratuit et
abonnement des tontiniers, demandes d'abonnement, administration.
