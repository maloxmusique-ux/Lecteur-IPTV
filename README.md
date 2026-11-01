# StreamFlow

Lecteur IPTV multiplateforme haute performance (Android, Android TV, iOS, Windows, macOS, Linux), écrit en Flutter avec le moteur **libmpv** via `media_kit`.

## Fonctionnalités

- Playlists **M3U / M3U8** (url-tvg, group-title, tvg-logo, `#EXTVLCOPT` User-Agent / Referer)
- Comptes **Xtream Codes** : TV en direct, films, séries (saisons et épisodes)
- **Guide TV XMLTV** (gzip supporté) : programme en cours, suivant, barre de progression
- Aperçu vidéo intégré sur grand écran, plein écran instantané sans recharger le flux
- Zapping : flèches Haut/Bas, PageUp/PageDown, touches chaîne de la télécommande, glissement vertical sur mobile
- Favoris, historique, recherche instantanée, pistes vidéo, audio et sous-titres
- Navigation à la télécommande (Android TV, lanceur Leanback), saisie du numéro de chaîne
- **Grille du guide TV** sur 8 jours (hier + 7 jours), recherche dans tous les programmes, fiche émission
- **Rappels** avec notification et passage automatique sur la chaîne
- **Rattrapage Xtream** (catch-up / timeshift serveur) : revoir ou télécharger les émissions passées
- **Pause du direct** : jusqu'à 2 h gardées sur disque, retour au direct en un clic
- **Enregistrements** immédiats ou programmés depuis le guide, téléchargement des films et épisodes
- **Reprise** des films et épisodes, rangée « Continuer à regarder »
- **Profils** (dont profil enfant), **contrôle parental** avec code, verrouillage auto des catégories adultes
- **Multi-écran** jusqu'à 4 chaînes, image dans l'image (Android), minuterie de mise en veille
- Organisation des catégories (ordre, masquer, verrouiller), langues audio et sous-titres préférées
- Sauvegarde et restauration de toutes les données
- Interface en **français, anglais, espagnol et portugais**

## Pourquoi c'est fluide

| Domaine | Technique |
|---|---|
| Lecture | Une seule instance libmpv réutilisée, décodage matériel avec repli logiciel, petit tampon de démarrage réglable (Rapide / Équilibré / Stable), paquets corrompus ignorés, reconnexion illimitée du direct et relance si le flux bloque |
| Chargement | Réseau et parsing M3U/JSON/XMLTV dans des **isolates** : l'UI ne bloque jamais (100 000 chaînes parsées en moins d'une seconde) |
| Démarrage | Cache disque du catalogue et de l'EPG, affichage immédiat puis rafraîchissement en arrière-plan |
| Listes | `itemExtent` fixe, images décodées à la taille d'affichage (`cacheWidth`), filtrage mémoïsé, recherche avec debounce |
| EPG | Parsing XMLTV en flux (pas de DOM), 8 jours à venir + passé des chaînes avec rattrapage, recherche binaire, grille qui ne construit que les cases visibles |

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

Haut/Bas : chaîne précédente/suivante · Gauche/Droite : -10 s/+10 s (aussi dans le direct) · Espace : pause · L : retour au direct · I : infos du flux · chiffres : aller à une chaîne · F : plein écran · M : muet · Échap : retour

## Cadre légal

StreamFlow est un lecteur multimédia, comme VLC. **Il ne contient, ne vend et ne référence aucune chaîne, playlist ou contenu**, et ne fait la promotion d'aucun service.

- Au premier lancement, l'utilisateur doit accepter de n'utiliser que des contenus auxquels il a légalement accès.
- Chaque source ajoutée nécessite de certifier ce droit d'accès.
- Une page « Mentions légales » (onglet Sources) rappelle les règles et suggère des sources légales : playlist officielle du fournisseur d'accès, tuner TNT personnel (TVHeadend, Jellyfin), flux gratuits publiés par les diffuseurs eux-mêmes, fournisseur IPTV sous licence.

Règle à respecter si tu distribues l'app (Play Store, App Store) : ne jamais intégrer de playlist par défaut, ni de lien ou de capture d'écran montrant des chaînes protégées sans autorisation.
