#!/usr/bin/env bash
set -euo pipefail

### —───────────────────────────────────
### Couleurs & helpers
### —───────────────────────────────────
RED=$'\e[31m'; GREEN=$'\e[32m'; BLUE=$'\e[34m'; RESET=$'\e[0m'
function err  { printf "%b[ERREUR] %s%b\n\n" "${RED}" "$1" "${RESET}" >&2; exit 1; }
function succ { printf "%b[OK]    %s%b\n"  "${GREEN}" "$1" "${RESET}"; }
function info { printf "%b[INFO]   %s%b\n"  "${BLUE}" "$1" "${RESET}"; }

### —───────────────────────────────────
### 1) Options
### —───────────────────────────────────
function show_usage {
  cat <<EOF
Usage : $0 [-p PORT]

Paramètres :
  -p   Port d'écoute Cockpit (défaut : 9090)
EOF
  exit 1
}

DEFAULT_PORT=9090
LISTEN_PORT=$DEFAULT_PORT
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)
      if [[ -n "${2-}" && "$2" =~ ^[0-9]+$ ]]; then
        LISTEN_PORT=$2; shift 2
      else
        err "Argument invalide pour -p : doit être un nombre"
      fi
      ;;
    -h|--help) show_usage ;;
    *) err "Option inconnue : $1" ;;
  esac
done
succ "Port Cockpit choisi : $LISTEN_PORT"

# vérifie que le user monitoring est créer
if ! id "monitoring" &>/dev/null; then
  err "L'utilisateur monitoring n'existe pas. Veuillez le créer avant de continuer."
  err "Exécutez la commande suivante : sudo bash A_1_setup_client.sh -u monitoring -p <mot_de_passe> -d heh.lan"
fi

### —───────────────────────────────────
### 1.b) Vérification des droits sudo pour monitoring
### —───────────────────────────────────
# On teste si monitoring a déjà une entrée sudoers
if ! sudo -l -U monitoring 2>/dev/null | grep -q '(ALL)'; then
  info "→ Configuration des droits sudo pour l'utilisateur monitoring"
  # Création d'un fichier sudoers dédié (NOPASSWD pour ne pas redemander de mot de passe)
  echo 'monitoring ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/monitoring >/dev/null
  # Verrouillage des permissions
  sudo chmod 440 /etc/sudoers.d/monitoring
  succ "Privilèges sudo accordés à monitoring (NOPASSWD)"
else
  succ "L'utilisateur monitoring dispose déjà des droits sudo"
fi


### —───────────────────────────────────
### 2) Libération du port
### —───────────────────────────────────
info "→ Vérification du port $LISTEN_PORT"
if sudo lsof -iTCP:"$LISTEN_PORT" -sTCP:LISTEN -t >/dev/null; then
  for PID in $(sudo lsof -iTCP:"$LISTEN_PORT" -sTCP:LISTEN -t); do
    info "Arrêt forcé PID $PID sur le port $LISTEN_PORT"
    sudo kill -9 "$PID" && succ "Processus $PID tué"
  done
else
  info "Port $LISTEN_PORT libre"
fi

### —───────────────────────────────────
### 3) Détection du gestionnaire de paquets
### —───────────────────────────────────
. /etc/os-release 2>/dev/null || true
case "${ID:-}-${VERSION_ID:-}" in
  ubuntu*|debian*)                   PKG_MGR=apt-get;;
  amzn-2*)                           PKG_MGR=yum;;
  amzn-2023*|rhel*|centos*|fedora*) PKG_MGR=dnf;;
  *)                                 PKG_MGR=$(command -v dnf||command -v yum||echo apt-get);;
esac
succ "Gestionnaire de paquets détecté : $PKG_MGR"

### —───────────────────────────────────
### 4) Installation du container engine
### —───────────────────────────────────
info "→ Installation de Podman ou Docker"
if ! command -v podman &>/dev/null; then
  case "$PKG_MGR" in
    apt-get) sudo apt-get update -y && sudo apt-get install -y podman || true ;;
    yum)      sudo yum install -y podman || true ;;
    *)        sudo dnf install -y podman || true ;;
  esac
fi

if command -v podman &>/dev/null; then
  CONTAINER_CMD=podman; succ "Utilisation de podman"
else
  case "$PKG_MGR" in
    apt-get) sudo apt-get update -y && sudo apt-get install -y docker.io ;;
    yum)      sudo yum install -y docker ;;
    *)        sudo dnf install -y docker ;;
  esac
  sudo systemctl enable --now docker || err "Impossible de démarrer Docker"
  CONTAINER_CMD=docker; succ "Utilisation de Docker"
fi

### —───────────────────────────────────
### 5) Lancement du conteneur Cockpit
### —───────────────────────────────────
info "→ Lancement du conteneur Cockpit (host network)"
sudo $CONTAINER_CMD rm -f cockpit &>/dev/null || true
sudo $CONTAINER_CMD run -d --name cockpit \
  --privileged \
  --network host \
  -v /:/host:ro \
  -v /etc/pam.d:/host/etc/pam.d:rw,Z \
  -v /etc/cockpit:/host/etc/cockpit:rw,Z \
  quay.io/cockpit/ws:latest \
  || err "Échec du lancement du conteneur Cockpit"
succ "Cockpit lancé via \`$CONTAINER_CMD\` sur le port $LISTEN_PORT"

### —───────────────────────────────────
### 6) Configuration du host distant
### —───────────────────────────────────
DATA_HOST="10.42.0.4"
DATA_USER="ec2-user"
SSH_KEY="/home/ec2-user/.ssh/id_rsa"
CFG="/etc/cockpit/machines.d/data-server.json"

info "→ Configuration du host distant $DATA_HOST dans Cockpit"
sudo mkdir -p "$(dirname "$CFG")"
sudo tee "$CFG" >/dev/null <<EOF
{
  "data-server": {
    "address":     "$DATA_HOST",
    "user":        "$DATA_USER",
    "identityFile":"$SSH_KEY",
    "visible":     true
  }
}
EOF
succ "Host distant configuré pour $DATA_HOST"

### —───────────────────────────────────
### 7) Reconfiguration du port (si différent)
### —───────────────────────────────────
if [[ "$LISTEN_PORT" != "$DEFAULT_PORT" ]]; then
  info "→ Reconfiguration du port Cockpit : $LISTEN_PORT"
  sudo mkdir -p /etc/cockpit
  sudo tee /etc/cockpit/cockpit.conf >/dev/null <<EOF
[WebService]
Port = $LISTEN_PORT
EOF
  succ "Port reconfiguré dans /etc/cockpit/cockpit.conf"
fi

### —───────────────────────────────────
### 8) Ouverture du port dans le pare-feu
### —───────────────────────────────────
if command -v firewall-cmd &>/dev/null; then
  info "→ Ouverture du port $LISTEN_PORT dans firewalld"
  sudo firewall-cmd --add-port=${LISTEN_PORT}/tcp --permanent \
    && sudo firewall-cmd --reload \
    && succ "Port $LISTEN_PORT/tcp ouvert"
fi

### —───────────────────────────────────
### 10) Vérification finale
### —───────────────────────────────────
info "→ Vérification de l'écoute sur le port $LISTEN_PORT"
if sudo ss -ltn | grep -q ":$LISTEN_PORT[[:space:]]"; then
  succ "Cockpit écoute sur le port $LISTEN_PORT"
else
  err "Cockpit n'écoute pas sur le port $LISTEN_PORT"
fi

MONITOR_IP=$(ip route get 8.8.8.8 | awk '/src/ { print $7; exit }')
succ "Adresse de monitoring détectée : $MONITOR_IP"

succ "✔ Script exécuté avec succès !

Accédez à Cockpit :
    URL         : https://$MONITOR_IP:$LISTEN_PORT/
    Identifiant : monitoring
    Mot de passe: pass"

succ "✔ Supervision du serveur distant configurée !

1) Connectez-vous au serveur et lancez :
     monitoring.sh
2) Dans Cockpit (https://$MONITOR_IP:$LISTEN_PORT/) :
     • Autres options
     • Se connecter à
   Puis saisissez l’adresse IP du serveur distant : $DATA_HOST
3) Ou connectez-vous directement via :
     https://$MONITOR_IP:$LISTEN_PORT/=$DATA_HOST"