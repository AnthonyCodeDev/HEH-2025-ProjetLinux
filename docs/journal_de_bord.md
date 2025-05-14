# Journal de bord

Ce document retrace, de manière chronologique, l’avancement du projet, les tâches effectuées, les difficultés rencontrées et les décisions prises.

---

## Semaine 1 (12/05/2025 – 15/05/2025)

### Jour 1 – 12-05-2025
- **Tâches réalisées :** 

  - *Guillaume*

  - Création du MOTD personnalisé :  
    ```bash
    sudo nano /etc/motd.d/99-custom-banner-99
    ```  
    Bannière incluse sur chaque serveur.  
  - Installation des serveurs Ubuntu 22.04 sur AWS EC2.  
  - Téléchargement et placement des clés SSH (`anthony.pem`, `guillaume.pem`).  
- **Configuration :**  
  - Ouverture du port SSH (22) dans les Security Groups.  
  - Liste des serveurs mise à jour :  
    - **Prod** : 10.42.0.198 (`ssh -i anthony.pem ec2-user@10.42.0.198`)  
    - **Dev Guillaume** : 10.42.0.53 (`ssh -i guillaume.pem ec2-user@10.42.0.53`)  
    - **Dev Anthony** : 10.42.0.26 (`ssh -i anthony.pem ec2-user@10.42.0.26`)  
- **Problèmes rencontrés :**  
  - Erreur de permissions sur la clé privée mal typée.  
- **Solutions apportées :**  
  - Recréation de la paire de clés, application de `chmod 600`.  
- **Temps passé :** 2 h  
- **Observations :**  
  - Vérifier systématiquement les permissions avant chaque connexion SSH.

### Jour 2 – 12-05-2025
- **Tâches réalisées :**  
  - Exécution du script `A_1_install_packages.sh` : installation de NFS, Samba, BIND9, Chrony.  
  - Exécution du script `A_2_configure_services.sh` : initialisation du partage FTP (vsftpd) et création des utilisateurs FTP.  
  - Mise en place des serveurs dédiés de sauvegarde et de monitoring.  
- **Configuration :**  
  - Mise à jour du mot de passe MySQL :  
    ```sql
    FLUSH PRIVILEGES;
    ALTER USER 'root'@'localhost' IDENTIFIED BY 'VotreNouveauMdp1!';
    FLUSH PRIVILEGES;
    EXIT;
    ```  
- **Problèmes rencontrés :**  
  - VSFTPD : “refusing to run with writable root inside chroot()”.  
- **Solutions apportées :**  
  - Ajustement des permissions sur le répertoire chroot et ajout de `allow_writeable_chroot=YES` dans `/etc/vsftpd.conf`.  
- **Temps passé :** 3 h  
- **Observations :**  
  - Tester l’accès FTP avec un compte utilisateur minimal.

### Jour 3 – 13-05-2025
- **Tâches réalisées :**  
  - Désinstallation complète de MariaDB/MySQL :  
    ```bash
    sudo systemctl stop mariadb.service
    sudo systemctl disable mariadb.service
    sudo apt-get purge -y mariadb-client mariadb-server mysql-client mysql-server
    sudo rm -rf /var/lib/mysql /etc/mysql /var/log/mysql*
    sudo userdel mysql || true
    sudo groupdel mysql || true
    ```  
- **Vérifications :**  
  - `which mysql` ne renvoie rien.  
  - `sudo systemctl status mariadb.service` confirme la suppression.  
- **Temps passé :** 2 h  
- **Observations :**  
  - Prévoir une installation propre si nécessaire sur un serveur dédié.

### Jour 4 – 14-05-2025
- **Tâches réalisées :**  
  - Rédaction du rapport final  
    - `rsync` des dossiers `/var/www` et `/etc`  
    - Dump des bases de données et upload S3 avec rotation (> 7 jours)  
- **Problèmes / Observations :**  
  - À automatiser via une tâche cron pour exécution quotidienne.

### Jour 5 – 15-05-2025
- **Tâches réalisées :**  
  - Présentation du projet devant les professeurs.
- **Problèmes rencontrés :**  
  - ... 
- **Solutions en cours :**  
  - ...

---

## Chapitres suivants

- **Lundi 12/05/2025 :** Sécurisation (UFW, quotas, AppArmor), script `A_4_secure.sh`  
- **Mardi 13/05/2025 :** Finalisation des derniers scripts, sécurité, etc..  
- **Mercredi 14/05/2025 :** Correction des derniers bugs + créer le script qui lancera tout a la fois  
- **Jeudi 15/05/2025  :** Préparation de la démonstration et rapport final

---

> **Conseils :**  
> - Rédigez le journal a la fin de la journée, idéalement chaque soir.  
> - Indiquez toujours les commandes exactes et les chemins de fichiers modifiés.  
> - Notez le temps passé et conclure par une leçon apprise ou une piste d’amélioration.  
