#!/usr/bin/env bash
# Creates a release: bumps the version everywhere, builds the web app into backend/public,
# commits and tags it. Push afterwards with: git push origin HEAD --follow-tags
#
# Usage: scripts/release.sh 2.1.0
#   MAJOR (3.0.0): changes that break something or need manual steps (data migration, new env vars)
#   MINOR (2.1.0): new features
#   PATCH (2.0.1): fixes only
set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Uso: scripts/release.sh X.Y.Z   (ejemplo: scripts/release.sh 2.1.0)" >&2
  exit 1
fi

cd "$(dirname "$0")/.."
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "La versión v$VERSION ya existe." >&2
  exit 1
fi
# A release must contain only committed work (backend/data.json is local data and is ignored)
if [ -n "$(git status --porcelain --untracked-files=no | grep -v ' backend/data.json$' || true)" ]; then
  echo "Hay cambios sin confirmar. Haga commit (o stash) antes de crear la versión:" >&2
  git status --short --untracked-files=no | grep -v ' backend/data.json$' >&2
  exit 1
fi

# Android needs an always-increasing build number: use the commit count
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

# CHANGELOG: add a section with the commits since the previous release if it is not written yet
if ! grep -q "^## \[$VERSION\]" CHANGELOG.md; then
  PREV=$(git describe --tags --abbrev=0 2>/dev/null || true)
  RANGE=${PREV:+$PREV..}HEAD
  ENTRY=$(printf '## [%s] - %s\n\n%s\n' "$VERSION" "$TODAY" "$(git log --format='- %s' "$RANGE" | grep -v '^- release:' || true)")
  awk -v entry="$ENTRY" 'NR==1,/^## \[/{ if ($0 ~ /^## \[/ && !done) { print entry "\n"; done=1 } } { print }' CHANGELOG.md > CHANGELOG.md.tmp
  mv CHANGELOG.md.tmp CHANGELOG.md
fi

export PATH="$HOME/flutter/bin:$PATH"
flutter test
flutter build web --release
rsync -a --delete build/web/ backend/public/

git add pubspec.yaml lib/version.dart backend/package.json backend/package-lock.json CHANGELOG.md backend/public
git commit -m "release: v$VERSION"
git tag -a "v$VERSION" -m "Rifa Master v$VERSION"

echo
echo "Versión v$VERSION creada (build $BUILD)."
echo "Revise CHANGELOG.md y publique con:  git push origin HEAD --follow-tags"
