# StreamFlow

Lecteur IPTV multiplateforme haute performance (Android, Android TV, iOS, Windows, macOS, Linux), écrit en Flutter avec le moteur **libmpv** via `media_kit`.

## Fonctionnalités

- Playlists **M3U / M3U8** (url-tvg, group-title, tvg-logo, `#EXTVLCOPT` User-Agent / Referer)
- Comptes **Xtream Codes** : TV en direct, films, séries (saisons et épisodes)
- **Guide TV XMLTV** (gzip supporté) : programme en cours, suivant, barre de progression
- Aperçu vidéo intégré sur grand écran, plein écran instantané sans recharger le flux
- Zapping : flèches Haut/Bas, PageUp/PageDown, touches chaîne de la télécommande, glissement vertical sur mobile
- Favoris, historique, recherche instantanée, pistes audio et sous-titres
- Navigation à la télécommande (Android TV, lanceur Leanback)

## Pourquoi c'est fluide

| Domaine | Technique |
|---|---|
| Lecture | Une seule instance libmpv réutilisée, décodage matériel, sondage du flux réduit (`analyzeduration 1.5s`), démarrage sans attendre le cache, reconnexion automatique |
| Chargement | Réseau et parsing M3U/JSON/XMLTV dans des **isolates** : l'UI ne bloque jamais (100 000 chaînes parsées en moins d'une seconde) |
| Démarrage | Cache disque du catalogue et de l'EPG, affichage immédiat puis rafraîchissement en arrière-plan |
| Listes | `itemExtent` fixe, images décodées à la taille d'affichage (`cacheWidth`), filtrage mémoïsé, recherche avec debounce |
| EPG | Parsing XMLTV en flux (pas de DOM), fenêtre de 36 h, recherche binaire du programme en cours |

## Lancer

```bash
flutter pub get
flutter run
```

Linux : `sudo apt install libmpv-dev libgtk-3-dev clang cmake ninja-build pkg-config`

Builds de release :

```bash
flutter build apk --release        # Android / Android TV
flutter build windows --release
flutter build macos --release
flutter build ios --release
flutter build linux --release
```

## Structure

```
lib/
  models/models.dart          Channel, Source, Catalog, Programme, EpgData
  services/m3u_parser.dart    Parseur M3U en une passe
  services/xtream_api.dart    Client Xtream Codes
  services/epg_parser.dart    Parseur XMLTV en flux
  services/repository.dart    Isolates et cache disque
  player/player_engine.dart   Moteur libmpv réglé pour l'IPTV
  state/app_state.dart        Sources, catalogue, favoris, EPG
  ui/                         Accueil, lecteur, séries, sources
```

## Raccourcis du lecteur

Haut/Bas : chaîne précédente/suivante · Gauche/Droite : -10 s/+10 s (VOD) · Espace : pause · F : plein écran · M : muet · Échap : retour

## Cadre légal

StreamFlow est un lecteur multimédia, comme VLC. **Il ne contient, ne vend et ne référence aucune chaîne, playlist ou contenu**, et ne fait la promotion d'aucun service.

- Au premier lancement, l'utilisateur doit accepter de n'utiliser que des contenus auxquels il a légalement accès.
- Chaque source ajoutée nécessite de certifier ce droit d'accès.
- Une page « Mentions légales » (onglet Sources) rappelle les règles et suggère des sources légales : playlist officielle du fournisseur d'accès, tuner TNT personnel (TVHeadend, Jellyfin), flux gratuits publiés par les diffuseurs eux-mêmes, fournisseur IPTV sous licence.

Règle à respecter si tu distribues l'app (Play Store, App Store) : ne jamais intégrer de playlist par défaut, ni de lien ou de capture d'écran montrant des chaînes protégées sans autorisation.
