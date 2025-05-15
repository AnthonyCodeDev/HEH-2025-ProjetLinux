#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# G_7_scan_trivy.sh
# Installe Docker (si manquant), installe Trivy (si manquant),
# configure un cron pour un scan quotidien à 8h, puis effectue un scan immédiat.
# Les résultats sont loggés et les anciens logs sauvegardés.
# Usage:
#   sudo /usr/local/bin/G_7_scan_trivy.sh [image1[:tag] image2[:tag] ...]
#   (sans argument, scanne toutes les images locales)
# ----------------------------------------------------------------------------
set -euo pipefail

# Charger les infos système
. /etc/os-release

# Variables de logging
LOG_DIR="/var/log/trivy"
BACKUP_DIR="$LOG_DIR/backups"
TODAY="$(date +%F)"
LOGFILE="$LOG_DIR/scan-$TODAY.log"

# 0. Installation et configuration du service cron
if ! command -v cronie &>/dev/null; then
  echo "[INFO] Cron non trouvé. Installation de cronie..."
  if command -v yum &>/dev/null; then
    sudo yum install -y cronie
  else
    sudo dnf install -y cronie
  fi
  sudo systemctl enable --now crond
  echo "[OK] Cron installé et démarré."
fi

# Créer la tâche cron
CRON_FILE="/etc/cron.d/g7_scan_trivy"
cat <<EOF | sudo tee ${CRON_FILE} >/dev/null
# Cron job pour le scan Trivy quotidien à 8h
0 8 * * * root /usr/local/bin/G_7_scan_trivy.sh
EOF
sudo chmod 644 ${CRON_FILE}
echo "[INFO] Cron configuré via ${CRON_FILE} pour exécuter le script chaque matin à 8h."

# 1. Préparer les dossiers de logs et rotation
sudo mkdir -p "$BACKUP_DIR"
# Compresser et archiver les logs plus vieux que 7 jours
find "$LOG_DIR" -maxdepth 1 -name "scan-*.log" -mtime +7 -exec gzip {} \; -exec mv {}.gz "$BACKUP_DIR/" \;

# 2. Vérifier / installer Docker si nécessaire
echo "[INFO] Vérification de Docker..."
if ! command -v docker &>/dev/null; then
  echo "[INFO] Docker non trouvé."
  if [[ "$ID" == "amzn" ]]; then
    echo "[INFO] Amazon Linux détecté. Installation via yum/dnf..."
    sudo yum install -y docker || sudo dnf install -y docker
  else
    echo "[INFO] Installation via script officiel Docker..."
    curl -fsSL https://get.docker.com | sh
  fi
  sudo systemctl enable --now docker
  echo "[OK] Docker installé et démarré."
else
  echo "[OK] Docker déjà installé."
fi

# 3. Vérifier / installer Trivy
echo "[INFO] Vérification de Trivy..."
if ! command -v trivy &>/dev/null; then
  echo "[INFO] Trivy non trouvé, installation..."
  curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh
  echo "[OK] Trivy installé."
else
  echo "[OK] Trivy déjà installé."
fi

# 4. Récupérer la liste des images à scanner
if [[ $# -gt 0 ]]; then
  IMAGES=("$@")
else
  mapfile -t IMAGES < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>')
fi
if [[ ${#IMAGES[@]} -eq 0 ]]; then
  echo "[WARN] Aucune image Docker trouvée à scanner." | tee -a "$LOGFILE" >&2
  exit 0
fi

# 5. Lancer le scan et logger
SEVERITY="HIGH,CRITICAL"
echo "[INFO] Démarrage du scan Trivy le $TODAY (sévérité : $SEVERITY) pour ${#IMAGES[@]} image(s)..." | tee -a "$LOGFILE"
for img in "${IMAGES[@]}"; do
  echo -e "\n[SCAN] $img" | tee -a "$LOGFILE"
  trivy image --exit-code 1 --severity "$SEVERITY" --no-progress "$img" 2>&1 | tee -a "$LOGFILE"
  if [[ \${PIPESTATUS[0]} -ne 0 ]]; then
    echo "[RESULT] Vulnérabilités trouvées dans $img." | tee -a "$LOGFILE"
  fi
done

echo -e "\n[OK] Scan Trivy terminé." | tee -a "$LOGFILE"
