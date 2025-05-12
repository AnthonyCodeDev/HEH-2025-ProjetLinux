#!/usr/bin/env bash
set -euo pipefail

# Ce script doit être lancé avec bash : sudo bash setup_client.sh

# ——————————————————————————
# Couleurs ANSI pour les messages
# ——————————————————————————
RED=$'\e[31m'; GREEN=$'\e[32m'; RESET=$'\e[0m'
function err  { printf "%b[ERREUR] %s%b\n" "$RED" "$1" "$RESET"; exit 1; }
function succ { printf "%b[OK]    %s%b\n" "$GREEN" "$1" "$RESET"; }

### Variables globales
# Détection du gestionnaire de paquets et du client SQL
PKG_MGR=""; CLIENT_PKG=""
if [ -r /etc/os-release ]; then
  . /etc/os-release
  case "${ID}-${VERSION_ID}" in
    amzn-2023)      PKG_MGR=dnf;     CLIENT_PKG=mariadb105;;
    amzn-2)         PKG_MGR=yum;     CLIENT_PKG=mariadb;;
    ubuntu*|debian*)PKG_MGR=apt-get; CLIENT_PKG=mariadb-client;;
    *)              PKG_MGR=$(command -v dnf||command -v yum||echo apt-get); CLIENT_PKG=mariadb-client;;
  esac
else
  PKG_MGR=yum; CLIENT_PKG=mariadb
fi

# Paramètres « ec2-user »
CLIENT=ec2-user
USER_PASS='VotreNouveauMdp1!'

# Mot de passe root = même que USER_PASS
ROOT_PW="${USER_PASS}"

# Base SQL pour ec2-user
DB_NAME=${CLIENT}_db
DB_USER=${CLIENT}
DB_PASS=${USER_PASS}

# Autres
DOMAIN=heh.lan
WEB_DIR=/var/www/${CLIENT}
VHOST_CONF=/etc/nginx/conf.d/${DOMAIN}.conf

succ "Package manager: ${PKG_MGR}, SQL client: ${CLIENT_PKG}"

# Fonction d'installation conditionnelle
install_if_missing(){
  local bin=$1 pkg=$2
  if ! command -v "$bin" &>/dev/null; then
    sudo ${PKG_MGR} install -y "$pkg" && succ "$pkg installé" || err "Impossible d'installer $pkg"
  else
    succ "$pkg déjà présent"
  fi
}

### 1) Services de base + client SQL
for pkg in nginx openssl vsftpd samba "${CLIENT_PKG}"; do
  [ "$PKG_MGR" = "apt-get" ] && [ "$pkg" = "${CLIENT_PKG}" ] && sudo apt-get update -y
  install_if_missing "$pkg" "$pkg"
done
for svc in nginx vsftpd smb nmb; do
  sudo systemctl enable --now "$svc" &>/dev/null && succ "Service $svc activé"
done

### 2) MariaDB + init datadir
if [ "${CLIENT_PKG}" = "mariadb105" ]; then
  SERVER_PKG="mariadb105-server"
else
  SERVER_PKG="${CLIENT_PKG%-client}-server"
fi
install_if_missing "$SERVER_PKG" "$SERVER_PKG"

if [ ! -d /var/lib/mysql/mysql ]; then
  succ "Initialisation du datadir MariaDB"
  if command -v mariadb-install-db &>/dev/null; then
    sudo mariadb-install-db --user=mysql --datadir=/var/lib/mysql \
      && succ "Datadir initialisé" || err "Échec init datadir"
  else
    err "mariadb-install-db introuvable"
  fi
  sudo chown -R mysql:mysql /var/lib/mysql
fi

# Créer le répertoire des sockets (si besoin)
sudo mkdir -p /var/run/mysqld
sudo chown mysql:mysql /var/run/mysqld

sudo systemctl enable mariadb
sudo systemctl start mariadb && succ "Service mariadb démarré"

### 3) SQL : définir root et créer ec2-user

# 3.1 Définir le mot de passe root en mysql_native_password
echo "→ Configuration de l’authentification root en mysql_native_password"
sudo mysql --protocol=socket --user=root <<SQL
ALTER USER 'root'@'localhost'
  IDENTIFIED VIA mysql_native_password
  USING PASSWORD('${ROOT_PW}');
FLUSH PRIVILEGES;
SQL
succ "Mot de passe root défini en mysql_native_password"

# 3.2 Créer la base et l'utilisateur ec2-user
mysql --protocol=socket -uroot -p"${ROOT_PW}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
succ "Base ${DB_NAME} et utilisateur SQL ${DB_USER} créés"

### 4) Utilisateur système ec2-user
if ! id "$CLIENT" &>/dev/null; then
  sudo useradd -m -d "$WEB_DIR" -s /sbin/nologin "$CLIENT"
  succ "Utilisateur système $CLIENT ajouté"
fi
echo "$CLIENT:$USER_PASS" | sudo chpasswd
succ "Mot de passe système de $CLIENT défini"

### 5) Web / FTP / Samba
[ ! -d "$WEB_DIR" ] && sudo mkdir -p "$WEB_DIR" && sudo chmod 755 "$WEB_DIR" && succ "Web dir créé"

if [ ! -f "$VHOST_CONF" ]; then
  sudo tee "$VHOST_CONF" >/dev/null <<EOF
server {
  listen 80;
  server_name ${DOMAIN};
  root ${WEB_DIR};
  index index.html index.htm;
  location / { try_files \$uri \$uri/ =404; }
}
EOF
  succ "vHost ajouté"
fi
sudo nginx -t && sudo systemctl reload nginx && succ "nginx rechargé"

if ! grep -qx "$CLIENT" /etc/vsftpd/user_list; then
  echo "$CLIENT" | sudo tee -a /etc/vsftpd/user_list >/dev/null
  sudo systemctl restart vsftpd && succ "FTP configuré"
fi

if ! grep -q "^\[$CLIENT\]" /etc/samba/smb.conf; then
  sudo tee -a /etc/samba/smb.conf >/dev/null <<EOF

[$CLIENT]
  path = ${WEB_DIR}
  valid users = ${CLIENT}
  browsable = yes
  writable = yes
  create mask = 0644
  directory mask = 0755
EOF
  (echo "${USER_PASS}"; echo "${USER_PASS}") | sudo smbpasswd -a -s "${CLIENT}"
  sudo systemctl restart smb nmb && succ "Samba configuré"
fi

### 6) Récapitulatif
cat <<EOF

=== IDENTIFIANTS ${CLIENT} ===
• Domaine       : http://${DOMAIN}
• Web dir       : ${WEB_DIR}
• Système       : ${CLIENT} / ${USER_PASS}
• FTP/Samba     : ${CLIENT} / ${USER_PASS}
• SQL root      : root / ${ROOT_PW}
• SQL client    : ${DB_USER} / ${DB_PASS} (base ${DB_NAME})
EOF
