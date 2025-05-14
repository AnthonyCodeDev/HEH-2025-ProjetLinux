#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# setup_uptimekuma.sh
# Script amélioré sans paramètres -u / -p. Admin hardcodé en début de script.
# Usage: sudo ./setup_uptimekuma.sh -data <IP> -certificat <IP> -monitoring <IP> -time <IP> -backup <IP>
# ----------------------------------------------------------------------------
set -euo pipefail
IFS=$' \t\n'

# --- 1. Variables d'administration hardcodées
ADMIN_USER="admin"
ADMIN_PASS="admin123"

# --- 2. Parsing des arguments obligatoires (sans user/pass)
if [[ $# -lt 10 ]]; then
  echo "[ERROR] Usage: sudo $0 -data <IP> -certificat <IP> -monitoring <IP> -time <IP> -backup <IP>" >&2
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -data)
      DATA_IP="$2"; shift 2;;
    -certificat)
      CERT_IP="$2"; shift 2;;
    -monitoring)
      MON_IP="$2"; shift 2;;
    -time)
      TIME_IP="$2"; shift 2;;
    -backup)
      BACKUP_IP="$2"; shift 2;;
    *)
      echo "[ERROR] Paramètre inconnu: $1" >&2; exit 1;;
  esac
 done

# Vérification de la présence de tous les paramètres
for var in DATA_IP CERT_IP MON_IP TIME_IP BACKUP_IP; do
  if [[ -z "${!var:-}" ]]; then
    echo "[ERROR] Le paramètre ${var} est requis." >&2
    exit 1
  fi
done

# --- 3. Variables par défaut
UI_CN=uptime-kuma
API_CN=uptime-kuma-api
WEB_PORT=3001
API_PORT=8000
UI_IMG=louislam/uptime-kuma:latest
API_IMG=medaziz11/uptimekuma_restapi:latest
UI_BASE="http://localhost:${WEB_PORT}"
API_BASE="http://localhost:${API_PORT}"

# --- 4. Vérif. et installation pip3 + firefox + autres dépendances
if ! command -v pip3 >/dev/null; then
  echo "[DEBUG] pip3 non trouvé, installation python3-pip..."
  dnf install -y python3-pip >/dev/null 2>&1
fi

for cmd in curl jq docker dnf python3 pip3 firefox; do
  if ! command -v "$cmd" >/dev/null; then
    echo "[DEBUG] '$cmd' non trouvé, installation via dnf..."
    dnf install -y "$cmd" >/dev/null 2>&1 || {
      echo "[ERROR] Impossible d'installer '$cmd'" >&2
      exit 1
    }
  fi
 done

# --- 5. Installation Python packages
echo "[DEBUG] pip3 install selenium + geckodriver-autoinstaller..."
pip3 install --quiet selenium geckodriver-autoinstaller

# --- 6. Firewall & iptables
echo "[INFO] Configuration firewalld…"
dnf install -y firewalld >/dev/null 2>&1 || true
systemctl enable --now firewalld >/dev/null 2>&1
echo "[INFO] Ouverture ports ${WEB_PORT} et ${API_PORT}"
firewall-cmd --permanent --add-port=${WEB_PORT}/tcp
firewall-cmd --permanent --add-port=${API_PORT}/tcp
firewall-cmd --reload

echo "[INFO] Vérification iptables DOCKER…"
if ! iptables -t nat -L DOCKER >/dev/null 2>&1; then
  dnf install -y iptables-services >/dev/null 2>&1
  systemctl enable --now iptables >/dev/null 2>&1
  systemctl restart docker
fi

# --- 7. Pull images & nettoyage
echo "[INFO] Pull des images Docker…"
for IMG in "$UI_IMG" "$API_IMG"; do
  docker rmi -f "$IMG" >/dev/null 2>&1 || true
  docker pull "$IMG"
done

docker rm -f "$UI_CN" "$API_CN" >/dev/null 2>&1 || true
docker volume rm -f uptime-kuma-data >/dev/null 2>&1 || true

# --- 8. Lancement UI
echo "[INFO] Démarrage UI Uptime-Kuma…"
docker run -d --name "$UI_CN" -p "${WEB_PORT}":3001 -v uptime-kuma-data:/app/data "$UI_IMG"

# --- 9. Création auto admin avec debug
echo "[INFO] Création automatique de l'utilisateur admin…"
echo "[DEBUG] Attente de la page de setup sur ${UI_BASE}…"
sleep 1

python3 - << 'PYCODE'
import os, traceback
import geckodriver_autoinstaller
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.service import Service

def debug(msg):
    print(f"[PY-DEBUG] {msg}", flush=True)

try:
    debug("Installation automatique de geckodriver…")
    gecko_path = geckodriver_autoinstaller.install()
    debug(f"Chemin Geckodriver = {gecko_path}")

    FIREFOX_BIN = "/usr/bin/firefox"
    if not os.path.isfile(FIREFOX_BIN):
        raise FileNotFoundError(f"{FIREFOX_BIN} introuvable")

    USER = os.environ.get("ADMIN_USER", "admin")
    PASS = os.environ.get("ADMIN_PASS", "admin123")
    URL = os.environ.get("UI_BASE", "http://localhost:3001") + "/setup"
    debug(f"TARGET URL = {URL}")

    opts = Options()
    opts.binary_location = FIREFOX_BIN
    opts.add_argument("--headless")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")

    debug("Initialisation du WebDriver Firefox…")
    service = Service(executable_path=gecko_path)
    driver = webdriver.Firefox(service=service, options=opts)

    debug("Ouverture de la page setup…")
    driver.get(URL)

    wait = WebDriverWait(driver, 20)
    debug("Attente du champ username…")
    elem_user = wait.until(EC.presence_of_element_located((By.ID, "floatingInput")))
    debug("Champ username trouvé, envoi de la valeur…")
    elem_user.send_keys(USER)

    debug("Envoi du password…")
    driver.find_element(By.ID, "floatingPassword").send_keys(PASS)
    debug("Envoi du repeat password…")
    driver.find_element(By.ID, "repeat").send_keys(PASS)

    debug("Clique sur le bouton Submit…")
    btn = driver.find_element(By.XPATH, '//button[@data-cy="submit-setup-form"]')
    btn.click()

    debug("Attente de la redirection vers /dashboard")
    wait.until(EC.url_contains("/dashboard"))
    debug("Redirection OK, admin créé.")
    driver.quit()
except Exception:
    print("[PY-ERROR] Exception levée durant la création admin :", flush=True)
    traceback.print_exc()
    try:
        driver.quit()
    except:
        pass
    exit(1)
finally:
    debug("Script Python terminé.")
PYCODE

echo "[OK] Utilisateur admin : ${ADMIN_USER}/${ADMIN_PASS}"

# --- 10. Lancement wrapper REST et création des moniteurs
echo "[INFO] Démarrage wrapper REST…"
docker run -d --name "$API_CN" --link "$UI_CN":uptime_kuma \
  -e KUMA_SERVER="http://uptime_kuma:3001" -e KUMA_USERNAME="$ADMIN_USER" \
  -e KUMA_PASSWORD="$ADMIN_PASS" -e ADMIN_PASSWORD="$ADMIN_PASS" \
  -e SECRET_KEY="$ADMIN_PASS" -e KUMA_LOGIN_PATH="/login/access-token" \
  -p "${API_PORT}":8000 "$API_IMG"

echo "[INFO] Attente API REST…"
until curl -s -o /dev/null -w '%{http_code}' "$API_BASE/monitors" | grep -E -q '^[24]'; do
  sleep 2
done

LOGIN=$(curl -s -X POST "$API_BASE/login/access-token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "username=${ADMIN_USER}" \
  --data-urlencode "password=${ADMIN_PASS}")
TOKEN=$(echo "$LOGIN" | jq -r '.access_token // empty')
[[ -z "$TOKEN" ]] && { echo "[ERROR] Échec login wrapper : $LOGIN" >&2; exit 1; }

echo "[INFO] Création des moniteurs…"
MONITORS=(
  "Serveur de Données|PING|$DATA_IP|60"
  "Serveur de Certificat|PING|$CERT_IP|60"
  "Serveur de Monitoring|PING|$MON_IP|60"
  "Serveur de Temps|PING|$TIME_IP|60"
  "Serveur de Backup|PING|$BACKUP_IP|60"
)
for entry in "${MONITORS[@]}"; do
  IFS='|' read -r name type addr interval <<< "$entry"
  payload=$(jq -n \
    --arg n "$name" \
    --arg h "$addr" \
    --argjson i "$interval" \
    '{name:$n,type:"ping",hostname:$h,interval:$i}')
  code=$(curl -s -w '%{http_code}' -o /dev/null \
         -X POST "$API_BASE/monitors" \
         -H "Content-Type: application/json" \
         -H "Authorization: Bearer $TOKEN" \
         -d "$payload")
  if [[ "$code" =~ ^(200|201|422)$ ]]; then
    echo "[OK] $name ($addr)"
  else
    echo "[ERROR] $name ($addr) HTTP $code"
  fi

  sleep 2
done

echo "[INFO] Script terminé à $(date +'%F %T')"