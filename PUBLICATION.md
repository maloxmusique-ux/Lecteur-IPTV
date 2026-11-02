# Publier Canalix dans les boutiques

Ce guide donne toutes les réponses à copier-coller dans App Store Connect, la Google Play Console
et le Microsoft Partner Center. L'app a été préparée pour respecter les règles en vigueur
(vérifiées le 1er novembre 2026).

## Ce qui est déjà prêt dans l'app

| Exigence | Où |
|---|---|
| Paiement Apple obligatoire (règle 3.1.1) | Version iPhone et Mac App Store : achats intégrés Apple, sans Stripe ni codes maison |
| Paiement Google obligatoire | Version Google Play (`STORE=google`) : facturation Google Play |
| Écran d'abonnement conforme (3.1.2) | Prix, durée, essai, renouvellement auto, annulation, liens Conditions et Confidentialité, bouton « Restaurer mes achats » |
| Annulation visible | Mon abonnement > gros bouton rouge « Gérer ou annuler mon abonnement » |
| Politique de confidentialité | `docs/confidentialite.html` (page publique) |
| Conditions d'utilisation (CLUF) | `docs/conditions.html` |
| Page d'aide | `docs/aide.html` |
| Démo légale pour les examinateurs | Onglet Sources > « Essayer avec la démonstration » (vidéos libres de droits) |
| Avertissement « aucun contenu fourni » | Écran d'acceptation au premier lancement + fiche boutique |
| Manifeste de confidentialité Apple | `ios/Runner/PrivacyInfo.xcprivacy` et `macos/Runner/PrivacyInfo.xcprivacy` |
| Chiffrement à l'export | `ITSAppUsesNonExemptEncryption = NO` (HTTPS et AES standard seulement) |
| Android API 36, pages de 16 Ko | Vérifié sur l'APK |
| Alarmes non exactes (pas de permission restreinte) | Rappels en mode « inexact » |
| Pas de compte utilisateur | Donc pas d'obligation de suppression de compte |

**Avant de soumettre :** activer les pages publiques (GitHub > dépôt > Settings > Pages >
Branch `main`, dossier `/docs`). Adresse : https://maloxmusique-ux.github.io/Lecteur-IPTV/
(on pourra passer à canalixtv.com plus tard ; changer alors `Brand.pages`).

---

## 1. App Store (iPhone, iPad et Mac)

### Créer l'app
App Store Connect > Apps > + > Nouvelle app
- Plateformes : iOS (et macOS si on publie aussi sur Mac)
- Nom : **Canalix IPTV Player**
- Langue principale : Français (Canada)
- Identifiant de paquet : **com.canalixtv.app**
- SKU : `canalix-001`

### Abonnements (Fonctionnalités > Abonnements)
Groupe d'abonnements : **Canalix Premium**. Créer 4 abonnements avec exactement ces identifiants :

| Identifiant produit | Durée | Prix (CAD) |
|---|---|---|
| `canalix_monthly` | 1 mois | 2,99 $ |
| `canalix_quarterly` | 3 mois | 7,99 $ |
| `canalix_semiannual` | 6 mois | 12,99 $ |
| `canalix_yearly` | 1 an | 19,99 $ |

Pour chacun : **Offre de lancement > Essai gratuit > 1 semaine**, tous les pays.
Nom affiché (fr) : « Canalix mensuel », « Canalix 3 mois », etc.
Ajouter une capture de l'écran des forfaits (exigée pour la révision des achats).

Achat intégré **non consommable** : `canalix_lifetime`, 39,99 $, nom « Canalix à vie ».

Programme pour petites entreprises : s'y inscrire (commission 15 % au lieu de 30 %).

### Fiche de l'app
- Sous-titre : **Lecteur pour ta liste IPTV**
- Mots-clés : `iptv,m3u,xtream,lecteur,player,epg,guide tv,live,enregistrement,catch up`
- URL d'assistance : https://maloxmusique-ux.github.io/Lecteur-IPTV/aide.html
- URL de confidentialité : https://maloxmusique-ux.github.io/Lecteur-IPTV/confidentialite.html
- CLUF : coller l'URL des Conditions dans « Contrat de licence » :
  https://maloxmusique-ux.github.io/Lecteur-IPTV/conditions.html
- Catégorie : Photo et vidéo (secondaire : Divertissement)

**Description (fr) :**
> Canalix est un lecteur rapide et simple pour ta propre liste IPTV (M3U ou Xtream Codes).
> Regarde le direct en HD, consulte le guide des programmes, mets le direct en pause,
> reviens en arrière avec le rattrapage, programme des enregistrements et retrouve tes films
> et séries avec la reprise de lecture.
>
> • Guide TV avec rappels
> • Pause du direct et rattrapage
> • Enregistrements, même chaque semaine
> • Films et séries avec fiches et reprise
> • Profils, favoris et contrôle parental
> • AirPlay et image dans l'image
> • Français, anglais, espagnol et portugais
>
> IMPORTANT : Canalix ne fournit aucune chaîne ni aucun contenu. Tu dois ajouter une liste
> fournie par ton propre fournisseur et n'utiliser que des contenus que tu as le droit de regarder.
>
> Abonnement : 7 jours gratuits pour les nouveaux abonnés, puis mensuel, 3 mois, 6 mois ou
> annuel, renouvelé automatiquement sauf annulation au moins 24 h avant la fin de la période.
> Gère ou annule ton abonnement dans les réglages de ton compte Apple. Achat unique « à vie » aussi offert.
> Conditions : https://maloxmusique-ux.github.io/Lecteur-IPTV/conditions.html
> Confidentialité : https://maloxmusique-ux.github.io/Lecteur-IPTV/confidentialite.html

**Captures d'écran — très important :** utiliser SEULEMENT la liste de démonstration
(vidéos Blender et Apple). Jamais de logo de chaîne connue (TVA, RDS, HBO, sports…),
jamais de « 10 000 chaînes » ou « chaînes gratuites ». C'est la première cause de refus des lecteurs IPTV.

### Notes pour l'examinateur (App Review Information > Notes)
> Canalix is a media player for playlists the user already owns (M3U / Xtream Codes).
> The app does not provide, sell or link to any content.
> To test without a playlist: open the Sources tab and tap "Essayer avec la démonstration"
> (Try the demo). It adds a playlist of royalty-free test streams (Apple BipBop, Blender
> open movies) hosted at https://maloxmusique-ux.github.io/Lecteur-IPTV/demo.m3u
> Subscriptions use In-App Purchase only (7-day free trial as an introductory offer).
> No account is required. Restore Purchases is on the plans screen and in Settings > My subscription.

Connexion requise : **Non**.

### Confidentialité de l'app (App Privacy)
- Collecte de données : **Oui**
  - Identifiants > ID de l'appareil : fonctionnalité de l'app, **non lié** à l'identité, **pas de pistage**
  - Achats > Historique d'achats : fonctionnalité de l'app, non lié, pas de pistage
- Tout le reste : non collecté. Pistage : **Non**.

### Classification par âge
Répondre honnêtement : l'app permet d'accéder à des flux vidéo non filtrés choisis par
l'utilisateur (« Accès Web/contenu non restreint » : Oui). Résultat attendu : **18+**.
Contrôle parental intégré : Oui (code PIN).

### Chiffrement
Déjà réglé dans l'app (`ITSAppUsesNonExemptEncryption = NO`) : aucune question à l'envoi.

### Envoyer une version
Sur le Mac : `cd ~/Developer/Canalix && ./tool/apple.sh` puis dans Xcode : Product > Archive >
Distribute App > App Store Connect. (Claude peut le faire depuis ton Mac.)
Tester d'abord avec **TestFlight** (achats en mode bac à sable, gratuits).

---

## 2. Google Play

### Créer l'app
Play Console > Créer une app
- Nom : **Canalix IPTV Player** · Langue : Français (Canada) · App · Payante ? **Gratuite** (abonnement dans l'app)
- Déclarations : respecter les règles, lois d'exportation.

### Fichier à envoyer
Le fichier **Canalix-googleplay.aab** est produit automatiquement par GitHub dès que les
3 secrets de la clé Android sont ajoutés (voir `CLE-ANDROID-A-GARDER.txt`).
Activer la **signature d'app par Google Play** (recommandé) au premier envoi.

### Produits (Monétiser > Produits)
Abonnements : créer 4 abonnements avec ces ID, chacun avec un forfait de base renouvelable :

| ID produit | Forfait de base | Prix |
|---|---|---|
| `canalix_monthly` | mensuel | 2,99 $ |
| `canalix_quarterly` | tous les 3 mois | 7,99 $ |
| `canalix_semiannual` | tous les 6 mois | 12,99 $ |
| `canalix_yearly` | annuel | 19,99 $ |

Sur chaque forfait de base : **Offre > Essai gratuit 7 jours**, admissibilité « nouveaux clients ».
Produit intégré (unique) : `canalix_lifetime`, 39,99 $.

### Contenu de l'app (Règles > Contenu de l'app)
- **Politique de confidentialité** : https://maloxmusique-ux.github.io/Lecteur-IPTV/confidentialite.html
- **Accès à l'app** : « Toutes les fonctionnalités sont accessibles sans restriction » + instructions :
  « Onglet Sources > Essayer avec la démonstration (vidéos libres de droits). »
- **Annonces** : Non.
- **Classification du contenu** : catégorie « Toutes les autres apps » ; contenu généré/partagé
  par l'utilisateur ou accès Internet non filtré : Oui. Résultat attendu : 17+ / Mature.
- **Public cible** : 18 ans et plus.
- **Sécurité des données (Data safety)** :
  - Collecte : Oui. Identifiants d'appareil ou autres ID (ID généré par l'app) : collecté,
    non partagé, traitement éphémère : non, obligatoire, finalité : fonctionnalité de l'app.
  - Achats intégrés (historique d'achats) : collecté, non partagé, fonctionnalité.
  - Données chiffrées en transit : **Oui**. Possibilité de demander la suppression : **Oui**
    (lien : page d'aide, section « Supprimer mes données »).
- **Services au premier plan** : type **dataSync** utilisé pour les enregistrements programmés
  (copie du flux dans un fichier pendant que l'app est en arrière-plan). Fournir une courte vidéo
  (écran Enregistrements > un enregistrement en cours avec la notification).
- **App d'actualités / gouvernement / finances / santé** : Non.

### Fiche du Play Store
- Description courte : **Lecteur rapide pour ta liste IPTV (M3U, Xtream) avec guide TV.**
- Description complète : même texte que pour Apple (remplacer « compte Apple » par « compte Google Play »).
- Catégorie : Lecteurs et éditeurs vidéo.
- Captures : mêmes règles qu'Apple (démo seulement). Ajouter aussi des captures **Android TV**
  (1920×1080) et la bannière TV (déjà dans l'app) pour la diffusion sur les télés Android.

---

## 3. Microsoft Store (Windows)

Microsoft permet d'utiliser son propre paiement (Stripe) pour les apps qui ne sont pas des jeux.
- Partner Center > Apps et jeux > Nouvelle app > nom « Canalix IPTV Player ».
- Envoyer `Canalix-windows.zip` empaqueté en MSIX ou un installateur signé (Claude peut le préparer).
- Déclarer « Paiement tiers : Stripe » dans la section des achats.
- Politique de confidentialité : même URL.

## 4. Les autres

| Plateforme | État | Remarque |
|---|---|---|
| Mac hors boutique | Prêt | Version Stripe, à distribuer en .dmg signé et notarisé |
| Samsung (Tizen) | À faire | App web séparée ; paiement Samsung Checkout ; Samsung accepte peu de lecteurs IPTV (demande préalable au Seller Office) |
| LG (webOS) | À faire | App web séparée ; paiement LG ou tiers |
| Amazon Fire TV | À faire | Paiement Amazon obligatoire ; nouveaux appareils sous Vega OS (pas de Flutter) |
| Roku | À évaluer | Réécriture complète (BrightScript) et Roku Pay obligatoire |

## 5. Points d'attention

- **Codes cadeaux et activation par adresse MAC** : seulement dans les versions hors boutique
  (Windows, Mac direct, APK). Dans l'App Store et Google Play, utiliser les **codes promo des boutiques**
  (Apple : « Offer Codes » ; Google : « Codes promo »). Un appareil activé depuis ton portail
  reste quand même débloqué dans ces versions.
- **Abonnement par appareil** : Apple exige qu'un abonnement suive le compte sur tous ses appareils.
  C'est le cas dans les versions boutiques. La règle « 1 abonnement = 1 appareil » reste pour les versions directes.
- **Vérification serveur des achats** (recommandé plus tard) : valider les reçus Apple et Google
  sur le serveur (App Store Server API, Google Play Developer API) pour bloquer la fraude.
