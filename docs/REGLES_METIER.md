# COTIZI — règles de fonctionnement

COTIZI est un service pour les **tontiniers** : ils créent et gèrent des
tontines, puis invitent leurs **clients**, qui ne font que participer.

## Compte

- Inscription avec **nom, numéro de téléphone et mot de passe** (aucun SMS).
- Le numéro (avec indicatif, +229 par défaut) sert d'identifiant de connexion.
- À l'inscription, on choisit **Tontinier** ou **Client** ; ce choix est définitif.
  - **Client** : le code d'invitation du tontinier est obligatoire (déjà rempli
    s'il arrive par le lien). Code introuvable : le compte n'est pas créé. Le
    client ne voit que ses tontines (Accueil, Mes tontines, Profil) et ne crée rien.
  - **Tontinier** : peut créer des tontines et aussi rejoindre celles d'un autre
    tontinier (« Je participe »).

## Essai gratuit et abonnement des tontiniers

- Un nouveau tontinier a **30 jours d'essai gratuit** à partir de son inscription.
- Ensuite, il faut un **abonnement** pour créer de nouvelles tontines, groupes et
  carnets. Sans abonnement, les groupes et carnets en cours **continuent** : le
  tontinier peut toujours valider ou refuser les paiements de ses clients.
- Le tontinier paie par Mobile Money au numéro affiché dans
  **Profil → Mon abonnement** (prix et numéro réglés par l'administrateur), puis
  prévient sur WhatsApp.
- L'**administrateur** de COTIZI (Profil → Administration) voit tous les
  tontiniers, prolonge l'abonnement de 1, 3 ou 12 mois (à partir de la fin en
  cours, sinon d'aujourd'hui) ou l'arrête. Il n'a pas besoin d'abonnement.

## Tontine à cagnotte

1. Le tontinier crée sa tontine, puis un ou plusieurs **groupes**.
2. Pour chaque groupe il fixe :
   - le **nombre de membres** (= nombre de tours) ;
   - la **cotisation** par membre et par tour ;
   - la **fréquence** : chaque jour, chaque semaine, toutes les 2 semaines ou chaque mois ;
   - la **date du premier tour** (les dates suivantes en découlent) ;
   - sa **commission** : un pourcentage ou un montant fixe, **retenue sur la cagnotte** du bénéficiaire.
3. Le groupe reçoit un **code d'invitation** que le tontinier partage (WhatsApp, SMS...).
   Les membres l'entrent dans l'application pour rejoindre le groupe.
4. Quand le groupe est **complet**, le tontinier **lance le tirage au sort** :
   l'application tire alors au hasard l'ordre de passage. Chaque membre
   **tire ensuite son numéro** pour découvrir son tour de réception de la cagnotte
   (il ne peut ni le choisir ni le changer). Le tontinier peut révéler les
   numéros des membres retardataires.
5. Quand tout le monde a son numéro, le groupe passe **en cours**.
6. À chaque tour, chaque membre **déclare son paiement** avec une **capture d'écran**
   de l'envoi. Le paiement est **en attente** jusqu'à ce que le tontinier :
   - le **valide**, ou
   - le **refuse en indiquant la raison** ; le membre peut alors déclarer à nouveau.

Exemple : 10 membres × 5 000 FCFA = cagnotte de 50 000 FCFA par tour ;
commission 5 % = 2 500 FCFA ; le bénéficiaire reçoit 47 500 FCFA.

## Tontine à carnet

1. Le tontinier crée sa tontine, puis des **carnets de 31 cases**, avec le
   **montant d'une case**.
2. Chaque carnet a un **code d'invitation** ; le client l'utilise pour devenir
   le titulaire du carnet (un seul client par carnet).
3. Le client **déclare ses paiements avec preuve** (une ou plusieurs cases à la fois) ;
   le tontinier valide ou refuse avec une raison, comme pour la cagnotte.
4. Le client paie **31 cases** et **récupère 30 cases** ; la **dernière case est la
   commission** du tontinier.

Exemple : case à 500 FCFA → le client paie 15 500 FCFA et reçoit 15 000 FCFA ;
commission 500 FCFA.

## Confidentialité des données

- Un membre ne voit que les groupes qu'il a rejoints, les membres de ces groupes
  et son tontinier ; il ne voit que ses propres paiements.
- Le tontinier voit ses tontines, ses membres / clients et tous les paiements
  et preuves de ses groupes et carnets.
- Les captures d'écran sont compressées et stockées de façon privée ; elles ne
  sont visibles que par leur auteur et le tontinier concerné.
- Ces règles sont appliquées par le serveur (règles de sécurité Firebase),
  pas seulement par l'application.
