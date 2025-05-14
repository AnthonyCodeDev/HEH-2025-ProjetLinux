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

# 0) Vérification des droits
if [ "$EUID" -ne 0 ]; then
  error "Lancez ce script avec sudo ou en root."
  exit 1
fi

# 1) Détection automatique de l'adresse IPv4 privée
PRIVATE_NET="10.42.0.0/16"
info "Détection de l'adresse IPv4 privée sur le réseau ${PRIVATE_NET}"
PRIVATE_IP=$(ip -4 addr show scope global \
  | grep -oP '(?<=inet\s)(10\.42\.(?:[0-9]{1,3}\.){1}[0-9]{1,3})' \
  | head -n1)
if [ -z "$PRIVATE_IP" ]; then
  error "Impossible de détecter l'adresse IPv4 privée (réseau ${PRIVATE_NET})."
  exit 1
fi

# --- début bloc interactif ---
# proposer la confirmation ou la saisie manuelle
read -p "L'adresse IP détectée est ${PRIVATE_IP}. Confirmez-vous ? [O/n] " REPLY
REPLY=${REPLY:-O}
if [[ ! "$REPLY" =~ ^[Oo] ]]; then
  read -p "Veuillez saisir manuellement l'adresse IPv4 à utiliser : " PRIVATE_IP
  # on peut retester rapidement la syntaxe si besoin :
  if ! [[ $PRIVATE_IP =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    error "Format d'adresse invalide : ${PRIVATE_IP}"
    exit 1
  fi
fi
# --- fin bloc interactif ---

success "Adresse privée retenue : ${PRIVATE_IP}"


# 3) Validation de chaque octet (0–255)
IFS='.' read -r o1 o2 o3 o4 <<< "$PRIVATE_IP"
for oct in $o1 $o2 $o3 $o4; do
  if (( oct < 0 || oct > 255 )); then
    error "Octet IPv4 hors plage (0–255) : ${oct}"
    exit 1
  fi
done

## ─── CONFIGURATION ────────────────────────────────────────────────────────────
DOMAIN="heh.lan"
NS_LABEL="master"
PRIVATE_NET="10.42.0.0/16"
REVERSE_ZONE="0.42.10.in-addr.arpa"
ZONE_DIR="/var/named"
ADMIN_EMAIL="admin.${DOMAIN}"
LOG_DIR="/var/log/named"
SERIAL="$(date +%Y%m%d)01"

# 4) Installation des paquets
info "Installation des paquets nécessaires"
yum update -y &>/dev/null
yum install -y bind bind-utils policycoreutils-python-utils firewalld &>/dev/null
success "Paquets installés"

# 5) Configuration de firewalld
info "Activation de firewalld et ouverture du DNS pour ${PRIVATE_NET}"
systemctl enable --now firewalld
firewall-cmd --permanent \
  --add-rich-rule="rule family='ipv4' source address='${PRIVATE_NET}' port protocol='tcp' port='53' accept"
firewall-cmd --permanent \
  --add-rich-rule="rule family='ipv4' source address='${PRIVATE_NET}' port protocol='udp' port='53' accept"
firewall-cmd --reload
success "Firewall configuré"

# 6) Préparation des logs
info "Création des logs BIND"
mkdir -p "${LOG_DIR}"
touch "${LOG_DIR}/query.log" "${LOG_DIR}/debug.log"
chown named:named "${LOG_DIR}"/*.log
chmod 640 "${LOG_DIR}"/*.log
success "Répertoire de logs prêt"

# 7) Sauvegarde de la configuration existante
info "Sauvegarde de /etc/named.conf"
cp -p /etc/named.conf /etc/named.conf.bak.$(date +%Y%m%d%H%M)
success "Sauvegarde effectuée"

# 8) Écriture de /etc/named.conf
info "Mise à jour de /etc/named.conf (écoute et requêtes restreintes)"
cat > /etc/named.conf <<EOF
options {
    directory       "${ZONE_DIR}";
    recursion       yes;
    allow-query     { any; };
    allow-recursion { 127.0.0.1; ${PRIVATE_NET}; };
    forwarders      { 8.8.8.8; 8.8.4.4; };
    dnssec-validation auto;
    auth-nxdomain no;
    version "none";
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

# 9) Création des zones
info "Création des fichiers de zone dans ${ZONE_DIR}"
mkdir -p "${ZONE_DIR}"
cd "${ZONE_DIR}"

# Zone directe
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

# Zone inverse
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

# 10) Permissions et SELinux
info "Ajustement des permissions et contexte SELinux"
chown named:named "${ZONE_DIR}/${DOMAIN}.db" "${ZONE_DIR}/db.${REVERSE_ZONE}"
chmod 640 "${ZONE_DIR}/${DOMAIN}.db" "${ZONE_DIR}/db.${REVERSE_ZONE}"
semanage fcontext -a -t named_zone_t "${ZONE_DIR}(/.*)?" 2>/dev/null || true
semanage fcontext -m -t named_zone_t "${ZONE_DIR}(/.*)?" 2>/dev/null || true
restorecon -Rv "${ZONE_DIR}" &>/dev/null
success "Permissions et SELinux OK"

# 11) Validation et rechargement
info "Vérification de la configuration BIND"
named-checkconf -z
named-checkzone "${DOMAIN}" "${ZONE_DIR}/${DOMAIN}.db"
named-checkzone "${REVERSE_ZONE}" "${ZONE_DIR}/db.${REVERSE_ZONE}"
success "Validation réussie"

info "Activation et rechargement de named"
systemctl enable --now named
rndc reconfig
success "named actif et configuration rechargée"

# 12) Récapitulatif
echo -e "\n${MAGENTA}${BOLD}✅ DNS privé '${DOMAIN}' configuré${RESET}"
echo "• Serveur DNS     : ${PRIVATE_IP} (accessible uniquement sur ${PRIVATE_NET})"
echo "• Tous les sous-domaines *.${DOMAIN} → ${PRIVATE_IP}"
echo -e "Testez avec : ${CYAN}dig @${PRIVATE_IP} any.${DOMAIN} A${RESET}"

# 13) Vérification finale du pare-feu et des zones
firewall-cmd --zone=public --add-service=dns --permanent
firewall-cmd --zone=public --list-services
firewall-cmd --zone=public --list-rich-rules
firewall-cmd --reload

named-checkconf -z
rndc reconfig

named-checkzone "${DOMAIN}" "${ZONE_DIR}/${DOMAIN}.db"
named-checkzone "${REVERSE_ZONE}" "${ZONE_DIR}/db.${REVERSE_ZONE}"
rndc reload
