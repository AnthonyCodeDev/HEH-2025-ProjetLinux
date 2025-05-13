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
### 5) Installation et configuration de ClamAV
### ——————————————————————————
info "→ Mise à jour de tous les paquets"
$PKG_MGR update -y

info "→ Installation de ClamAV et composants"
$PKG_MGR install -y clamav clamav-update clamav-scanner-systemd || err "Échec installation ClamAV"

# Génération automatique de /etc/clamd.d/scan.conf
info "→ Création du fichier de configuration clamd@scan"
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

# ——————————————————————————
# Création du groupe/utilisateur clamd s’ils n’existent pas
# ——————————————————————————
if ! getent group clamd >/dev/null; then
  info "Création du groupe clamd…"
  groupadd --system clamd || err "Impossible de créer le groupe clamd"
  succ "Groupe clamd créé"
else
  succ "Groupe clamd déjà présent"
fi

if ! id -u clamd >/dev/null 2>&1; then
  info "Création de l’utilisateur clamd…"
  useradd --system --no-create-home --shell /sbin/nologin --gid clamd clamd \
    || err "Impossible de créer l’utilisateur clamd"
  succ "Utilisateur clamd créé"
else
  succ "Utilisateur clamd déjà présent"
fi

# Préparation des dossiers nécessaires et réglage des permissions
mkdir -p /var/run/clamd.scan /var/log/clamav
chown -R clamd:clamd /var/run/clamd.scan /var/log/clamav || err "Échec chown sur clamd:clamd"
succ "Répertoires /var/run/clamd.scan et /var/log/clamav prêts"

info "→ Mise à jour de la base de signatures"
freshclam || err "freshclam a échoué"

info "→ Recharger systemd"
systemctl daemon-reload

info "→ Activation et démarrage de clamd@scan"
systemctl enable --now clamd@scan || err "Impossible d’activer clamd@scan"

info "→ Exécution d’un scan complet de /home"
clamscan -r /home --log=/var/log/clamav/home-scan.log || err "Scan de /home échoué"

info "→ Activation du timer clamd@scan pour scan quotidien"
systemctl enable --now clamd@scan.timer || err "Impossible d’activer clamd@scan.timer"

succ "ClamAV installé et configuré (scan initial de /home, timer actif)"

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
  info "Initialisation de la base AIDE…"
  aide --init || err "Échec init AIDE"
  mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
  succ "Base AIDE initialisée"
else
  succ "Base AIDE déjà présente"
fi

if ! crontab -u root -l 2>/dev/null | grep -q "aide --check"; then
  ( crontab -u root -l 2>/dev/null; echo "0 4 * * * aide --check --log=/var/log/aide/aide.log" ) | crontab -u root -
  succ "Cron AIDE ajouté (vérif quotidienne à 04h)"
else
  succ "Cron AIDE déjà configuré"
fi

### ——————————————————————————
### Fin
### ——————————————————————————
succ "Sécurisation terminée : pare-feu, SSH, SELinux, ClamAV, Fail2Ban, AIDE."
