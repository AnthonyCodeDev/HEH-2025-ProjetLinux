#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# H_11_setup_auto_updates.sh
# Installe et active les mises à jour automatiques de sécurité via dnf-automatic,
# de façon idempotente (vérifie l'installation, sauvegarde la config si nécessaire).
# Usage: sudo ./H_11_setup_auto_updates.sh
# ----------------------------------------------------------------------------
set -euo pipefail
IFS=$' \t\n'

# 1. Vérifier les droits
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Ce script doit être exécuté en tant que root." >&2
  exit 1
fi

dnf_auto_pkg="dnf-automatic"
config_file="/etc/dnf/automatic.conf"
backup_file="${config_file}.orig"

# 2. Installer le paquet si absent
if ! rpm -q $dnf_auto_pkg &>/dev/null; then
  echo "[INFO] Paquet $dnf_auto_pkg non installé. Installation..."
  dnf install -y $dnf_auto_pkg
  echo "[INFO] Installation terminée."
else
  echo "[INFO] $dnf_auto_pkg déjà installé."
fi

# 3. Sauvegarde de la configuration d'origine
if [[ -f "$config_file" ]]; then
  if [[ ! -f "$backup_file" ]]; then
    echo "[INFO] Sauvegarde de la config existante vers $backup_file"
    cp "$config_file" "$backup_file"
  else
    echo "[INFO] Backup déjà présent ($backup_file)."
  fi
else
  echo "[WARN] Fichier de configuration $config_file introuvable. Création d'une config vierge."
  mkdir -p "$(dirname "$config_file")"
  touch "$config_file"
fi

# 4. Écriture de la nouvelle configuration
cat > "$config_file" <<'EOF'
[commands]
# Seulement les errata de type security
upgrade_type = security
# Applique automatiquement
apply_updates = yes

[emitters]
# Emission vers stdout (journal)
emit_via = stdio

[logging]
# Niveau minimal : info suffit pour tracer les mises à jour
level = info
EOF

echo "[INFO] Configuration mise à jour dans $config_file"

# 5. Activer et démarrer le timer systemd
echo "[INFO] Activation du timer dnf-automatic..."
systemctl daemon-reload
systemctl enable --now dnf-automatic.timer

# 6. Vérification du statut
echo "[OK] Timer dnf-automatic status:"
systemctl is-active dnf-automatic.timer && echo "  => actif" || echo "  => inactif"

# 7. Exemple de consultation des logs
cat << 'USAGE'

Pour voir l'historique des mises à jour automatiques:
  journalctl -u dnf-automatic.service --no-pager

Pour les logs du timer:
  journalctl -u dnf-automatic.timer --no-pager
USAGE
