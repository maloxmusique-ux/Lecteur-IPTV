# Résumé du projet StreamFlow (Lecteur IPTV)

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
- **Enregistrements** : maintenant (jusqu'à la fin de l'émission, 30 min, 1-4 h) ou programmés depuis le guide (marges avant/après réglables). Copie directe du flux (TS ou HLS), presque aucun processeur, reconnexion en cas de coupure. Téléchargement des rattrapages, films et épisodes. Onglet **Enregistrements** (en cours, programmés, terminés), relecture dans l'app. Dossier par défaut : `Vidéos\StreamFlow` (modifiable). L'app doit rester ouverte pendant un enregistrement.
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
  ui/widgets/                  Tuile de chaîne, affiche, logo, code parental
test/parsers_test.dart         Tests des parseurs
test/features_test.dart        Tests des nouvelles fonctions et des traductions
```

Ajouter une langue : ajouter une colonne dans `l10n/strings.dart` et la langue dans `kLanguages` / `_order` de `l10n/i18n.dart`. Le test vérifie qu'aucun texte ne manque.

## 5. GitHub

- Dépôt : https://github.com/maloxmusique-ux/Lecteur-IPTV (branche `main`)
- Compilation automatique (`.github/workflows/build.yml`) : APK Android et version Windows à chaque envoi sur `main`, publiés dans la release « Dernière version ».
  - Windows : https://github.com/maloxmusique-ux/Lecteur-IPTV/releases/download/derniere-version/StreamFlow-windows.zip
  - Android : https://github.com/maloxmusique-ux/Lecteur-IPTV/releases/download/derniere-version/StreamFlow-android.apk
- Signature Android : sans secrets, l'APK est signé avec une clé temporaire (désinstaller avant chaque mise à jour). Pour une clé fixe, ajouter dans GitHub (Settings, Secrets and variables, Actions) : `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`.

## 6. Reste à faire (prochaines étapes proposées)

1. Léandre teste la version 2 sur Windows avec son compte Xtream (rattrapage, enregistrement, pause du direct) et signale les problèmes.
2. Tester sur un vrai téléphone Android et une box Android TV.
3. Enregistrement en arrière-plan sur Android (service au premier plan) pour enregistrer app fermée.
4. Une vraie icône et un nom d'app définitifs.
5. Idées : affiches et résumés des films (TMDB), synchronisation entre appareils, Chromecast/AirPlay, version iPhone depuis le Mac.

## 7. Pour compiler toi-même

```bash
flutter pub get
flutter run
flutter build apk --release
flutter build windows --release
```

Linux : installer `libmpv-dev libgtk-3-dev clang cmake ninja-build pkg-config`.

Astuce : si une icône s'affiche comme un carré avec des lettres après une modification, faire `flutter clean` puis recompiler.
