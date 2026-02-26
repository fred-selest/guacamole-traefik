# 🚀 Guide post-déploiement

## Actions à effectuer après l'installation

> **Optionnel après déploiement :**
> - Sauvegardes automatiques : `sudo bash scripts/4_backup_mysql.sh install`
> - Intégration LDAP/AD : `sudo bash scripts/5_configure_ldap.sh`

---

## 1. Guacamole — Premier accès

1. Ouvrir `https://guac.votre-domaine.com/guacamole`
2. Se connecter avec `guacadmin` et le mot de passe dans `/root/credentials-*.txt`
3. **Changer le mot de passe** : Menu utilisateur (en haut à droite) → **Paramètres** → **Mot de passe**
4. **Configurer le TOTP** : Paramètres → **Authentification à deux facteurs** → Scanner le QR code avec Google Authenticator ou Authy

---

## 2. Portainer — Création du compte admin

> ⚠️ Portainer expire après **5 minutes** sans connexion initiale — se connecter rapidement après le déploiement

1. Ouvrir `https://portainer.votre-domaine.com`
2. Créer le compte administrateur
3. Cliquer sur **Get Started** → **local**
4. Tu peux maintenant gérer tous les conteneurs via l'interface web

---

## 3. Créer une connexion RDP dans Guacamole

1. Menu → **Connexions** → **Nouvelle connexion**
2. Remplir :
   - **Nom** : Nom du serveur
   - **Protocole** : RDP
   - **Nom d'hôte** : IP du serveur Windows
   - **Port** : 3389
   - **Nom d'utilisateur** / **Mot de passe** : identifiants Windows
   - **Domaine** : nom de domaine AD si applicable
3. Onglet **Sécurité** :
   - **Mode sécurité** : Any (négociation automatique)
   - ✅ Ignorer le certificat du serveur
4. Onglet **Affichage** :
   - ✅ Activer le lissage des polices
   - ✅ Activer le papier peint
5. Cliquer **Enregistrer**

---

## 4. Créer des groupes d'utilisateurs

1. Menu → **Groupes** → **Nouveau groupe**
2. Créer par exemple :
   - `Administrateurs` — accès à toutes les connexions
   - `Techniciens` — accès aux connexions de leur périmètre
   - `Administrateurs IT` — groupe principal

3. Assigner des connexions au groupe : onglet **Connexions** du groupe

---

## 5. Vérifier le renouvellement des certificats

```bash
# Vérifier la date d'expiration
echo | openssl s_client -connect guac.votre-domaine.com:443 2>/dev/null | openssl x509 -noout -dates

# Simuler un renouvellement (sans modifier acme.json)
sudo docker exec traefik traefik version
```

Les certificats Let's Encrypt sont valables **90 jours** et se renouvellent automatiquement à **30 jours** de l'expiration.

---

## 6. Test de sécurité

```bash
# Tester les headers de sécurité
curl -sI https://guac.votre-domaine.com/guacamole/ | grep -i "strict\|x-frame\|x-content\|referrer"

# Vérifier le rate limiting (doit retourner 429 après 30+ req/min)
for i in $(seq 1 35); do curl -sk https://guac.votre-domaine.com/guacamole/ -o /dev/null -w "$i: %{http_code}\n"; done

# Scanner SSL (via ssllabs en ligne)
# https://www.ssllabs.com/ssltest/analyze.html?d=guac.votre-domaine.com
```

---

## 7. Configurer les sauvegardes MySQL (optionnel)

```bash
# Installe un cron de backup quotidien à 2h30 avec 7 jours de rétention
sudo bash scripts/4_backup_mysql.sh install

# Personnalisation
BACKUP_DIR=/var/backups/guacamole RETENTION_DAYS=14 BACKUP_TIME=03:00 \
  sudo bash scripts/4_backup_mysql.sh install

# Vérifier les backups
sudo /usr/local/sbin/guacamole-backup list

# Restaurer un backup
sudo /usr/local/sbin/guacamole-backup restore
```

---

## 8. Configurer les alertes email (optionnel)

Pour recevoir des alertes si un conteneur tombe, ajouter dans le `docker-compose.yml` :

```yaml
# Ajouter le service watchtower pour les mises à jour automatiques
watchtower:
  image: containrrr/watchtower
  container_name: watchtower
  restart: unless-stopped
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
  environment:
    - WATCHTOWER_CLEANUP=true
    - WATCHTOWER_SCHEDULE=0 0 4 * * *   # 4h du matin
    - WATCHTOWER_NOTIFICATIONS=email
    - WATCHTOWER_NOTIFICATION_EMAIL_FROM=alert@votre-domaine.com
    - WATCHTOWER_NOTIFICATION_EMAIL_TO=admin@votre-domaine.com
    - WATCHTOWER_NOTIFICATION_EMAIL_SERVER=smtp.votre-domaine.com
    - WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT=587
```
