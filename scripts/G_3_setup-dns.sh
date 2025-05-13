#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-dns-private.sh — Installe et configure un DNS maître + cache + reverse
# Strictement privé : uniquement accessible sur 10.42.0.0/16
# Pour Amazon Linux 2 / RHEL / CentOS (yum)
# -----------------------------------------------------------------------------
set -euo pipefail

### ─── COULEURS ───────────────────────────────────────────────────────────────
CSI="\033["
RESET="${CSI}0m"
BOLD="${CSI}1m"
RED="${CSI}31m"
GREEN="${CSI}32m"
YELLOW="${CSI}33m"
BLUE="${CSI}34m"
MAGENTA="${CSI}35m"
CYAN="${CSI}36m"

info()     { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success()  { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()     { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()    { echo -e "${RED}[ERROR]${RESET} $*"; }

## ─── CONFIGURATION ────────────────────────────────────────────────────────────
DOMAIN="heh.lan"
NS_LABEL="master"
PRIVATE_NET="10.42.0.0/16"
PRIVATE_IP="10.42.0.157"
REVERSE_ZONE="0.42.10.in-addr.arpa"
ZONE_DIR="/var/named"
ADMIN_EMAIL="admin.${DOMAIN}"
LOG_DIR="/var/log/named"
## ──────────────────────────────────────────────────────────────────────────────

# 0) Droits
if [ "$EUID" -ne 0 ]; then
  error "Lancez ce script avec sudo ou en root."
  exit 1
fi

# 1) Installer bind, SELinux tools et firewalld
info "Installation des paquets nécessaires"
yum update -y &>/dev/null
yum install -y bind bind-utils policycoreutils-python-utils firewalld &>/dev/null
success "Paquets installés"

# 2) Configurer firewalld pour n’autoriser DNS que sur le LAN
info "Activation de firewalld et ouverture du DNS pour ${PRIVATE_NET}"
systemctl enable --now firewalld
firewall-cmd --permanent \
  --add-rich-rule="rule family='ipv4' source address='${PRIVATE_NET}' port protocol='tcp' port='53' accept"
firewall-cmd --permanent \
  --add-rich-rule="rule family='ipv4' source address='${PRIVATE_NET}' port protocol='udp' port='53' accept"
firewall-cmd --reload
success "Firewall configuré"

# 3) Création du répertoire de logs et permissions
info "Création des logs BIND"
mkdir -p "${LOG_DIR}"
touch "${LOG_DIR}/query.log" "${LOG_DIR}/debug.log"
chown named:named "${LOG_DIR}"/*.log
chmod 640 "${LOG_DIR}"/*.log
success "Répertoire de logs prêt"

# 4) Sauvegarde de la conf BIND existante
info "Sauvegarde de /etc/named.conf"
cp -p /etc/named.conf /etc/named.conf.bak.$(date +%Y%m%d%H%M)
success "Sauvegarde de named.conf effectuée"

# 5) Serial basé sur la date
SERIAL="$(date +%Y%m%d)01"

# 6) Écrire /etc/named.conf
info "Mise à jour de /etc/named.conf (écoute et requêtes restreintes au LAN)"
cat > /etc/named.conf <<EOF
options {
    directory       "${ZONE_DIR}";
    recursion       yes;
    allow-query     { 127.0.0.1; ${PRIVATE_NET}; };
    allow-recursion { 127.0.0.1; ${PRIVATE_NET}; };
    forwarders      { 8.8.8.8; 8.8.4.4; };
    dnssec-validation auto;
    auth-nxdomain no;      /* conforme RFC1035 */
    version "none";        /* ne pas divulguer la version de BIND */
    listen-on port 53 { 127.0.0.1; ${PRIVATE_IP}; };
    listen-on-v6 port 53 { ::1; };
};

logging {
    channel querylog {
        file      "${LOG_DIR}/query.log" versions 3 size 20m;
        severity  info;
        print-time yes;
    };
    channel debuglog {
        file      "${LOG_DIR}/debug.log" versions 3 size 20m;
        severity  debug;
        print-time yes;
    };
    category queries  { querylog; };
    category default  { debuglog; };
};

zone "." IN {
    type hint;
    file "named.ca";
};

zone "${DOMAIN}" IN {
    type master;
    file "${DOMAIN}.db";
    allow-update { none; };
};

zone "${REVERSE_ZONE}" IN {
    type master;
    file "db.${REVERSE_ZONE}";
    allow-update { none; };
};
EOF
success "named.conf mis à jour"

# 7) Création des fichiers de zone
info "Création des zones dans ${ZONE_DIR}"
mkdir -p "${ZONE_DIR}"
cd "${ZONE_DIR}"

# zone directe
cat > "${DOMAIN}.db" <<EOF
\$ORIGIN ${DOMAIN}.
\$TTL 86400
@   IN SOA ${NS_LABEL}.${DOMAIN}. ${ADMIN_EMAIL}. (
      ${SERIAL} ; serial
      3600      ; refresh
      1800      ; retry
      604800    ; expire
      86400 )   ; minimum
    IN NS ${NS_LABEL}.${DOMAIN}.
*      IN A ${PRIVATE_IP}
@      IN A ${PRIVATE_IP}
EOF

# zone inverse
LAST_OCTET="${PRIVATE_IP##*.}"
cat > "db.${REVERSE_ZONE}" <<EOF
\$ORIGIN ${REVERSE_ZONE}.
\$TTL 86400
@   IN SOA ${NS_LABEL}.${DOMAIN}. ${ADMIN_EMAIL}. (
      ${SERIAL} ; serial
      3600      ; refresh
      1800      ; retry
      604800    ; expire
      86400 )   ; minimum
    IN NS ${NS_LABEL}.${DOMAIN}.
${LAST_OCTET} IN PTR ${NS_LABEL}.${DOMAIN}.
EOF
success "Fichiers de zone créés"

# 8) Permissions et SELinux
info "Ajustement des permissions et contexte SELinux"
chown named:named "${ZONE_DIR}/${DOMAIN}.db" "${ZONE_DIR}/db.${REVERSE_ZONE}"
chmod 640 "${ZONE_DIR}/${DOMAIN}.db" "${ZONE_DIR}/db.${REVERSE_ZONE}"
semanage fcontext -a -t named_zone_t "${ZONE_DIR}(/.*)?" 2>/dev/null || true
semanage fcontext -m -t named_zone_t "${ZONE_DIR}(/.*)?" 2>/dev/null || true
restorecon -Rv "${ZONE_DIR}" &>/dev/null
success "Permissions et SELinux OK"

# 9) Validation et rechargement
info "Vérification de la configuration BIND"
named-checkconf -z
named-checkzone "${DOMAIN}" "${ZONE_DIR}/${DOMAIN}.db"
named-checkzone "${REVERSE_ZONE}" "${ZONE_DIR}/db.${REVERSE_ZONE}"
success "Validation réussie"

info "Activation et rechargement de named"
systemctl enable --now named
rndc reconfig
success "named actif et configuration rechargée"

# 10) Récapitulatif
echo -e "\n${MAGENTA}${BOLD}✅ DNS privé '${DOMAIN}' configuré${RESET}"
echo "• Serveur DNS     : ${PRIVATE_IP} (accessible uniquement sur ${PRIVATE_NET})"
echo "• Tous les sous-domaines *.${DOMAIN} → ${PRIVATE_IP}"
echo -e "Testez avec : ${CYAN}dig @${PRIVATE_IP} any.${DOMAIN} A${RESET}"
