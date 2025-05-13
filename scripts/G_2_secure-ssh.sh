#!/usr/bin/env bash
# -----------------------------------------------------
# secure-ssh-same-key.sh
# Hardens SSH and deploys the same key for ec2-user & admin
# Usage: sudo bash secure-ssh-same-key.sh
# -----------------------------------------------------
set -euo pipefail

ADMIN_USER="admin"
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_PORT=22

# 1) Create admin user if missing
if ! id -u "${ADMIN_USER}" &>/dev/null; then
  echo "[1/6] Creating user '${ADMIN_USER}'..."
  useradd -m -s /bin/bash "${ADMIN_USER}"
else
  echo "[1/6] User '${ADMIN_USER}' already exists. Skipping creation."
fi

# 2) Grant sudo privileges to admin without password
echo "[2/6] Granting sudo privileges to '${ADMIN_USER}'..."
cat <<EOF > /etc/sudoers.d/${ADMIN_USER}
${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 /etc/sudoers.d/${ADMIN_USER}
echo " → '${ADMIN_USER}' can now sudo without password."

# 3) Ensure existing ec2-user key is copied to admin
echo "[3/6] Deploying ec2-user public key to ${ADMIN_USER}..."
EC2_AUTH="/home/ec2-user/.ssh/authorized_keys"
ADMIN_SSH_DIR="/home/${ADMIN_USER}/.ssh"
ADMIN_AUTH="${ADMIN_SSH_DIR}/authorized_keys"

if [ ! -f "${EC2_AUTH}" ]; then
  echo "Error: ec2-user authorized_keys not found at ${EC2_AUTH}" >&2
  exit 1
fi

mkdir -p "${ADMIN_SSH_DIR}"
cp "${EC2_AUTH}" "${ADMIN_AUTH}"
chown -R ${ADMIN_USER}:${ADMIN_USER} "${ADMIN_SSH_DIR}"
chmod 700 "${ADMIN_SSH_DIR}"
chmod 600 "${ADMIN_AUTH}"
echo " → Authorized key for ${ADMIN_USER} deployed."

# 4) Install & configure SSH
echo "[4/6] Installing and configuring OpenSSH..."
if   command -v apt &>/dev/null; then
  apt update && apt install -y openssh-server
elif command -v yum &>/dev/null; then
  yum install -y openssh-server
elif command -v dnf &>/dev/null; then
  dnf install -y openssh-server
else
  echo "No supported package manager found" >&2
  exit 1
fi

cp "${SSH_CONFIG}" "${SSH_CONFIG}.bak_$(date +%F_%T)"

enable_directive() {
  local key="$1" value="$2"
  if grep -qE "^#?${key} " "${SSH_CONFIG}"; then
    sed -ri "s|^#?${key} .*|${key} ${value}|" "${SSH_CONFIG}"
  else
    echo "${key} ${value}" >> "${SSH_CONFIG}"
  fi
}

enable_directive Port                     ${SSH_PORT}
enable_directive PermitRootLogin          no
enable_directive PasswordAuthentication    no
enable_directive PubkeyAuthentication      yes
enable_directive AuthorizedKeysFile        .ssh/authorized_keys
enable_directive AllowUsers               ${ADMIN_USER}
enable_directive X11Forwarding            no
enable_directive AllowTcpForwarding       no
echo "UsePAM yes"                            >> "${SSH_CONFIG}"
echo "ChallengeResponseAuthentication no"     >> "${SSH_CONFIG}"

systemctl enable sshd
systemctl restart sshd
echo " → SSH configured: key-only on port ${SSH_PORT}, admin only."

# 5) Install and configure Fail2Ban
echo "[5/6] Installing Fail2Ban..."
if   command -v apt &>/dev/null; then
  apt update && apt install -y fail2ban
elif command -v yum &>/dev/null; then
  yum install -y fail2ban
elif command -v dnf &>/dev/null; then
  dnf install -y fail2ban
fi

LOGPATH="/var/log/auth.log"
[ -f /var/log/secure ] && LOGPATH="/var/log/secure"

cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled   = true
port      = ${SSH_PORT}
filter    = sshd
logpath   = ${LOGPATH}
maxretry  = 5
bantime   = 600
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo "[6/6] SSH and Fail2Ban setup complete. Use your private key to login as '${ADMIN_USER}'."



# CREATION DU PANEL PERSONALISE POUR VOIR LES INFORMATIONS DE FAIL2BAN


#!/usr/bin/env bash
# ------------------------------------------------------------------
# Script d'installation du rapport Fail2Ban pour l'utilisateur admin
# ------------------------------------------------------------------
# Ce script :
#   1. Crée le répertoire /admin si nécessaire
#   2. Télécharge fail2ban_status.sh depuis GitHub dans /admin
#   3. Le rend exécutable
#   4. Ajoute la commande d'affichage du statut dans
#      /home/admin/.bashrc, sans la dupliquer
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
  chown "${ADMIN_USER}:${ADMIN_USER}" "${INSTALL_DIR}"
fi

# 2) Télécharger le script fail2ban_status.sh
echo "[2/4] Téléchargement de fail2ban_status.sh vers ${SCRIPT_PATH}"
wget -q -O "${SCRIPT_PATH}" "${RAW_URL}"
chown "${ADMIN_USER}:${ADMIN_USER}" "${SCRIPT_PATH}"
chmod +x "${SCRIPT_PATH}"

# 3) Vérifier/Créer .bashrc pour admin
echo "[3/4] Vérification de ${BASHRC}"
if [ ! -f "${BASHRC}" ]; then
  touch "${BASHRC}"
  chown "${ADMIN_USER}:${ADMIN_USER}" "${BASHRC}"
fi

# 4) Ajouter l'appel au script dans .bashrc uniquement s'il n'existe pas déjà
echo "[4/4] Ajout de l'appel dans ${BASHRC} si absent"
CALL_LINE="sudo \"${SCRIPT_PATH}\" || echo \"⚠️ Erreur lors de l'exécution du script Fail2ban.\""
if ! grep -Fxq "${CALL_LINE}" "${BASHRC}"; then
  printf "\n%s\n" "${CALL_LINE}" >> "${BASHRC}"
  chown "${ADMIN_USER}:${ADMIN_USER}" "${BASHRC}"
fi

echo -e "\n✔ Installation terminée pour ${ADMIN_USER}."
echo "Reconnectez-vous en tant que ${ADMIN_USER} ou faites : source ${BASHRC}"
