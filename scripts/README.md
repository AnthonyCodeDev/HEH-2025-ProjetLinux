## README for the `scripts` folder

This folder contains various bash scripts for setting up and configuring a Linux server and its clients. The scripts automate tasks such as installing and configuring NFS and Samba shares, setting up client environments, implementing monitoring, creating backups, enhancing security, generating SSL certificates, configuring NTP, and setting up DNS. There is also a `windows` subfolder with a Powershell script to configure IP and DNS settings in Windows environments.

Here's a breakdown of the scripts:

*   **[A_0_setup_nfs_samba.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_0_setup_nfs_samba.sh)**: Installs and configures NFS and Samba for file sharing. It creates shared directories, sets permissions, and opens the necessary firewall ports.
*   **[A_1_setup_client.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_1_setup_client.sh)**: Sets up client environments by creating users, databases, web directories, and configuring FTP access.
*   **[A_2_monitoring.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_2_monitoring.sh)**: Configures server monitoring using Cockpit within a Docker container.
*   **[A_3_backup_server.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_3_backup_server.sh)**: Implements a backup solution, including setting up a dedicated backup user and configuring cron jobs for automated backups.
*   **[A_4_security.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_4_security.sh)**: Enhances server security by configuring firewalls, hardening SSH, and installing Fail2Ban and AIDE.
*   **[A_5_generate_certif.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/A_5_generate_certif.sh)**: Generates a self-signed wildcard SSL certificate and deploys it to a remote server.
*   **[G_0_client-ntp.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/G_0_client-ntp.sh)**: Configures an NTP client using Chrony.
*   **[G_1_setup-ntp.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/G_1_setup-ntp.sh)**: Sets up an NTP server using Chrony and distributes the client configuration script.
*   **[G_2_secure-ssh.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/G_2_secure-ssh.sh)**: Further secures SSH access, including the setup of fail2ban and a report panel.
*   **[G_3_setup-dns.sh](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/G_3_setup-dns.sh)**: Installs and configures a private DNS server using BIND.

*   **[windows/set-vpn-ip-dns.ps1](https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux/blob/main/anthonycodedev-heh-2025-projetlinux/scripts/windows/set-vpn-ip-dns.ps1)**: A PowerShell script to configure IP and DNS settings for a TAP OpenVPN adapter on Windows.
