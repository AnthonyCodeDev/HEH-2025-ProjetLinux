#!/usr/bin/env bash
set -euo pipefail

# Usage :
#   sudo bash setup_client.sh -u user1 [user2 …] -p PASSWORD
# Example :
#   sudo bash setup_client.sh -u guillaume antho -p S3cr3tP@ss

### —───────────────────────────────────
### Couleurs & helpers
### —───────────────────────────────────
RED=$'\e[31m'; GREEN=$'\e[32m'; BLUE=$'\e[34m'; RESET=$'\e[0m'

function show_usage {
  cat <<EOF
Usage : $0 -u user1 [user2 …] -p PASSWORD

Paramètres obligatoires :
  -u   Liste d'un ou plusieurs utilisateurs (séparés par des espaces)
  -p   Mot de passe commun aux utilisateurs

Exemple :
  sudo bash $0 -u guillaume antho -p S3cr3tP@ss
EOF
}

function err {
  printf "%b[ERREUR] %s%b\n\n" "$RED" "$1" "$RESET" >&2
  show_usage
  exit 1
}

function succ {
  printf "%b[OK]    %s%b\n" "$GREEN" "$1" "$RESET"
}

function info {
  printf "%b[INFO]   %s%b\n" "$BLUE" "$1" "$RESET"
}

### 1) Parse options
PASSWORD=''; USERS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -u)
      shift
      while [[ $# -gt 0 && $1 != -* ]]; do
        USERS+=("$1")
        shift
      done
      ;;
    -p)
      PASSWORD=$2; shift 2;;
    *)
      err "Argument inconnu : $1"
      ;;
  esac
done

[ ${#USERS[@]} -ge 1 ] || err "Il faut au moins un utilisateur après -u"
[ -n "$PASSWORD" ]    || err "Il manque -p PASSWORD"

# Mot de passe root MariaDB
ROOT_PW='JSShFZtpt35MHX'
DOMAIN='heh.lan'
succ "Domaine    : $DOMAIN"
succ "Password clients : $PASSWORD"
succ "Clients à provisionner : ${USERS[*]}"

SSL_CERT="/etc/ssl/certs/wildcard.${DOMAIN}.crt.pem"
SSL_KEY="/etc/ssl/private/wildcard.${DOMAIN}.key.pem"

if [[ ! -f "$SSL_CERT" || ! -f "$SSL_KEY" ]]; then
  err "Certificat wildcard SSL non trouvé. Génère le certificat SSL (*.${DOMAIN}) avant d'exécuter ce script."
fi

### 2) Détection pkg manager & SQL client
PKG_MGR=""; CLIENT_PKG=""
. /etc/os-release 2>/dev/null || true
case "${ID:-}-${VERSION_ID:-}" in
  amzn-2023)      PKG_MGR=dnf;     CLIENT_PKG=mariadb105;;
  amzn-2)         PKG_MGR=yum;     CLIENT_PKG=mariadb;;
  ubuntu*|debian*)PKG_MGR=apt-get; CLIENT_PKG=mariadb-client;;
  *)              PKG_MGR=$(command -v dnf||command -v yum||echo apt-get); CLIENT_PKG=mariadb-client;;
esac
succ "Package manager: $PKG_MGR, SQL client: $CLIENT_PKG"

function install_if_missing {
  local bin="$1" pkg="$2"
  if ! command -v "$bin" &>/dev/null; then
    sudo $PKG_MGR install -y "$pkg" && succ "$pkg installé" || err "Impossible d'installer $pkg"
  else
    succ "$pkg déjà présent"
  fi
}

### 3) Installation/activation services
for pkg in nginx openssl vsftpd samba "$CLIENT_PKG"; do
  [[ $PKG_MGR = apt-get && $pkg = $CLIENT_PKG ]] && sudo apt-get update -y
  install_if_missing "$pkg" "$pkg"
done
for svc in nginx vsftpd smb nmb mariadb; do
  sudo systemctl enable --now "$svc" && succ "Service $svc activé"
done

### 3.b) Vérification et installation de firewalld
if ! command -v firewall-cmd &>/dev/null; then
  info "firewalld absent, installation en cours…"
  sudo $PKG_MGR install -y firewalld \
    && succ "firewalld installé" \
    || err "Impossible d'installer firewalld"
fi
# Activer et démarrer firewalld si ce n’est pas déjà fait
sudo systemctl enable --now firewalld && succ "Service firewalld activé"

### 4) Ouverture des ports FTP dans le firewall (firewalld)
info "Ouverture des ports FTP 21 et 40000-40100 dans firewalld"
sudo firewall-cmd --add-port=21/tcp --permanent && succ "Port 21/tcp ouvert"
sudo sudo firewall-cmd --permanent --add-service=http && succ "Service http ouvert"
sudo firewall-cmd --permanent --add-service=https && sudo firewall-cmd --reload
sudo firewall-cmd --add-port=40000-40100/tcp --permanent && succ "Plage 40000-40100/tcp ouverte"
# → Ajout du service Samba (SMB)
info "Ouverture du service Samba (SMB) dans firewalld"
sudo firewall-cmd --permanent --add-service=samba && succ "Service samba autorisé dans firewalld"

sudo firewall-cmd --reload && succ "firewalld rechargé"

### 5) Init MariaDB datadir
if [[ $CLIENT_PKG = mariadb105 ]]; then
  SERVER_PKG=mariadb105-server
else
  SERVER_PKG=${CLIENT_PKG%-client}-server
fi
install_if_missing "$SERVER_PKG" "$SERVER_PKG"
if [[ ! -d /var/lib/mysql/mysql ]]; then
  succ "Initialisation du datadir MariaDB"
  sudo mariadb-install-db --user=mysql --datadir=/var/lib/mysql && succ "Datadir initialisé" || err "Échec init datadir"
  sudo chown -R mysql:mysql /var/lib/mysql
fi
sudo mkdir -p /var/run/mysqld && sudo chown mysql:mysql /var/run/mysqld

# Assurer que le service MariaDB tourne avant d'appliquer le mot de passe root
sudo systemctl enable --now mariadb.service && succ "Service mariadb démarré pour configuration"

### 6) Configurer root MySQL
succ "→ Définition du mot de passe root@localhost"
sudo mysql --protocol=socket -uroot -p"$ROOT_PW" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('$ROOT_PW');
FLUSH PRIVILEGES;
EOF
succ "Mot de passe root configuré"

### 7) Configurer SSHD (password auth)
SSHD=/etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD"
sudo sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' "$SSHD"
sudo sed -i 's/^#\?UsePAM.*/UsePAM yes/' "$SSHD"
sudo systemctl reload sshd && succ "sshd rechargé"

### 8) Configurer vsftpd pour chroot par utilisateur + FTP standalone
VSF=/etc/vsftpd/vsftpd.conf
# mode standalone IPv4
sudo sed -i 's|^#\?listen=.*|listen=YES|'               "$VSF"
sudo sed -i 's|^#\?listen_ipv6=.*|listen_ipv6=NO|'      "$VSF"
# PAM
sudo sed -i 's|^#\?pam_service_name=.*|pam_service_name=vsftpd|' "$VSF"
# habiliter les comptes locaux
sudo sed -i 's|^#\?local_enable=.*|local_enable=YES|'   "$VSF"
sudo sed -i 's|^#\?write_enable=.*|write_enable=YES|'   "$VSF"
# chroot et autoriser write dans chroot
sudo sed -i 's|^#\?chroot_local_user=.*|chroot_local_user=YES|' "$VSF"
if grep -q '^allow_writeable_chroot' "$VSF"; then
  sudo sed -i 's|^allow_writeable_chroot=.*|allow_writeable_chroot=YES|' "$VSF"
else
  echo 'allow_writeable_chroot=YES' | sudo tee -a "$VSF" >/dev/null
fi
# config par utilisateur
sudo sed -i 's|^#\?user_config_dir=.*|user_config_dir=/etc/vsftpd_user_conf|' "$VSF"

# Passive mode (ports 40000–40100, adresse du serveur)
if ! grep -q '^pasv_enable=' "$VSF"; then
  cat <<EOF | sudo tee -a "$VSF"

# Passive FTP
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_address=$(hostname -I | awk '{print $1}')
EOF
fi

# Redémarrage
sudo systemctl restart vsftpd \
  && succ "vsftpd redémarré (FTP standalone activé)" \
  || err "Impossible de redémarrer vsftpd"

# Créer le dossier de configuration individuelle FTP
sudo mkdir -p /etc/vsftpd_user_conf
sudo chown root:root /etc/vsftpd_user_conf
sudo chmod 755 /etc/vsftpd_user_conf

### 9) Boucle de configuration pour chaque client
for USER_NAME in "${USERS[@]}"; do
  WEB_DIR="/var/www/$USER_NAME"
  HOME_DIR="/home/$USER_NAME"
  VHOST="/etc/nginx/conf.d/${USER_NAME}.${DOMAIN}.conf"
  DB_NAME="${USER_NAME}_db"
  DB_USER="$USER_NAME"
  DB_PASS="$PASSWORD"

  if id "$USER_NAME" &>/dev/null && [[ -d $WEB_DIR ]]; then
    info "Utilisateur $USER_NAME existe déjà, mise à jour de la configuration"
  else
    succ "=== Configuration de $USER_NAME ==="

    # SQL : base & user
    sudo mysql --protocol=socket -uroot -p"$ROOT_PW" <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
    succ "SQL : base & user pour $USER_NAME"

    # Création de l’utilisateur
    sudo useradd -m -d "$HOME_DIR" -s /bin/bash "$USER_NAME" \
      && succ "Utilisateur système $USER_NAME ajouté (home=$HOME_DIR)" \
      || ( sudo usermod -d "$HOME_DIR" -s /bin/bash "$USER_NAME" \
           && succ "Home de $USER_NAME défini sur $HOME_DIR" )
    echo "$USER_NAME:$PASSWORD" | sudo chpasswd
    succ "Mot de passe système défini pour $USER_NAME"
  fi
  
  # Créer séparément le web dir et y donner les droits
  sudo mkdir -p "$WEB_DIR"
  sudo chown -R "$USER_NAME:$USER_NAME" "$WEB_DIR"
  sudo chmod -R 755 "$WEB_DIR"
  succ "Web dir $WEB_DIR prêt (séparé du home)"

  echo "$USER_NAME:$PASSWORD" | sudo chpasswd
  succ "Mot de passe système défini pour $USER_NAME"

  # Config FTP individuel : chroot dans son web dir
  echo "local_root=$WEB_DIR" | sudo tee /etc/vsftpd_user_conf/"$USER_NAME" >/dev/null
  sudo chmod 644 /etc/vsftpd_user_conf/"$USER_NAME"

  # Permissions web dir
  sudo mkdir -p "$WEB_DIR"
  sudo chown -R "$USER_NAME:$USER_NAME" "$WEB_DIR"
  sudo chmod -R 755 "$WEB_DIR"
  succ "Web dir $WEB_DIR prêt"

# Créer un index.html avec un <h1> de bienvenue
sudo tee "$WEB_DIR/index.html" >/dev/null <<EOF
<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><title>Bienvenue</title><style>body{margin:0;display:flex;height:100vh;align-items:center;justify-content:center;font-family:-apple-system,system-ui,sans-serif;background:#fff}h1{font-size:2rem}span{color:#007AFF}</style></head><body><h1>Bienvenue <span>$USER_NAME</span> dans votre espace web</h1></body></html>
EOF

sudo chown "$USER_NAME:$USER_NAME" "$WEB_DIR/index.html"
sudo chmod 644 "$WEB_DIR/index.html"
succ "Fichier index.html personnalisé créé dans $WEB_DIR"

  # vsftpd per-user config
  sudo tee "/etc/vsftpd_user_conf/$USER_NAME" >/dev/null <<EOF
local_root=$WEB_DIR
EOF
  succ "vsftpd : local_root défini sur $WEB_DIR pour $USER_NAME"
  sudo systemctl restart vsftpd && succ "vsftpd rechargé pour $USER_NAME"

  # ~/.bash_profile
  sudo tee "$HOME_DIR/.bash_profile" >/dev/null <<PROFILE
# Source global configs
[ -f /etc/profile ] && . /etc/profile
[ -f /etc/bashrc ]   && . /etc/bashrc
cd "\$HOME"
PROFILE
  succ "~/.bash_profile créé pour $USER_NAME"


  # vHost nginx
  if [[ ! -f $VHOST ]]; then
    sudo tee "$VHOST" >/dev/null <<NGINX
server {
  listen 80;
  server_name ${USER_NAME}.${DOMAIN};
  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2;
  server_name ${USER_NAME}.${DOMAIN};

  ssl_certificate      $SSL_CERT;
  ssl_certificate_key  $SSL_KEY;
  ssl_protocols        TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers on;

  root  $WEB_DIR;
  index index.html index.htm;
  location / { try_files \$uri \$uri/ =404; }
}
NGINX
    succ "vHost nginx ajouté pour $DOMAIN"
    sudo nginx -t && sudo systemctl reload nginx && succ "nginx rechargé"
  else
    succ "vHost pour $DOMAIN déjà existant"
  fi

  # Samba
  if ! grep -q "^\[$USER_NAME\]" /etc/samba/smb.conf; then
    sudo tee -a /etc/samba/smb.conf >/dev/null <<SAMBA
[$USER_NAME]
  path = $WEB_DIR
  valid users = $USER_NAME
  browsable = yes
  writable = yes
  create mask = 0644
  directory mask = 0755
SAMBA
    (echo "$PASSWORD"; echo "$PASSWORD") | sudo smbpasswd -a -s "$USER_NAME"
    sudo systemctl restart smb nmb && succ "Samba configuré pour $USER_NAME"
  else
    succ "Samba déjà configuré pour $USER_NAME"
  fi

  # Récapitulatif
  cat <<EOF

=== IDENTIFIANTS $USER_NAME ===
• Domaine     : http://${USER_NAME}.${DOMAIN}
• Web dir     : $WEB_DIR
• FTP/Samba   : $USER_NAME / $PASSWORD
• SQL root    : root / $ROOT_PW
• SQL client  : $DB_USER / $DB_PASS (base $DB_NAME)

EOF
done

succ "Tous les clients (${USERS[*]}) ont été configurés."
