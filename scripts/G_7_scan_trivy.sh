#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# G_7_scan_trivy.sh
# Installe Docker (si manquant), installe Trivy (si manquant),
# configure un cron pour un scan quotidien à 8h, puis effectue un scan immédiat.
# Usage:
#   sudo /usr/local/bin/G_7_scan_trivy.sh [image1[:tag] image2[:tag] ...]
#   (sans argument, scanne toutes les images locales)
# ----------------------------------------------------------------------------
set -euo pipefail

# Charger les infos système
. /etc/os-release

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

# Créer un fichier de tâche cron sous /etc/cron.d pour exécuter le script à 8h chaque jour
CRON_FILE="/etc/cron.d/g7_scan_trivy"
cat <<EOF | sudo tee ${CRON_FILE} >/dev/null
# Cron job pour le scan Trivy quotidien à 8h
0 8 * * * root /usr/local/bin/G_7_scan_trivy.sh
EOF
sudo chmod 644 ${CRON_FILE}
echo "[INFO] Cron configuré via ${CRON_FILE} pour exécuter le script chaque matin à 8h."

# 1. Vérifier / installer Docker si nécessaire
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

# 2. Vérifier / installer Trivy
echo "[INFO] Vérification de Trivy..."
if ! command -v trivy &>/dev/null; then
  echo "[INFO] Trivy non trouvé, installation..."
  curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh
  echo "[OK] Trivy installé."
else
  echo "[OK] Trivy déjà installé."
fi

# 3. Récupérer la liste des images à scanner
if [[ $# -gt 0 ]]; then
  IMAGES=("$@")
else
  mapfile -t IMAGES < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>')
fi

if [[ ${#IMAGES[@]} -eq 0 ]]; then
  echo "[WARN] Aucune image Docker trouvée à scanner." >&2
  exit 0
fi

# 4. Lancer le scan pour chaque image
SEVERITY="HIGH,CRITICAL"
echo "[INFO] Démarrage du scan Trivy (sévérité : $SEVERITY) pour ${#IMAGES[@]} image(s)..."
for img in "${IMAGES[@]}"; do
  echo -e "\n[SCAN] $img"
  trivy image --exit-code 1 --severity "$SEVERITY" --no-progress "$img" \
    || echo "[RESULT] Vulnérabilités trouvées dans $img (voir ci-dessus)."
done

echo -e "\n[OK] Scan Trivy terminé."
