#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# setup_uptimekuma.sh
# Installe Docker si nécessaire (avec dnf), démarre Uptime-Kuma (web) + wrapper REST,
# crée des moniteurs et une page de statut avec tous les moniteurs.
# Usage: sudo ./setup_uptimekuma.sh monitors.conf
# ----------------------------------------------------------------------------
set -euo pipefail
IFS=$' \t\n'

CFG="${1:-}"
[[ -z "$CFG" || ! -r "$CFG" ]] && {
  echo "Usage: sudo $0 monitors.conf" >&2
  exit 1
}

# 1. Vérifier et installer Docker si nécessaire
if ! command -v docker >/dev/null; then
  echo "[INFO] Docker non trouvé. Installation de Docker avec dnf..."
  # Préparer le dépôt Docker
  dnf install -y dnf-plugins-core
  dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  # Installer Docker Engine
  dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
  echo "[INFO] Docker installé et démarré."
fi

# 2. Vérifier les dépendances supplémentaires
for cmd in curl jq; do
  command -v "$cmd" >/dev/null || { echo "[ERROR] '$cmd' manquant" >&2; exit 1; }
done

# 3. Variables
UI_CN=uptime-kuma
API_CN=uptime-kuma-api
ADMIN_USER=admin
ADMIN_PASS=admin123
WEB_PORT=3001
API_PORT=8000
UI_IMG=louislam/uptime-kuma:latest
API_IMG=medaziz11/uptimekuma_restapi:latest
API_BASE="http://localhost:${API_PORT}"

# 4. (Re)créer l’UI Uptime-Kuma
docker rm -f "$UI_CN" >/dev/null 2>&1 || true
docker run -d --name "$UI_CN" \
  -e ADMIN_USER="$ADMIN_USER" \
  -e ADMIN_PASSWORD="$ADMIN_PASS" \
  -p "$WEB_PORT":3001 \
  -v uptime-kuma-data:/app/data \
  "$UI_IMG"

# 5. (Re)créer le wrapper REST
docker rm -f "$API_CN" >/dev/null 2>&1 || true
docker run -d --name "$API_CN" \
  --link "$UI_CN":uptime_kuma \
  -e KUMA_SERVER="http://uptime_kuma:3001" \
  -e KUMA_USERNAME="$ADMIN_USER" \
  -e KUMA_PASSWORD="$ADMIN_PASS" \
  -e ADMIN_PASSWORD="$ADMIN_PASS" \
  -e SECRET_KEY="$ADMIN_PASS" \
  -e KUMA_LOGIN_PATH="/login/access-token" \
  -p "$API_PORT":8000 \
  "$API_IMG"

# 6. Attendre le wrapper REST
echo "[INFO] Attente du wrapper REST…"
until curl -s -o /dev/null -w '%{http_code}' "$API_BASE/monitors" | grep -E -q '^[24]'; do
  sleep 2
done
echo "[INFO] Wrapper REST prêt."

# 7. Authentification REST
echo "[INFO] Récupération du token REST…"
RESP=$(curl -s -X POST "$API_BASE/login/access-token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "username=$ADMIN_USER" \
  --data-urlencode "password=$ADMIN_PASS")
TOKEN=$(echo "$RESP" | jq -r '.access_token // empty')
if [[ -z "$TOKEN" ]]; then
  echo "[ERROR] Échec login wrapper. Réponse :" >&2
  echo "$RESP" >&2
  exit 1
fi
echo "[INFO] Token REST obtenu."

# 8. Création des moniteurs
echo "[INFO] Création des moniteurs…"
while read -r name type addr interval; do
  [[ "$name" == \#* || -z "$name" ]] && continue
  case "$type" in
    HTTP)
      payload=$(jq -n --arg n "$name" --arg u "$addr" --argjson i "$interval" \
        '{name:$n,type:"http",url:$u,interval:$i}') ;;
    TCP)
      host=${addr%%:*}; port=${addr##*:}
      payload=$(jq -n --arg n "$name" --arg h "$host" --argjson p "$port" --argjson i "$interval" \
        '{name:$n,type:"tcp",hostname:$h,port:$p,interval:$i}') ;;
    PING)
      payload=$(jq -n --arg n "$name" --arg h "$addr" --argjson i "$interval" \
        '{name:$n,type:"ping",hostname:$h,interval:$i}') ;;
    *)
      echo "[WARN] Type '$type' inconnu. Ignoré." >&2
      continue ;;
  esac

  RESP_TMP=$(mktemp)
  code=$(curl -s -w '%{http_code}' -o "$RESP_TMP" \
    -X POST "$API_BASE/monitors" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "$payload")
  if [[ "$code" =~ ^(200|201|422)$ ]]; then
    echo "[OK] Moniteur '$name' traité (HTTP $code)."
  else
    echo "[ERROR] Échec création '$name' (HTTP $code). Réponse :" >&2
    cat "$RESP_TMP" >&2
  fi
  rm -f "$RESP_TMP"
done < "$CFG"

# 9. Création de la page de statut affichant tous les moniteurs
echo "[INFO] Création de la page de statut..."
RAW=$(curl -s -H "Authorization: Bearer $TOKEN" "$API_BASE/monitors")
MONITOR_IDS=$(echo "$RAW" | jq 'if (type=="object" and .monitors) then .monitors else . end | map(.id)')
STATUSPAGE_PAYLOAD=$(jq -n \
  --arg name "Statut général" \
  --arg slug "statut-general" \
  --argjson mons "$MONITOR_IDS" \
  '{
     name: $name,
     slug: $slug,
     publicGroupList: [
       {
         name: $name,
         weight: 0,
         monitorList: $mons
       }
     ]
   }')

code=(curl -s -w '%{http_code}' -o /dev/null \
  -X POST "$API_BASE/statuspages" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "$STATUSPAGE_PAYLOAD")

if [[ "$code" -eq 201 ]]; then
  echo "[OK] Page de statut 'Statut général' créée."
elif [[ "$code" -eq 422 ]]; then
  echo "[WARN] La page de statut existe peut-être déjà."
else
  echo "[ERROR] Échec création page de statut (HTTP $code)."
fi

echo "[OK] Script terminé."
