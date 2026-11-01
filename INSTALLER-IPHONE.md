# Installer Canalix sur ton iPhone (depuis ton Mac)

Apple ne permet pas d'installer une app iPhone par un simple fichier à télécharger.
Il faut la compiler une fois sur ton Mac avec Xcode et ton compte développeur Apple (que tu as déjà).
Compte environ 30 à 45 minutes la première fois, puis 2 minutes pour les mises à jour.

## 1. Préparer le Mac (une seule fois)

1. Installe **Xcode** depuis l'App Store (gratuit, c'est long à télécharger).
2. Ouvre Xcode une fois, accepte la licence et laisse-le installer les composants.
3. Dans Xcode : menu **Xcode > Settings > Accounts**, clique sur **+** et connecte ton compte Apple développeur.
4. Installe **Flutter** : ouvre le Terminal et colle :
   ```bash
   brew install --cask flutter
   ```
   (Si `brew` n'existe pas, installe d'abord Homebrew depuis https://brew.sh.)
5. Vérifie : `flutter doctor` (les lignes Xcode et Flutter doivent être en vert).

## 2. Récupérer le projet

```bash
cd ~/Desktop
git clone https://github.com/maloxmusique-ux/Lecteur-IPTV.git
cd Lecteur-IPTV
flutter pub get
```

Pour une mise à jour plus tard : `cd ~/Desktop/Lecteur-IPTV && git pull && flutter pub get`.

## 3. Préparer l'iPhone (une seule fois)

1. Branche l'iPhone au Mac avec le câble et accepte « Faire confiance à cet ordinateur ».
2. Sur l'iPhone : **Réglages > Confidentialité et sécurité > Mode développeur**, active-le et redémarre.

## 4. Signer et installer

1. Ouvre le projet iPhone dans Xcode :
   ```bash
   open ios/Runner.xcworkspace
   ```
2. À gauche, clique sur **Runner**, puis l'onglet **Signing & Capabilities**.
3. **Team** : choisis ton équipe (ton compte développeur).
4. **Bundle Identifier** : mets un identifiant à toi, par exemple `com.canalixtv.app`.
5. En haut de la fenêtre, choisis ton iPhone comme appareil.
6. De retour dans le Terminal :
   ```bash
   flutter run --release
   ```
   L'app s'installe et s'ouvre sur l'iPhone. Tu peux débrancher le câble ensuite.

Avec un compte développeur payant, l'app reste valide 1 an. Pour l'installer sur d'autres iPhone
sans câble, on pourra passer par **TestFlight** (dis-le à Claude, il te guidera).

## Différences sur iPhone

- Pas d'enregistrement en arrière-plan : Apple l'interdit. Le rattrapage Xtream le remplace très bien.
- La recherche automatique des Chromecast demande une autorisation spéciale d'Apple. En attendant, entre l'adresse IP du Chromecast à la main (elle est dans l'appli Google Home, réglages de l'appareil).
- Les enregistrements faits sur l'iPhone sont visibles dans l'app **Fichiers**, dossier Canalix.
