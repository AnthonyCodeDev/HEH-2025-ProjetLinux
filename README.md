# HEH-2025 Projet Linux

**Auteurs :** Anthony & Guillaume
**Encadrement :** Mr Malaise, Mr Dambrin, Mr Roland
**Année académique :** 2024–2025
**UE :** Projets Linux (Bachelier en informatique, spécialité Télécommunications et réseaux, Bloc 2)

---

## Table des matières

1. [Description du projet](#description-du-projet)
2. [Architecture & Environnement](#architecture--environnement)
3. [Prérequis](#prérequis)
4. [Installation et déploiement](#installation-et-déploiement)
5. [Services implémentés](#services-implémentés)
6. [Automatisation & Scripts](#automatisation--scripts)
7. [Sécurisation](#sécurisation)
8. [Plan de sauvegarde](#plan-de-sauvegarde)
9. [Structure du dépôt](#structure-du-dépôt)
10. [Livrables & Rapport](#livrables--rapport)
11. [Contribuer](#contribuer)
12. [Licence](#licence)
13. [Contact](#contact)

---

## Description du projet

Ce projet vise à déployer et configurer une architecture de serveurs Linux virtualisés sur AWS, dans le cadre du cours **Projets Linux** à la HEH (Mons, Belgique).
L’objectif est de mettre en place divers services réseau automatisés, monitorés et sécurisés :

* Partage de fichiers NFS & Samba (Linux/Windows)
* Accès SSH sécurisé pour l’administration
* Hébergement Web (Apache ou Nginx)
* Service FTP + accès Samba au dossier web
* Bases de données isolées par utilisateur (MySQL/PostgreSQL)
* DNS (zone directe et inverse) avec cache
* Serveur NTP pour synchronisation horaire
* Monitoring centralisé via interface Web
* Automatisation complète via scripts Bash

---

## Architecture & Environnement

* **Cloud Provider :** AWS EC2 (instances t2.micro ou t3.micro)
* **Système d’exploitation :** Ubuntu Server 22.04 LTS (ou Debian 11)
* **Réseau :** VPC privé avec subnets public/privé, Security Groups configurés
* **Accès :** Clés SSH (`.pem`) stockées dans `keys/`

---

## Prérequis

* Compte AWS étudiant avec droit de créer des instances EC2
* Clé SSH configurée pour chaque étudiant (`anthony.pem`, `guillaume.pem`)
* Git installé localement
* Connexion Internet et accès au groupe Teams/Discord du cours

---

## Installation et déploiement

1. **Cloner le dépôt :**

   ```bash
   git clone https://github.com/AnthonyCodeDev/HEH-2025-ProjetLinux.git
   cd HEH-2025-ProjetLinux
   ```
2. **Déploiement AWS :**

   * Créer les instances EC2 selon l’architecture décrite
   * Déployer les clés dans `~/.ssh/` et ajuster les permissions
3. **Exécution des scripts :**

   ```bash
   cd scripts/
   sudo chmod +x *.sh
   sudo ./01_install_packages.sh    # Installation des paquets
   sudo ./02_configure_services.sh   # Configuration des services
   sudo ./03_secure.sh               # Sécurisation et pare-feu
   sudo ./04_monitoring.sh           # Mise en place du monitoring
   ```
4. **Validation :**

   * Pinger les serveurs
   * Tester le site web, l’accès FTP/Samba, le DNS, etc.

---

## Services implémentés

| Service          | Description                                           | Port par défaut |
| ---------------- | ----------------------------------------------------- | --------------- |
| NFS              | Partage de dossier Linux                              | 2049            |
| Samba            | Partage Windows & Linux                               | 445             |
| SSH              | Administration sécurisée                              | 22              |
| HTTP/HTTPS       | Serveur Web (Apache/Nginx)                            | 80 / 443        |
| FTP              | Upload/Download via vsftpd                            | 21              |
| MySQL/PostgreSQL | Bases de données isolées par utilisateur              | 3306 / 5432     |
| DNS (BIND9)      | Serveur de noms maître et cache, zone directe/inverse | 53              |
| NTP (Chrony)     | Synchronisation horaire                               | 123             |
| Monitoring       | Zabbix/Prometheus + Grafana (interface Web)           | 10050 / 3000    |

---

## Automatisation & Scripts

Tous les services sont configurés et automatisés à l’aide de scripts Bash situés dans le dossier `scripts/`.
Chaque script correspond à une étape clé :

1. **Installation des paquets** (`01_install_packages.sh`)
2. **Configuration des services** (`02_configure_services.sh`)
3. **Sécurisation** (`03_secure.sh`)
4. **Monitoring** (`04_monitoring.sh`)

> **Astuce :** Exécutez `scripts/deploy_all.sh` pour lancer l’ensemble des scripts en une seule commande.

---

## Sécurisation

* **Pare-feu :** UFW avec règles limitées aux ports nécessaires
* **SSH :** Désactivation de l’authentification par mot de passe, utilisation de clés
* **SELinux/AppArmor :** Profil applicatif adapté
* **Antivirus :** Installation de ClamAV pour analyse périodique

---

## Plan de sauvegarde

* Sauvegarde quotidienne des fichiers critiques via `rsync`
* Export et exportation des bases MySQL/PostgreSQL
* Stockage des backups sur un bucket S3 (chiffrement AES-256)
* Rotation et purge automatique des sauvegardes > 7 jours

---

## Structure du dépôt

```
├── README.md
├── scripts/              # Scripts d’automatisation
│   ├── 01_install_packages.sh
│   ├── 02_configure_services.sh
│   ├── 03_secure.sh
│   ├── 04_monitoring.sh
│   └── deploy_all.sh
├── keys/                 # Clés SSH (.pem)
├── docs/                 # Documentation et reporting
│   ├── journal_de_bord.md
│   └── rapport_final.pdf
└── .gitignore
```

---

## Livrables & Rapport

* **Démonstration** : Vendredi 16 mai à partir de 8h00, présentation auprès des professeurs.
* **Rapport** : À envoyer par email à `antoine.malaise@heh.be` avant **23 mai 2025 23:59**.

  * Cahier des charges, partitionnement, configuration des services, sécurisation, scripts, plan de sauvegarde, problèmes rencontrés, améliorations, bibliographie.

---

## Contribuer

1. Fork du dépôt
2. Création d’une branche (`git checkout -b feature/ma-feature`)
3. Commit et push (branche `feature/...`)
4. Pull request pour revue par les encadrants

---

## Licence

Ce projet est distribué sous la licence MIT. Consultez le fichier `LICENSE` pour plus de détails.

---

## Contact

Pour toute question, contactez :

* **Anthony** & **Guillaume** (équipe projets Linux)
* Mr Antoine Malaise : [antoine.malaise@heh.be](mailto:antoine.malaise@heh.be)
* Mr Dambrin & Mr Roland (cours Projets Linux)
