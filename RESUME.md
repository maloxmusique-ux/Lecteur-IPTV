# Résumé du projet StreamFlow (Lecteur IPTV)

Ce fichier résume tout le travail fait jusqu'ici, pour reprendre le projet dans une nouvelle conversation.
Pour reprendre : ouvre une nouvelle session Claude Code avec le dépôt `maloxmusique-ux/Lecteur-IPTV` sélectionné, puis dis « lis RESUME.md et continuons ».

## 1. L'objectif

Créer un lecteur IPTV **très fluide et haute performance**, **multiplateforme** et **100 % légal**.

Choix faits ensemble :
- Plateformes : Android, Android TV, iOS, Windows, macOS, Linux (une seule base de code).
- Sources : playlists M3U/M3U8, comptes Xtream Codes, guide TV XMLTV (EPG).
- Légal : l'app ne fournit aucune chaîne. L'utilisateur n'ajoute que des sources auxquelles il a légalement accès.

## 2. Technologies

- **Flutter 3.47** (Dart 3.13)
- **media_kit** (moteur **libmpv**, celui de mpv) pour la lecture vidéo, avec décodage matériel
- `provider` (état), `http`, `xml`, `shared_preferences`, `path_provider`

## 3. Ce qui est fait et fonctionne

### Fonctionnalités
- Ajout de sources M3U (URL) ou Xtream Codes (serveur + identifiant + mot de passe), avec options avancées (URL EPG, User-Agent).
- Onglets : TV, Films, Séries, Favoris, Sources.
- Catégories, recherche instantanée, numéros de chaînes, logos.
- Guide TV : programme en cours et suivant, barre de progression, liste des programmes à venir.
- Grand écran : aperçu vidéo à droite. 1er clic = aperçu, 2e clic = plein écran sans recharger le flux.
- Mobile : liste + lecteur plein écran.
- Lecteur : zapping (flèches Haut/Bas, PageUp/PageDown, touches chaîne de télécommande, glisser vertical sur mobile), pause, avance/retour 10 s pour les films, barre de lecture, pistes audio et sous-titres, favori, plein écran (touche F), muet (M), retour (Échap).
- Séries Xtream : saisons et épisodes, enchaînement épisode suivant.
- Favoris et historique « Vus récemment ».
- Android TV : lanceur Leanback, navigation à la télécommande.

### Performance
- Un seul lecteur libmpv réutilisé : zapping quasi instantané.
- Décodage matériel, analyse du flux réduite (démarrage plus rapide), démarrage sans attendre le cache.
- Reconnexion automatique des chaînes live (3 tentatives).
- Téléchargement et parsing (M3U, JSON Xtream, XMLTV) en arrière-plan (isolates) : l'interface ne bloque jamais. 100 000 chaînes parsées en moins d'une seconde (testé).
- Cache disque : la liste et le guide s'affichent immédiatement au démarrage, puis se mettent à jour (catalogue toutes les 12 h, guide toutes les 6 h).
- Listes optimisées (hauteur fixe, images décodées à la bonne taille, filtrage mémorisé).

### Cadre légal
- Écran d'acceptation obligatoire au premier lancement.
- Case obligatoire « Je certifie avoir légalement le droit d'accéder aux contenus de cette source » à chaque ajout.
- Page « Mentions légales » (bouton bouclier dans l'onglet Sources) avec des idées de sources légales : playlist officielle du fournisseur d'accès, tuner TNT perso (TVHeadend, Jellyfin), flux officiels des chaînes, fournisseur IPTV sous licence.
- Aucune playlist intégrée, aucun lien vers un service.

### Vérifications faites
- Analyse du code : aucun problème.
- 5 tests unitaires (parseurs M3U et XMLTV) : tous passent.
- Version Linux compilée et testée en vrai avec une playlist de test : aperçu, plein écran, zapping, guide TV, flux HLS et MPEG-TS, vue mobile.

### Bugs corrigés en route
- Chaînes avec la même URL toutes surlignées : identifiant rendu unique.
- Fausse erreur « Flux indisponible » causée par la sortie audio : ignorée, et l'erreur s'efface dès que la lecture avance.
- Compilation Linux bloquée par le téléchargement de mimalloc : option désactivée dans `linux/CMakeLists.txt`.

## 4. Organisation du code

```
lib/
  main.dart                    Démarrage, thème, écran légal ou accueil
  models/models.dart           Channel, Source, Catalog, Programme, EpgData
  services/net.dart            Téléchargement (gzip géré)
  services/m3u_parser.dart     Parseur M3U
  services/xtream_api.dart     Client Xtream Codes
  services/epg_parser.dart     Parseur XMLTV en flux
  services/repository.dart     Isolates + cache disque
  player/player_engine.dart    Moteur libmpv réglé pour l'IPTV
  state/app_state.dart         Sources, catalogue, EPG, favoris, acceptation légale
  ui/home_screen.dart          Accueil, listes, aperçu, favoris
  ui/player_screen.dart        Lecteur plein écran
  ui/series_screen.dart        Saisons et épisodes
  ui/sources_screen.dart       Gestion des sources
  ui/legal_screen.dart         Écran d'acceptation et mentions légales
  ui/widgets/                  Tuile de chaîne, affiche, logo
test/parsers_test.dart         Tests des parseurs
```

## 5. GitHub

- Dépôt : https://github.com/maloxmusique-ux/Lecteur-IPTV (branche `main`)
- L'application GitHub Claude est installée sur ce dépôt : Claude peut y pousser directement les modifications.

## 6. Reste à faire (prochaines étapes proposées)

1. ~~Accents dans toute l'interface~~ : fait (1er novembre 2026).
2. ~~Compilation automatique sur GitHub~~ : fait. Le fichier `.github/workflows/build.yml` compile l'APK Android et la version Windows à chaque envoi sur `main`, et les publie dans la release « Dernière version » (onglet Releases du dépôt).
   - Signature Android : sans secrets, l'APK est signé avec une clé temporaire (il faut désinstaller avant chaque mise à jour). Pour une clé fixe, ajouter dans GitHub (Settings, Secrets and variables, Actions) : `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`. `android/app/build.gradle.kts` les utilise automatiquement via `android/key.properties`.
3. Tester sur un vrai téléphone, une box Android TV et Windows (seul Linux a été testé).
4. Une vraie icône et un nom d'app définitifs.
5. Fonctions possibles : grille de guide TV complète, reprise des films là où on s'est arrêté, contrôle parental, plusieurs profils.

## 7. Pour compiler toi-même

```bash
flutter pub get
flutter run
flutter build apk --release
flutter build windows --release
```

Linux : installer `libmpv-dev libgtk-3-dev clang cmake ninja-build pkg-config`.

Astuce : si une icône s'affiche comme un carré avec des lettres après une modification, faire `flutter clean` puis recompiler.
