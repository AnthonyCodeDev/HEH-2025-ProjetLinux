#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# A_19_setup_uptimekuma.sh
# Installe et configure Uptime-Kuma en container Docker,
# puis ajoute des moniteurs définis dans un fichier de configuration.
# Usage: sudo ./A_19_setup_uptimekuma.sh monitors.conf
# monitors.conf format (champ séparés par espaces):
#   <name> <type> <address> <interval_sec>
# Ex: web01 HTTP https://example.com 60
#     db01 TCP 192.168.0.10:3306 30
#     gw01 PING 192.168.0.1 20
# ----------------------------------------------------------------------------
set -euo pipefail
IFS=$' \t\n'

CONFIG_FILE="${1:-}"
# Expansion du tilde (~)
if [[ "$CONFIG_FILE" == ~* ]]; then
  CONFIG_FILE="${CONFIG_FILE/#\~/$HOME}"
fi

# Variables principales
UPK_CONTAINER="uptime-kuma"
UPK_PORT=3001
ADMIN_USER="admin"
ADMIN_PASS="admin123"
BASE_URL="http://localhost:${UPK_PORT}"
SETUP_ENDPOINT="/api/setup/admin"
LOGIN_ENDPOINT="/api/login"
MONITOR_ENDPOINT="/api/monitor"

# 1. Vérifier l'exécution en root
if [[ $(id -u) -ne 0 ]]; then
  echo "[ERROR] Ce script doit être exécuté en root." >&2
  exit 1
fi

# 2. Vérifier dépendances
for cmd in curl jq docker; do
  if ! command -v "$cmd" >/dev/null; then
    echo "[ERROR] '$cmd' introuvable. Installez-le et relancez." >&2
    exit 1
  fi
done

# 3. Vérifier le fichier de configuration
if [[ -z "$CONFIG_FILE" ]]; then
  echo "Usage: $(basename "$0") monitors.conf" >&2
  exit 1
fi
if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "[ERROR] Fichier '$CONFIG_FILE' introuvable ou non lisible." >&2
  exit 1
fi

# 4. Lancer Uptime-Kuma si nécessaire
if ! docker ps --format '{{.Names}}' | grep -qw "$UPK_CONTAINER"; then
  echo "[INFO] Démarrage du container Uptime-Kuma avec réglage initial d'administration..."
  docker run -d --name "$UPK_CONTAINER" \
    -e "ADMIN_USER=${ADMIN_USER}" \
    -e "ADMIN_PASSWORD=${ADMIN_PASS}" \
    -p ${UPK_PORT}:3001 \
    -v uptime-kuma-data:/app/data \
    louislam/uptime-kuma:latest

  # Attente du démarrage : test toutes les 5s jusqu'à HTTP 200 sur /api/user
  echo "[INFO] Attente du démarrage du service Uptime-Kuma..."
  until curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/user" | grep -q '^2'; do
    sleep 5
  done
  echo "[INFO] Service Uptime-Kuma démarré."
else
  echo "[INFO] Container $UPK_CONTAINER déjà en cours."
fi

# 5. Création de l'admin initial si nécessaire
HTTP_USER=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/user")
if [[ "$HTTP_USER" -eq 404 ]]; then
  echo "[INFO] Pas d'utilisateur admin trouvé, création via $SETUP_ENDPOINT"
  curl -s -X POST "$BASE_URL$SETUP_ENDPOINT" \
       -H "Content-Type: application/json" \
       -d '{"user":"'"$ADMIN_USER"'","password":"'"$ADMIN_PASS"'"}' \
    || { echo "[ERROR] Échec de la création admin initial" >&2; exit 1; }
  echo "[INFO] Admin initial créé."
fi

# 6. Authentification et récupération du token
echo "[INFO] Obtention du token API…"
LOGIN_RESP=$(curl -s -X POST "$BASE_URL$LOGIN_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{"username":"'"$ADMIN_USER"'","password":"'"$ADMIN_PASS"'"}')

if ! echo "$LOGIN_RESP" | jq -e . >/dev/null 2>&1; then
  echo "[ERROR] Réponse API invalide: $LOGIN_RESP" >&2
  exit 1
fi

TOKEN=$(echo "$LOGIN_RESP" | jq -r .token)
if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "[ERROR] Échec authentification API. Réponse: $LOGIN_RESP" >&2
  exit 1
fi
echo "[INFO] Authentification réussie, token obtenu."

# 7. Création des moniteurs
while read -r name type address interval; do
  [[ "$name" =~ ^# ]]   && continue
  [[ -z "$name" ]]      && continue

  echo "[INFO] Création moniteur '$name' ($type $address)..."
  case "$type" in
    HTTP)
      payload=$(jq -n \
        --arg name "$name" \
        --arg url  "$address" \
        --argjson interval "$interval" \
        '{"name":$name, "type":"http", "url":$url, "interval":$interval}')
      ;;
    TCP)
      host=${address%%:*}
      port=${address##*:}
      payload=$(jq -n \
        --arg name "$name" \
        --arg host "$host" \
        --argjson port "$port" \
        --argjson interval "$interval" \
        '{"name":$name, "type":"tcp", "hostname":$host, "port":$port, "interval":$interval}')
      ;;
    PING)
      payload=$(jq -n \
        --arg name "$name" \
        --arg addr "$address" \
        --argjson interval "$interval" \
        '{"name":$name, "type":"ping", "hostname":$addr, "interval":$interval}')
      ;;
    *)
      echo "[WARNING] Type inconnu: $type. Ignoré." >&2
      continue
      ;;
  esac

  curl -s -X POST "$BASE_URL$MONITOR_ENDPOINT" \
       -H "Content-Type: application/json" \
       -H "Authorization: Bearer $TOKEN" \
       -d "$payload" \
    && echo "[OK] Moniteur '$name' créé." \
    || echo "[ERROR] Échec création '$name'."
done < "$CONFIG_FILE"

echo "[OK] Configuration Uptime-Kuma terminée."
