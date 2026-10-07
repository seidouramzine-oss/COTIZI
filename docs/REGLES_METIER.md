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

## Profil pro du tontinier

- **Profil → Mon profil pro** : nom de l'activité, logo, ville, numéro WhatsApp
  et jusqu'à **3 numéros Mobile Money** (opérateur, numéro, titulaire).
- Les clients voient ces informations au moment de payer (numéros à copier),
  sur les reçus et sur les relevés PDF.
- **Profil → Mes gains** : encaissé ce mois-ci, commissions gagnées et à venir,
  pénalités encaissées, montant en retard et remises des 7 prochains jours.

## Tontine à cagnotte

1. Le tontinier crée sa tontine, puis un ou plusieurs **groupes**.
2. Pour chaque groupe il fixe :
   - le **nombre de participants** (= nombre de cagnottes : chacun reçoit une fois) ;
   - la **cotisation** et sa **fréquence** : chaque jour, chaque semaine, toutes
     les 2 semaines ou chaque mois ;
   - la **durée de collecte** avant chaque remise (ex. 30 jours = 30 cotisations) ;
   - l'**ordre des remises** : **tirage au sort** ou **ordre fixé** par le tontinier ;
   - sa **commission** (pourcentage ou montant fixe), **retenue sur chaque cagnotte** ;
   - une **pénalité de retard** facultative (montant par cotisation en retard,
     après un nombre de jours de tolérance) ; elle revient au tontinier ;
   - la **date de début** et la **date de la 1re remise** prévues. La **date de
     fin** (dernière remise) est calculée et affichée.
3. Tant que la tontine n'a pas démarré, le tontinier peut **modifier** le groupe,
   **retirer** un participant ou **supprimer** le groupe.
4. Le groupe reçoit un **lien / code d'invitation** que le tontinier partage.
   Pour un participant **sans téléphone**, le tontinier l'ajoute avec son nom et
   son numéro (« Ajouter un participant sans application ») : il paie au
   tontinier, qui encaisse pour lui. S'il installe COTIZI plus tard avec **le
   même numéro** et le code d'invitation, il **récupère sa place** et tout son
   historique.
5. Quand le groupe est **complet** :
   - **tirage au sort** : le tontinier le lance ; chaque participant **tire son
     numéro** (= son rang de remise, sans pouvoir le choisir ni le changer). Le
     tontinier tire pour les retardataires et les participants sans application ;
   - **ordre fixé** : le tontinier classe les participants lui-même.
6. Le groupe est alors **prêt à démarrer**. Le tontinier vérifie les dates et
   appuie sur **« Démarrer la tontine »** : la date de début et la date de fin
   sont **figées** ; plus aucune modification n'est possible. Les paiements ne
   sont acceptés qu'après le démarrage.
7. La cagnotte n°1 est **en cours de collecte**. Tous les participants cotisent
   pour elle (barre de progression, montant validé / total, date et compte à
   rebours de la remise).
8. Le participant **paie une ou plusieurs cotisations à la fois** (il peut payer
   d'avance) et déclare son paiement :
   - **Mobile Money** : avec **une capture d'écran** ; les numéros du tontinier
     sont affichés ;
   - **Espèces** : il a remis l'argent en main propre au tontinier.
   Les **pénalités** des cotisations en retard s'ajoutent automatiquement. Le
   paiement est **en attente** jusqu'à ce que le tontinier :
   - le **valide** (« Argent reçu » pour les espèces) : un **reçu** est alors
     disponible à partager ;
   - ou le **refuse en indiquant la raison** (les cotisations sont à repayer).
9. Le tontinier peut aussi **encaisser** lui-même un paiement reçu (espèces ou
   Mobile Money) pour un participant : il est validé directement et un reçu est
   créé.
10. **« Vous êtes à jour »** : toutes les cotisations arrivées à échéance sont
    déclarées. Sinon l'accueil affiche le nombre de cotisations **en retard**, le
    montant et les pénalités. Le tontinier voit qui est en retard et peut
    **relancer sur WhatsApp**.
11. Les cotisations comptent dans l'ordre : les N premières pour la cagnotte n°1,
    les N suivantes pour la n°2, etc.
12. **Une cagnotte ne peut être remise que lorsque sa collecte est complète**
    (toutes les cotisations de tous les participants pour cette cagnotte sont
    validées). Avant, le bouton de remise est verrouillé et l'écran montre
    **ce qui manque** : qui doit encore combien, avec un bouton pour relancer
    chacun sur WhatsApp, ou tout le groupe en un message. Si un participant ne
    paie pas, le tontinier peut **encaisser pour lui** (il avance l'argent) pour
    débloquer la remise. Le serveur vérifie aussi cette règle.
13. Collecte complète : le tontinier appuie sur **« Remettre la cagnotte »**,
    vérifie le récapitulatif (collecte, sa commission, montant à remettre) et
    choisit le mode de remise (**espèces** ou **Mobile Money**). Le
    **bénéficiaire confirme l'avoir reçue** (ou signale un problème) ; le
    tontinier suit les 3 étapes (collecte complète, remise faite, réception
    confirmée) et peut partager un **reçu de remise**. La collecte suivante
    devient la cagnotte en cours. Après la dernière remise, la tontine est
    **terminée**.
14. Chaque action importante est notée dans l'**historique** du groupe (création,
    tirage, démarrage, paiements, remises…). Le tontinier voit tout ; un
    participant voit les actions générales et celles qui le concernent.
15. **Relevés PDF** : le tontinier partage le bilan d'un groupe ou le relevé d'un
    participant ; le participant peut partager son propre relevé.

## Rappels sur le téléphone

- Le **client** reçoit un rappel **la veille de chaque cotisation à payer**
  (à 18 h), et le lendemain matin s'il a des cotisations en retard.
- Le **tontinier** reçoit un rappel **le matin de chaque remise prévue**.
- Les rappels sont préparés par le téléphone (pas de serveur) et mis à jour à
  chaque ouverture de l'application. On peut les couper dans
  **Profil → Paramètres → Rappels**.

Exemple : 10 participants, 5 000 FCFA par jour, collecte de 30 jours ;
cagnotte = 10 × 30 × 5 000 = 1 500 000 FCFA ; commission 5 % = 75 000 FCFA ;
le bénéficiaire reçoit 1 425 000 FCFA, une remise tous les 30 jours.

Les groupes créés avant la version 2.0 restent consultables mais n'acceptent
plus de paiements. Pour les groupes démarrés avec la version 2.0, la remise
reste bloquée par l'application tant que la collecte n'est pas complète.

## Tontine à carnet

1. Le tontinier crée sa tontine, puis des **carnets de 31 cases**, avec le
   **montant d'une case**.
2. Chaque carnet a un **code d'invitation** ; le client l'utilise pour devenir
   le titulaire du carnet (un seul client par carnet).
3. Le client **déclare ses paiements** (une ou plusieurs cases à la fois), par
   Mobile Money avec preuve ou en espèces ; le tontinier valide ou refuse avec
   une raison, comme pour la cagnotte. Le tontinier peut aussi **encaisser** des
   cases lui-même.
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
