#!/usr/bin/env bash
#
# ATOS — web release derlemesi + Google Maps anahtari enjeksiyonu.
#
# Neden var: anahtar kaynak kodda (web/index.html) durursa git gecmisine
# girer. Bunun yerine index.html'de __MAPS_API_KEY__ yer tutucusu durur;
# gercek anahtar buradan, DERLEME CIKTISINA yazilir.
#
# ONEMLI / DURUSTLUK NOTU: Bu, anahtari kullanicilardan GIZLEMEZ. Web'de
# harita anahtari tarayiciya inen dosyalarda her zaman gorunur — teknik
# olarak baska turlusu mumkun degil. Asil koruma Google Cloud Console'daki
# HTTP referrer kisitidir (web.app, firebaseapp.com, localhost:5858).
# Buradaki kazanc: anahtar DEPODA ve git gecmisinde durmuyor.
#
# Kullanim:
#   ./tool/build_web.sh                 # .maps_api_key dosyasindan okur
#   MAPS_API_KEY=AIza... ./tool/build_web.sh
#   ./tool/build_web.sh --wasm          # ekstra parametreler flutter'a gecer

set -euo pipefail

cd "$(dirname "$0")/.."

PLACEHOLDER='__MAPS_API_KEY__'
INDEX='build/web/index.html'

# --- 1) Anahtari bul: once ortam degiskeni, sonra yerel dosya ---
KEY="${MAPS_API_KEY:-}"
if [[ -z "$KEY" && -f .maps_api_key ]]; then
  KEY="$(tr -d '[:space:]' < .maps_api_key)"
fi

if [[ -z "$KEY" ]]; then
  cat >&2 <<'MSG'
HATA: Google Maps anahtari bulunamadi.

Cozum (ikisinden biri):
  1) Proje kokune .maps_api_key dosyasini koyun (icinde sadece anahtar):
       echo 'AIza...' > .maps_api_key
     Bu dosya .gitignore'da; depoya girmez.
  2) Ya da ortam degiskeni verin:
       MAPS_API_KEY=AIza... ./tool/build_web.sh

Anahtar: Google Cloud Console > teknofest-atik-toplama projesi.
MSG
  exit 1
fi

# --- 2) Flutter'i bul (PATH'te yoksa bilinen kurulum yerine bak) ---
if ! command -v flutter >/dev/null 2>&1; then
  if [[ -x "$HOME/development/flutter/bin/flutter" ]]; then
    export PATH="$HOME/development/flutter/bin:$PATH"
  else
    echo "HATA: flutter komutu bulunamadi (PATH ve ~/development/flutter/bin)." >&2
    exit 1
  fi
fi

# --- 3) Derle ---
echo "==> flutter build web --release"
flutter build web --release "$@"

# --- 4) Yer tutucuyu gercek anahtarla degistir ---
if [[ ! -f "$INDEX" ]]; then
  echo "HATA: $INDEX olusmamis; derleme basarisiz olmus olabilir." >&2
  exit 1
fi

if ! grep -q "$PLACEHOLDER" "$INDEX"; then
  echo "HATA: $INDEX icinde $PLACEHOLDER yer tutucusu yok." >&2
  echo "      web/index.html elle degistirilmis olabilir." >&2
  exit 1
fi

# Degistirmeyi python3 yapiyor: anahtardaki ozel karakterler sed'i bozmasin.
KEY="$KEY" PLACEHOLDER="$PLACEHOLDER" python3 - "$INDEX" <<'PY'
import os, sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    html = f.read()

html = html.replace(os.environ['PLACEHOLDER'], os.environ['KEY'])

with open(path, 'w', encoding='utf-8') as f:
    f.write(html)
PY

# --- 5) Dogrula: yer tutucu kalmadi, anahtar yerinde ---
if grep -q "$PLACEHOLDER" "$INDEX"; then
  echo "HATA: yer tutucu hala duruyor, enjeksiyon basarisiz." >&2
  exit 1
fi

echo "==> Maps anahtari $INDEX icine yazildi (…${KEY: -4})"
echo "==> Hazir. Yerel test:  cd build/web && python3 -m http.server 5858"
echo "==> Yayin:              firebase deploy --only firestore:rules,hosting"
