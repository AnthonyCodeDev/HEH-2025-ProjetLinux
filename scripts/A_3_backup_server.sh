#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

### —───────────────────────────────────
###  Vérification d’exécution en root
### —───────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en tant que root. Utilisez sudo." >&2
  exit 1
fi

### —───────────────────────────────────
###  Couleurs & helpers
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
###  CONFIGURATION GÉNÉRALE
### —───────────────────────────────────
SCRIPT_PATH="/usr/local/bin/backup_script.sh"
REMOTE_USER="backup"
SSHPASS="pxmiXvkEte808X"
REMOTE_BASE_DIR="/backups"
LOGFILE="/var/log/backup_script.log"
DATE=$(date +%Y%m%d_%H%M%S)

# --- Paramètres base de données MySQL/MariaDB
DB_USER="root"
DB_PASS="votre_mot_de_passe_db"
DB_NAME="nom_de_la_base"
DB_HOST="localhost"
DB_PORT="3306"

# --- Variables à remplir par parsing
REMOTE_HOST=""
BACKUP_TYPE=""

### —───────────────────────────────────
###  Parsing des arguments (IP obligatoire)
### —───────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -ip)
      if [[ -n "${2-}" && ! "$2" =~ ^- ]]; then
        REMOTE_HOST="$2"
        shift 2
      else
        err "L’option -ip requiert une adresse IP en argument."
      fi
      ;;
    *)
      if [[ -z "$BACKUP_TYPE" ]]; then
        BACKUP_TYPE="$1"
        shift
      else
        err "Argument inattendu : $1"
      fi
      ;;
  esac
done

# Vérification que -ip et le type de backup sont présents
if [[ -z "$REMOTE_HOST" ]]; then
  err "Le paramètre -ip <IP_SERVEUR> est obligatoire."
fi
if [[ -z "$BACKUP_TYPE" ]]; then
  err "Vous devez indiquer le type de backup (root, home, var-www, logs, db, services, users ou all)."
fi

### —───────────────────────────────────
###  0) Vérifications et création de l’utilisateur backup
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
###  0.1) Ajout dans sudoers pour mkdir/chown
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
###  1) Détection du gestionnaire de paquets
### —───────────────────────────────────
. /etc/os-release 2>/dev/null || true
case "${ID:-}-${VERSION_ID:-}" in
  amzn-2*)                           PKG_MGR=yum;;
  amzn-2023*|rhel*|centos*|fedora*) PKG_MGR=dnf;;
  *)                                 PKG_MGR=$(command -v dnf||command -v yum||echo apt-get);;
esac
succ "Gestionnaire détecté : $PKG_MGR"

### —───────────────────────────────────
###  2) Installation des dépendances
### —───────────────────────────────────
info "→ Installation de sshpass, cronie et client MySQL/MariaDB si nécessaire"
# sshpass
if ! command -v sshpass &>/dev/null; then
  $PKG_MGR install -y sshpass
  succ "sshpass installé"
else
  succ "sshpass déjà installé"
fi

# cronie ou cron
if ! rpm -q cronie &>/dev/null && ! dpkg -l cron &>/dev/null; then
  $PKG_MGR install -y cronie
  succ "cronie installé"
else
  succ "cronie déjà installé"
fi

# mysqldump
if ! command -v mysqldump &>/dev/null; then
  if [[ "$PKG_MGR" == "apt-get" ]]; then
    $PKG_MGR install -y mariadb-client
  else
    $PKG_MGR install -y mariadb
  fi
  succ "Client MySQL/MariaDB installé"
else
  succ "mysqldump déjà disponible"
fi

### —───────────────────────────────────
###  3) Activation et démarrage du service cron
### —───────────────────────────────────
info "→ Activation et démarrage du service cron"
systemctl daemon-reload
if systemctl enable --now crond.service &>/dev/null; then
  succ "Service crond.service activé et démarré"
elif systemctl enable --now cron.service &>/dev/null; then
  succ "Service cron.service activé et démarré"
elif systemctl enable --now cronie.service &>/dev/null; then
  succ "Service cronie.service activé et démarré"
else
  err "Impossible d’activer ou démarrer un service cron"
fi

### —───────────────────────────────────
###  4) Préparation du fichier de log
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
###  5) Mise à jour de la crontab de backup (sans doublons)
### —───────────────────────────────────
info "→ Mise à jour de la crontab de l’utilisateur $REMOTE_USER"
CRON_TMP=$(mktemp)
crontab -l -u "$REMOTE_USER" 2>/dev/null > "$CRON_TMP" || true

declare -a JOBS=(
  "# Sauvegarde hebdomadaire du /root chaque lundi à 02h00"
  "0 2 * * 1 $SCRIPT_PATH root -ip $REMOTE_HOST"
  "# Sauvegarde hebdomadaire du /home chaque lundi à 03h00"
  "0 3 * * 1 $SCRIPT_PATH home -ip $REMOTE_HOST"
  "# Sauvegarde quotidienne du /var/www chaque jour à minuit"
  "0 0 * * * $SCRIPT_PATH var-www -ip $REMOTE_HOST"
  "# Sauvegarde quotidienne de la base de données chaque jour à 01h00"
  "0 1 * * * $SCRIPT_PATH db -ip $REMOTE_HOST"
  "# Sauvegarde quotidienne des logs chaque jour à 02h00"
  "0 2 * * * $SCRIPT_PATH logs -ip $REMOTE_HOST"
  "# Sauvegarde quotidienne de la liste des services chaque jour à 03h00"
  "0 3 * * * $SCRIPT_PATH services -ip $REMOTE_HOST"
  "# Sauvegarde quotidienne de la liste des utilisateurs chaque jour à 04h00"
  "0 4 * * * $SCRIPT_PATH users -ip $REMOTE_HOST"
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
###  Fonctions de backup
### —───────────────────────────────────
backup_dir() {
  local SRC="$1" TYPE="$2"
  local FILENAME="${TYPE}_backup_${DATE}.tar.gz"
  local LOCAL_TMP="/tmp/${FILENAME}"

  log "▶ Début backup « ${TYPE} » de ${SRC}"
  [ -d "$SRC" ] || { log "❌ Répertoire source $SRC introuvable."; err "Répertoire source $SRC introuvable."; }

  tar -czf "$LOCAL_TMP" -C "$SRC" . \
    && { log "✅ Archive $FILENAME créée."; succ "Archive $FILENAME créée."; } \
    || { log "❌ Échec création archive."; err "Échec création de l’archive."; }

  sshpass -p "$SSHPASS" ssh -o StrictHostKeyChecking=no \
    "$REMOTE_USER@$REMOTE_HOST" \
    "sudo mkdir -p '$REMOTE_BASE_DIR/$TYPE' && sudo chown '$REMOTE_USER':'$REMOTE_USER' '$REMOTE_BASE_DIR/$TYPE'" \
    && { log "✅ Répertoire distant prêt : $REMOTE_BASE_DIR/$TYPE"; succ "Répertoire distant prêt."; } \
    || { log "❌ Échec prépa dir distant."; err "Impossible de préparer le répertoire distant."; }

  sshpass -p "$SSHPASS" scp -o StrictHostKeyChecking=no \
    "$LOCAL_TMP" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_BASE_DIR/$TYPE/" \
    && { log "✅ Transfert de $FILENAME terminé."; succ "Transfert de $FILENAME terminé."; } \
    || { log "❌ Échec transfert."; err "Échec du transfert de $FILENAME."; }

  rm -f "$LOCAL_TMP" && { log "✅ Fichier temporaire supprimé."; succ "Fichier temporaire supprimé."; }
  log "✔ Backup « ${TYPE} » terminé."
  succ "Backup « ${TYPE} » terminé avec succès."
}

backup_db() {
  local FILENAME="db_backup_${DATE}.sql.gz"
  local LOCAL_TMP="/tmp/${FILENAME}"

  log "▶ Début backup de la base '${DB_NAME}'"
  mysqldump -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -P "$DB_PORT" "$DB_NAME" | gzip > "$LOCAL_TMP" \
    && { log "✅ Dump DB créé."; succ "Dump DB créé."; } \
    || { log "❌ Échec dump base de données."; err "Échec du dump de la base de données."; }

  sshpass -p "$SSHPASS" ssh -o StrictHostKeyChecking=no \
    "$REMOTE_USER@$REMOTE_HOST" \
    "sudo mkdir -p '$REMOTE_BASE_DIR/db' && sudo chown '$REMOTE_USER':'$REMOTE_USER' '$REMOTE_BASE_DIR/db'" \
    && { log "✅ Répertoire distant prêt : $REMOTE_BASE_DIR/db"; succ "Répertoire distant prêt."; } \
    || { log "❌ Échec prépa dir distant."; err "Impossible de préparer le répertoire distant."; }

  sshpass -p "$SSHPASS" scp -o StrictHostKeyChecking=no \
    "$LOCAL_TMP" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_BASE_DIR/db/" \
    && { log "✅ Transfert de $FILENAME terminé."; succ "Transfert de $FILENAME terminé."; } \
    || { log "❌ Échec transfert."; err "Échec du transfert de $FILENAME."; }

  rm -f "$LOCAL_TMP" && { log "✅ Fichier temporaire supprimé."; succ "Fichier temporaire supprimé."; }
  log "✔ Backup de la base terminée."
  succ "Backup de la base de données terminé avec succès."
}

backup_services() {
  local FILENAME="services_list_${DATE}.txt"
  local LOCAL_TMP="/tmp/${FILENAME}"

  log "▶ Début backup liste des services"
  systemctl list-unit-files > "$LOCAL_TMP" \
    && { log "✅ Liste des services enregistrée."; succ "Liste des services enregistrée."; } \
    || { log "❌ Échec génération liste services."; err "Échec génération de la liste des services."; }

  sshpass -p "$SSHPASS" ssh -o StrictHostKeyChecking=no \
    "$REMOTE_USER@$REMOTE_HOST" \
    "sudo mkdir -p '$REMOTE_BASE_DIR/services' && sudo chown '$REMOTE_USER':'$REMOTE_USER' '$REMOTE_BASE_DIR/services'" \
    && { log "✅ Répertoire distant prêt : $REMOTE_BASE_DIR/services"; succ "Répertoire distant prêt."; } \
    || { log "❌ Échec prépa dir distant."; err "Impossible de préparer le répertoire distant."; }

  sshpass -p "$SSHPASS" scp -o StrictHostKeyChecking=no \
    "$LOCAL_TMP" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_BASE_DIR/services/" \
    && { log "✅ Transfert de $FILENAME terminé."; succ "Transfert de $FILENAME terminé."; } \
    || { log "❌ Échec transfert."; err "Échec du transfert de $FILENAME."; }

  rm -f "$LOCAL_TMP" && { log "✅ Fichier temporaire supprimé."; succ "Fichier temporaire supprimé."; }
  log "✔ Backup des services terminé."
  succ "Backup de la liste des services terminé avec succès."
}

backup_users() {
  local FILENAME="users_list_${DATE}.txt"
  local LOCAL_TMP="/tmp/${FILENAME}"

  log "▶ Début backup liste des utilisateurs"
  getent passwd > "$LOCAL_TMP" \
    && { log "✅ Liste des utilisateurs enregistrée."; succ "Liste des utilisateurs enregistrée."; } \
    || { log "❌ Échec génération liste utilisateurs."; err "Échec génération de la liste des utilisateurs."; }

  sshpass -p "$SSHPASS" ssh -o StrictHostKeyChecking=no \
    "$REMOTE_USER@$REMOTE_HOST" \
    "sudo mkdir -p '$REMOTE_BASE_DIR/users' && sudo chown '$REMOTE_USER':'$REMOTE_USER' '$REMOTE_BASE_DIR/users'" \
    && { log "✅ Répertoire distant prêt : $REMOTE_BASE_DIR/users"; succ "Répertoire distant prêt."; } \
    || { log "❌ Échec prépa dir distant."; err "Impossible de préparer le répertoire distant."; }

  sshpass -p "$SSHPASS" scp -o StrictHostKeyChecking=no \
    "$LOCAL_TMP" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_BASE_DIR/users/" \
    && { log "✅ Transfert de $FILENAME terminé."; succ "Transfert de $FILENAME terminé."; } \
    || { log "❌ Échec transfert."; err "Échec du transfert de $FILENAME."; }

  rm -f "$LOCAL_TMP" && { log "✅ Fichier temporaire supprimé."; succ "Fichier temporaire supprimé."; }
  log "✔ Backup des utilisateurs terminé."
  succ "Backup de la liste des utilisateurs terminé avec succès."
}

### —───────────────────────────────────
###  6) Exécution du backup demandé
### —───────────────────────────────────
if [[ "$BACKUP_TYPE" == "all" ]]; then
  succ "Lancement de TOUS les backups…"
  backup_dir "/root"    "root"
  backup_dir "/home"    "home"
  backup_dir "/var/www" "var-www"
  backup_dir "/var/log" "logs"
  backup_db
  backup_services
  backup_users
  succ "Tous les backups sont terminés !"
  exit 0
fi

case "$BACKUP_TYPE" in
  root)     backup_dir "/root"    "root"    ;;
  home)     backup_dir "/home"    "home"    ;;
  var-www)  backup_dir "/var/www" "var-www" ;;
  logs)     backup_dir "/var/log" "logs"    ;;
  db)       backup_db                        ;;
  services) backup_services                  ;;
  users)    backup_users                     ;;
  *)        err "Argument invalide : root, home, var-www, logs, db, services, users ou all." ;;
esac

exit 0
