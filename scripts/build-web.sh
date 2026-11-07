#!/usr/bin/env bash
# Compila la web con un identificador único de build. El servidor lo publica en /api/health y la app lo compara
# con el suyo: si difieren, el usuario recibe el aviso "Hay una nueva versión" con el botón Actualizar.
# Uso: scripts/build-web.sh        (el resultado queda en build/web)
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/development/flutter/bin:$HOME/flutter/bin:$PATH"

VERSION=$(grep -E "^const String appVersion" lib/version.dart | sed -E "s/.*'(.*)'.*/\1/")
BUILD_ID="$(date -u +%Y%m%d%H%M%S)"

flutter build web --release --dart-define=BUILD_ID="$BUILD_ID" "$@"
printf '{"version":"%s","build":"%s","builtAt":"%s"}\n' "$VERSION" "$BUILD_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > build/web/build.json
echo "Web compilada: v$VERSION build $BUILD_ID"
