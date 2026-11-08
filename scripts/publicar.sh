#!/usr/bin/env bash
# PUBLICA TODO EN UN SOLO PASO, cuando el trabajo ya está terminado:
#   1) sube la versión (pubspec, lib/version.dart, backend/package.json) y escribe el CHANGELOG
#   2) compila la web y el APK (apuntando a williamrifas)
#   3) los sube al servidor y verifica que respondan
#   4) crea el commit + la etiqueta vX.Y.Z y los sube a git. La etiqueta hace que GitHub compile y publique
#      el APK en "Releases" (rifa-master.apk), con la misma firma, así el enlace de GitHub también queda al día.
#
# Uso:
#   scripts/publicar.sh            # sube el PARCHE (3.3.0 -> 3.3.1)
#   scripts/publicar.sh minor      # 3.3.1 -> 3.4.0   (funciones nuevas)
#   scripts/publicar.sh major      # 3.4.0 -> 4.0.0   (cambios que obligan a migrar)
#   scripts/publicar.sh 3.5.2      # versión exacta
#
# Antes de empezar debe estar todo confirmado en git (commit). El push final pide confirmación porque
# un push a master redespliega producción (ver docs/INFRAESTRUCTURA_VPS.md).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/development/flutter/bin:$PATH"

# ---- versión nueva
CURRENT="$(sed -n -E 's/^version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml)"
IFS=. read -r MA MI PA <<<"$CURRENT"
case "${1:-patch}" in
  patch) VERSION="$MA.$MI.$((PA + 1))" ;;
  minor) VERSION="$MA.$((MI + 1)).0" ;;
  major) VERSION="$((MA + 1)).0.0" ;;
  [0-9]*.[0-9]*.[0-9]*) VERSION="$1" ;;
  *) echo "Uso: scripts/publicar.sh [patch|minor|major|X.Y.Z]" >&2; exit 1 ;;
esac
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then echo "La versión v$VERSION ya existe." >&2; exit 1; fi

# ---- todo debe estar confirmado
if [ -n "$(git status --porcelain --untracked-files=no | grep -v ' backend/data.json$' || true)" ]; then
  echo "Hay cambios sin confirmar. Haga commit antes de publicar:" >&2
  git status --short --untracked-files=no >&2
  exit 1
fi

echo "Publicando v$VERSION (actual: v$CURRENT)"
read -r -p "¿Continuar? (s/N) " OK
[ "$OK" = "s" ] || { echo "Cancelado."; exit 1; }

# ---- 1) versión + changelog
BUILD=$(( $(git rev-list --count HEAD) + 1 ))
TODAY=$(date +%Y-%m-%d)
sed -i -E "s/^version: .*/version: $VERSION+$BUILD/" pubspec.yaml
sed -i -E "s/^const String appVersion = '.*';/const String appVersion = '$VERSION';/" lib/version.dart
node -e "
const fs = require('fs');
for (const f of ['backend/package.json', 'backend/package-lock.json']) {
  if (!fs.existsSync(f)) continue;
  const j = JSON.parse(fs.readFileSync(f, 'utf8'));
  j.version = '$VERSION';
  if (j.packages && j.packages['']) j.packages[''].version = '$VERSION';
  fs.writeFileSync(f, JSON.stringify(j, null, 2) + '\n');
}"
if ! grep -q "^## \[$VERSION\]" CHANGELOG.md; then
  PREV=$(git describe --tags --abbrev=0 2>/dev/null || true)
  RANGE=${PREV:+$PREV..}HEAD
  ENTRY=$(printf '## [%s] - %s\n\n%s\n' "$VERSION" "$TODAY" "$(git log --format='- %s' "$RANGE" | grep -v '^- release:' || true)")
  awk -v entry="$ENTRY" 'NR==1,/^## \[/{ if ($0 ~ /^## \[/ && !done) { print entry "\n"; done=1 } } { print }' CHANGELOG.md > CHANGELOG.md.tmp
  mv CHANGELOG.md.tmp CHANGELOG.md
fi

# ---- 2) revisión + compilación
echo "→ Revisando el código ..."
if flutter analyze lib 2>&1 | grep -E '^\s+error'; then echo "Hay errores de análisis: corríjalos y vuelva a intentar." >&2; git checkout -- . ; exit 1; fi
echo "→ Compilando la web ..."
scripts/build-web.sh >/dev/null
echo "→ Compilando el APK ..."
scripts/build-apk.sh | tail -1

# ---- 3) servidor
scripts/desplegar-vps.sh

# ---- 4) git
git add pubspec.yaml lib/version.dart backend/package.json backend/package-lock.json CHANGELOG.md
git commit -q -m "release: v$VERSION"
git tag -a "v$VERSION" -m "Rifa Master v$VERSION"
echo
echo "Versión v$VERSION publicada en el servidor y confirmada en git (commit + etiqueta)."
read -r -p "¿Subir a GitHub ahora? Un push a master redespliega producción y compila el APK de Releases. (s/N) " PUSH
if [ "$PUSH" = "s" ]; then
  git push origin HEAD --follow-tags
  echo "✓ Subido. GitHub compilará el APK y lo publicará en Releases en unos minutos."
else
  echo "Cuando quiera: git push origin HEAD --follow-tags"
fi
