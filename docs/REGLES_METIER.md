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
   - le **nombre de participants** (= nombre de cagnottes : chacun reçoit une fois) ;
   - la **cotisation** et sa **fréquence** : chaque jour, chaque semaine, toutes
     les 2 semaines ou chaque mois ;
   - la date de la **première cotisation** ;
   - la **durée de collecte** avant chaque remise (ex. 30 jours = 30 cotisations) ;
   - la **date de la 1re remise** au bénéficiaire (par défaut, le dernier jour de
     collecte) ; les remises suivantes ont lieu tous les « durée de collecte » ;
   - sa **commission** (pourcentage ou montant fixe), **retenue sur chaque cagnotte**.
3. Le groupe reçoit un **lien / code d'invitation** que le tontinier partage.
4. Quand le groupe est **complet**, le tontinier **lance le tirage au sort** ;
   chaque participant **tire son numéro** = son rang de remise (il ne peut ni le
   choisir ni le changer). Le tontinier peut tirer pour les retardataires.
5. Le groupe passe **en cours** : la cagnotte n°1 est **en cours de collecte**.
   Tous les participants cotisent pour elle (barre de progression, montant
   validé / total, date et compte à rebours de la remise).
6. Le participant **paie une ou plusieurs cotisations à la fois** et déclare le
   paiement avec **une capture d'écran**. Il peut payer d'avance. Le paiement est
   **en attente** jusqu'à ce que le tontinier :
   - le **valide** (un **reçu** est alors disponible à partager), ou
   - le **refuse en indiquant la raison** (les cotisations sont à repayer).
7. **« Vous êtes à jour »** : toutes les cotisations arrivées à échéance sont
   déclarées. Sinon l'accueil affiche le nombre de cotisations **en retard** et le
   montant. Le tontinier voit qui est en retard et peut **relancer sur WhatsApp**.
8. Les cotisations comptent dans l'ordre : les N premières pour la cagnotte n°1,
   les N suivantes pour la n°2, etc.
9. À la remise, le tontinier **confirme « Cagnotte remise »** : elle passe dans
   l'historique (visible des participants) et la collecte suivante devient la
   cagnotte en cours. Après la dernière remise, la tontine est **terminée**.

Exemple : 10 participants, 5 000 FCFA par jour, collecte de 30 jours ;
cagnotte = 10 × 30 × 5 000 = 1 500 000 FCFA ; commission 5 % = 75 000 FCFA ;
le bénéficiaire reçoit 1 425 000 FCFA, une remise tous les 30 jours.

Les groupes créés avant la version 1.4 (une cotisation par tour) restent
consultables mais n'acceptent plus de paiements.

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
