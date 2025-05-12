#!/bin/bash

# Fonction pour afficher des messages d'erreur
function print_error {
    echo -e "\033[31m[ERREUR] $1\033[0m"
}

# Fonction pour afficher des messages de succès
function print_success {
    echo -e "\033[32m[SUCCESS] $1\033[0m"
}

# Nettoyer et mettre à jour le cache de yum
print_success "Nettoyage du cache yum..."
sudo yum clean all
sudo yum makecache

# Vérification de l'existence des paquets nécessaires
print_success "Vérification de l'existence des paquets nécessaires..."

# Vérifier si NFS est installé
if ! rpm -q nfs-utils &> /dev/null; then
    print_error "NFS n'est pas installé. Installation en cours..."
    sudo yum install -y nfs-utils || { print_error "Échec de l'installation de NFS."; exit 1; }
    print_success "NFS installé avec succès."
else
    print_success "NFS est déjà installé."
fi

# Vérifier si Samba est installé
if ! rpm -q samba &> /dev/null; then
    print_error "Samba n'est pas installé. Installation en cours..."
    sudo yum install -y samba || { print_error "Échec de l'installation de Samba."; exit 1; }
    print_success "Samba installé avec succès."
else
    print_success "Samba est déjà installé."
fi

# Vérifier si smbclient est installé
if ! command -v smbclient &> /dev/null; then
    print_error "smbclient n'est pas installé. Installation en cours..."
    sudo yum install -y samba-client || { print_error "Échec de l'installation de smbclient."; exit 1; }
    print_success "smbclient installé avec succès."
else
    print_success "smbclient est déjà installé."
fi

# Créer les répertoires à partager
print_success "Création des répertoires à partager..."

NFS_SHARE_DIR="/srv/nfs/shared"
SAMBA_SHARE_DIR="/srv/samba/shared"

# Créer les répertoires s'ils n'existent pas déjà
if [ ! -d "$NFS_SHARE_DIR" ]; then
    sudo mkdir -p "$NFS_SHARE_DIR" || { print_error "Échec de la création du répertoire NFS."; exit 1; }
    sudo chmod 777 "$NFS_SHARE_DIR" || { print_error "Échec de la modification des permissions pour NFS."; exit 1; }
    print_success "Répertoire NFS créé et permissions modifiées."
else
    print_success "Le répertoire NFS existe déjà."
fi

if [ ! -d "$SAMBA_SHARE_DIR" ]; then
    sudo mkdir -p "$SAMBA_SHARE_DIR" || { print_error "Échec de la création du répertoire Samba."; exit 1; }
    sudo chmod 777 "$SAMBA_SHARE_DIR" || { print_error "Échec de la modification des permissions pour Samba."; exit 1; }
    print_success "Répertoire Samba créé et permissions modifiées."
else
    print_success "Le répertoire Samba existe déjà."
fi

# Configurer NFS pour partager le répertoire
print_success "Configuration du partage NFS..."

NFS_EXPORTS_FILE="/etc/exports"

if ! grep -q "$NFS_SHARE_DIR" "$NFS_EXPORTS_FILE"; then
    echo "$NFS_SHARE_DIR *(rw,sync,no_subtree_check,no_auth_nlm)" | sudo tee -a "$NFS_EXPORTS_FILE" \
        || { print_error "Échec de l'ajout de l'export NFS."; exit 1; }
    print_success "Partage NFS ajouté à /etc/exports."
else
    print_success "Le partage NFS est déjà configuré dans /etc/exports."
fi

# Redémarrer le service NFS
sudo systemctl restart nfs-server || { print_error "Échec de la mise à jour du service NFS."; exit 1; }
print_success "Service NFS redémarré avec succès."

# Configurer Samba pour partager le répertoire
print_success "Configuration du partage Samba..."

SAMBA_CONF_FILE="/etc/samba/smb.conf"

if ! grep -q "\[shared\]" "$SAMBA_CONF_FILE"; then
    sudo bash -c "cat <<EOT >> $SAMBA_CONF_FILE

[shared]
path = $SAMBA_SHARE_DIR
available = yes
valid users = nobody
read only = no
browsable = yes
public = yes
writable = yes
guest ok = yes
guest only = yes
EOT" || { print_error "Échec de l'ajout de la configuration Samba."; exit 1; }
    print_success "Partage Samba ajouté à $SAMBA_CONF_FILE."
else
    print_success "Le partage Samba est déjà configuré dans $SAMBA_CONF_FILE."
fi

# Redémarrer les services Samba
sudo systemctl restart smb || { print_error "Échec du redémarrage de Samba."; exit 1; }
sudo systemctl restart nmb || { print_error "Échec du redémarrage de NMB."; exit 1; }
print_success "Services Samba redémarrés avec succès."

# Activer les services Samba pour le démarrage automatique
sudo systemctl enable smb || { print_error "Échec de l'activation du service Samba."; exit 1; }
sudo systemctl enable nmb || { print_error "Échec de l'activation du service NMB."; exit 1; }
print_success "Services Samba activés pour le démarrage automatique."

# ---------------------------------------------------
# Section pare-feu avec vérification du port 445/tcp
# ---------------------------------------------------

print_success "Vérification de firewalld et ouverture du port Samba..."

# Installer firewalld si nécessaire
if ! command -v firewall-cmd &> /dev/null; then
    print_error "firewalld n'est pas installé. Installation en cours..."
    sudo yum install -y firewalld || { print_error "Échec de l'installation de firewalld."; exit 1; }
    print_success "firewalld installé avec succès."
else
    print_success "firewalld est déjà installé."
fi

# Démarrer firewalld si nécessaire
sudo systemctl start firewalld || { print_error "Échec du démarrage de firewalld."; exit 1; }
print_success "firewalld démarré."

# Ouvrir le port 445 seulement s'il n'est pas déjà ouvert
if ! sudo firewall-cmd --zone=public --query-port=445/tcp &> /dev/null; then
    print_success "Ouverture du port 445/tcp pour Samba..."
    sudo firewall-cmd --zone=public --add-port=445/tcp --permanent \
        || { print_error "Échec de l'ouverture du port 445."; exit 1; }
    sudo firewall-cmd --reload || { print_error "Échec du rechargement du pare-feu."; exit 1; }
    print_success "Port 445 ouvert et rechargé avec succès."
else
    print_success "Le port 445/tcp est déjà ouvert pour Samba. Aucun changement nécessaire."
fi

# Vérification des partages NFS et Samba
print_success "Vérification des partages NFS et Samba..."
sudo exportfs -v || { print_error "Échec de la vérification des partages NFS."; exit 1; }
sudo smbclient -L localhost -U% || { print_error "Échec de la vérification des partages Samba."; exit 1; }

# Vérification du statut des services
print_success "Vérification du statut des services NFS et Samba..."
sudo systemctl status nfs-server | grep "Active:" || { print_error "Le service NFS n'est pas actif."; exit 1; }
sudo systemctl status smb | grep "Active:" || { print_error "Le service Samba n'est pas actif."; exit 1; }

# Récupérer l'IP du serveur
SERVER_IP=$(hostname -I | awk '{print $1}')

# Instructions pour accéder depuis Windows
print_success "Tout est configuré ! Voici comment accéder aux partages depuis Windows :"

echo ""
echo "1. Ouvrez l'explorateur de fichiers de Windows."
echo "2. Rendez-vous dans \"Ce PC\"."
echo "3. Cliquez droit et ensuite cliquez gauchesur \"Ajouter un emplacement réseau\"."
echo "4. Suivez les étapes et entrez l'adresse suivante :"
echo "   \\\\$SERVER_IP\shared"
echo "5. Appuyez sur 'Entrée'."
echo ""
echo "Si vous êtes invité à entrer un nom d'utilisateur et un mot de passe, utilisez :"
echo "Nom d'utilisateur : guest"
echo "Mot de passe : (laissez vide)"
echo ""

print_success "Votre serveur est maintenant prêt à partager des dossiers via NFS et Samba sans authentification."
