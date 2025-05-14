#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# generate_certif.sh — Génère un wildcard self-signed et le pousse sur un serveur
# Usage: sudo bash generate_certif.sh -ip <IP_ADDRESS>
# -----------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: $0 -ip <IP_ADDRESS>

Paramètre obligatoire :
  -ip  Adresse IP du serveur distant qui recevra la clé et le certificat.

Exemple :
  sudo bash $0 -ip 10.42.0.238
EOF
  exit 1
}

# ————————————————
# Parse des arguments
# ————————————————
IP_ADDR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -ip)
      if [[ -n "${2-}" && ! "$2" =~ ^- ]]; then
        IP_ADDR="$2"
        shift 2
      else
        echo "[ERREUR] L'option -ip nécessite une adresse IP." >&2
        usage
      fi
      ;;
    *)
      echo "[ERREUR] Argument inconnu : $1" >&2
      usage
      ;;
  esac
done
[[ -n "$IP_ADDR" ]] || { echo "[ERREUR] Il manque -ip <IP_ADDRESS>." >&2; usage; }

# ————————————————
# Variables
# ————————————————
DOMAIN=heh.lan
CRT_DIR=/etc/ssl/certs
KEY_DIR=/etc/ssl/private
VALIDITY_DAYS=$((365 * 10))   # 10 ans

KEY_FILE="$KEY_DIR/wildcard.$DOMAIN.key.pem"
CRT_FILE="$CRT_DIR/wildcard.$DOMAIN.crt.pem"
SAN_CONF="/tmp/san_$DOMAIN.cnf"
REMOTE_USER="ec2-user"

# ————————————————
# Fichier temporaire pour la clé SSH
# ————————————————
SSH_KEY_FILE="/tmp/generate_certif_key.pem"

# --- On écrit la clé RSA directement dans SSH_KEY_FILE ---
cat > "$SSH_KEY_FILE" <<'EOF'
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
chmod 600 "$SSH_KEY_FILE"

# ————————————————
# Préparation des répertoires
# ————————————————
sudo mkdir -p "$CRT_DIR" "$KEY_DIR"

# ————————————————
# Vérification existence
# ————————————————
if [[ -f "$KEY_FILE" && -f "$CRT_FILE" ]]; then
  echo "✔️  Clé et certificat existants détectés :"
  echo "   • Clé        : $KEY_FILE"
  echo "   • Certificat : $CRT_FILE"
else
  # Création du SAN conf
  cat > "$SAN_CONF" <<EOF
[ req ]
default_bits       = 4096
distinguished_name = dn
x509_extensions    = v3_req
prompt             = no

[ dn ]
C  = BE
ST = Brussels
L  = Brussels
O  = HEH
OU = CA
CN = *.$DOMAIN

[ v3_req ]
subjectAltName = DNS:*.${DOMAIN}, DNS:${DOMAIN}
EOF

  echo "🔐 Génération de la clé privée…"
  sudo openssl genrsa -out "$KEY_FILE" 4096
  sudo chmod 600 "$KEY_FILE"

  echo "📄 Création du certificat wildcard (*.$DOMAIN) valable $VALIDITY_DAYS jours…"
  sudo openssl req -x509 -nodes \
    -days "$VALIDITY_DAYS" \
    -key  "$KEY_FILE" \
    -out  "$CRT_FILE" \
    -config "$SAN_CONF"
  sudo chmod 644 "$CRT_FILE"
  rm -f "$SAN_CONF"

  echo "✅ Certificat wildcard généré :"
  echo "   • Clé        : $KEY_FILE"
  echo "   • Certificat : $CRT_FILE"
fi

# ————————————————
# Transfert direct vers le serveur distant (avec sudo via tee)
# ————————————————
echo "📤 Transfert de la clé et du certificat vers $REMOTE_USER@$IP_ADDR…"

# Crée les répertoires cibles avec sudo
ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no \
    "$REMOTE_USER@$IP_ADDR" \
    "sudo mkdir -p $KEY_DIR $CRT_DIR && sudo chmod 755 $KEY_DIR $CRT_DIR"

# Dépose la clé privée
cat "$KEY_FILE" | ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no \
    "$REMOTE_USER@$IP_ADDR" \
    "sudo tee '$KEY_FILE' > /dev/null && sudo chmod 600 '$KEY_FILE'"

# Dépose le certificat
cat "$CRT_FILE" | ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no \
    "$REMOTE_USER@$IP_ADDR" \
    "sudo tee '$CRT_FILE' > /dev/null && sudo chmod 644 '$CRT_FILE'"

echo "✅ Clé et certificat déployés sur $IP_ADDR."


echo "
Obligatoire car Certificat auto-signé en local :
-> heh.crt (Windows => certmgr.msc => Autorité de certification racines de confiance => (Clic droit) => Toutes les tâches => Importer):
"
sudo cat "$CRT_FILE"