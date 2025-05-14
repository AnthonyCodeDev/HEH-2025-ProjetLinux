#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# setup_uptimekuma.sh
# Installe Docker si nécessaire, démarre Uptime-Kuma + wrapper REST,
# crée des moniteurs et une page de statut.
# Usage: sudo ./setup_uptimekuma.sh monitors.conf
# ----------------------------------------------------------------------------
set -euo pipefail
IFS=$' \t\n'

# --- 1. Vérif. argument
CFG="${1:-}"
[[ -z "$CFG" || ! -r "$CFG" ]] && {
  echo "Usage: sudo $0 monitors.conf" >&2
  exit 1
}

# --- 2. Variables
UI_CN=uptime-kuma
API_CN=uptime-kuma-api
ADMIN_USER=admin
ADMIN_PASS=admin123
WEB_PORT=3001
API_PORT=8000
UI_IMG=louislam/uptime-kuma:latest
API_IMG=medaziz11/uptimekuma_restapi:latest
UI_BASE="http://localhost:${WEB_PORT}"
API_BASE="http://localhost:${API_PORT}"

# --- 3. Dépendances
for cmd in curl jq docker dnf; do
  command -v "$cmd" >/dev/null || { echo "[ERROR] '$cmd' manquant" >&2; exit 1; }
done

# --- 4. Firewall
echo "[INFO] Configuration firewalld…"
dnf install -y firewalld >/dev/null 2>&1 || true
systemctl enable --now firewalld >/dev/null 2>&1
firewall-cmd --permanent --add-port=${WEB_PORT}/tcp
firewall-cmd --permanent --add-port=${API_PORT}/tcp
firewall-cmd --reload
echo "[INFO] Ports ${WEB_PORT}, ${API_PORT} ouverts."

# --- 5. Iptables pour Docker
echo "[INFO] Vérification iptables DOCKER…"
if ! iptables -t nat -L DOCKER >/dev/null 2>&1; then
  dnf install -y iptables-services >/dev/null 2>&1
  systemctl enable --now iptables
  systemctl restart docker
fi

# --- 6. Pull images & cleanup
for IMG in "$UI_IMG" "$API_IMG"; do
  docker rmi -f "$IMG" >/dev/null 2>&1 || true
  docker pull "$IMG"
done
docker rm -f "$UI_CN" >/dev/null 2>&1 || true
docker rm -f "$API_CN" >/dev/null 2>&1 || true
docker volume rm -f uptime-kuma-data >/dev/null 2>&1 || true

# --- 7. Lancement UI
echo "[INFO] Démarrage UI Uptime-Kuma…"
docker run -d --name "$UI_CN" \
  -p "${WEB_PORT}":3001 \
  -v uptime-kuma-data:/app/data \
  "$UI_IMG"

# --- 8. Alerte création manuelle admin
echo
echo "************************************************************"
echo "*   Veuillez maintenant créer l'utilisateur admin manuellement via*"
echo "*   votre navigateur à l'adresse :                           *"
echo "*       ${UI_BASE}                                            *"
echo "*   (identifiants choisis : ${ADMIN_USER} / ${ADMIN_PASS})   *"
echo "************************************************************"
echo

read -p "Appuyez sur [Entrée] une fois l'admin créé pour continuer…" _

# --- 9. Lancement wrapper REST
echo "[INFO] Démarrage wrapper REST…"
docker run -d --name "$API_CN" \
  --link "$UI_CN":uptime_kuma \
  -e KUMA_SERVER="http://uptime_kuma:3001" \
  -e KUMA_USERNAME="$ADMIN_USER" \
  -e KUMA_PASSWORD="$ADMIN_PASS" \
  -e ADMIN_PASSWORD="$ADMIN_PASS" \
  -e SECRET_KEY="$ADMIN_PASS" \
  -e KUMA_LOGIN_PATH="/login/access-token" \
  -p "${API_PORT}":8000 \
  "$API_IMG"

# --- 10. Attente et auth
echo "[INFO] Attente de l'API REST…"
until curl -s -o /dev/null -w '%{http_code}' "$API_BASE/monitors" | grep -E -q '^[24]'; do
  sleep 2
done

echo "[INFO] Récupération du token REST…"
LOGIN=$(curl -s -X POST "$API_BASE/login/access-token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "username=${ADMIN_USER}" \
  --data-urlencode "password=${ADMIN_PASS}")
TOKEN=$(echo "$LOGIN" | jq -r '.access_token // empty')
if [[ -z "$TOKEN" ]]; then
  echo "[ERROR] Échec login wrapper :"; echo "$LOGIN"; exit 1
fi

# --- 11. Création moniteurs
echo "[INFO] Création des moniteurs…"
while read -r name type addr interval; do
  [[ "$name" =~ ^# || -z "$name" ]] && continue
  case "$type" in
    HTTP) payload=$(jq -n --arg n "$name" --arg u "$addr" --argjson i "$interval" \
              '{name:$n,type:"http",url:$u,interval:$i}') ;;
    TCP) host=${addr%%:*}; port=${addr##*:}
         payload=$(jq -n --arg n "$name" --arg h "$host" --argjson p "$port" --argjson i "$interval" \
              '{name:$n,type:"tcp",hostname:$h,port:$p,interval:$i}') ;;
    PING) payload=$(jq -n --arg n "$name" --arg h "$addr" --argjson i "$interval" \
              '{name:$n,type:"ping",hostname:$h,interval:$i}') ;;
    *) echo "[WARN] Type '$type' inconnu."; continue ;;
  esac

  code=$(curl -s -w '%{http_code}' -o /dev/null -X POST "$API_BASE/monitors" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "$payload")

  if [[ "$code" =~ ^(200|201|422)$ ]]; then
    echo "[OK] $name"
  else
    echo "[ERROR] $name (HTTP $code)"
  fi
done < "$CFG"

# --- 12. Création page de statut
echo "[INFO] Création page statut…"
MON_IDS=$(curl -s -H "Authorization: Bearer $TOKEN" "$API_BASE/monitors" \
  | jq 'if .monitors then .monitors else . end | map(.id)')
STATUS=$(jq -n --argjson mons "$MON_IDS" \
  '{name:"Statut général",slug:"statut-general",publicGroupList:[{name:"Statut général",weight:0,monitorList:$mons}]}')
code=$(curl -s -w '%{http_code}' -o /dev/null -X POST "$API_BASE/statuspages" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "$STATUS")
if   [[ "$code" -eq 201 ]]; then echo "[OK] Page créée."
elif [[ "$code" -eq 422 ]]; then echo "[WARN] Page existante."
else echo "[ERROR] Page statut (HTTP $code)"; fi

echo "[INFO] Script terminé à $(date +'%F %T')"
