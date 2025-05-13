#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# If executed with sh, re-exec under bash
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

### ——————————————————————————
### Vérification d’exécution en root
### ——————————————————————————
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en tant que root." >&2
  exit 1
fi

### ——————————————————————————
### Couleurs & helpers
### ——————————————————————————
RED=$'\e[31m'; GREEN=$'\e[32m'; BLUE=$'\e[34m'; RESET=$'\e[0m'
err()   { printf "%b[ERREUR] %s%b\n"   "$RED"   "$1" "$RESET" >&2; exit 1; }
succ()  { printf "%b[OK]      %s%b\n"   "$GREEN" "$1" "$RESET"; }
info()  { printf "%b[INFO]    %s%b\n"   "$BLUE"  "$1" "$RESET"; }

### ——————————————————————————
### 1) Détection du gestionnaire de paquets & plateforme
### ——————————————————————————
. /etc/os-release 2>/dev/null || true
case "${ID:-}-${VERSION_ID:-}" in
  amzn-2*|rhel*|centos*|fedora*)
    PKG_MGR="yum"; FIREWALLD=yes;;
  amzn-2023*)
    PKG_MGR="dnf"; FIREWALLD=yes;;
  ubuntu*|debian*)
    PKG_MGR="apt-get"; FIREWALLD=no;;
  *)
    PKG_MGR=$(command -v dnf || command -v yum || echo apt-get)
    FIREWALLD=no;;
esac
info "Gestionnaire de paquets : $PKG_MGR"

install_if_missing() {
  local bin="$1" pkg="$2"
  if ! command -v "$bin" &>/dev/null; then
    info "Installation de $pkg…"
    $PKG_MGR install -y "$pkg" || err "Impossible d’installer $pkg"
    succ "$pkg installé"
  else
    succ "$pkg déjà présent"
  fi
}

### ——————————————————————————
### 2) Pare-feu (firewalld ou ufw)
### ——————————————————————————
if [ "$FIREWALLD" = yes ]; then
  install_if_missing firewall-cmd firewalld
  systemctl enable --now firewalld
  succ "firewalld activé"
  for svc in ssh http https; do
    firewall-cmd --permanent --add-service="$svc" && succ "Ouvert $svc" || err "Échec ouverture $svc"
  done
  firewall-cmd --reload && succ "firewalld rechargé"
else
  install_if_missing ufw ufw
  ufw default deny incoming
  ufw default allow outgoing
  for port in 22/tcp 80/tcp 443/tcp; do
    ufw allow "$port" && succ "ufw : autorisé $port" || err "ufw : échec $port"
  done
  ufw --force enable && succ "ufw activé"
fi

### ——————————————————————————
### 3) Renforcement SSH
### ——————————————————————————
SSHD_CONF=/etc/ssh/sshd_config
info "Hardening SSH…"
cp -n "$SSHD_CONF" "$SSHD_CONF.bak"
sed -i \
  -e 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
  -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
  -e 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
  "$SSHD_CONF"
systemctl reload sshd && succ "sshd rechargé (root désactivé, auth par clé)"

### ——————————————————————————
### 4) SELinux en mode enforcing
### ——————————————————————————
if command -v getenforce &>/dev/null; then
  info "Configuration SELinux…"
  if grep -q "^SELINUX=enforcing" /etc/selinux/config; then
    succ "SELinux déjà en enforcing"
  else
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    succ "/etc/selinux/config mis à jour"
  fi
  setenforce 1 && succ "SELinux passé en enforcing"
else
  info "SELinux non disponible"
fi

### ——————————————————————————
### 5) Installation et configuration de ClamAV (installé mais service non démarré)
### ——————————————————————————
info "→ Mise à jour de tous les paquets"
$PKG_MGR update -y

info "→ Installation de ClamAV et composants"
$PKG_MGR install -y clamav clamav-update clamav-scanner-systemd || err "Échec installation ClamAV"

info "→ Génération de /etc/clamd.d/scan.conf"
cat > /etc/clamd.d/scan.conf <<EOF
# clamd@scan instance configuration
LogFile /var/log/clamav/clamd.scan.log
LocalSocket /var/run/clamd.scan/clamd.sock
FixStaleSocket yes
# Exécuter sous l'utilisateur et le groupe 'clamd'
User clamd
ScanArchive yes
ArchiveBlockEncrypted no
LogVerbose yes
EOF
succ "/etc/clamd.d/scan.conf généré"

info "→ Création du groupe/utilisateur clamd si manquant"
if ! getent group clamd >/dev/null; then
  groupadd --system clamd || err "Impossible de créer le groupe clamd"
  succ "Groupe clamd créé"
else
  succ "Groupe clamd déjà présent"
fi
if ! id -u clamd >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /sbin/nologin --gid clamd clamd \
    || err "Impossible de créer l’utilisateur clamd"
  succ "Utilisateur clamd créé"
else
  succ "Utilisateur clamd déjà présent"
fi

info "→ Préparation des dossiers et permissions"
mkdir -p /var/run/clamd.scan /var/log/clamav
chown -R clamd:clamd /var/run/clamd.scan /var/log/clamav || err "Échec chown clamd:clamd"
succ "Répertoires prêts (/var/run/clamd.scan, /var/log/clamav)"

info "→ Mise à jour des signatures"
freshclam || err "freshclam a échoué"
succ "Signatures ClamAV à jour"

info "→ Systemd rechargé"
systemctl daemon-reload

# Note : ClamAV installé et configuré, mais les commandes de démarrage/enable sont volontairement omises
succ "ClamAV installé et configuré (service non activé)"

### ——————————————————————————
### 6) Fail2Ban
### ——————————————————————————
install_if_missing fail2ban fail2ban
if [ ! -f /etc/fail2ban/jail.local ]; then
  cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF
  succ "jail.local créé pour SSH"
else
  succ "jail.local existant"
fi
systemctl enable --now fail2ban && succ "fail2ban activé"

### ——————————————————————————
### 7) AIDE (intégrité des fichiers)
### ——————————————————————————
install_if_missing aide aide
if [ ! -f /var/lib/aide/aide.db.gz ]; then
  aide --init || err "Échec init AIDE"
  mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
  succ "Base AIDE initialisée"
else
  succ "Base AIDE déjà présente"
fi
### ——————————————————————————
### 8) Installation de cron et planification de la vérification AIDE
### ——————————————————————————
info "→ Vérification et installation de cron (si nécessaire)"
# Vérification de crontab
if command -v crontab &>/dev/null; then
  succ "crontab déjà présent"
else
  if [[ "$PKG_MGR" =~ ^(yum|dnf)$ ]]; then
    $PKG_MGR install -y cronie || err "Impossible d’installer cronie"
    succ "cronie installé"
  else
    $PKG_MGR install -y cron || err "Impossible d’installer cron"
    succ "cron installé"
  fi
fi

# Choix du nom du service en fonction du gestionnaire de paquets
if [[ "$PKG_MGR" =~ ^(yum|dnf)$ ]]; then
  CRON_SVC="crond.service"
else
  CRON_SVC="cron.service"
fi

info "→ Activation et démarrage de ${CRON_SVC}"
systemctl enable --now "${CRON_SVC}" \
  && succ "${CRON_SVC} activé et démarré" \
  || err "Impossible d'activer ou démarrer ${CRON_SVC}"

# Ajout de la tâche cron pour la vérification AIDE quotidienne à 3h
CRON_JOB="0 3 * * * /usr/bin/aide --check >> /var/log/aide-check.log 2>&1"
# On filtre l’ancienne ligne puis on ajoute la nouvelle
( crontab -l 2>/dev/null | grep -Fv "/usr/bin/aide --check" ; echo "${CRON_JOB}" ) | crontab - \
  && succ "Tâche cron AIDE planifiée : ${CRON_JOB}" \
  || err "Échec de l'ajout de la tâche cron AIDE"


### ——————————————————————————
### Fin
### ——————————————————————————
succ "Sécurisation terminée : pare-feu, SSH, SELinux, ClamAV (non activé), Fail2Ban, AIDE."
