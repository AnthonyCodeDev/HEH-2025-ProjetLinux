#!/usr/bin/env bash
set -euo pipefail

### —───────────────────────────────────
### Couleurs & helpers
### —───────────────────────────────────
RED=$'\e[31m'; GREEN=$'\e[32m'; BLUE=$'\e[34m'; RESET=$'\e[0m'

function show_usage {
  cat <<EOF
Usage : $0 [-p PORT]

Paramètres :
  -p   Port d'écoute Cockpit (défaut : 9090)
EOF
  exit 1
}

function err {
  printf "%b[ERREUR] %s%b\n\n" "${RED}" "${1}" "${RESET}" >&2
  exit 1
}

function succ {
  printf "%b[OK]    %s%b\n" "${GREEN}" "${1}" "${RESET}"
}

function info {
  printf "%b[INFO]   %s%b\n" "${BLUE}" "${1}" "${RESET}"
}

### —───────────────────────────────────
### 1) Options
### —───────────────────────────────────
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
    *)         err "Option inconnue : $1" ;;
  esac
done

succ "Port Cockpit choisi : $LISTEN_PORT"

### —───────────────────────────────────
### 2) Vérification et libération du port
### —───────────────────────────────────
info "→ Vérification du port $LISTEN_PORT"
if sudo lsof -iTCP:"$LISTEN_PORT" -sTCP:LISTEN -t >/dev/null; then
  PIDS=$(sudo lsof -iTCP:"$LISTEN_PORT" -sTCP:LISTEN -t)
  for PID in $PIDS; do
    info "Port $LISTEN_PORT utilisé par PID $PID, arrêt forcé"
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
### 4) Bascule automatique en conteneur
### —───────────────────────────────────
info "→ Mode conteneur Cockpit (auto)"

# Installer Podman si possible, sinon Docker
if ! command -v podman &>/dev/null; then
  info "→ Installation de podman"
  if [[ "$PKG_MGR" == "apt-get" ]]; then
    sudo apt-get update -y
    sudo apt-get install -y podman || true
  elif [[ "$PKG_MGR" == "yum" ]]; then
    sudo yum install -y podman || true
  else
    sudo dnf install -y podman || true
  fi
fi

if command -v podman &>/dev/null; then
  CONTAINER_CMD=podman
  succ "Utilisation de podman"
else
  info "podman non trouvé, installation de docker"
  if [[ "$PKG_MGR" == "apt-get" ]]; then
    sudo apt-get update -y
    sudo apt-get install -y docker.io
  elif [[ "$PKG_MGR" == "yum" ]]; then
    sudo yum install -y docker
  else
    sudo dnf install -y docker
  fi
  sudo systemctl enable --now docker || err "Impossible de démarrer Docker"
  CONTAINER_CMD=docker
  succ "Utilisation de Docker"
fi

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
succ "Cockpit lancé en conteneur via \`$CONTAINER_CMD\` sur le port $LISTEN_PORT"

### —───────────────────────────────────
### 5) Activation du socket systemd
### —───────────────────────────────────
info "→ Activation du socket systemd cockpit (si disponible)"
if systemctl list-unit-files --type=socket | grep -q '^cockpit.socket'; then
  if sudo systemctl enable --now cockpit.socket; then
    succ "cockpit.socket activé et démarré"
  else
    err "Impossible d'activer cockpit.socket"
  fi
else
  info "Unité cockpit.socket non trouvée : activation ignorée (mode conteneur)"
fi

### —───────────────────────────────────
### 6) Reconfiguration du port (si différent)
### —───────────────────────────────────
CONF_FILE=/etc/cockpit/cockpit.conf
if [[ "$LISTEN_PORT" != "$DEFAULT_PORT" ]]; then
  info "Reconfiguration du port Cockpit : $LISTEN_PORT"
  sudo mkdir -p "$(dirname "$CONF_FILE")"
  sudo tee "$CONF_FILE" >/dev/null <<EOF
[WebService]
Port = $LISTEN_PORT
EOF
  sudo systemctl reload cockpit.socket \
    && succ "cockpit.socket rechargé sur le port $LISTEN_PORT" \
    || err "Échec du rechargement de cockpit.socket"
else
  info "Port par défaut ($DEFAULT_PORT) conservé"
fi

### —───────────────────────────────────
### 7) Ouverture du port dans le pare-feu
### —───────────────────────────────────
if command -v firewall-cmd &>/dev/null; then
  info "Ouverture du port $LISTEN_PORT/tcp dans firewalld"
  sudo firewall-cmd --add-port=${LISTEN_PORT}/tcp --permanent \
    && sudo firewall-cmd --reload \
    && succ "Port $LISTEN_PORT/tcp ouvert" \
    || err "Échec de l'ouverture du port dans firewalld"
else
  info "firewall-cmd non trouvé, vérifiez votre pare-feu manuellement"
fi

### —───────────────────────────────────
### 8) Vérification finale
### —───────────────────────────────────
info "Vérification de l'écoute sur le port $LISTEN_PORT"
if sudo ss -ltn | grep -q ":$LISTEN_PORT[[:space:]]"; then
  succ "Cockpit écoute correctement sur le port $LISTEN_PORT"
else
  err "Cockpit n'écoute pas sur le port $LISTEN_PORT"
fi

succ "Installation et configuration de Cockpit terminées !"
