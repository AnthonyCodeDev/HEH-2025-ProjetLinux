# Journal de bord

Ce document retrace, de manière chronologique, l’avancement du projet, les tâches effectuées, les difficultés rencontrées et les décisions prises.

---

## Semaine du 12/05/2025 – 15/05/2025

### Jour 1 – 12-05-2025
- **Tâches réalisées :** 

  - Création du MOTD personnalisé :  
  - Installation des serveurs Ubuntu 22.04 sur AWS EC2.  
  - Téléchargement et placement des clés SSH (`anthony.pem`, `guillaume.pem`).
  - Création des scripts : 
    ```
    - A_0_setup_nfs_samba.sh : script qui permet de setup NFS et SAMBA.
    - A_1_setup_client.sh : script qui permet de créer un utilisateur (client).
    - A_2_monitoring.sh : script qui permet la configurationdu monitoring centralisé via une interface web
    - G_0_client-ntp.sh : script qui permet de setup le nfs sur un client.
    - G_1_setup-ntp.sh : script qui permet de setup le service NTP sur un serveur.
    - G_2_secure-ssh.sh : script qui permet de configurer le ssh sécurise sur le serveur.
    ``` 
- **Problèmes rencontrés :**  
  - Erreur de permissions sur les clé privée mal typée.  

### Jour 2 – 12-05-2025
- **Tâches réalisées :**  
  - Exécution du script `A_1_install_packages.sh` : installation de NFS, Samba, BIND9, Chrony.  
  - Exécution du script `A_2_configure_services.sh` : initialisation du partage FTP (vsftpd) et création des utilisateurs FTP.  
  - Mise en place des serveurs dédiés de sauvegarde et de monitoring.
  - Création des scripts : 
    ```
    - A_3_backup_server.sh : script qui permet de faire des backups..
    - A_4_security.sh : script qui permet de gerer toute la sécurité du serveur.
    - G_3_setup-dns.sh : script qui permet la configurationdu du DNS.
    ``` 
- **Problèmes rencontrés :**  
  - VSFTPD : “refusing to run with writable root inside chroot()”.  

### Jour 3 – 13-05-2025
- **Tâches réalisées :**
  - Création du README.md pour le projet
  - Création des scripts : 
    ```
      - A_5_generate_certif.sh : script qui permet de generer des certificats ssl auto signer.
      - A_6_go.sh : script qui permet de faire lancer tout les script en une fois.
      - G_set-vpn-ip-dns.ps1 : script qui permet de setup une adresse ip sur un client windows pour openvpn.
      - G_4_mount_xvdb.sh : script qui permet de monter sur xvdb.
      - G_5_uptime-kuma.sh : script qui permet de configurer un service de monitoring pour les serveurs mis en place.
    ```
- **Problèmes rencontrés :**  


### Jour 4 – 14-05-2025
- **Tâches réalisées :**  
  - Rédaction du rapport final  
    - `rsync` des dossiers `/var/www` et `/etc`  
    - Dump des bases de données et upload S3 avec rotation (> 7 jours)  
- **Problèmes / Observations :**  
  - À automatiser via une tâche cron pour exécution quotidienne.

### Jour 5 – 15-05-2025
- **Tâches réalisées :**
  - Mise en place des différents serveurs.
  - Création du script go qui permet de lancer tout le projet en 1 fois.
  - Présentation du projet devant les professeurs.
- **Problèmes rencontrés :**  
  - ... 

> **Conseils :**  
> - Rédigez le journal a la fin de la journée, idéalement chaque soir.  
> - Indiquez toujours les commandes exactes et les chemins de fichiers modifiés.  
> - Notez le temps passé et conclure par une leçon apprise ou une piste d’amélioration.  
