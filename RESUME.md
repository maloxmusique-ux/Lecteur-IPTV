# Résumé du projet Canalix (Lecteur IPTV, anciennement StreamFlow)

Ce fichier résume tout le travail fait jusqu'ici, pour reprendre le projet dans une nouvelle conversation.
Pour reprendre : ouvre une nouvelle session Claude avec le dépôt `maloxmusique-ux/Lecteur-IPTV`, puis dis « lis RESUME.md et continuons ».

## 1. L'objectif

Créer un lecteur IPTV **très fluide et haute performance**, **multiplateforme** et **100 % légal**.

Choix faits ensemble :
- Plateformes : Android, Android TV, iOS, Windows, macOS, Linux (une seule base de code).
- Sources : playlists M3U/M3U8, comptes Xtream Codes, guide TV XMLTV (EPG).
- Légal : l'app ne fournit aucune chaîne. L'utilisateur n'ajoute que des sources auxquelles il a légalement accès.
- Léandre utilise un compte **Xtream**. Il teste sur son ordinateur Windows (ASUS) ; l'iPhone viendra plus tard depuis le Mac.

## 2. Technologies

- **Flutter 3.47** (Dart 3.13)
- **media_kit** (moteur **libmpv**) pour la lecture vidéo, avec décodage matériel
- `provider` (état), `http`, `xml`, `shared_preferences`, `path_provider`
- `flutter_local_notifications` + `timezone` (rappels), `file_picker` (dossier d'enregistrement, sauvegarde), `flutter_localizations` (langues)

## 3. Ce qui est fait et fonctionne

### Base (version 1)
- Sources M3U (URL) ou Xtream Codes, options avancées (URL EPG, User-Agent).
- TV, Films, Séries, catégories, recherche instantanée, numéros de chaînes, logos.
- Grand écran : aperçu vidéo à droite, 1er clic = aperçu, 2e clic = plein écran sans recharger.
- Zapping (flèches, PageUp/PageDown, télécommande, glisser sur mobile), pistes audio/sous-titres.
- Séries Xtream : saisons, épisodes, enchaînement automatique.
- Android TV : lanceur Leanback, navigation à la télécommande.
- Parsing en arrière-plan (isolates), cache disque, listes optimisées.

### Ajouté le 1er novembre 2026 (version 2)
**Lecture HD sans bug**
- Mode de lecture réglable : Rapide / Équilibré (par défaut, petit tampon de 1,2 s pour la HD) / Stable (connexion faible ou 4K).
- Reconnexion **illimitée** du direct avec délai croissant, relance automatique si le flux reste bloqué plus de 15 s.
- Paquets corrompus ignorés (`fflags=+discardcorrupt`) : moins de blocs verts.
- Décodage matériel avec repli logiciel, option pour le désactiver.
- Choix de qualité (Meilleure, 1080p max, 720p max, Économie de données) + choix de la piste vidéo.
- Panneau **Infos du flux** (touche I) : résolution, codec, images/s, débit, décodage, images perdues, tampon, vitesse.

**Guide TV**
- Onglet **Guide** : grille chaînes × heures sur 8 jours (hier + 7 jours), ligne rouge de l'heure actuelle, jours, « Maintenant », molette ou glisser pour avancer dans le temps, filtre par catégorie ou favoris.
- **Recherche** dans tous les programmes (ex. « hockey »).
- **Fiche émission** : description, Regarder, Depuis le début, Revoir, Me le rappeler, Enregistrer, Télécharger.
- Le passé des chaînes avec rattrapage est gardé dans le guide.

**Rappels**
- Notification avant le début (délai réglable), alerte dans l'app avec « Regarder », option de passage automatique sur la chaîne après 10 s.
- Sur Android/iOS/macOS, la notification arrive même app fermée. Sur Windows/Linux, l'app doit être ouverte.

**Rattrapage, pause du direct, enregistrement**
- **Rattrapage Xtream** (`tv_archive`) : icône historique sur les chaînes concernées, écran Rattrapage par chaîne (API `get_simple_data_table`), URL `/timeshift/user/pass/durée/AAAA-MM-JJ:HH-MM/id.ts`. Fuseau du serveur calculé depuis `server_info`.
- **Pause du direct** : cache sur disque de libmpv (`cache-on-disk`), jusqu'à 120 min, barre « -mm:ss », bouton/touche L pour revenir au direct.
- **Enregistrements** : maintenant (jusqu'à la fin de l'émission, 30 min, 1-4 h) ou programmés depuis le guide (marges avant/après réglables). Copie directe du flux (TS ou HLS), presque aucun processeur, reconnexion en cas de coupure. Téléchargement des rattrapages, films et épisodes. Onglet **Enregistrements** (en cours, programmés, terminés), relecture dans l'app. Dossier par défaut : `Vidéos\Canalix` (modifiable).
- Avertissement si l'abonnement n'autorise qu'une connexion.

**Confort**
- **Reprise** des films/épisodes (« Reprendre à 34:12 ? ») et rangée **Continuer à regarder**.
- Onglet **Ma liste** : continuer à regarder, chaînes favorites, rappels, films/séries favoris, vus récemment.
- **Profils** (favoris, historique et reprise séparés), profil **enfant**.
- **Contrôle parental** : code à 4 chiffres, verrouillage automatique des catégories adultes, verrouillage manuel de catégories, réglages protégés pour les profils enfants.
- **Multi-écran** : jusqu'à 4 chaînes, le son vient de la fenêtre choisie.
- **Image dans l'image** sur Android, **minuterie de mise en veille**, saisie du numéro de chaîne à la télécommande.
- **Langues audio et sous-titres préférées**.
- **Organiser les catégories** : ordre, masquer, verrouiller.
- **Sauvegarde / restauration** de toutes les données (fichier JSON).
- **Langue de l'interface** : Automatique, Français, English, Español, Português (choix aussi sur le tout premier écran).

### Ajouté le 1er novembre 2026 (version 3)
- **Icône et bannière Android TV** StreamFlow (dossier `assets/icon/`, générées avec `dart run flutter_launcher_icons`). Logo aussi dans la barre de gauche.
- **Clé de signature Android** créée (`streamflow-release.jks`, alias `streamflow`). Léandre la garde dans `Bureau\IPTV\Cle-Android` avec le fichier `CLE-ANDROID-A-GARDER.txt` qui explique comment ajouter les 3 secrets GitHub. Elle n'est PAS dans le dépôt. Tant que les secrets ne sont pas ajoutés, l'APK reste signé avec une clé temporaire.
- **Fiches films et séries** (Xtream `get_vod_info` / `get_series_info`, sans clé) : affiche, image de fond, année, durée, genre, note sur 10, résumé, réalisation, distribution, bande-annonce YouTube, bouton « Reprendre à », téléchargement. Série : bouton qui lance le prochain épisode, résumés et durées des épisodes, épisodes vus cochés.
- **Enregistrement app fermée** :
  - Android : moteur Flutter gardé dans `CanalixApp.kt` (survit à la fermeture de l'écran), service au premier plan (`RecordingService.kt`), alarme système `RecordingAlarm.kt` qui relance l'app 1 min avant l'heure prévue (même app fermée depuis les apps récentes ou après redémarrage, `BootReceiver`). Autorisation « Alarmes et rappels » proposée dans l'onglet Enregistrements pour l'heure exacte.
  - Windows : tâche planifiée `Canalix\ProchainEnregistrement` (réveille le PC en veille) qui lance `Canalix.exe --background` 2 min avant, fenêtre réduite, une seule instance, fermeture automatique quand plus rien n'est prévu dans les 15 min et que personne n'a touché l'app.
  - Impossible : télé Samsung/LG éteinte (le système coupe les apps), iPhone app fermée (Apple l'interdit), Mac/Linux app fermée (pas encore fait). Seule vraie solution : enregistrement « dans le nuage » sur un serveur (coût et risque légal, décision de Léandre).
- **Stockage** : carte en haut de l'onglet Enregistrements, espace libre / total du disque des enregistrements, place prise, heures HD possibles (~3 Go/h), alerte rouge sous 2 Go ou 5 %.
- **Enregistreur maison** (`services/home_recorder.dart`, écran `ui/home_recorder_screen.dart`, télé `tv/js/home.js`) : comme le terminal de Bell/Vidéotron. Un appareil Canalix toujours allumé (boîte Android TV, PC Windows, Mac, vieux téléphone branché) active « Utiliser cet appareil comme enregistreur maison » : petit serveur HTTP sur le réseau local (port 8765), code à 6 chiffres (10 erreurs = blocage 10 min), API ping/list/schedule/rule/occurrences/now/stop/delete/unrule et lecture des fichiers avec reprise (Range). Les adresses de flux et mots de passe ne sortent jamais dans la liste. Android : service « usage spécial » permanent, redémarre avec l'appareil. Windows : démarre à l'ouverture de session (clé Run, `--background`), ne se ferme plus tout seul.
  - Écrans reliés (iPhone, autre Android, PC, télé Samsung/LG) : Réglages > Enregistreur maison > Chercher (balayage du réseau /24 ; sur Samsung, IP de la télé ; sinon réseaux courants) ou adresse à la main, puis code. Les enregistrements de direct partent alors sur l'enregistreur ; l'onglet Enregistrements montre ses enregistrements, son espace libre, et les lit à distance. Séries « chaque diffusion » : l'écran envoie les diffusions trouvées dans son guide.
  - Télé : bouton ROUGE ou REC sur une chaîne (émission en cours, suivante, 30 min à 4 h), Réglages > Mes enregistrements (lire, annuler, supprimer avec double OK).
  - Testé : test automatique `test/home_recorder_test.dart` (appairage, programmation, enregistrement réel, lecture partielle, refus sans code) et app télé dans un navigateur contre un vrai enregistreur. Pas encore testé sur de vrais appareils.
- **Accueil** (`ui/launcher_view.dart`) : à l'ouverture, grandes tuiles TV en direct, Guide, Films, Séries (avec le nombre), rangée « Reprendre » (dernières chaînes), puis Ma liste, Enregistrements, Multi-écran, Sources, Réglages, Recharger. Barre du bas sur téléphone : Accueil, TV, Guide, Films, Séries (l'ancien menu « Plus » est remplacé par l'accueil). Sur téléphone, TV/Films/Séries montrent d'abord la liste des catégories (avec le nombre), puis les chaînes de celle choisie ; flèche ou bouton retour = retour aux catégories, puis à l'accueil. Sur ordinateur et télé, la mise en page à 3 colonnes reste.
- **Exigences Apple ajoutées** : Réglages > « À propos et mentions légales » (`ui/about_screen.dart` : éditeur `Brand.publisher` à remplacer par le vrai nom légal, contact, hébergement, avertissement « aucun contenu », confidentialité, conditions, utilisation légale, aide, licences libres) et « Supprimer mes données » (serveur : action `delete` de la fonction `license` qui annule Stripe, supprime le client Stripe, archive les montants sans lien dans `payments_archive`, efface l'appareil en cascade ; appareil : `services/eraser.dart`, avec un repère `erase_pending` fini au lancement suivant). Écran final sans retour (pas de fermeture forcée sur iPhone). Politique de confidentialité, aide et PUBLICATION.md à jour.
- **Son iPhone corrigé** : la libmpv iOS n'a pas le filtre `volume` (seulement `equalizer` et `aresample`) : les modes de son n'utilisent plus que `equalizer`, et si un filtre est refusé, le son repart sans filtre (vérification 3 s après le début).
- **Mini-lecteur iPhone** : bouton mini-lecteur = la vidéo part directement dans la fenêtre flottante d'Apple (`MiniPlayer` dans `AppDelegate.swift`, canal `canalix/pip`), sans ouvrir l'écran du lecteur Apple. « Revenir dans l'app » reprend dans Canalix. AirPlay garde le lecteur Apple.
- **Son** (Réglages > Lecture > Son) : Automatique (par défaut), Voix claires, Mode nuit, Original ; option « Son ambiophonique vers ampli ou barre de son » (Dolby/DTS tels quels). Le 5.1 est mixé en stéréo sans perte de volume, avec les basses. Attention : les libmpv livrées (Android, Windows) n'ont que les filtres `equalizer` et `volume` (vérifié dans l'APK et la DLL), donc pas de compresseur ni de normalisation dynamique : tout est fait à l'égaliseur.
- **Chromecast** (`lib/services/cast.dart`) : protocole Cast v2 écrit à la main (aucun SDK), recherche mDNS `_googlecast._tcp` (verrou multicast sur Android) ou adresse IP manuelle, lecteur multimédia par défaut de Google. Les flux Xtream `.ts` sont envoyés en `.m3u8`. Le zapping suit sur la télé. Certains flux (http HLS) peuvent être refusés par le Chromecast : message clair dans ce cas. Pas encore testé sur un vrai Chromecast.
- **Mac et iPhone** : réglages iOS (réseau local, Bonjour, Fichiers, langues), droits macOS (réseau, dossiers). La compilation GitHub produit maintenant `Canalix-macos.zip` et vérifie que l'app iPhone compile. Guide pas à pas : `INSTALLER-IPHONE.md` (Xcode sur le Mac). La publication Windows/Android n'est jamais bloquée par un échec Apple.
- Échap = retour en arrière sur ordinateur.

### Ajouté le 1er novembre 2026 (version 4 : abonnements)
Modèle choisi par Léandre : **app gratuite à télécharger, accès payant par appareil, aucune chaîne fournie** (comme IBO Player / TiviMate).
- **Essai gratuit de 7 jours** au premier lancement, sans carte. Bandeau « Essai gratuit : encore X jours » en haut. Après l'essai, la lecture ouvre l'écran des forfaits (les menus restent accessibles).
- **Forfaits (CAD)** : Mensuel 2,99 $, 3 mois 7,99 $, 6 mois 12,99 $, Annuel 19,99 $ (mis en avant), À vie 39,99 $. Renouvellement automatique pour 1 à 12 mois.
- **Un abonnement = un appareil.** L'app génère une « adresse MAC » unique (les vraies MAC ne sont plus lisibles sur iPhone/Android) + un secret privé, gardés dans `device.json` (hors sauvegardes).
- **Annulation très visible** : sur l'écran des forfaits (« Sans engagement », « Annulable à tout moment en 1 clic »), et dans Réglages > Mon abonnement avec un gros bouton rouge, confirmation claire, date de fin d'accès, bouton « Réactiver ». Reçus listés.
- **Aide et contact** : 7 questions fréquentes + bouton « Nous écrire » (courriel prérempli avec l'adresse MAC).
- **Paiement** : Stripe Checkout ouvert dans l'app (navigateur intégré sur mobile), avec code QR pour payer depuis un téléphone (télés). Apple/Google : leur facturation obligatoire (à faire lors de la publication dans les boutiques).
- **Serveur** : `supabase/` (tables `devices`, `licenses`, `payments`, vue `dashboard` ; fonctions `license` et `stripe-webhook`). Guide complet : `PAIEMENTS.md`.
- **Mode test** tant que les variables GitHub `LICENSE_API` et `LICENSE_KEY` ne sont pas définies : paiements simulés, outils « Recommencer / Terminer l'essai » dans Mon abonnement.
- Nom, courriel de support et site : un seul fichier, `lib/config/brand.dart`.

### Version 5 (1er novembre 2026) : nom Canalix, codes cadeaux, portail
- **Nom : Canalix** (« StreamFlow » était déjà pris par d'autres apps IPTV). Nom en boutique : « Canalix IPTV Player ». Domaines libres au 1er nov. 2026 : `canalixtv.com`, `getcanalix.com` (à acheter). Identifiant d'app partout : `com.canalixtv.app`. Exécutable Windows : `canalix.exe`. Fichiers publiés : `Canalix-windows.zip`, `Canalix-android.apk`, `Canalix-macos.zip`. Le paquet Dart garde le nom interne `streamflow` (invisible). Au premier lancement, les données de l'ancienne app StreamFlow sont copiées automatiquement (`services/migrate.dart`).
- **Codes cadeaux** : 1, 3, 6, 12 mois ou à vie. Bouton « J'ai un code » sur l'écran des forfaits et dans Mon abonnement. Un accès offert ne se renouvelle jamais (rien à annuler, rien de prélevé) ; une durée s'ajoute à un accès offert déjà en cours. En mode test : `TEST-1M`, `TEST-12M`, `TEST-VIE`. Serveur : tables `promo_codes` et `redemptions`, action `redeem` de la fonction `license`.
- **Portail de Léandre** : `portail/index.html` (un seul fichier, à ouvrir dans le navigateur). Créer des codes (durée, nombre, personnes par code, note), activer une adresse MAC directement, retirer un accès offert, désactiver un code, voir les appareils et les revenus. Protégé par le secret Supabase `ADMIN_PASSWORD` (fonction `admin`). Mode démo sans serveur. Aucun compte client à gérer.
- **VPN** : écarté (coûteux, responsabilité légale, et les fournisseurs IPTV bloquent souvent les VPN). À la place :
- **Identifiants chiffrés** : les sources (URL, utilisateurs, mots de passe) sont chiffrées en AES-256-GCM (`services/vault.dart`), clé dans le trousseau du système (`flutter_secure_storage`). Les anciennes sources en clair sont chiffrées au démarrage. La sauvegarde exporte les sources en clair pour pouvoir les restaurer ailleurs.
- **Enregistrements récurrents** : en appuyant sur « Enregistrer », choix « Une seule fois », « Chaque fois qu'elle passe » (même titre sur la même chaîne, trouvé dans le guide, 8 jours à l'avance) ou « Chaque semaine » (même jour, même heure ; heures exactes reprises du guide si dispo). Section « Séries d'enregistrement » dans l'onglet Enregistrements avec « Arrêter la série ». Une diffusion annulée à la main ne revient pas. Code : `RecRule` dans `services/recorder.dart`.
- **Connexion protégée (VPN) au choix** : Réglages > Connexion protégée. L'utilisateur entre les infos de SON fournisseur VPN (SOCKS5 ou HTTP : serveur, port, utilisateur, mot de passe chiffré). Un relais local (`services/proxy.dart`) fait passer catalogue, guide, lecture (option `http-proxy` de libmpv) et enregistrements par le VPN ; si le VPN tombe, ça échoue au lieu de fuir. Bouton « Tester » (IP vue avec et sans VPN). Le réseau local (Chromecast) reste direct. Canalix ne fournit aucun VPN.
- **Recherche Chromecast renforcée** (`scanForCast`) : mDNS + SSDP/DIAL + balayage du réseau local (port 8009 en TLS), car le pare-feu Windows bloque souvent le mDNS. Si une télé sans Chromecast (Samsung, LG…) est vue, un message l'explique.
- **Lecteur** : format d'image (Ajuster, Remplir, Étirer, 16:9, 4:3, mémorisé, aussi dans Réglages) ; cadenas sur mobile qui bloque l'écran (bouton « Débloquer » au toucher).
- **Mini-lecteur** : Android, image dans l'image automatique en quittant l'app pendant une lecture (réglage « Mini-lecteur en quittant l'app ») ; iPhone, bouton mini-lecteur qui passe au lecteur Apple (PiP natif + AirPlay).
- **Téléphone** : toucher une chaîne = aperçu vidéo en haut, liste et catégories visibles ; toucher l'image = plein écran. Catégories (pays) en colonne verticale à gauche, chaînes à droite, lignes allégées sur téléphone. Guide sur 2 lignes. « Recharger l'application » dans Plus et Réglages (reconstruit l'écran, relance liste, guide et lecteur). iPhone signé avec l'équipe Apple payante de Danielle (L2SL7Z7R78) : le compte Apple de Léandre est gratuit (profils de 7 jours, pas d'App Store Connect).
- **Boutiques** (`PUBLICATION.md` = toutes les réponses aux formulaires) : versions App Store / Google Play (`--dart-define=STORE=apple|google`, iPhone = toujours Apple) avec achats intégrés (`services/store_billing.dart`, produits `canalix_monthly/quarterly/semiannual/yearly/lifetime`, essai = offre de lancement 7 jours), bouton Restaurer, annulation via le compte de la boutique, sans Stripe ni codes maison. Manifeste de confidentialité iOS/macOS, `ITSAppUsesNonExemptEncryption = NO`. Pages publiques dans `docs/` (GitHub Pages à activer) : accueil, aide, conditions (CLUF), confidentialité, `demo.m3u`. Bouton « Essayer avec la démonstration » dans Sources pour les examinateurs. CI : `Canalix-googleplay.aab` quand la clé Android est dans les secrets. Android déjà conforme (API 36, 16 Ko).
- **Positionnement** : « Canalix Player », présenté comme lecteur vidéo (fiches, pages, textes), sans cacher ce qu'il fait.
- **Guide sur téléphone** : liste des chaînes (émission en cours + suivante) ; toucher = horaire complet de la chaîne jour par jour.
- **Limite d'écrans du fournisseur** : si la lecture échoue, Canalix interroge le compte Xtream (active_cons / max_connections) et explique que le compte est utilisé ailleurs. Pas de contournement.
- **Windows** : installateur `Canalix-setup.exe` (Inno Setup, `windows/installer/canalix.iss`) produit par la CI.
- **Télés Samsung et LG** : app web dans `tv/` (HTML/JS, AVPlay sur Samsung, vidéo native sur LG, hls.js en navigateur), catégories à gauche, chaînes, aperçu puis plein écran au 2e OK, guide maintenant/ensuite, films, réglages, forfaits avec QR code, codes cadeaux, licence par adresse MAC (vraie MAC sur Samsung). CI : `Canalix-lg.ipk` et `Canalix-samsung.zip` (à signer avec le certificat Samsung). Voir `tv/README.md`.
- **iPhone** : identifiant `com.canalixtv.player` (l'ancien `com.canalixtv.app` est réservé par le compte gratuit de Léandre), équipe de Danielle L2SL7Z7R78.
- **Politique de confidentialité** : `CONFIDENTIALITE.md` (Loi 25 / LPRPDE), résumé dans l'aide de l'app (2 nouvelles questions : code cadeau, données).

### Cadre légal
- Écran d'acceptation obligatoire au premier lancement, case de certification à chaque ajout de source, page « Mentions légales ». Aucune playlist intégrée.

### Vérifications faites (1er novembre 2026)
- `flutter analyze` : aucun problème. 13 tests unitaires (parseurs, traductions des 4 langues, URL de rattrapage, fuseau, guide, reprise, parental) : tous passent.
- Version Linux compilée et testée en vrai contre un faux serveur Xtream (flux 1080p générés par ffmpeg) : aperçu, plein écran, infos du flux, pause du direct (-00:11 puis -00:21, retour au direct), guide, fiche émission, rappel, enregistrement programmé, rattrapage, enregistrement immédiat (fichier 1080p valide), relecture, reprise d'un film, Ma liste, changement de langue, contrôle parental, multi-écran.
- Bug trouvé et corrigé : les jours du guide étaient faux le jour du changement d'heure.

## 4. Organisation du code

```
lib/
  main.dart                    Démarrage, thème, langue, écran légal / profils / accueil, alertes de rappel
  l10n/i18n.dart               Fonction tr(), formats de date et durée
  l10n/strings.dart            Tous les textes en FR / EN / ES / PT
  models/models.dart           Channel (avec rattrapage), Source, Catalog, Programme, EpgData
  models/profile.dart          Profile, WatchProgress (reprise)
  services/net.dart            Téléchargement (gzip géré)
  services/m3u_parser.dart     Parseur M3U
  services/xtream_api.dart     Client Xtream (compte, rattrapage, URL timeshift)
  services/epg_parser.dart     Parseur XMLTV en flux
  services/repository.dart     Isolates + cache disque
  services/notifier.dart       Notifications système
  services/reminders.dart      Rappels
  services/recorder.dart       Enregistrements et téléchargements (TS et HLS)
  services/backup.dart         Sauvegarde / restauration
  player/player_engine.dart    Moteur libmpv (tampon, reconnexion, pause du direct, infos, veille)
  state/settings.dart          Réglages
  state/app_state.dart         Sources, catalogue, EPG, profils, favoris, reprise, parental, catégories
  ui/home_screen.dart          Accueil, onglets, listes, aperçu, Ma liste, menus
  ui/guide_screen.dart         Grille du guide TV et recherche
  ui/programme_sheet.dart      Fiche émission, enregistrement immédiat
  ui/catchup_screen.dart       Rattrapage d'une chaîne
  ui/recordings_screen.dart    Enregistrements
  ui/player_screen.dart        Lecteur plein écran
  ui/multiview_screen.dart     Multi-écran
  ui/settings_screen.dart      Réglages et organisation des catégories
  ui/profiles_screen.dart      Profils
  ui/series_screen.dart        Saisons et épisodes
  ui/sources_screen.dart       Gestion des sources (expiration et connexions Xtream)
  ui/legal_screen.dart         Écran d'acceptation et mentions légales
  ui/navigation.dart           Ouverture des contenus, reprise
  ui/reminder_alert.dart       Alerte de rappel
  services/store_billing.dart  Achats App Store / Google Play
  services/pip.dart            Mini-lecteur automatique Android
  docs/                        Pages publiques (aide, conditions, confidentialité, démo)
  services/proxy.dart          Relais vers le VPN de l'utilisateur (SOCKS5 / HTTP)
  ui/vpn_screen.dart           Réglage « Connexion protégée (VPN) »
  services/vault.dart          Chiffrement des identifiants (AES-256-GCM, clé dans le trousseau)
  services/migrate.dart        Reprise des données de l'ancienne app StreamFlow
  config/brand.dart            Nom, contacts, serveur de licences, forfaits et prix
  services/license.dart        Licence par appareil (MAC, essai, abonnement, mode test)
  ui/subscription_screen.dart  Forfaits, paiement, Mon abonnement, bandeau d'essai, Aide
  ui/details_screen.dart       Fiche film (et en-tête commun des fiches)
  ui/cast_ui.dart              Choix du Chromecast et bandeau de diffusion
  services/cast.dart           Protocole Chromecast
  ui/widgets/                  Tuile de chaîne, affiche, logo, code parental
supabase/                    Serveur de licences (tables, fonctions license, stripe-webhook, admin)
portail/index.html           Portail administrateur de Léandre
test/parsers_test.dart         Tests des parseurs
test/features_test.dart        Tests des nouvelles fonctions et des traductions
```

Ajouter une langue : ajouter une colonne dans `l10n/strings.dart` et la langue dans `kLanguages` / `_order` de `l10n/i18n.dart`. Le test vérifie qu'aucun texte ne manque.

## 5. GitHub

- Dépôt : https://github.com/maloxmusique-ux/Lecteur-IPTV (branche `main`)
- Compilation automatique (`.github/workflows/build.yml`) : APK Android et version Windows à chaque envoi sur `main`, publiés dans la release « Dernière version ».
  - Windows : https://github.com/maloxmusique-ux/Lecteur-IPTV/releases/download/derniere-version/Canalix-windows.zip
  - Android : https://github.com/maloxmusique-ux/Lecteur-IPTV/releases/download/derniere-version/Canalix-android.apk
  - Mac : https://github.com/maloxmusique-ux/Lecteur-IPTV/releases/download/derniere-version/Canalix-macos.zip
- Signature Android : sans secrets, l'APK est signé avec une clé temporaire (désinstaller avant chaque mise à jour). Pour une clé fixe, ajouter dans GitHub (Settings, Secrets and variables, Actions) : `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`.

## 6. Reste à faire (prochaines étapes proposées)

1. Léandre achète `canalixtv.com`, crée les comptes Stripe et Supabase et choisit son `ADMIN_PASSWORD` (`PAIEMENTS.md`). Publier `CONFIDENTIALITE.md` sur le site.
1. Léandre ajoute les 3 secrets GitHub de la clé Android (voir `CLE-ANDROID-A-GARDER.txt`).
1. Version télé Samsung/LG (web, Tizen + webOS) puis Roku. Version Google Play et App Store avec leurs achats intégrés.
2. Tester sur un vrai téléphone Android, une box Android TV et un vrai Chromecast.
3. Installer sur l'iPhone depuis le Mac (`INSTALLER-IPHONE.md`), puis éventuellement TestFlight.
4. Idées : AirPlay sur iPhone, synchronisation entre appareils, publication sur Google Play.

## 7. Pour compiler toi-même

```bash
flutter pub get
flutter run
flutter build apk --release
flutter build windows --release
```

Linux : installer `libmpv-dev libgtk-3-dev clang cmake ninja-build pkg-config`.

Astuce : si une icône s'affiche comme un carré avec des lettres après une modification, faire `flutter clean` puis recompiler.
