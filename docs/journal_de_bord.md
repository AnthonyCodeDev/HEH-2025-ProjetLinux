
# Journal de bord

Ce document retrace, de manière chronologique, l’avancement du projet, les tâches effectuées, les difficultés rencontrées et les décisions prises.

---

## Semaine du 12/05/2025 au 15/05/2025

---

### Jour 1 – 12/05/2025

**Tâches réalisées :**
- Connexion à la plateforme AWS.
- Installation d’OpenVPN.
- Déploiement des serveurs Ubuntu 22.04 sur AWS EC2.
- Téléchargement et configuration des clés SSH (`anthony.pem`, `guillaume.pem`).
- Création des scripts suivants :
  ```bash
  A_0_setup_nfs_samba.sh     : Configuration de NFS et SAMBA.
  A_1_setup_client.sh        : Création d’un utilisateur (client).
  A_2_monitoring.sh          : Mise en place du monitoring centralisé via interface web.
  G_0_client-ntp.sh          : Configuration de NFS sur un client.
  G_1_setup-ntp.sh           : Configuration du service NTP sur un serveur.
  G_2_secure-ssh.sh          : Sécurisation du service SSH sur le serveur.
  ```

**Problèmes rencontrés :**
- Problème de permissions lié à une clé privée mal formatée.

---

### Jour 2 – 12/05/2025

**Tâches réalisées :**
- Développement des scripts suivants :
  ```bash
  A_3_backup_server.sh       : Sauvegarde des données serveur.
  A_4_security.sh            : Gestion de la sécurité du serveur.
  G_3_setup-dns.sh           : Configuration du service DNS.
  ```

**Problèmes rencontrés :**
- Aucun problème spécifié.

---

### Jour 3 – 13/05/2025

**Tâches réalisées :**
- Rédaction du fichier `README.md` du projet.
- Rédaction du `README.md` pour le script `G_set-vpn-ip-dns.ps1`.
- Création des scripts suivants :
  ```bash
  A_5_generate_certif.sh     : Génération de certificats SSL auto-signés.
  A_6_go.sh                  : Lancement automatisé de l’ensemble des scripts.
  G_set-vpn-ip-dns.ps1       : Attribution d’une IP pour OpenVPN (Windows).
  G_4_mount_xvdb.sh          : Montage du volume xvdb.
  G_5_uptime-kuma.sh         : Mise en place d’un service de monitoring via Uptime Kuma.
  ```

**Problèmes rencontrés :**
- Aucun problème spécifié.

---

### Jour 4 – 14/05/2025

**Tâches réalisées :**
- Création des scripts suivants :
  ```bash
  G_6_setup-auto-updates.sh : Automatisation des mises à jour critiques.
  G_7_scan_trivy.sh         : Analyse des vulnérabilités critiques avec Trivy.
  ```

**Problèmes rencontrés :**
- Aucun problème spécifié.

---

### Jour 5 – 15/05/2025

**Tâches réalisées :**
- Déploiement final des différents serveurs.
- Mise à jour du script `A_6_go.sh` pour automatiser le lancement complet du projet.
- Installation et configuration de phpMyAdmin.
- Présentation du projet devant les enseignants.

**Problèmes rencontrés :**
- Non spécifié.

---

## Conseils de rédaction

- Rédiger le journal en fin de journée pour une meilleure précision.
- Indiquer systématiquement les commandes exécutées et les chemins de fichiers modifiés.
- Noter le temps investi et conclure chaque jour par une leçon retenue ou une piste d’amélioration.
