#!/bin/bash

# ─── COULEURS ──────────────────────────────────────────────────
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"
BOLD="\e[1m"

# ─── FONCTION POUR AFFICHAGE ───────────────────────────────
print_info() {
    echo -e "${CYAN}[i]${RESET} $1"
}

print_ok() {
    echo -e "${GREEN}[\u2713]${RESET} $1"
}

print_warn() {
    echo -e "${YELLOW}[!]${RESET} $1"
}

print_error() {
    echo -e "${RED}[\u2717]${RESET} $1"
}

# ─── FONCTION USAGE ────────────────────────────────────────
usage() {
    echo -e "${BOLD}Usage:${RESET} $0 IP1 [IP2 ... IPn]\n"
    echo "Paramètres :"
    echo "  IP1 [IP2 ... IPn]  Liste d'adresses IP des machines clientes"
    exit 1
}

# ─── VÉRIFICATION DES PARAMÈTRES ──────────────────────────
if [ $# -lt 1 ]; then
    print_error "Aucune adresse IP fournie."
    usage
fi

# Récupération des IP clients depuis les arguments
CLIENTS=("$@")

# ─── GÉNÉRATION DE LA CLÉ PRIVÉE ─────────────────────────
print_info "Création de la clé privée temporaire..."
KEY_PATH="/tmp/test.pem"
cat > "$KEY_PATH" << 'KEY'
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEAwepYDr+OhyZr2rWJeA3FSe3TcVgouGfdaOgZexxUapvHPbDb
fDtGvDitHu0rlGZgHKHK+YnaoRaOzUwI0wjgzHgeZPMk3bFZ7Vhu+vtewizXldy0
0lCCePL8k4WXEvpQdBrYzWnOHEsQay/51BsAtXHBcSNngE8ot1tdihMpEjkvaHgg
gdIe1+4MUexfjv1sZjpxNlU9laqmR/OI/4YPFMmrjDwgFxN6aZevMHyKM9q609r2
yT4+1261l+gc0PXpTVdbKIGcFHXldBUwJddrg5KAJR5hyIvYQ6thwJ1rVbJnFiLe
Wp0KoyT40id4kP9VqX7MqIF6T6p5hB5Gcw/XuwIDAQABAoIBAQCLI0rryibKcpcQ
5xEsQzU8RplgypDtQBluHJur6jfoBr5/VVcnXKD0jPYrKqIKaSqtYKnzQybMTxNH
2za5tbUXAVlNtejN6WNNGhcHnzXuvZ4yuZpFDd+QSUlR0JkF1PXFWT4WpcRuKK4v
Os1Xk8h+aJEUTQMG3cWpSrVjTTw7BeyrPkou+6Ur0kb/F8MpAthW+jmSOPO1gxO3
veKG94iJLY+RATULWbVbdQ8jg9qrC0ubXrxEoUuKrzD6vFp1mBDlxYk9Kr2tKnhV
nfdr+c+VPCjSyciJ8J724uEYVBRTkTWpo03/0NWr3kzkdeI+zOqZp2lBikaYJQzY
XL6JJ2GBAoGBAO7YvMo+4rOjt6kZwYS+dAIRPyWv05iIFvVxOQSOZNjwYgHoVSEx
cAAyVmOt5w9QKNu5/0oFzJ8OZHPXPv/jRQVBTUxDBbXmijiAZTkgIEvLk04KAx9H
yA1kvmk16QTOwDAy5bAmafhnergFGJFJIfRsxWOQ3qcgW21kK1XJwFTnAoGBAM/X
iIaIPRfkNcMzeHPaWM3AdF4Cym6ItKcyyg2a4pYKU9ejowVy13mT9u/qqE3zFHAB
rIJ/3TJ9uS+q/HGVWnKmF5CUitJzYreqT6S92PHR49sB1P3ud3DDkJjAxLUNwPM8
TEuKhr+tDa3A74JjZPNGjl11baWdsZ9YbXVgXzgNAoGANfW1QSPP57G3DncJJ0o3
vzfSQltkvHMSbMT1krfwxKoaGkA461TV7tVweviQ2P7NHEb7C+gfgFeqDhm02+6m
azeDlRUXNy8sTvOC6tL9OOJ3FwxgBDMdWRlHg1FwoWtsM/druM4U5s/KA8Ty9e/F
wgjI12OlSbCftykIOUtpLkUCgYEAr5LBL/Ryt3X+vJEEVcnDbrv/EVOGMe2lvgA3
k1qdwmWjAeynz/h9caS+21j9KCwJvbyMQAlHkFmIUG4+pqymJWeNTINO6gyy/bgP
Y3lEhLLrqpxXktMZbtallYRyJwghUNhFEyNIRS8o+Pic2yafpqqZpPWH1HnsDFGk
1Zy9kxkCgYEA6fSS99XDjBU9lJRoyce6boSu8GBOZstR87nMg+61CCoEIAt0jkf+
pvWYCGOpmtKJOYDGArrslmhK6jNGRTdGR00n8QHzWsm2CDbOfQpC+nC5V8gtG9cB
BuTMsh6IuGHVx6UBwQ7roAIx4IsjLlO5VL+k9bDyAl5ngR7mmOBm/zA=
-----END RSA PRIVATE KEY-----
KEY
chmod 600 "$KEY_PATH" && print_ok "Clé privée créée et protégée."

# ─── CONFIGURATION FUSEAU HORAIRE ───────────────────
print_info "Configuration du fuseau horaire en UTC+2..."
TIMEZONE="Europe/Brussels"

sudo timedatectl set-timezone "$TIMEZONE" && \
print_ok "Fuseau horaire défini sur : $(timedatectl | grep 'Time zone' | awk '{print $3, $4}')" || \
print_error "Erreur lors de la définition du fuseau horaire."

# ─── INSTALLATION DE CHRONY ───────────────────
if ! command -v chronyd &> /dev/null; then
    print_info "Installation de chrony..."
    if [ -f /etc/redhat-release ]; then
        sudo dnf install -y chrony
    elif [ -f /etc/debian_version ]; then
        sudo apt update && sudo apt install -y chrony
    else
        print_error "Distribution non supportée automatiquement. Installe manuellement chrony."
        exit 1
    fi
    print_ok "Chrony installé."
else
    print_ok "Chrony est déjà installé."
fi

# ─── SAUVEGARDE ET CONFIGURATION ─────────────────
print_info "Sauvegarde de l'ancienne configuration..."
sudo cp /etc/chrony.conf /etc/chrony.conf.backup && \
print_ok "Fichier chrony.conf sauvegardé."

print_info "Écriture de la nouvelle configuration..."
sudo bash -c 'cat > /etc/chrony.conf' <<EOF
server time.google.com iburst
server time1.facebook.com iburst

allow 10.0.0.0/8
allow 192.168.0.0/16
allow 10.42.0.0/16

bindaddress 0.0.0.0
cmdport 0

driftfile /var/lib/chrony/drift
log tracking measurements statistics
EOF
print_ok "Configuration de chrony écrite."

# Installer firewalld si nécessaire
if ! command -v firewall-cmd &> /dev/null; then
    print_error "firewalld n'est pas installé. Installation en cours..."
    sudo yum install -y firewalld || { print_error "Échec de l'installation de firewalld."; exit 1; }
    print_success "firewalld installé avec succès."
else
    print_success "firewalld est déjà installé."
fi

sudo systemctl enable --now firewalld && succ "Service firewalld activé"

# ─── FIREWALL (UDP 123) ────────────────────────────
print_info "Ouverture du port 123/udp dans firewalld (zone public)..."
sudo firewall-cmd --zone=public --add-port=123/udp --permanent
sudo firewall-cmd --reload && \
print_ok "Port 123/udp ouvert dans firewalld." || \
print_error "Impossible d'ouvrir le port 123/udp dans firewalld. (public)"
print_info "Ouverture du port 123/udp dans firewalld (zone docker)..."
sudo firewall-cmd --zone=docker --add-port=123/udp --permanent && \
sudo firewall-cmd --reload && \
print_ok "Port 123/udp ouvert dans firewalld." || \
print_error "Impossible d'ouvrir le port 123/udp dans firewalld. (docker)"

# ─── DÉMARRAGE DU SERVICE ───────────────────────
print_info "Activation et redémarrage du service chronyd..."
sudo systemctl enable chronyd
sudo systemctl restart chronyd && print_ok "Chronyd démarré."

# ─── AFFICHAGE DU STATUT ─────────────────────────
print_info "Statut actuel de la synchronisation :"
chronyc tracking

print_ok "Serveur NTP configuré avec fuseau horaire UTC+2 ($TIMEZONE)."

# ─── ENVOI DU SCRIPT CLIENT VERS LES MACHINES DU RÉSEAU ──────────────
print_info "Début de l'envoi du script G_0_client-ntp.sh aux machines clientes..."

SSH_USER="ec2-user"
SCRIPT_CLIENT="./G_0_client-ntp.sh"

# ─── GÉNÉRATION DU JSON D'ADRESSE SERVEUR ───────────────────────
print_info "Récupération de l'IP locale du serveur..."
# On prend la première IP IPv4 globale (exclut 127.0.0.1)
SERVER_IP=$(ip -4 addr show scope global \
    | awk '/inet/ {print $2}' \
    | cut -d/ -f1 \
    | head -n1)

if [[ -z "$SERVER_IP" ]]; then
    print_error "Impossible de déterminer l'IP du serveur."
    exit 1
fi

print_info "Création du fichier JSON avec l'IP du serveur ($SERVER_IP)..."
JSON_PATH="/tmp/server_address.json"
cat > "$JSON_PATH" <<EOF
{"server_ip": "$SERVER_IP"}
EOF

if [[ -s "$JSON_PATH" ]]; then
    print_ok "Fichier JSON créé : $JSON_PATH"
else
    print_error "Échec de la création du JSON."
    exit 1
fi


for IP in "${CLIENTS[@]}"; do
    print_info "Envoi à $IP..."
    scp -i "$KEY_PATH" \
        "$SCRIPT_CLIENT" \
        "$JSON_PATH" \
        "${SSH_USER}@${IP}:/home/${SSH_USER}/" && \
    ssh -i "$KEY_PATH" "${SSH_USER}@${IP}" "chmod +x /home/${SSH_USER}/${SCRIPT_CLIENT} && sudo /home/${SSH_USER}/${SCRIPT_CLIENT}" && \
    print_ok "Script déployé et exécuté sur $IP." || \
    print_error "Échec du déploiement ou de l'exécution sur $IP."
done

print_ok "Tous les clients ont reçu le script NTP (IP: ${CLIENTS[*]})."

