#!/usr/bin/env bash
set -euo pipefail

# Usage :
#   sudo bash setup_client.sh -u user1 [user2 …] -p PASSWORD -d DOMAIN

### ——————————————————————————
### Couleurs & helpers
### ——————————————————————————
RED=$'\e[31m'; GREEN=$'\e[32m'; BLUE=$'\e[34m'; RESET=$'\e[0m'
function err  { printf "%b[ERREUR] %s%b\n" "$RED" "$1" "$RESET" >&2; exit 1; }
function succ { printf "%b[OK]    %s%b\n" "$GREEN" "$1" "$RESET"; }
function info { printf "%b[INFO]   %s%b\n" "$BLUE" "$1" "$RESET"; }

### 1) Parse options
PASSWORD=''; DOMAIN=''; USERS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -u) shift; while [[ $# -gt 0 && $1 != -* ]]; do USERS+=("$1"); shift; done ;;
    -p) PASSWORD=$2; shift 2 ;;
    -d) DOMAIN=$2;   shift 2 ;;
    *)  err "Usage : $0 -u user1 [user2 …] -p PASSWORD -d DOMAIN" ;;
  esac
done
[ ${#USERS[@]} -ge 1 ]  || err "Il faut au moins un utilisateur après -u"
[ -n "$PASSWORD" ]     || err "Il manque -p PASSWORD"
[ -n "$DOMAIN"   ]     || err "Il manque -d DOMAIN"

# mot de passe root MariaDB
ROOT_PW='VotreNouveauMdp1!'

succ "Domaine    : ${DOMAIN}"
succ "Password clients : ${PASSWORD}"
succ "Clients à provisionner : ${USERS[*]}"

### 2) Détection pkg manager & SQL client
PKG_MGR=""; CLIENT_PKG=""
. /etc/os-release 2>/dev/null || true
case "${ID:-}-${VERSION_ID:-}" in
  amzn-2023)      PKG_MGR=dnf;     CLIENT_PKG=mariadb105;;
  amzn-2)         PKG_MGR=yum;     CLIENT_PKG=mariadb;;
  ubuntu*|debian*)PKG_MGR=apt-get; CLIENT_PKG=mariadb-client;;
  *)              PKG_MGR=$(command -v dnf||command -v yum||echo apt-get); CLIENT_PKG=mariadb-client;;
esac
succ "Package manager: ${PKG_MGR}, SQL client: ${CLIENT_PKG}"

install_if_missing(){
  local bin=$1 pkg=$2
  if ! command -v "$bin" &>/dev/null; then
    sudo ${PKG_MGR} install -y "$pkg" && succ "$pkg installé" || err "Impossible d'installer $pkg"
  else
    succ "$pkg déjà présent"
  fi
}

### 3) Installation/activation services (une seule fois)
for pkg in nginx openssl vsftpd samba "${CLIENT_PKG}"; do
  [ "$PKG_MGR" = "apt-get" ] && [ "$pkg" = "${CLIENT_PKG}" ] && sudo apt-get update -y
  install_if_missing "$pkg" "$pkg"
done
for svc in nginx vsftpd smb nmb mariadb; do
  sudo systemctl enable --now "$svc" &>/dev/null && succ "Service $svc activé"
done

### 4) Init MariaDB datadir (une seule fois)
if [ "${CLIENT_PKG}" = "mariadb105" ]; then SERVER_PKG="mariadb105-server"; else SERVER_PKG="${CLIENT_PKG%-client}-server"; fi
install_if_missing "$SERVER_PKG" "$SERVER_PKG"
if [ ! -d /var/lib/mysql/mysql ]; then
  succ "Initialisation du datadir MariaDB"
  sudo mariadb-install-db --user=mysql --datadir=/var/lib/mysql \
    && succ "Datadir initialisé" || err "Échec init datadir"
  sudo chown -R mysql:mysql /var/lib/mysql
fi
sudo mkdir -p /var/run/mysqld && sudo chown mysql:mysql /var/run/mysqld

### 5) Configurer root MySQL (idempotent)
echo "→ Vérification du plugin root@localhost"
if plugin=$(sudo mysql --batch --skip-column-names --protocol=socket --user=root \
    -p"${ROOT_PW}" -e "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost';" 2>/dev/null) \
  || plugin=$(sudo mysql --batch --skip-column-names --protocol=socket --user=root \
    -e "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost';"); then

  if [ "$plugin" != "mysql_native_password" ]; then
    echo "→ Passage en mysql_native_password"
    if [ "$plugin" = "unix_socket" ]; then
      sudo mysql --protocol=socket --user=root <<SQL
ALTER USER 'root'@'localhost'
  IDENTIFIED VIA mysql_native_password
  USING PASSWORD('${ROOT_PW}');
FLUSH PRIVILEGES;
SQL
    else
      sudo mysql --protocol=socket --user=root -p"${ROOT_PW}" <<SQL
ALTER USER 'root'@'localhost'
  IDENTIFIED VIA mysql_native_password
  USING PASSWORD('${ROOT_PW}');
FLUSH PRIVILEGES;
SQL
    fi
    succ "root@localhost en mysql_native_password"
  else
    succ "root@localhost déjà en mysql_native_password"
  fi
else
  err "Impossible de détecter le plugin root"
fi

### 6) Configurer SSHD (password auth)
SSHD=/etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD"
sudo sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' "$SSHD"
sudo sed -i 's/^#\?UsePAM.*/UsePAM yes/' "$SSHD"
sudo systemctl reload sshd && succ "sshd rechargé avec PasswordAuth"

### 7) Configurer vsftpd pour options essentielles et désactiver userlist
VSF=/etc/vsftpd/vsftpd.conf
sudo sed -i 's/^#\?local_enable=.*/local_enable=YES/'      "$VSF"
sudo sed -i 's/^#\?write_enable=.*/write_enable=YES/'      "$VSF"
sudo sed -i 's/^#\?chroot_local_user=.*/chroot_local_user=YES/' "$VSF"
# commenter les userlist_*
sudo sed -i 's/^\(userlist_enable\|userlist_file\|userlist_deny\)=.*$/# &/' "$VSF"
if ! grep -q '^allow_writeable_chroot=' "$VSF"; then
  echo 'allow_writeable_chroot=YES' | sudo tee -a "$VSF"
fi
sudo systemctl restart vsftpd && succ "vsftpd reconfiguré"

### 8) Boucle de configuration pour chaque client
for USER_NAME in "${USERS[@]}"; do
  WEB_DIR="/var/www/${USER_NAME}"
  VHOST="/etc/nginx/conf.d/${DOMAIN}.conf"
  DB_NAME="${USER_NAME}_db"
  DB_USER="${USER_NAME}"
  DB_PASS="${PASSWORD}"

  # Si l'utilisateur existe déjà et que son répertoire web est en place, on passe
  if id "$USER_NAME" &>/dev/null && [ -d "$WEB_DIR" ]; then
    info "Utilisateur ${USER_NAME} existe déjà, configuration ignorée"
    continue
  fi

  succ "=== Configuration de $USER_NAME ==="

  # SQL : base & user
  sudo mysql --protocol=socket -uroot -p"${ROOT_PW}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
  succ "SQL : base & user pour $USER_NAME"

  # Utilisateur système
  if ! id "$USER_NAME" &>/dev/null; then
    sudo useradd -m -d "$WEB_DIR" -s /bin/bash "$USER_NAME"
    succ "Utilisateur système $USER_NAME ajouté (home=$WEB_DIR)"
  else
    sudo usermod -d "$WEB_DIR" -s /bin/bash "$USER_NAME"
    succ "Home de $USER_NAME mis à $WEB_DIR"
  fi
  echo "$USER_NAME:${PASSWORD}" | sudo chpasswd
  succ "Mot de passe système défini pour $USER_NAME"

  # ~/.bash_profile
  sudo tee "${WEB_DIR}/.bash_profile" >/dev/null <<'EOF'
# Source global configs
[ -f /etc/profile ] && . /etc/profile
[ -f /etc/bashrc ]   && . /etc/bashrc
# Aller dans le dossier home (web dir)
cd "$HOME"
EOF
  succ "~/.bash_profile créé pour $USER_NAME"

  # Web dir & vHost nginx
  [ ! -d "$WEB_DIR" ] && sudo mkdir -p "$WEB_DIR"
  sudo chown -R "${USER_NAME}:${USER_NAME}" "$WEB_DIR"
  sudo chmod -R 755 "$WEB_DIR"
  succ "Web dir $WEB_DIR prêt"
  if [ ! -f "$VHOST" ]; then
    sudo tee "$VHOST" >/dev/null <<EOF
server {
  listen 80;
  server_name ${DOMAIN};
  root ${WEB_DIR};
  index index.html index.htm;
  location / { try_files \$uri \$uri/ =404; }
}
EOF
    succ "vHost nginx ajouté pour ${DOMAIN}"
    sudo nginx -t && sudo systemctl reload nginx && succ "nginx rechargé"
  else
    succ "vHost pour ${DOMAIN} déjà existant"
  fi

  # FTP (vsftpd)
  if ! grep -qx "$USER_NAME" /etc/vsftpd/user_list; then
    echo "$USER_NAME" | sudo tee -a /etc/vsftpd/user_list >/dev/null
    sudo systemctl restart vsftpd && succ "FTP configuré pour $USER_NAME"
  else
    succ "FTP déjà configuré pour $USER_NAME"
  fi

  # Samba
  if ! grep -q "^\[${USER_NAME}\]" /etc/samba/smb.conf; then
    sudo tee -a /etc/samba/smb.conf >/dev/null <<EOF

[${USER_NAME}]
  path = ${WEB_DIR}
  valid users = ${USER_NAME}
  browsable = yes
  writable = yes
  create mask = 0644
  directory mask = 0755
EOF
    (echo "${PASSWORD}"; echo "${PASSWORD}") | sudo smbpasswd -a -s "${USER_NAME}"
    sudo systemctl restart smb nmb && succ "Samba configuré pour $USER_NAME"
  else
    succ "Samba déjà configuré pour $USER_NAME"
  fi

  # Récapitulatif
  cat <<EOF

=== IDENTIFIANTS ${USER_NAME} ===
• Domaine     : http://${DOMAIN}
• Web dir     : ${WEB_DIR}
• Système     : ${USER_NAME} / ${PASSWORD}
• FTP/Samba   : ${USER_NAME} / ${PASSWORD}
• SQL root    : root / ${ROOT_PW}
• SQL client  : ${DB_USER} / ${DB_PASS} (base ${DB_NAME})

EOF
done

succ "Tous les clients (${USERS[*]}) ont été configurés."