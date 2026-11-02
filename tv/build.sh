#!/bin/bash
# Prepare les paquets tele dans dist/ :
#   Canalix-lg.ipk       LG webOS (installable en mode developpeur, a envoyer au LG Seller Lounge)
#   Canalix-samsung.zip  contenu Samsung Tizen, a signer avec le certificat Samsung (Tizen Studio)
# Variables : LICENSE_API et LICENSE_KEY (serveur de licences), sinon mode test.
set -e
cd "$(dirname "$0")"
rm -rf dist build && mkdir -p dist build/app
cp -R index.html css js lib icon.png icon_small.png icon_lg.png config.xml appinfo.json build/app/
if [ -n "$LICENSE_API" ]; then
  sed -i.bak "s#licenseApi: ''#licenseApi: '$LICENSE_API'#; s#licenseKey: ''#licenseKey: '$LICENSE_KEY'#" build/app/js/config.js
  rm -f build/app/js/config.js.bak
fi
# LG : paquet .ipk
npx --yes -p @webos-tools/cli@3.2.6 ares-package build/app -o dist --no-minify >/dev/null
mv dist/*.ipk dist/Canalix-lg.ipk
# Samsung : contenu pret a signer (Tizen Studio > Certificate Manager > profil Samsung)
(cd build/app && zip -qr ../../dist/Canalix-samsung.zip . -x appinfo.json icon_small.png icon_lg.png)
ls -la dist
