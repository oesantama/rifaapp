# Infraestructura del VPS y entornos multi-cliente (LEER ANTES DE TOCAR EL SERVIDOR)

> Documento para humanos y para otras IA. Si vas a desplegar, crear un entorno o tocar nginx/Docker en el VPS,
> lee todo esto primero. **No hay credenciales aquí**: pídelas al dueño del proyecto y no las guardes en el repo.

## 1. Servidor

| Dato | Valor |
|---|---|
| Proveedor / plan | Contabo, Cloud VPS 6 (St. Louis), Ubuntu 24.04, ~12 GB RAM, 193 GB disco |
| IP | `45.137.192.195` (usuario `root`, acceso por SSH) |
| Dominio | `santamariapp.com` en GoDaddy (NS `ns13/ns14.domaincontrol.com`) |
| DNS | Registro **comodín** `A  *  →  45.137.192.195`: cualquier subdominio ya llega al VPS. No hace falta tocar GoDaddy al crear entornos |
| Firewall (ufw) | Abiertos: SSH, Nginx Full (80/443), 8080 (Evolution API). Todo lo demás cerrado |

## 2. Qué corre en el VPS

```
Internet ─▶ nginx (host, 80/443, certbot) ─┬─▶ 127.0.0.1:3001  rifa-williamrifas    (entorno ÚNICO activo)
                                           └─▶ (rifaapp-backend eliminado a petición del dueño)
Docker: evolution_api (:8080) + evolution_postgres + evolution_redis  ← WhatsApp vinculado a williamrifas
```

### Producción original (NO ROMPER)
- Código: `/opt/rifaapp` (repo git, rama `master`). Datos: `/var/lib/rifaapp` (vía `RIFAAPP_DATA_DIR` en `/opt/rifaapp/.env`).
- URL: `https://45-137-192-195.sslip.io` (también responde como `default_server` en el puerto 80 por IP).
- **Auto-deploy**: un webhook de GitHub (`/api/deploy-webhook` → `webhook_server.py` en 127.0.0.1:9000) ejecuta
  `/opt/rifaapp/deploy.sh`: `git reset --hard origin/master` + `docker compose up -d --build`.
  Cualquier `git push` a `master` redespliega producción. **No hagas push sin que el dueño lo pida.**
- `git reset --hard` borra cambios no versionados dentro de `/opt/rifaapp`. No edites archivos a mano ahí.
- `/opt/rifaapp/backend/public` es el build de Flutter Web (ya compilado y versionado). Lo comparten (solo lectura) los demás entornos.

### Entornos de clientes (multi-entorno)
Cada cliente = un entorno aislado, creado con **`/opt/envs/nuevo-entorno.sh <nombre> <dominio> [puerto]`**
(copia versionada en este repo: `scripts/vps-nuevo-entorno.sh`).

| Cosa | Ruta |
|---|---|
| Código base compartido (se construye a imagen) | `/opt/envs/code` → imagen Docker `rifaapp-multi:latest` |
| Config del entorno | `/opt/envs/<nombre>/{docker-compose.yml,.env}` |
| Datos del entorno (data.json, secrets, backups, assets) | `/var/lib/rifaapp-envs/<nombre>/` |
| Contenedor | `rifa-<nombre>`, puerto `127.0.0.1:<3001..>:3000` |
| nginx | `/etc/nginx/sites-available/<nombre>.conf` (+ symlink en `sites-enabled`), HTTPS con certbot |

Entornos existentes:

| Nombre | Dominio | Puerto |
|---|---|---|
| (producción) rifaapp-backend | 45-137-192-195.sslip.io | 3000 |
| williamrifas | williamrifas.santamariapp.com | 3001 |

(Actualiza esta tabla cuando crees otro.)

**Historial:** el 2026-11-06, a petición expresa del dueño, `williamrifas` se restauró con una copia de los datos de producción
(`/var/lib/rifaapp/data.json` + `secrets/data.key` + `assets/`). Consecuencias: usa la **misma llave de cifrado y las mismas
cuentas/claves** que producción (la clave SuperAdmin generada por el script ya no aplica; vale la de producción), y comparte con
producción los códigos de empresa/asesores → **riesgo de choque de instancias WhatsApp** (regla 7). El estado previo quedó en
`/var/lib/rifaapp-envs/williamrifas/pre-restore-<fecha>/`.
Segunda sincronización (mismo día, a petición del dueño): datos frescos de producción + `.env` de producción (credenciales de
Google Drive; `PUBLIC_BASE_URL`/`PUBLIC_WEBHOOK_URL` se mantienen propios) + front compilado propio en
`/opt/envs/williamrifas/public` (incluye el botón «Reorganizar números al azar»; el compose de este entorno ya NO monta el `public` de producción).
**Es una copia puntual, no hay sincronización continua**: producción y williamrifas son bases separadas. Compilar el front:
`export PATH=$HOME/development/flutter/bin:$PATH; flutter build web --release` y subir `build/web` a `/opt/envs/<nombre>/public`.
Estado previo en `pre-sync-<fecha>/`. Nunca apuntes dos contenedores al mismo `data.json` (se pisan y se corrompe la base).

## 3. Procedimientos

### Crear un entorno nuevo
```bash
ssh root@45.137.192.195
/opt/envs/nuevo-entorno.sh nombrecliente nombrecliente.santamariapp.com
```
El script: genera `.env` con una clave SuperAdmin aleatoria, crea el compose, genera la base inicial (arranca un contenedor
semilla y copia su `data.json`), levanta el contenedor, crea el vhost nginx y pide el certificado. Al final imprime URL y clave
SuperAdmin (usuario `superadmin`) → **entrégala al dueño y que la cambie al entrar**.
Después: entrar como SuperAdmin, **borrar los datos demo** (rifa y asesores de ejemplo que trae la base inicial) y crear la
empresa del cliente con un **código único** (ver «Reglas»).

### Actualizar el código de los entornos de clientes
El auto-deploy solo actualiza producción. Para los entornos de clientes:
```bash
# 1) subir el backend actualizado a /opt/envs/code (sin data.json, secrets, backups, assets, public, .env, node_modules)
# 2) reconstruir y reiniciar cada entorno:
cd /opt/envs/code && docker build -t rifaapp-multi:latest -f Containerfile .
for d in /opt/envs/*/; do [ -f "$d/docker-compose.yml" ] && (cd "$d" && docker compose up -d --force-recreate); done
```
El front (Flutter Web) sale de `/opt/rifaapp/backend/public`, montado en solo lectura; se actualiza solo cuando producción se
despliega desde git.

### Ver estado / logs / respaldos
```bash
docker ps; docker logs --tail 50 rifa-<nombre>
ls /var/lib/rifaapp-envs/<nombre>/backups     # el servidor crea copias automáticas cada 12 h
nginx -t && systemctl reload nginx; certbot certificates
```

## 4. Reglas — lo que NO hay que hacer

1. **No copies `data.json` de producción a otro entorno**: son datos reales de clientes. Cada entorno arranca con base propia.
2. **No reutilices puertos ni nombres de contenedor.** El script elige el puerto libre; no pises el 3000 (producción).
3. **No cambies el `server_name _`/default_server de nginx ni los bloques de producción** al agregar entornos.
4. **No hagas `git push`, `git reset`, ni `docker compose down` en `/opt/rifaapp`** sin pedirlo el dueño: redespliega o apaga producción.
5. **No abras puertos de los entornos al exterior**: solo `127.0.0.1`; el acceso público es por nginx + HTTPS.
6. **No guardes contraseñas, tokens ni `.env` en el repo** (`*.env` está en `.gitignore`). No pegues claves en commits, docs ni mensajes.
7. **WhatsApp (Evolution API) es compartido.** Los nombres de instancia salen del código de empresa (`empresa_<codigo>`,
   `asesor_<id>`) y de `superadmin_sales`/`rifaapp_bot`. **Cada entorno debe usar códigos de empresa únicos** y no usar la
   instancia del superadmin fuera de producción; si dos entornos usan el mismo nombre se pisan las sesiones y los mensajes
   entrantes llegan al entorno equivocado.
8. **Variables por entorno obligatorias** en `/opt/envs/<nombre>/.env`: `PUBLIC_BASE_URL` (enlaces de boleta enviados por
   WhatsApp), `PUBLIC_WEBHOOK_URL` (webhook de Evolution hacia ESE entorno) y `SUPERADMIN_PASSWORD`. Sin ellas los enlaces/mensajes
   apuntan a producción. No hardcodees dominios en el código: usa `PUBLIC_BASE_URL`.
9. **Google Drive**: los entornos de clientes no traen credenciales de Drive (para no mezclar archivos). Si el cliente las necesita,
   ponlas en SU `.env` (`GOOGLE_DRIVE_FOLDER_ID`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN`) con su propia carpeta.
10. **`data.json` se monta como archivo.** Si no existe en el host, Docker crea un *directorio* con ese nombre y el servidor falla.
    Por eso el script genera el archivo con un contenedor semilla antes del primer arranque.
11. Antes de borrar/sobrescribir algo en el VPS, míralo primero (`ls`, `cat`, `docker ps`). Respalda `data.json` antes de migrarlo.

## 5. Cambios de código relacionados
- `backend/server.js` y `backend/whatsappService.js`: constante `PUBLIC_BASE_URL` (por defecto la URL sslip de producción).
- `POST /api/raffles/:id/reshuffle-numbers` (admin): reorganiza al azar los números de las boletas solo si **todas** están
  DISPONIBLES y cada boleta tiene ≥2 oportunidades; el botón está en *Gestionar Sorteo* (`raffle_edit_dialog.dart`). Requiere
  recompilar Flutter Web para que aparezca el botón.
- `lib/data/services/api_service.dart` usa rutas relativas (`/api`) en web, por lo que el mismo build sirve para cualquier dominio.
