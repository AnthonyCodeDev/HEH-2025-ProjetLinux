#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 -data <IP_DATA> -certificat <IP_CERT> -monitoring <IP_MON> -time <IP_TIME> -backup <IP_BACKUP>"
  exit 1
}

# Au moins 10 arguments attendus (5 options + 5 valeurs)
if [ "$#" -lt 10 ]; then
  usage
fi

# Lecture des options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -data)
      DATA_IP="$2"; shift 2
      ;;
    -certificat)
      CERT_IP="$2"; shift 2
      ;;
    -monitoring)
      MONITORING_IP="$2"; shift 2
      ;;
    -time)
      TIME_IP="$2"; shift 2
      ;;
    -backup)
      BACKUP_IP="$2"; shift 2
      ;;
    *)
      echo "Option inconnue : $1"
      usage
      ;;
  esac
done

# Vérification que toutes les variables sont définies
for var in DATA_IP CERT_IP MONITORING_IP TIME_IP BACKUP_IP; do
  if [[ -z "${!var:-}" ]]; then
    echo "Erreur : la variable $var n'est pas définie"
    usage
  fi
done

echo "Variables configurées :
  DATA_IP=$DATA_IP
  CERT_IP=$CERT_IP
  MONITORING_IP=$MONITORING_IP
  TIME_IP=$TIME_IP
  BACKUP_IP=$BACKUP_IP"


SSH_USER="ec2-user"
PRIVATE_KEY_FILE="./cert_key.pem"
REPO_URL="https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux.git"
LOCAL_CERT_DIR="./certs"

#
# 1) On génère la clé privée locale
#
cat > "${PRIVATE_KEY_FILE}" << 'EOF'
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
EOF
chmod 400 "${PRIVATE_KEY_FILE}"

#
# FONCTION UTILE SSH
#
run_remote() {
  local target_ip=$1
  shift
  ssh -o StrictHostKeyChecking=no -i "${PRIVATE_KEY_FILE}" \
      "${SSH_USER}@${target_ip}" bash -lc "$*"
}

#
# 2) SERVEUR DE DATA — NFS/SAMBA
#
echo ">>> Configuration du serveur DATA (${DATA_IP})"
run_remote "${DATA_IP}" "
  sudo dnf install -y git &&
  git clone ${REPO_URL} ~/HEH-2025-ProjetLinux || true &&
  cd ~/HEH-2025-ProjetLinux/scripts &&
  sudo bash A_0_setup_nfs_samba.sh
"

#
# 3) SERVEUR DE CERTIFICAT — génération des certificats
#
echo ">>> Configuration du serveur CERTIFICAT (${CERT_IP})"
run_remote "${CERT_IP}" "
  sudo dnf install -y git &&
  git clone ${REPO_URL} ~/HEH-2025-ProjetLinux || true &&
  cd ~/HEH-2025-ProjetLinux/scripts &&
  sudo bash A_5_generate_certif.sh \
    -ip ${DATA_IP} \
"

scp -o StrictHostKeyChecking=no -i "${PRIVATE_KEY_FILE}" \
    "${SSH_USER}@${CERT_IP}:/etc/ssl/certs/wildcard.heh.lan.crt.pem" \
    ./windows.crt
# 4) RÉCUPÉRATION DES CERTIFICATS EN LOCAL
echo ">>> Récupération du(s) certificat(s) en local"
mkdir -p "${LOCAL_CERT_DIR}"

DOMAIN="heh.lan"

# Récupérer la clé privée via sudo cat (scp ne peut pas accéder à /etc/ssl/private/)
ssh -o StrictHostKeyChecking=no -i "${PRIVATE_KEY_FILE}" \
    "${SSH_USER}@${CERT_IP}" \
    "sudo cat /etc/ssl/private/wildcard.${DOMAIN}.key.pem" \
    > "${LOCAL_CERT_DIR}/wildcard.${DOMAIN}.key.pem"
chmod 600 "${LOCAL_CERT_DIR}/wildcard.${DOMAIN}.key.pem"

# Récupérer le certificat (généralement lisible sans sudo)
scp -o StrictHostKeyChecking=no -i "${PRIVATE_KEY_FILE}" \
  "${SSH_USER}@${CERT_IP}:/etc/ssl/certs/wildcard.${DOMAIN}.crt.pem" \
  "${LOCAL_CERT_DIR}/wildcard.${DOMAIN}.crt.pem"

echo "✅ Clé et certificat récupérés dans : ${LOCAL_CERT_DIR}/"


#
# 5) SERVEUR DE MONITORING — clone + installation + monitoring
#
echo ">>> Configuration du serveur MONITORING (${MONITORING_IP})"
run_remote "${MONITORING_IP}" "
  sudo dnf install -y git &&
  git clone ${REPO_URL} ~/HEH-2025-ProjetLinux || true
"
scp -o StrictHostKeyChecking=no -i "${PRIVATE_KEY_FILE}" \
    "${LOCAL_CERT_DIR}/"*.pem \
    "${SSH_USER}@${MONITORING_IP}:/home/ec2-user/HEH-2025-ProjetLinux/scripts/"
run_remote "${MONITORING_IP}" "
  cd ~/HEH-2025-ProjetLinux/scripts &&
  sudo bash A_1_setup_client.sh -u monitoring -p pass &&
  sudo bash A_2_monitoring.sh -d ${DATA_IP}
"

#
# 6) AJOUT DU CLIENT MONITORING ET BACKUP SUR DATA
#
echo ">>> Ajout des clients MONITORING & BACKUP sur DATA (${DATA_IP})"
run_remote "${DATA_IP}" "
  cd ~/HEH-2025-ProjetLinux/scripts &&
  sudo bash A_1_setup_client.sh -u monitoring anthony guillaume -p pass &&
  sudo bash A_1_setup_client.sh -u backup -p pxmiXvkEte808X &&
  sudo bash A_2_monitoring.sh -d ${DATA_IP} &&
  sudo bash G_3_setup-dns.sh
"

#
# 7) SERVEUR DE TEMPS — NTP
#
echo ">>> Configuration du serveur TEMPS (${TIME_IP})"
run_remote "${TIME_IP}" "
  sudo dnf install -y git &&
  git clone ${REPO_URL} ~/HEH-2025-ProjetLinux || true &&
  cd ~/HEH-2025-ProjetLinux/scripts &&
  sudo bash G_1_setup-ntp.sh ${DATA_IP}
"

#
# 8) SERVEUR DE BACKUP — clone + client + backup
#
echo ">>> Configuration du serveur BACKUP (${BACKUP_IP})"
run_remote "${BACKUP_IP}" "
  sudo dnf install -y git &&
  git clone ${REPO_URL} ~/HEH-2025-ProjetLinux || true
"
scp -o StrictHostKeyChecking=no -i "${PRIVATE_KEY_FILE}" \
    "${LOCAL_CERT_DIR}/"*.pem \
    "${SSH_USER}@${BACKUP_IP}:/home/ec2-user/HEH-2025-ProjetLinux/scripts/"

run_remote "${BACKUP_IP}" "
  sudo cp ~/HEH-2025-ProjetLinux/scripts/A_3_backup_server.sh /usr/local/bin/backup_script.sh
  sudo chmod +x /usr/local/bin/backup_script.sh
  sudo /usr/local/bin/backup_script.sh
"

#
# 9) SERVEUR UPTIME KUMA
#

echo ">>> Configuration du serveur MONITORING (UPTIME KUMA) (${MONITORING_IP})"
run_remote "${MONITORING_IP}" "
  cd ~/HEH-2025-ProjetLinux/scripts &&
  sudo bash G_5_uptime-kuma.sh \
    -data ${DATA_IP} \
    -certificat ${CERT_IP} \
    -monitoring ${MONITORING_IP} \
    -time ${TIME_IP} \
    -backup ${BACKUP_IP}
"
echo ""
echo ">>> Tous les serveurs sont configurés ✅"
echo "1. Serveur de Donnée: https://anthony.heh.lan"
echo "2. Serveur de Monitoring: $MONITORING_IP:9090"
echo "3. Serveur de Uptime Kuma: $MONITORING_IP:3001/dashboard"
echo " - Client Uptime Kuma: Utilisateur: admin - Mot de passe: admin123"
echo "4. Serveur de Backup: $BACKUP_IP"
echo "5. Serveur de Temps: $TIME_IP"
echo "6. Serveur de Certificat: $CERT_IP"
echo " - Client Samba: \\\\$DATA_IP\shared (guest, no password)"
echo " - Client FTP: IP: $DATA_IP - Port: 21 - Utilisateur: anthony - Mot de passe: pass"