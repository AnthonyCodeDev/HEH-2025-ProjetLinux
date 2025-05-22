#!/usr/bin/env bash
set -euo pipefail

# ─── CONFIGURATION ──────────────────────────────────────────────
DOMAIN="heh.lan"
ROOT_PW="JSShFZtpt35MHX"  # mot de passe root MariaDB
SSL_CERT="/etc/ssl/certs/wildcard.${DOMAIN}.crt.pem"
SSL_KEY="/etc/ssl/private/wildcard.${DOMAIN}.key.pem"

# ─── COULEURS ───────────────────────────────────────────────────
RED=$'\e[31m'; GREEN=$'\e[32m'; BLUE=$'\e[34m'; RESET=$'\e[0m'

info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
succ() { echo -e "${GREEN}[OK]${RESET}   $1"; }
err()  { echo -e "${RED}[ERREUR]${RESET} $1" >&2; exit 1; }

# ─── VERIFICATION PARAMETRE ─────────────────────────────────────
if [[ $# -ne 1 ]]; then
  echo "Usage: sudo bash $0 <nom_utilisateur>"
  exit 1
fi

USER_NAME="$1"
DB_NAME="${USER_NAME}_db"
VHOST="/etc/nginx/conf.d/${USER_NAME}.${DOMAIN}.conf"
WEB_DIR="/var/www/${USER_NAME}"
HOME_DIR="/home/${USER_NAME}"

# ─── 1) SUPPRESSION DE LA BASE DE DONNÉES ───────────────────────
info "Suppression de la base de données et de l'utilisateur SQL..."
sudo mysql --protocol=socket -uroot -p"$ROOT_PW" <<EOF
DROP DATABASE IF EXISTS \`$DB_NAME\`;
DROP USER IF EXISTS '$USER_NAME'@'localhost';
FLUSH PRIVILEGES;
EOF
succ "Base de données et utilisateur SQL supprimés"

# ─── 2) SUPPRESSION DE LA CONFIGURATION NGINX ───────────────────
if [[ -f "$VHOST" ]]; then
  sudo rm -f "$VHOST" && succ "vHost supprimé : $VHOST"
  sudo nginx -t && sudo systemctl reload nginx && succ "nginx rechargé"
else
  info "Aucun vHost nginx trouvé pour $USER_NAME"
fi

# ─── 3) SUPPRESSION DU DOSSIER WEB ──────────────────────────────
if [[ -d "$WEB_DIR" ]]; then
  sudo rm -rf "$WEB_DIR" && succ "Dossier web supprimé : $WEB_DIR"
else
  info "Dossier web déjà absent : $WEB_DIR"
fi

# ─── 4) SUPPRESSION CONFIG FTP vsftpd ───────────────────────────
VSFTP_CONF="/etc/vsftpd_user_conf/${USER_NAME}"
if [[ -f "$VSFTP_CONF" ]]; then
  sudo rm -f "$VSFTP_CONF" && succ "Fichier FTP vsftpd supprimé"
fi
sudo systemctl restart vsftpd && succ "vsftpd rechargé"

# ─── 5) SUPPRESSION CONFIG SAMBA ────────────────────────────────
if grep -q "^\[$USER_NAME\]" /etc/samba/smb.conf; then
  sudo sed -i "/^\[$USER_NAME\]/,/^$/d" /etc/samba/smb.conf
  sudo smbpasswd -x "$USER_NAME" &>/dev/null || true
  sudo systemctl restart smb nmb && succ "Configuration Samba supprimée"
else
  info "Aucune section Samba pour $USER_NAME"
fi

# ─── 6) SUPPRESSION DU QUOTA ────────────────────────────────────
if sudo setquota -u "$USER_NAME" 0 0 0 0 /var/www; then
  succ "Quota réinitialisé pour $USER_NAME"
else
  info "Aucun quota actif ou déjà supprimé"
fi

# ─── 7) SUPPRESSION DE L'UTILISATEUR SYSTÈME ────────────────────
if id "$USER_NAME" &>/dev/null; then
  sudo userdel -r "$USER_NAME" && succ "Utilisateur système supprimé"
else
  info "Utilisateur système inexistant"
fi

# ─── FIN ────────────────────────────────────────────────────────
succ "Toutes les configurations liées à '$USER_NAME' ont été supprimées avec succès."
