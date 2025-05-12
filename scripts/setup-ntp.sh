#!/usr/bin/env bash
# setup_ntp.sh — Installation et configuration sécurisée d'un serveur NTP (Chrony)
# Usage : sudo ./setup_ntp.sh -c <NETWORK_CIDR>
set -euo pipefail
IFS=$'\n\t'

# === Variables ===
NETWORK_CIDR=""       # CIDR autorisé pour la synchronisation NTP
CHRONY_CONF="/etc/chrony.conf"
BACKUP_SUFFIX=".orig.$(date +%Y%m%d%H%M%S)"
AWS_NTP="169.254.169.123"  # AWS Time Sync Service

# === Fonctions ===
usage() {
  cat <<EOF
Usage: sudo $0 -c <NETWORK_CIDR>
  -c  CIDR réseau autorisé pour la synchronisation NTP
EOF
  exit 1
}
require_root() { [[ $EUID -eq 0 ]] || { echo "ERREUR : exécutez en root." >&2; exit 1; } }

# === Arguments ===
while getopts "c:" opt; do
  case "$opt" in
    c) NETWORK_CIDR=$OPTARG ;; 
    *) usage ;; 
  esac
done
[[ -n "$NETWORK_CIDR" ]] || usage
require_root

# === 1. SELinux: enforcing et port NTP ===
if command -v setenforce &>/dev/null; then
  sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config || true
  setenforce 1 || true
fi
command -v semanage &>/dev/null || dnf install -y policycoreutils-python-utils
semanage port -a -t ntp_port_t -p udp 123 2>/dev/null || true

# === 2. Installer Chrony ===
dnf install -y chrony

# === 3. Sauvegarde et configuration de Chrony ===
if [[ ! -e "${CHRONY_CONF}${BACKUP_SUFFIX}" ]]; then
  cp -p "$CHRONY_CONF" "${CHRONY_CONF}${BACKUP_SUFFIX}"
fi
cat > "$CHRONY_CONF" <<EOF
# Configuration NTP générée par setup_ntp.sh

# Sources externes fiables
server ${AWS_NTP} prefer iburst
server 0.pool.ntp.org iburst
server 1.pool.ntp.org iburst

# Autorisation du réseau local
allow ${NETWORK_CIDR}

# Fallback local si aucune source externe accessible
local stratum 10

driftfile /var/lib/chrony/drift
rtcsync
EOF
chmod 600 "$CHRONY_CONF"
chown root:root "$CHRONY_CONF"

# Restaurer le contexte SELinux du fichier de config
command -v restorecon &>/dev/null && restorecon -v "$CHRONY_CONF" || true

# === 4. Pare-feu local ===
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-service=ntp
  firewall-cmd --reload
else
  iptables -C INPUT -p udp --dport 123 -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -p udp --dport 123 -j ACCEPT
  iptables-save > /etc/iptables.rules
fi

# === 5. Activer et démarrer Chrony ===
systemctl enable chronyd
systemctl restart chronyd

# === 6. Vérification ===
echo -e "\n=== Sources Chrony ==="
chronyc sources

echo -e "\n=== Suivi de synchronisation ==="
chronyc tracking

echo -e "\nServeur NTP configuré et sécurisé pour le réseau ${NETWORK_CIDR}."
