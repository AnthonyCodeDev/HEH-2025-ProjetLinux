#!/usr/bin/env bash
# ------------------------------------------------------------------
# Script d'installation du rapport Fail2Ban pour l'utilisateur admin
# ------------------------------------------------------------------
# Ce script :
#   1. Crée le répertoire /admin si nécessaire
#   2. Télécharge fail2ban_status.sh depuis GitHub dans /admin
#   3. Le rend exécutable
#   4. Ajoute un hook dans /home/admin/.bashrc pour afficher le statut
#      à chaque connexion interactive de l'utilisateur admin
# Usage : sudo ./install_fail2ban_report.sh
# ------------------------------------------------------------------

set -euo pipefail

# Configuration des chemins
ADMIN_USER="admin"
ADMIN_HOME="/home/${ADMIN_USER}"
INSTALL_DIR="/admin"
SCRIPT_PATH="${INSTALL_DIR}/fail2ban_status.sh"
BASHRC="${ADMIN_HOME}/.bashrc"
RAW_URL="https://raw.githubusercontent.com/AnthonyCodeDev/fail2ban-report-panel/main/fail2ban_status.sh"

# 1) Créer le répertoire /admin
echo "[1/4] Création de ${INSTALL_DIR} si nécessaire"
if [ ! -d "${INSTALL_DIR}" ]; then
  mkdir -p "${INSTALL_DIR}"
  chown ${ADMIN_USER}:${ADMIN_USER} "${INSTALL_DIR}"
fi

# 2) Télécharger le script fail2ban_status.sh
echo "[2/4] Téléchargement de fail2ban_status.sh vers ${SCRIPT_PATH}"
wget -q -O "${SCRIPT_PATH}" "${RAW_URL}"
chown ${ADMIN_USER}:${ADMIN_USER} "${SCRIPT_PATH}"
chmod +x "${SCRIPT_PATH}"

# 3) Vérifier/Créer .bashrc pour admin
echo "[3/4] Vérification de ${BASHRC}"
if [ ! -f "${BASHRC}" ]; then
  touch "${BASHRC}"
  chown ${ADMIN_USER}:${ADMIN_USER} "${BASHRC}"
fi

# 4) Ajouter le hook dans .bashrc
HOOK_MARKER="# Fail2Ban status hook"
echo "[4/4] Ajout du hook dans ${BASHRC} si absent"
grep -qxF "${HOOK_MARKER}" "${BASHRC}" || cat << 'EOF' | tee -a "${BASHRC}" > /dev/null
${HOOK_MARKER}
if [[ \$- == *i* ]]; then
    /admin/fail2ban_status.sh || echo "⚠️ Erreur lors de lexécution du script Fail2ban."
fi
EOF
chown ${ADMIN_USER}:${ADMIN_USER} "${BASHRC}"

echo -e "\n✔ Installation terminée pour ${ADMIN_USER}."
echo "Reconnectez-vous en tant que ${ADMIN_USER} ou faites: source ${BASHRC}"
