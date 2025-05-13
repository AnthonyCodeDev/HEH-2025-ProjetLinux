#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

### —───────────────────────────────────
### Vérification d’exécution en root
### —───────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en tant que root. Utilisez sudo." >&2
  exit 1
fi

### —───────────────────────────────────
### Couleurs & helpers
### —───────────────────────────────────
RED=$'\e[31m'; GREEN=$'\e[32m'; BLUE=$'\e[34m'; RESET=$'\e[0m'

err() {
  printf "%b[ERREUR] %s%b\n\n" "${RED}" "${1}" "${RESET}" >&2
  exit 1
}

succ() {
  printf "%b[OK]    %s%b\n" "${GREEN}" "${1}" "${RESET}"
}

info() {
  printf "%b[INFO]   %s%b\n" "${BLUE}" "${1}" "${RESET}"
}

### —───────────────────────────────────
### CONFIGURATION GÉNÉRALE
### —───────────────────────────────────
SCRIPT_PATH="/usr/local/bin/backup_script.sh"
REMOTE_USER="backup"
REMOTE_HOST="10.42.0.248"
SSHPASS="pxmiXvkEte808X"
REMOTE_BASE_DIR="/backups"
LOGFILE="/var/log/backup_script.log"
# On inclut maintenant l’heure pour différencier chaque archive
DATE=$(date +%Y%m%d_%H%M%S)

### —───────────────────────────────────
### 0) Vérifications et création de l’utilisateur backup
### —───────────────────────────────────
[ -f "$SCRIPT_PATH" ] || err "Le fichier $SCRIPT_PATH est introuvable."
succ "Script trouvé : $SCRIPT_PATH"

if id "$REMOTE_USER" &>/dev/null; then
  succ "Utilisateur '$REMOTE_USER' trouvé"
else
  info "Utilisateur '$REMOTE_USER' introuvable, création..."
  useradd -m -s /bin/bash "$REMOTE_USER"
  echo "${REMOTE_USER}:${SSHPASS}" | chpasswd
  succ "Utilisateur '$REMOTE_USER' créé avec home et shell /bin/bash"
fi

### —───────────────────────────────────
### 0.1) Ajout dans sudoers pour mkdir/chown
### —───────────────────────────────────
SUDOERS_FILE="/etc/sudoers.d/${REMOTE_USER}"
if [ ! -f "$SUDOERS_FILE" ]; then
  cat > "$SUDOERS_FILE" <<EOF
# Permet à backup de créer et chown sous $REMOTE_BASE_DIR sans mot de passe
${REMOTE_USER} ALL=(root) NOPASSWD: /usr/bin/mkdir, /usr/bin/chown
EOF
  chmod 440 "$SUDOERS_FILE"
  succ "Fichier sudoers créé: $SUDOERS_FILE"
else
  succ "Sudoers déjà en place: $SUDOERS_FILE"
fi

### —───────────────────────────────────
### 1) Détection du gestionnaire de paquets
### —───────────────────────────────────
. /etc/os-release 2>/dev/null || true
case "${ID:-}-${VERSION_ID:-}" in
  amzn-2*)                           PKG_MGR=yum;;
  amzn-2023*|rhel*|centos*|fedora*) PKG_MGR=dnf;;
  *)                                 PKG_MGR=$(command -v dnf||command -v yum||echo apt-get);;
esac
succ "Gestionnaire détecté : $PKG_MGR"

### —───────────────────────────────────
### 2) Installation de sshpass et cronie (si nécessaire)
### —───────────────────────────────────
info "→ Installation de sshpass et cronie (si nécessaire)"
if ! command -v sshpass &>/dev/null; then
  $PKG_MGR install -y sshpass
  succ "sshpass installé"
else
  succ "sshpass déjà installé"
fi

if ! rpm -q cronie &>/dev/null; then
  $PKG_MGR install -y cronie
  succ "cronie installé"
else
  succ "cronie déjà installé"
fi

### —───────────────────────────────────
### 3) Activation et démarrage du service cron
### —───────────────────────────────────
if systemctl status crond.service &>/dev/null; then
  CRON_SVC="crond.service"
elif systemctl status cronie.service &>/dev/null; then
  CRON_SVC="cronie.service"
else
  err "Service cron non trouvé (ni crond.service ni cronie.service)"
fi

info "→ Activation et démarrage de ${CRON_SVC}"
systemctl enable --now "$CRON_SVC" \
  && succ "${CRON_SVC} activé et démarré" \
  || err "Impossible d'activer ou démarrer ${CRON_SVC}"

### —───────────────────────────────────
### 4) Préparation du fichier de log
### —───────────────────────────────────
if [ ! -f "$LOGFILE" ]; then
  touch "$LOGFILE"
  chown root:root "$LOGFILE"
  chmod 600 "$LOGFILE"
  succ "Fichier de log créé : $LOGFILE"
else
  succ "Fichier de log existant : $LOGFILE"
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

### —───────────────────────────────────
### 5) Mise à jour de la crontab de backup (sans doublons)
### —───────────────────────────────────
info "→ Mise à jour de la crontab de l’utilisateur $REMOTE_USER"
CRON_TMP=$(mktemp)
crontab -l -u "$REMOTE_USER" 2>/dev/null > "$CRON_TMP" || true

declare -a JOBS=(
  "# Sauvegarde hebdomadaire du /root chaque lundi à 02h00"
  "0 2 * * 1 $SCRIPT_PATH root"
  "# Sauvegarde hebdomadaire du /home chaque lundi à 03h00"
  "0 3 * * 1 $SCRIPT_PATH home"
  "# Sauvegarde quotidienne du /var/www chaque jour à minuit"
  "0 0 * * * $SCRIPT_PATH var-www"
)

for LINE in "${JOBS[@]}"; do
  if ! grep -Fxq "$LINE" "$CRON_TMP"; then
    echo "$LINE" >> "$CRON_TMP"
    succ "Ajouté dans crontab ($REMOTE_USER): $LINE"
  else
    info "Déjà présent dans crontab ($REMOTE_USER): $LINE"
  fi
done

crontab -u "$REMOTE_USER" "$CRON_TMP"
rm -f "$CRON_TMP"
succ "Crontab de '$REMOTE_USER' mise à jour"

### —───────────────────────────────────
### 6) Exécution des backups (si argument fourni)
### —───────────────────────────────────
backup_dir() {
  local SRC="$1"; local TYPE="$2"
  local FILENAME="${TYPE}_backup_${DATE}.tar.gz"
  local LOCAL_TMP="/tmp/${FILENAME}"

  log "▶ Début backup « ${TYPE} » de ${SRC}"
  [ -d "$SRC" ] || { log "❌ Répertoire source $SRC introuvable."; err "Répertoire source $SRC introuvable."; }

  # Création de l'archive
  tar -czf "$LOCAL_TMP" -C "$SRC" . \
    && { log "✅ Archive $FILENAME créée."; succ "Archive $FILENAME créée."; } \
    || { log "❌ Échec création archive."; err "Échec création de l’archive."; }

  # Préparation du répertoire distant
  sshpass -p "$SSHPASS" ssh -o StrictHostKeyChecking=no \
    "$REMOTE_USER@$REMOTE_HOST" \
    "sudo mkdir -p '$REMOTE_BASE_DIR/$TYPE' && sudo chown '$REMOTE_USER':'$REMOTE_USER' '$REMOTE_BASE_DIR/$TYPE'" \
    && { log "✅ Répertoire distant prêt : $REMOTE_BASE_DIR/$TYPE"; succ "Répertoire distant prêt."; } \
    || { log "❌ Échec préparation répertoire distant."; err "Impossible de préparer le répertoire distant."; }

  # Transfert
  sshpass -p "$SSHPASS" scp -o StrictHostKeyChecking=no \
    "$LOCAL_TMP" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_BASE_DIR/$TYPE/" \
    && { log "✅ Transfert de $FILENAME terminé."; succ "Transfert de $FILENAME terminé."; } \
    || { log "❌ Échec transfert."; err "Échec du transfert de $FILENAME."; }

  # Nettoyage
  rm -f "$LOCAL_TMP" && { log "✅ Fichier temporaire supprimé."; succ "Fichier temporaire supprimé."; }

  log "✔ Backup « ${TYPE} » terminé."
  succ "Backup « ${TYPE} » terminé avec succès."
}

if [ $# -eq 1 ]; then
  case "$1" in
    root)    backup_dir "/root"    "root"   ;;
    home)    backup_dir "/home"    "home"   ;;
    var-www) backup_dir "/var/www" "var-www";;
    *)       err "Argument invalide : root, home ou var-www." ;;
  esac
fi

exit 0
