## Bienvenue dans le dossier `scripts` !

Ce dépôt contient une collection de scripts bash conçus pour automatiser la configuration et la gestion de serveurs Linux et de leurs clients. Ces scripts simplifient des tâches complexes comme le partage de fichiers, la gestion des utilisateurs, la sécurité, la surveillance et les sauvegardes. Un script PowerShell est également inclus pour les configurations Windows.

### Aperçu des scripts

*   **[A_0_setup_nfs_samba.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_0_setup_nfs_samba.sh)**: Déploie des partages de fichiers NFS et Samba en un clin d'œil. Configure les répertoires partagés, ajuste les permissions et ouvre les ports du firewall.

*   **[A_1_setup_client.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_1_setup_client.sh)**: Prépare l'environnement client avec la création d'utilisateurs, de bases de données et de répertoires web, sans oublier l'accès FTP.

*   **[A_2_monitoring.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_2_monitoring.sh)**: Active la surveillance du serveur via Cockpit, le tout dans un conteneur Docker.

*   **[A_3_backup_server.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_3_backup_server.sh)**: Met en place une stratégie de sauvegarde robuste avec un utilisateur dédié et des tâches cron automatisées.

*   **[A_4_security.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_4_security.sh)**: Renforce la sécurité du serveur en configurant les firewalls, en durcissant SSH et en installant Fail2Ban et AIDE.

*   **[A_5_generate_certif.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_5_generate_certif.sh)**: Génère un certificat SSL wildcard auto-signé et le déploie sur un serveur distant pour sécuriser les communications.

*   **[G_0_client-ntp.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/G_0_client-ntp.sh)**: Configure un client NTP (Network Time Protocol) avec Chrony pour une synchronisation précise de l'heure.

*   **[G_1_setup-ntp.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/G_1_setup-ntp.sh)**: Configure un serveur NTP avec Chrony et distribue le script de configuration client aux machines du réseau.

*   **[G_2_secure-ssh.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/G_2_secure-ssh.sh)**: Sécurise davantage l'accès SSH, y compris l'installation de fail2ban et un panneau de rapport.

*   **[G_3_setup-dns.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/G_3_setup-dns.sh)**: Installe et configure un serveur DNS privé avec BIND.

*   **[windows/set-vpn-ip-dns.ps1](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/windows/set-vpn-ip-dns.ps1)**: Un script PowerShell pour ajuster les paramètres IP et DNS d'un adaptateur TAP OpenVPN sous Windows.
