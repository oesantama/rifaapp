#!/usr/bin/env bash
# Uso: nuevo-entorno.sh <nombre> <dominio> [puerto]
# Crea un entorno RifaApp aislado: contenedor propio, datos propios, vhost nginx y certificado HTTPS.
set -euo pipefail
NAME="${1:?nombre (ej: williamrifas)}"; DOMAIN="${2:?dominio (ej: williamrifas.santamariapp.com)}"
BASE=/opt/envs; DIR="$BASE/$NAME"; DATA="/var/lib/rifaapp-envs/$NAME"
[[ "$NAME" =~ ^[a-z0-9-]+$ ]] || { echo "nombre invalido"; exit 1; }
[ -e "$DIR" ] && { echo "El entorno $NAME ya existe en $DIR"; exit 1; }
# puerto: el indicado o el siguiente libre a partir de 3001
if [ -n "${3:-}" ]; then PORT="$3"; else
  PORT=3001; while ss -tln | grep -q ":$PORT " || grep -rqs "127.0.0.1:$PORT:3000" $BASE/*/docker-compose.yml; do PORT=$((PORT+1)); done
fi
SAPW="Rm$(openssl rand -hex 8)#$(( RANDOM % 90 + 10 ))"
mkdir -p "$DIR" "$DATA"/{secrets,backups,assets}; chmod 700 "$DATA/secrets" "$DATA/backups"

# Clave de Evolution API: se toma del contenedor (o de la variable EVOLUTION_APIKEY); nunca va escrita en el script
EVO_KEY="${EVOLUTION_APIKEY:-$(docker exec evolution_api printenv AUTHENTICATION_API_KEY 2>/dev/null || true)}"
[ -n "$EVO_KEY" ] || { echo "No pude obtener la clave de Evolution API: defina EVOLUTION_APIKEY"; exit 1; }

cat > "$DIR/.env" <<ENV
EVOLUTION_APIKEY=$EVO_KEY
SUPERADMIN_PASSWORD=$SAPW
PUBLIC_BASE_URL=https://$DOMAIN
PUBLIC_WEBHOOK_URL=https://$DOMAIN/api/whatsapp/webhook
ENV
chmod 600 "$DIR/.env"

cat > "$DIR/docker-compose.yml" <<YML
name: rifa-$NAME
services:
  app:
    image: rifaapp-multi:latest
    container_name: rifa-$NAME
    restart: always
    ports:
      - "127.0.0.1:$PORT:3000"
    env_file: ./.env
    environment:
      - PORT=3000
      - DATA_SOURCE=local
      - EVOLUTION_URL=http://evolution_api:8080
    volumes:
      - $DATA/data.json:/app/data.json
      - $DATA/secrets:/app/secrets
      - $DATA/backups:/app/backups
      - $DATA/assets:/app/assets
      - /opt/rifaapp/backend/public:/app/public:ro
    networks: [default, evolution_net]
networks:
  default:
  evolution_net:
    name: evolution-api_default
    external: true
YML

# Primer arranque sin data.json para que el servidor genere la base inicial; luego se copia al volumen
if [ ! -s "$DATA/data.json" ]; then
  docker rm -f "seed-$NAME" >/dev/null 2>&1 || true
  docker run -d --name "seed-$NAME" --env-file "$DIR/.env" -e PORT=3000 -e DATA_SOURCE=local rifaapp-multi:latest >/dev/null
  for i in $(seq 1 30); do sleep 1; docker exec "seed-$NAME" test -s /app/data.json 2>/dev/null && break; done
  sleep 2
  docker cp "seed-$NAME:/app/data.json" "$DATA/data.json"
  docker cp "seed-$NAME:/app/secrets/." "$DATA/secrets/" 2>/dev/null || true
  docker rm -f "seed-$NAME" >/dev/null
fi
[ -s "$DATA/data.json" ] || { echo "No se pudo generar data.json inicial"; exit 1; }

(cd "$DIR" && docker compose up -d)

cat > "/etc/nginx/sites-available/$NAME.conf" <<NGX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    client_max_body_size 50M;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml application/wasm;
    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGX
ln -sf "/etc/nginx/sites-available/$NAME.conf" "/etc/nginx/sites-enabled/$NAME.conf"
nginx -t && systemctl reload nginx
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect

echo "=============================="
echo "Entorno: $NAME  URL: https://$DOMAIN  puerto interno: $PORT"
echo "Datos: $DATA   Config: $DIR"
echo "SuperAdmin usuario: superadmin   clave: $SAPW"
