#!/usr/bin/env bash
# Compila el APK de Android apuntando al servidor de producción y lo deja en build/rifamaster.apk.
# Súbalo al servidor (carpeta public/ del entorno, como rifamaster.apk) para que la app lo ofrezca como actualización.
# Uso: scripts/build-apk.sh [https://dominio]   (por defecto https://williamrifas.santamariapp.com)
set -euo pipefail
cd "$(dirname "$0")/.."
SITE="${1:-https://williamrifas.santamariapp.com}"
export PATH="$HOME/development/flutter/bin:$PATH"
flutter build apk --release --dart-define=API_URL="$SITE/api"
cp build/app/outputs/flutter-apk/app-release.apk build/rifamaster.apk
echo "APK listo: build/rifamaster.apk ($(du -h build/rifamaster.apk | cut -f1)) → $SITE"
