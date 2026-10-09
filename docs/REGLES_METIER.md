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

## Les plans COTIZI (Gratuit, Pro, Business)

- **Plan Gratuit** : sans limite de temps, mais avec des **limites** : un nombre
  maximum de groupes en cours, de carnets en cours et de clients (par défaut
  2 groupes, 3 carnets, 30 clients). Les groupes clôturés et les carnets fermés
  ne comptent plus.
- **Plan Pro** : tout illimité. Un nouveau tontinier a **30 jours d'essai Pro
  gratuit** à partir de son inscription, puis il passe au plan Gratuit s'il ne
  prend pas Pro.
- **Plan Business** (bientôt) : pour les entreprises de tontine (plusieurs
  tontiniers, salaires, recrutement réservé aux tontiniers Pro).
- **Les prix et les limites sont réglés par l'administrateur** dans
  Profil → Administration → « Plans, paiement et assistance » : prix du plan
  Pro par mois, prix du plan Business par mois, limites du plan Gratuit
  (groupes, carnets, clients), numéro Mobile Money, WhatsApp, e-mail et horaires
  de l'assistance.
- Quand une limite est atteinte, la création est refusée avec le message
  « Limite du plan Gratuit » et un bouton **« Passer à Pro »**.
- **Rien n'est jamais mis en pause** : quand le plan Pro se termine, le
  tontinier revient au plan Gratuit. Ses groupes et carnets en cours continuent,
  ses clients déclarent et il valide normalement ; seules les nouvelles
  créations au-delà des limites sont refusées.
- Dans **Profil → Mon plan**, le tontinier voit les 3 plans, choisit la durée
  (1, 3 ou 12 mois) et appuie sur **« Demander le plan Pro sur WhatsApp »** :
  sa demande est enregistrée et WhatsApp s'ouvre vers COTIZI. Il paie par
  Mobile Money ; dès réception, l'administrateur **active** le plan Pro.
- L'**administrateur** voit les demandes (bouton « Paiement reçu : activer »)
  et tous les tontiniers ; il prolonge le plan Pro de 1, 3 ou 12 mois ou
  l'arrête. Il n'a pas besoin de plan.
- **Les clients n'ont jamais de plan à prendre** : COTIZI est gratuit pour eux.

## Avantages du plan Pro (version 3.1)

Réservés au plan Pro (essai Pro compris). En plan Gratuit, ils sont marqués
« PRO » et proposent « Passer à Pro ».

- **Comptabilité** (Profil → Comptabilité, ou raccourci de l'accueil) : pour
  chaque mois, l'argent reçu des clients (dont pénalités), les cagnottes
  remises, les carnets remis ou remboursés, les **dépenses** notées par le
  tontinier (transport, crédit, matériel, personnel, autre), le solde du mois,
  les commissions gagnées et le **bénéfice** (commissions + pénalités −
  dépenses). Liste des opérations et relevé PDF à partager. Seul le tontinier
  voit ses dépenses ; il peut les supprimer, pas les modifier.
- **Statistiques** : argent reçu sur 6 mois (barres) et évolution par rapport
  au mois précédent, total reçu et commissions depuis le début, clients en
  cours et part de clients à jour, les plus réguliers et ceux à surveiller.
- **Badge vérifié** : le tontinier envoie une photo de sa pièce d'identité et
  un selfie avec la pièce. L'administrateur (Administration → Demandes de
  badge) donne le badge ou refuse avec une raison ; **les photos sont effacées
  dès la décision**. Le badge « Vérifié » s'affiche à côté du nom du tontinier
  (profil, note de confiance vue par les clients) **tant que son plan Pro est
  actif**. Seul l'administrateur peut donner ou retirer un badge.

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
   - **quand la cagnotte est remise** :
     - **à chaque cotisation (tontine tournante)**, le choix par défaut : chaque
       jour (ou semaine, ou mois) tout le monde cotise et un participant reçoit
       la cagnotte. Avec 15 participants qui cotisent chaque jour, la tontine
       dure 15 jours et, à la fin, chacun a reçu sa cagnotte une fois ;
     - **après plusieurs cotisations** : on fixe la **durée de collecte** avant
       chaque remise (ex. 30 jours = 30 cotisations) ;
   - l'**ordre des remises** : **tirage au sort** ou **ordre fixé** par le tontinier ;
   - sa **commission** (pourcentage ou montant fixe), **retenue sur chaque cagnotte** ;
   - une **pénalité de retard** facultative : un **montant fixe** ou un
     **pourcentage du montant dû** par cotisation en retard, appliquée après le
     nombre de jours de retard choisi (ex. 10 % après 2 jours) ; elle revient
     au tontinier ;
   - ses **règles** (texte libre, facultatif) ;
   - la **date de début** et la **date de la 1re remise** prévues. La **date de
     fin** (dernière remise) est calculée et affichée.
3. Ces conditions et ces règles forment le **règlement du groupe**. Chaque
   participant avec l'application doit **l'accepter** (bouton « Lire et
   accepter le règlement ») ; le tontinier se porte garant des participants sans
   application. **La tontine ne peut pas démarrer** tant que tous n'ont pas
   accepté. Tant que la tontine n'a pas démarré, le tontinier peut **modifier**
   le groupe (si les conditions ou les règles changent, chacun doit accepter de
   nouveau), **retirer** un participant ou **supprimer** le groupe.
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
9. **C'est toujours le participant qui déclare son paiement** ; le tontinier
   valide ou refuse. Seule exception : un participant **sans application**
   (ajouté par le tontinier) ne peut pas déclarer, le tontinier **encaisse pour
   lui** (validé directement, avec un reçu).
10. **« Vous êtes à jour »** : toutes les cotisations arrivées à échéance
    (celle du jour comprise) sont déclarées. Un participant n'est **en retard**
    que pour les cotisations déjà dues et non déclarées : les cotisations à
    venir de la cagnotte ne comptent pas comme un retard. Sinon l'accueil affiche le nombre de cotisations **en retard**, le
    montant et les pénalités. Le tontinier voit qui est en retard et peut
    **relancer sur WhatsApp**.
11. Les cotisations comptent dans l'ordre : les N premières pour la cagnotte n°1,
    les N suivantes pour la n°2, etc.
12. **Une cagnotte ne peut être remise que lorsque sa collecte est complète**
    (toutes les cotisations de tous les participants pour cette cagnotte sont
    validées). Avant, le bouton de remise est verrouillé ; l'écran montre les
    **participants en retard** pour cette cagnotte, avec un bouton pour relancer
    chacun sur WhatsApp, ou tout le groupe en un message. Si un participant ne
    paie pas, il faut qu'il déclare son paiement (ou, pour un participant sans
    application, que le tontinier encaisse pour lui) pour débloquer la remise. Le serveur vérifie aussi cette règle.
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

## Aide et assistance

- **Aide et assistance** (bouton « ? » de l'accueil, ou Profil) : carte
  « AIDE ET SUPPORT — Besoin d'assistance ? Nous sommes à un clic ! » avec un
  bouton **WhatsApp** (assistance COTIZI) et un bouton **E-mail** (ou
  « Appeler » si aucun e-mail n'est réglé), et les **horaires** dans un bandeau
  jaune. Le numéro, l'e-mail et les horaires se règlent dans Administration →
  « Prix, Mobile Money et assistance ». En dessous : les explications pas à pas.
- Un client peut aussi **écrire à son tontinier** depuis la page de son groupe.

## Confiance et anti-fraude

- **COTIZI ne touche jamais l'argent** : les clients paient le tontinier
  (Mobile Money ou espèces) et déclarent le paiement ; le tontinier valide.
- **Capture d'écran obligatoire et unique** : pour un paiement Mobile Money,
  le client ajoute la capture de l'envoi (obligatoire). COTIZI calcule son
  empreinte : **une même capture ne peut servir qu'à un seul paiement** dans
  tout COTIZI (vérifié par le serveur). Si le tontinier **refuse** le paiement,
  la capture redevient utilisable.
- **Référence Mobile Money (tontinier)** : quand le tontinier encaisse pour un
  participant sans application un paiement Mobile Money, il peut saisir la
  référence du SMS (facultatif) ; une référence ne peut servir qu'une fois.
- **Rien ne s'efface** : un paiement validé et une remise ne peuvent plus être
  modifiés ni supprimés, par personne.
- **Reçus numérotés** : chaque paiement validé a un numéro de reçu unique
  (CZ-XXXX-XXXX) ; chaque remise aussi (CZ-XXXX-XXXX-n). Le reçu indique la
  référence Mobile Money (si elle a été saisie) et si le bénéficiaire a confirmé la réception.
- **Note de confiance du tontinier**, visible par tous avant de rejoindre
  (écran « Rejoindre » après la vérification du code) et sur la page du
  groupe : cagnottes remises, pourcentage confirmé par les bénéficiaires,
  problèmes signalés. Les chiffres sont tenus par le serveur : chaque compteur
  n'avance qu'avec la remise, la confirmation ou le signalement correspondant ;
  le tontinier ne peut pas les modifier.
- **Remise non confirmée** : tant que le bénéficiaire n'a pas confirmé, la
  remise reste « en attente » ; après 2 jours, l'accueil du tontinier l'affiche
  dans « À faire aujourd'hui ». Un problème signalé y apparaît en rouge.
- **Guide « Démarrer avec COTIZI »** (accueil du tontinier) : profil pro et
  numéros Mobile Money, première tontine, invitation des clients, premier
  paiement validé.

## Clôture d'un groupe (cagnotte)

Quand **toutes les cagnottes ont été remises**, le tontinier clôture le groupe
(« Clôturer le groupe », rappelé dans « À faire aujourd'hui »). Le groupe
devient « Groupe clôturé » et plus rien ne peut y être modifié ; les
participants sont prévenus.

## Accueil du tontinier : masquer les chiffres

Le bouton en forme d'œil, sur la carte « Encaissé ce mois-ci », masque les
montants de l'accueil (••••• FCFA), par exemple devant des clients. Le choix
est mémorisé sur le téléphone.

## Suggestions

« Suggestions (aidez-nous à améliorer COTIZI) » : sur l'accueil du tontinier
et dans Profil. Chacun choisit Idée, Problème ou Autre, écrit sa suggestion
(5 à 1 000 caractères) et la retrouve dans « Mes suggestions » avec son état
(Envoyée, Lue par COTIZI, Prise en compte). L'administrateur les lit toutes
dans Administration → « Suggestions reçues », les marque comme lues ou prises
en compte, répond sur WhatsApp ou les supprime. Personne d'autre ne les voit.

## Navigation

Comme dans WhatsApp, on change d'onglet (Accueil, Mes tontines, Je participe,
Profil) en **glissant le doigt** vers la gauche ou la droite, ou en touchant la
barre du bas. Chaque onglet garde sa position et se met à jour quand on y
revient.

## Notifications (la cloche)

- La **cloche** en haut de l'accueil montre le nombre de nouvelles
  notifications. En l'ouvrant, on voit la liste (Aujourd'hui / Plus tôt) et
  elles passent en « lues ». Toucher une notification ouvre le groupe ou le
  carnet concerné.
- Le **tontinier** est prévenu quand un client : rejoint un groupe ou un carnet,
  accepte le règlement, déclare un paiement, confirme ou conteste la réception
  d'une cagnotte.
- Le **client** est prévenu quand son tontinier : démarre la tontine, valide ou
  refuse son paiement, enregistre un paiement pour lui, lui remet sa cagnotte.
- Une notification ne peut être envoyée qu'entre un tontinier et ses propres
  clients (vérifié par les règles du serveur) ; chacun ne lit que les siennes.

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
   une raison, comme pour la cagnotte. Le tontinier n'encaisse pas lui-même :
   c'est toujours le client qui déclare.
4. Le client paie **31 cases** et **récupère 30 cases** ; la **dernière case est la
   commission** du tontinier.

Exemple : case à 500 FCFA → le client paie 15 500 FCFA et reçoit 15 000 FCFA ;
commission 500 FCFA.

- **Remboursement avant la fin** : le client peut arrêter son carnet à tout
  moment (« Demander le remboursement », sans paiement en attente). Il reçoit
  ses **cases payées moins une** : la dernière case payée revient au tontinier
  (ex. 20 cases payées → 19 cases rendues). Plus aucun paiement n'est possible
  ensuite.
- **Clôture** : quand il a remis l'argent (remboursement, ou carnet complet de
  31 cases → 30 cases rendues), le tontinier appuie sur « Cotisations
  remboursées · clôturer » (ou « Carnet remis · clôturer »). Le montant rendu
  est vérifié par le serveur ; le client est prévenu.

## Confidentialité des données

- Un membre ne voit que les groupes qu'il a rejoints, les membres de ces groupes
  et son tontinier ; il ne voit que ses propres paiements.
- Le tontinier voit ses tontines, ses membres / clients et tous les paiements
  et preuves de ses groupes et carnets.
- Les captures d'écran sont compressées et stockées de façon privée ; elles ne
  sont visibles que par leur auteur et le tontinier concerné.
- Ces règles sont appliquées par le serveur (règles de sécurité Firebase),
  pas seulement par l'application.
