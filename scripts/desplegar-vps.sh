#!/usr/bin/env bash
# Sube al servidor (entorno williamrifas): backend, web y APK, y comprueba que todo quedó funcionando.
# No guarda ninguna contraseña: use llave SSH (ssh-copy-id una sola vez) o exporte SSH_ASKPASS en su sesión.
#
# Uso: scripts/desplegar-vps.sh [--sin-apk]
#   Antes: scripts/build-web.sh (web en build/web) y scripts/build-apk.sh (APK en build/rifamaster.apk)
#   Variables: VPS_HOST (por defecto root@45.137.192.195), VPS_ENV (por defecto williamrifas)
set -euo pipefail
cd "$(dirname "$0")/.."

VPS_HOST="${VPS_HOST:-root@45.137.192.195}"
VPS_ENV="${VPS_ENV:-williamrifas}"
SITE="${SITE:-https://williamrifas.santamariapp.com}"
CON_APK=1
[ "${1:-}" = "--sin-apk" ] && CON_APK=0

[ -f build/web/index.html ] || { echo "Falta la web compilada: ejecute scripts/build-web.sh" >&2; exit 1; }
if [ "$CON_APK" = 1 ] && [ ! -f build/rifamaster.apk ]; then
  echo "Falta el APK: ejecute scripts/build-apk.sh (o use --sin-apk)" >&2; exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar czf "$TMP/web.tgz" -C build/web .
(cd backend && tar czf "$TMP/code.tgz" --exclude=node_modules --exclude=data.json --exclude=secrets --exclude=backups \
  --exclude=assets --exclude=public --exclude=.env --exclude=serviceAccountKey.json .)

echo "→ Copiando archivos a $VPS_HOST ..."
scp -q "$TMP/web.tgz" "$TMP/code.tgz" "$VPS_HOST:/tmp/"
[ "$CON_APK" = 1 ] && scp -q build/rifamaster.apk "$VPS_HOST:/opt/envs/$VPS_ENV/public/rifamaster.apk.new"

echo "→ Publicando en el servidor ..."
ssh "$VPS_HOST" "set -e
cd /opt/envs/code && tar xzf /tmp/code.tgz && docker build -q -t rifaapp-multi:latest -f Containerfile . >/dev/null
tar xzf /tmp/web.tgz -C /opt/envs/$VPS_ENV/public && rm -f /tmp/web.tgz /tmp/code.tgz
if [ -f /opt/envs/$VPS_ENV/public/rifamaster.apk.new ]; then
  cd /opt/envs/$VPS_ENV/public && mv -f rifamaster.apk.new rifamaster.apk && cp -f rifamaster.apk app.apk
fi
cd /opt/envs/$VPS_ENV && docker compose up -d --force-recreate >/dev/null 2>&1
sleep 8"

echo "→ Verificando ..."
HEALTH="$(curl -fsS "$SITE/api/health")"
echo "   API: $HEALTH" | cut -c1-120
WEB="$(curl -s -o /dev/null -w '%{http_code}' "$SITE/")"
echo "   Web: HTTP $WEB"
if [ "$CON_APK" = 1 ]; then
  SIZE_LOCAL=$(stat -c %s build/rifamaster.apk)
  SIZE_REMOTE=$(curl -sI "$SITE/descargar-apk" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-length"{print $2}')
  [ "$SIZE_LOCAL" = "$SIZE_REMOTE" ] && echo "   APK: OK ($SIZE_REMOTE bytes)" || { echo "   APK: NO coincide (local $SIZE_LOCAL, servidor $SIZE_REMOTE)" >&2; exit 1; }
fi
[ "$WEB" = 200 ] || { echo "La web no respondió 200" >&2; exit 1; }
echo "✓ Servidor actualizado."
