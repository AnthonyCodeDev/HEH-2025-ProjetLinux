#!/bin/bash

# ─── COULEURS ─────────────────────────────────────────────────────────
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"
BOLD="\033[1m"

# ─── FONCTIONS D'AFFICHAGE ─────────────────────────────────────
print_info() {
    echo -e "${CYAN}${BOLD}[i]${RESET} $1"
}

print_ok() {
    echo -e "${GREEN}${BOLD}[\u2713]${RESET} $1"
}

print_warn() {
    echo -e "${YELLOW}${BOLD}[!]${RESET} $1"
}

print_error() {
    echo -e "${RED}${BOLD}[\u2717]${RESET} $1"
}

# ─── CONFIGURATION FUSEAU HORAIRE ─────────────────────────────
print_info "Configuration du fuseau horaire en UTC+2..."
TIMEZONE="Europe/Brussels"

sudo timedatectl set-timezone $TIMEZONE && \
print_ok "Fuseau horaire défini sur : $(timedatectl | grep 'Time zone' | awk '{print $3, $4}')" || \
print_error "Erreur lors de la définition du fuseau horaire."

# ─── INSTALLATION DE CHRONY ──────────────────────────────
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

# ─── CONFIGURATION CLIENT ──────────────────────────────────
# Nouveau code : récupération dynamique de l'IP du serveur depuis le JSON
JSON_PATH="/home/ec2-user/server_address.json"
if [[ -f "$JSON_PATH" ]]; then
    SERVER_IP=$(grep -oP '(?<="server_ip": ")[^"]+' "$JSON_PATH")
    print_ok "IP du serveur récupérée depuis $JSON_PATH : $SERVER_IP"
    print_info "Utilisation de l'adresse IP du serveur NTP : $SERVER_IP"
else
    print_error "Fichier JSON $JSON_PATH introuvable."
    exit 1
fi

print_info "Sauvegarde de l'ancienne configuration..."
sudo cp /etc/chrony.conf /etc/chrony.conf.backup && \
print_ok "Fichier chrony.conf sauvegardé."

print_info "Écriture de la configuration client..."
sudo bash -c "cat > /etc/chrony.conf" <<EOF
server $SERVER_IP iburst

driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
keyfile /etc/chrony.keys
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony
log tracking measurements statistics
EOF
print_ok "Configuration client écrite (serveur NTP : $SERVER_IP)."

# ─── REDÉMARRAGE DE CHRONY ─────────────────────────────
print_info "Redémarrage du service chronyd..."
sudo systemctl enable chronyd
sudo systemctl restart chronyd && print_ok "Chronyd redémarré."

# ─── VÉRIFICATION SYNCHRONISATION ───────────────────────────────
print_info "Vérification de la synchronisation..."

MAX_RETRIES=5
for ((i=1; i<=MAX_RETRIES; i++)); do
    LEAP_STATUS=$(chronyc tracking | grep "Leap status" | awk -F ': ' '{print $2}')
    if [[ "$LEAP_STATUS" == "Normal" ]]; then
        print_ok "Le client est bien synchronisé avec le serveur NTP ! 🎉"
        break
    else
        print_warn "Tentative $i/$MAX_RETRIES : Pas encore synchronisé..."
        sleep 5
    fi
done


# Affiche l'état final
chronyc tracking