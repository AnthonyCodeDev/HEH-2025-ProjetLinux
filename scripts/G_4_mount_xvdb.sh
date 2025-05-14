#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# mount_xvdb.sh
# Script pour détecter, formater si nécessaire et monter /dev/xvdb sur /var/www,
# avec vérifications et mise à jour de /etc/fstab, puis vérification finale même si déjà monté.
# Usage: sudo ./mount_xvdb.sh
# ----------------------------------------------------------------------------
set -euo pipefail
IFS=$' \t\n'

DEVICE="/dev/xvdb"
MOUNT_POINT="/var/www"
FSTAB="/etc/fstab"

# 1. Vérifier l'exécution en root
if [[ $(id -u) -ne 0 ]]; then
  echo "[ERROR] Ce script doit être exécuté en root." >&2
  exit 1
fi

# 2. Vérifier que le device existe
if [[ ! -b "$DEVICE" ]]; then
  echo "[ERROR] Périphérique $DEVICE introuvable." >&2
  exit 1
fi

# 3. Créer le point de montage si nécessaire
if [[ ! -d "$MOUNT_POINT" ]]; then
  echo "[INFO] Création du répertoire de montage $MOUNT_POINT"
  mkdir -p "$MOUNT_POINT"
fi

# 4. Déterminer UUID pour l'entrée fstab et pattern de vérification
UUID=$(blkid -s UUID -o value "$DEVICE" || true)
if [[ -n "$UUID" ]]; then
  FSTAB_KEY="UUID=$UUID"
else
  FSTAB_KEY="$DEVICE"
fi

# 5. Vérifier si déjà monté
ALREADY_MOUNTED=false
if mountpoint -q "$MOUNT_POINT"; then
  echo "[INFO] $DEVICE est déjà monté sur $MOUNT_POINT."
  ALREADY_MOUNTED=true
fi

# 6. Si non monté, formater/sélectionner FS et ajouter dans fstab
if [[ "$ALREADY_MOUNTED" = false ]]; then
  FS_TYPE=$(blkid -s TYPE -o value "$DEVICE" || true)
  if [[ -z "$FS_TYPE" ]]; then
    echo "[INFO] Aucun filesystem détecté sur $DEVICE. Formatage en ext4..."
    mkfs.ext4 -F "$DEVICE"
    FS_TYPE="ext4"
  elif [[ "$FS_TYPE" != "ext4" ]]; then
    echo "[WARNING] Filesystem existant ($FS_TYPE) n'est pas ext4. Tentative de montage direct."
  fi

  ENTRY="$FSTAB_KEY    $MOUNT_POINT    $FS_TYPE    defaults,nofail    0    2"
  if ! grep -Eq "^[[:space:]]*$FSTAB_KEY[[:space:]]" "$FSTAB"; then
    echo "[INFO] Ajout de l'entrée dans $FSTAB"
    echo "$ENTRY" >> "$FSTAB"
  else
    echo "[INFO] Une entrée pour $FSTAB_KEY existe déjà dans $FSTAB."
  fi

  echo "[INFO] Montage de $DEVICE sur $MOUNT_POINT"
  mount "$MOUNT_POINT"
fi

# 7. Finish et vérification finale
if mountpoint -q "$MOUNT_POINT"; then
  echo "[OK] $DEVICE monté sur $MOUNT_POINT"
else
  echo "[ERROR] Montage de $DEVICE sur $MOUNT_POINT manquant." >&2
  exit 1
fi

echo "finish"

echo "[INFO] Démarrage de la vérification finale..."
# 7.1 Entrée fstab
if grep -Eq "^[[:space:]]*$FSTAB_KEY[[:space:]]" "$FSTAB"; then
  echo "[OK] Entrée dans /etc/fstab confirmée"
else
  echo "[ERROR] Entrée manquante dans /etc/fstab" >&2
fi
# 7.2 Monture active
if mountpoint -q "$MOUNT_POINT"; then
  echo "[OK] Montage actif confirmé"
else
  echo "[ERROR] Montage non actif" >&2
fi
# 7.3 Test d'écriture
TEST_FILE="$MOUNT_POINT/.test_write"
if touch "$TEST_FILE" && rm -f "$TEST_FILE"; then
  echo "[OK] Test d'écriture réussi"
else
  echo "[ERROR] Échec du test d'écriture" >&2
fi

echo "[INFO] Vérification finale terminée"
exit 0