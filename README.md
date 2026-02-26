# 🖥️ Guacamole Stack — Accès distant sécurisé

> Déploiement automatisé d'Apache Guacamole avec Traefik v2, Portainer et thème personnalisé sur Ubuntu 22.04/24.04.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?logo=ubuntu)](https://ubuntu.com)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)](https://docker.com)
[![Traefik](https://img.shields.io/badge/Traefik-v2.11-24A1C1?logo=traefikproxy)](https://traefik.io)
[![Shell Check](https://github.com/YOUR_USERNAME/guacamole-stack/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/YOUR_USERNAME/guacamole-stack/actions/workflows/shellcheck.yml)

---

## 📋 Table des matières

- [Architecture](#-architecture)
- [Prérequis](#-prérequis)
- [Installation rapide](#-installation-rapide)
- [Scripts](#-scripts)
- [Configuration](#-configuration)
- [Sécurité](#-sécurité)
- [Dépannage](#-dépannage)
- [Roadmap](#-roadmap)

---

## 🏗️ Architecture

```
Internet
    │
    ▼
Traefik v2.11 (reverse proxy + Let's Encrypt)
    │
    ├── guac.votre-domaine.com     → Guacamole (RDP/SSH/VNC)
    ├── traefik.votre-domaine.com  → Dashboard Traefik (BasicAuth)
    └── portainer.votre-domaine.com → Portainer CE
            │
            ▼
    Réseau Docker "proxy" (externe)
            │
    ┌───────┴────────┐
    │                │
  guacamole       guacd
    │                │
    └───────┬────────┘
            │
    Réseau "guacamole-backend" (interne)
            │
         MySQL 8.4
```

### Conteneurs déployés

| Conteneur | Image | Rôle |
|---|---|---|
| `traefik` | `traefik:v2.11` | Reverse proxy, TLS, routing |
| `guacamole` | `guacamole/guacamole:latest` | Interface web HTML5 |
| `guacd` | `guacamole/guacd:latest` | Démon protocoles RDP/SSH/VNC |
| `guac-db` | `mysql:8.4` | Base de données utilisateurs/connexions |
| `portainer` | `portainer/portainer-ce:latest` | Interface gestion Docker |

---

## ✅ Prérequis

- Serveur **Ubuntu 22.04 ou 24.04** (VPS ou dédié)
- Accès **root** ou **sudo**
- **3 entrées DNS** de type A pointant vers l'IP du serveur :
  ```
  guac.votre-domaine.com        → IP_SERVEUR
  traefik.votre-domaine.com     → IP_SERVEUR
  portainer.votre-domaine.com   → IP_SERVEUR
  ```
- Ports **80** et **443** ouverts

---

## 🚀 Installation rapide

```bash
# 1. Cloner le dépôt
git clone https://github.com/fred-selest/guacamole-traefik.git
cd guacamole-traefik

# 2. Rendre les scripts exécutables
chmod +x scripts/*.sh

# 3. Installer les prérequis (Docker, UFW, Fail2ban...)
sudo bash scripts/1_prerequisites.sh

# 4. Configurer les DNS puis redémarrer
sudo reboot

# 5. Déployer la stack complète
sudo bash scripts/2_deploy_guacamole.sh

# 6. (Optionnel) Appliquer le thème sombre
sudo bash scripts/3_theme_guacamole.sh

# 7. (Optionnel) Configurer les sauvegardes automatiques MySQL
sudo bash scripts/4_backup_mysql.sh install

# 8. (Optionnel) Intégrer LDAP / Active Directory
sudo bash scripts/5_configure_ldap.sh
```

> ⚠️ **Avant le script 2**, éditer les variables en tête de fichier :
> ```bash
> DOMAIN_GUAC="guac.votre-domaine.com"
> DOMAIN_TRAEFIK="traefik.votre-domaine.com"
> DOMAIN_PORTAINER="portainer.votre-domaine.com"
> EMAIL="votre@email.com"
> TIMEZONE="Europe/Paris"   # Optionnel — défaut : Europe/Paris
> ```

> ⚠️ **Avant le script 1**, la timezone peut aussi être passée en variable :
> ```bash
> sudo TIMEZONE="America/New_York" bash scripts/1_prerequisites.sh
> ```

Les credentials sont automatiquement sauvegardés dans `/root/credentials-DATE.txt`.

---

## 📁 Scripts

### `scripts/1_prerequisites.sh`
Prépare un Ubuntu vierge :
- Mise à jour système
- Installation Docker CE + Docker Compose plugin
- Configuration UFW (ports 22, 80, 443)
- Fail2ban (SSH : 3 tentatives → ban 24h)
- Mises à jour de sécurité automatiques (unattended-upgrades)
- Hardening SSH (PermitRootLogin=no, MaxAuthTries=3)
- Paramètres kernel sysctl

### `scripts/2_deploy_guacamole.sh`
Déploie la stack complète :
- Génération automatique de tous les mots de passe (openssl rand)
- Configuration Traefik (traefik.yml + dynamic.yml)
- Schéma SQL Guacamole auto-généré
- Docker Compose avec réseaux isolés
- Certificats Let's Encrypt automatiques
- Portainer inclus
- Sauvegarde credentials dans `/root/`

### `scripts/3_theme_guacamole.sh`
Installe un thème sombre moderne :
- Extension Guacamole officielle (.jar)
- Thème sombre avec variables CSS personnalisables
- Logo SVG généré automatiquement
- Persiste aux mises à jour Guacamole
- Branding entièrement personnalisable via variables (`COMPANY_NAME`, `COMPANY_SUBTITLE`, couleurs…)

### `scripts/4_backup_mysql.sh`
Sauvegarde automatique de la base MySQL :
- Backup quotidien via cron (heure configurable)
- Compression gzip automatique
- Rotation configurable (défaut : 7 jours)
- Modes : `install` | `backup` | `restore` | `list`
- Restauration interactive avec confirmation

### `scripts/5_configure_ldap.sh`
Intégration LDAP / Active Directory :
- Configuration interactive ou via variables d'environnement
- Compatible Active Directory (sAMAccountName) et OpenLDAP (uid)
- Chiffrement : LDAP / StartTLS / LDAPS (SSL)
- Support des groupes AD (synchronisation des permissions)
- Test de connectivité avant application
- Backup automatique du docker-compose avant modification
- Restauration simple en cas de problème

---

## ⚙️ Configuration

### Personnaliser le thème

Éditer les variables en tête de `scripts/3_theme_guacamole.sh` ou les passer en env :

```bash
COMPANY_NAME="Votre Société" \
COMPANY_SUBTITLE="Accès distant sécurisé" \
PRIMARY_COLOR="#2563eb" \
sudo bash scripts/3_theme_guacamole.sh
```

### Configurer les sauvegardes MySQL

```bash
# Installation avec paramètres personnalisés
BACKUP_DIR=/var/backups/guacamole \
RETENTION_DAYS=14 \
BACKUP_TIME=03:00 \
sudo bash scripts/4_backup_mysql.sh install

# Commandes disponibles
sudo /usr/local/sbin/guacamole-backup list
sudo /usr/local/sbin/guacamole-backup backup
sudo /usr/local/sbin/guacamole-backup restore
```

### Configurer LDAP / Active Directory

Pré-requis : un compte de service avec droits de lecture sur l'annuaire.

```bash
# Active Directory
LDAP_HOSTNAME=dc.mondomaine.com \
LDAP_USER_BASE_DN="OU=Utilisateurs,DC=mondomaine,DC=com" \
LDAP_SEARCH_BIND_DN="CN=guac-svc,OU=Services,DC=mondomaine,DC=com" \
LDAP_SEARCH_BIND_PASSWORD="MotDePasseService" \
LDAP_GROUP_BASE_DN="OU=Groupes,DC=mondomaine,DC=com" \
sudo bash scripts/5_configure_ldap.sh

# Mode interactif (sans variables)
sudo bash scripts/5_configure_ldap.sh
```

### Structure des fichiers sur le serveur

```
/opt/guacamole/
├── docker-compose.yml
├── .env                        # Mots de passe (chmod 600)
└── init/
    └── initdb.sql

/opt/traefik/
├── traefik.yml                 # Config statique
├── config/
│   └── dynamic.yml             # Middlewares + dashboard router
├── certs/
│   └── acme.json               # Certificats Let's Encrypt
└── logs/
    ├── traefik.log
    └── access.log

/opt/guacamole-extensions/
└── custom-theme.jar            # Thème personnalisé
```

### Réseaux Docker

| Réseau | Type | Utilisé par |
|---|---|---|
| `proxy` | external | Traefik, Guacamole, guacd, Portainer |
| `guacamole-backend` | internal | guacd, guac-db, Guacamole |

> **Note** : guacd est sur les **deux** réseaux pour pouvoir joindre les serveurs distants (RDP/SSH) tout en communiquant avec Guacamole en interne.

---

## 🔐 Sécurité

### Mesures implémentées

- **TLS automatique** via Let's Encrypt (HTTP challenge)
- **Redirection HTTP → HTTPS** forcée
- **Headers de sécurité** : HSTS, XSS filter, X-Frame-Options, CSP
- **Rate limiting** : 30 req/min par IP (Traefik middleware)
- **BasicAuth** sur le dashboard Traefik (hash apr1)
- **TOTP 2FA** activé dans Guacamole
- **UFW** avec règles DOCKER-USER (Docker ne bypass pas le firewall)
- **Fail2ban** sur SSH
- **no-new-privileges** sur tous les conteneurs
- **Réseaux Docker isolés** (guacamole-backend en mode internal)
- **Mots de passe 32+ caractères** générés aléatoirement

### Commandes utiles

```bash
# Statut des conteneurs
sudo docker ps

# Logs en temps réel
sudo docker compose -f /opt/guacamole/docker-compose.yml logs -f

# Logs Traefik
sudo tail -f /opt/traefik/logs/traefik.log

# Logs guacd (connexions RDP/SSH)
sudo docker logs guacd -f

# Statut UFW
sudo ufw status numbered

# Statut Fail2ban
sudo fail2ban-client status sshd
```

---

## 🔧 Dépannage

### Guacamole retourne 404
```bash
# Vérifier que le dashboard est activé
grep "dashboard" /opt/traefik/traefik.yml
# Doit afficher : dashboard: true
sudo docker restart traefik
```

### Connexion RDP impossible — "server unreachable"
```bash
# Tester la connectivité depuis guacd
sudo docker exec guacd ping -c 3 IP_SERVEUR_CIBLE
sudo docker exec guacd nc -zv IP_SERVEUR_CIBLE 3389
# Si Network unreachable → vérifier que guacd est sur le réseau "proxy"
sudo docker inspect guacd | python3 -c "
import json,sys; d=json.load(sys.stdin)
for n in d[0]['NetworkSettings']['Networks']: print(n)"
```

### Certificat Let's Encrypt non émis
```bash
# Vider acme.json et redémarrer
sudo truncate -s 0 /opt/traefik/certs/acme.json
sudo docker restart traefik
sudo tail -f /opt/traefik/logs/traefik.log | grep -i acme
```

### Dashboard Traefik — 401 Unauthorized
```bash
# Régénérer le hash (apr1 requis)
sudo apt-get install -y apache2-utils
htpasswd -nbm admin "NOUVEAU_MOT_DE_PASSE"
# Copier le hash ($ simples) dans /opt/traefik/config/dynamic.yml
```

---

## 🗺️ Roadmap

- [x] Déploiement automatisé Guacamole + Traefik + Portainer
- [x] Certificats Let's Encrypt automatiques
- [x] Sécurité renforcée (UFW, Fail2ban, headers, rate limit)
- [x] Thème sombre personnalisé et configurable
- [x] Paramétrage complet des variables (timezone, domaines, branding)
- [x] Backup automatique MySQL (cron + rotation + restauration)
- [x] Intégration LDAP / Active Directory
- [ ] VPN Tailscale multi-sites (subnet router)
- [ ] Monitoring Prometheus + Grafana
- [ ] Alertes Uptime Kuma
- [ ] Enregistrement des sessions RDP
- [ ] GitHub Actions — validation ShellCheck

---

## 📄 License

MIT — voir [LICENSE](LICENSE)

---

## 🤝 Contribution

Les PRs sont les bienvenues. Pour les changements majeurs, ouvrir d'abord une issue.

```bash
git clone https://github.com/fred-selest/guacamole-traefik.git
cd guacamole-traefik
# Créer une branche
git checkout -b feature/ma-fonctionnalite
# Tester les scripts avec ShellCheck
shellcheck scripts/*.sh
```
