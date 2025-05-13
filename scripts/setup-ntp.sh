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

# ─── CONFIGURATION FUSEAU HORAIRE ───────────────────
print_info "Configuration du fuseau horaire en UTC+2..."
TIMEZONE="Europe/Brussels"

sudo timedatectl set-timezone $TIMEZONE && \
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

# ─── FIREWALL (UDP 123) ────────────────────────────
print_info "Ouverture du port 123/udp dans firewalld (zone docker)..."
sudo firewall-cmd --zone=docker --add-port=123/udp --permanent && \
sudo firewall-cmd --reload && \
print_ok "Port 123/udp ouvert dans firewalld." || \
print_error "Impossible d'ouvrir le port 123/udp dans firewalld."

# ─── DÉMARRAGE DU SERVICE ───────────────────────
print_info "Activation et redémarrage du service chronyd..."
sudo systemctl enable chronyd
sudo systemctl restart chronyd && print_ok "Chronyd démarré."

# ─── AFFICHAGE DU STATUT ─────────────────────────
print_info "Statut actuel de la synchronisation :"
chronyc tracking

print_ok "Serveur NTP configuré avec fuseau horaire UTC+2 ($TIMEZONE)."

# ─── ENVOI DU SCRIPT CLIENT VERS LES MACHINES DU RÉSEAU ──────────────
print_info "Début de l'envoi du script client-ntp.sh aux machines clientes..."

# Liste des IPs ou noms des machines clientes (modifie selon ton réseau)
CLIENTS=("10.42.0.101" "10.42.0.102" "10.42.0.103")

# Clé SSH et utilisateur pour la connexion sans mot de passe
KEY_PATH="test.pem"
SSH_USER="ec2-user"

# Chemin vers le script client local
SCRIPT_CLIENT="./client-ntp.sh"

for IP in "${CLIENTS[@]}"; do
    print_info "Envoi à $IP..."
    scp -i "$KEY_PATH" "$SCRIPT_CLIENT" "${SSH_USER}@${IP}:/home/${SSH_USER}/client-ntp.sh" && \
    ssh -i "$KEY_PATH" "${SSH_USER}@${IP}" "chmod +x /home/${SSH_USER}/client-ntp.sh && sudo /home/${SSH_USER}/client-ntp.sh" && \
    print_ok "Script déployé et exécuté sur $IP." || \
    print_error "Échec du déploiement ou de l'exécution sur $IP."
done

print_ok "Tous les clients ont reçu le script NTP."
