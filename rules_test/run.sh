#!/usr/bin/env bash
#
# ATOS — Firestore guvenlik kurallarinin birim testleri.
#
# Kullanim:
#   ./rules_test/run.sh                 # guncel firestore.rules
#   RULES_FILE=/yol/eski.rules ./rules_test/run.sh   # baska bir kural dosyasi
#
# Emulator kullanir; CANLI PROJEYE HIC DOKUNMAZ.
#
# NOT: `firebase emulators:exec` kullanmiyoruz — Firebase CLI kendi gomulu
# Node'uyla calistirdigi icin `node --test` bayragini yutuyor. Bu yuzden
# emulator ayri baslatilip testler sistem Node'uyla kosuluyor.

set -euo pipefail

cd "$(dirname "$0")/.."

# Java (emulator icin sart) — Homebrew openjdk PATH'te olmayabilir.
# DIKKAT: macOS'ta /usr/bin/java diye CALISMAYAN bir kabuk vardir; bu
# yuzden "komut var mi" degil "gercekten calisiyor mu" diye bakiyoruz.
if ! java -version >/dev/null 2>&1; then
  if [[ -x /opt/homebrew/opt/openjdk/bin/java ]]; then
    export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
  else
    echo "HATA: java bulunamadi. Kurulum: brew install openjdk" >&2
    exit 1
  fi
fi

PORT=8080
STARTED_HERE=0

cleanup() {
  if [[ "$STARTED_HERE" == "1" && -n "${EMU_PID:-}" ]]; then
    kill "$EMU_PID" 2>/dev/null || true
    wait "$EMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Emulator zaten ayakta mi?
if curl -s -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then
  echo "==> Calisan emulator kullaniliyor (port $PORT)"
else
  echo "==> Firestore emulator baslatiliyor..."
  firebase emulators:start --only firestore --project atos-rules-test \
    >/tmp/atos-emulator.log 2>&1 &
  EMU_PID=$!
  STARTED_HERE=1

  for _ in $(seq 1 60); do
    if curl -s -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then break; fi
    sleep 1
  done

  if ! curl -s -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then
    echo "HATA: emulator baslamadi. Kayit: /tmp/atos-emulator.log" >&2
    exit 1
  fi
fi

export FIRESTORE_EMULATOR_HOST="127.0.0.1:$PORT"
echo "==> Kural testleri calisiyor..."
node --test rules_test/rules.test.js
