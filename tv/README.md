# Canalix pour téléviseurs (Samsung et LG)

Application web pour télé, sans compilation : HTML, CSS et JavaScript.
- `index.html`, `css/`, `js/` : l'app (liste de lecture, catégories à gauche, chaînes, aperçu, guide, plein écran).
- `js/config.js` : adresse du serveur de licences (vide = mode test avec essai de 7 jours et paiements simulés).
- `config.xml` : manifeste Samsung Tizen. `appinfo.json` : manifeste LG webOS.
- `lib/` : hls.js (Apache 2.0) et qrcode-generator (MIT).

## Tester sur un ordinateur
```bash
cd tv && python3 -m http.server 8099
```
Ouvrir http://localhost:8099 dans Chrome (flèches, Entrée, Échap). Pour charger une liste d'un autre serveur
depuis le navigateur, lancer Chrome avec `--disable-web-security` (sur la télé, ce n'est pas nécessaire).

## Paquets
`./build.sh` produit `dist/Canalix-lg.ipk` et `dist/Canalix-samsung.zip`. GitHub les produit aussi à chaque version.

### LG (webOS)
1. Télé : installer l'app « Developer Mode » depuis le LG Content Store et l'activer (compte LG développeur gratuit).
2. Ordinateur : `npx -p @webos-tools/cli ares-setup-device` puis `ares-install Canalix-lg.ipk`.
3. Publication : https://seller.lgappstv.com (compte vendeur, envoi du .ipk, révision par LG).

### Samsung (Tizen)
1. Installer Tizen Studio + l'extension « Samsung Certificate » et créer un certificat Samsung (compte Samsung).
2. Télé : Apps > taper 12345 > Developer mode ON avec l'adresse IP de l'ordinateur.
3. Tizen Studio : importer le contenu de `Canalix-samsung.zip`, signer avec le certificat, installer sur la télé.
4. Publication : https://seller.samsungapps.com/tv (compte Samsung Seller Office, révision par Samsung).

L'app se présente comme un lecteur vidéo ; elle ne fournit aucun contenu et l'affiche au premier lancement.
