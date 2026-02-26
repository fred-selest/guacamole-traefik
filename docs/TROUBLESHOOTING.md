# 🔧 Guide de dépannage

## Problèmes courants et solutions

---

### 🔴 Guacamole — Erreur 404 après déploiement

**Symptôme** : `curl https://guac.domaine.com/guacamole/` retourne 404

**Causes possibles** :
1. Le dashboard Traefik est désactivé
2. Le middleware `guac-strip` supprime le préfixe `/guacamole`

**Solution** :
```bash
# Vérifier que dashboard=true dans traefik.yml
grep "dashboard" /opt/traefik/traefik.yml

# Vérifier le middleware dans docker-compose.yml
grep "addprefix\|strip" /opt/guacamole/docker-compose.yml
# Doit utiliser addprefix, pas stripprefix

sudo docker restart traefik guacamole
```

---

### 🔴 Dashboard Traefik — 401 Unauthorized

**Symptôme** : `curl -u admin:pass https://traefik.domaine.com/dashboard/` retourne 401

**Cause** : Hash `$$` au lieu de `$` dans `dynamic.yml`, ou hash généré sur une autre machine

**Solution** :
```bash
# Régénérer le hash SUR LE SERVEUR
sudo apt-get install -y apache2-utils
NEW_HASH=$(htpasswd -nbm admin "VOTRE_MOT_DE_PASSE")
echo "$NEW_HASH"

# Injecter le hash dans dynamic.yml
sudo python3 -c "
import re
hash_val = '$(htpasswd -nbm admin VOTRE_MOT_DE_PASSE)'
content = open('/opt/traefik/config/dynamic.yml').read()
content = re.sub(r'- \"admin:[^\"]*\"', '- \"' + hash_val + '\"', content)
open('/opt/traefik/config/dynamic.yml', 'w').write(content)
print('OK')
"

sudo docker restart traefik
sleep 5
curl -sk -u "admin:VOTRE_MOT_DE_PASSE" https://traefik.domaine.com/dashboard/ -o /dev/null -w "%{http_code}\n"
```

---

### 🔴 RDP — "Connection failed (server unreachable)"

**Symptôme** : Guacamole affiche une erreur de connexion au serveur Windows

**Diagnostic** :
```bash
# Étape 1 — Vérifier les réseaux de guacd
sudo docker inspect guacd | python3 -c "
import json,sys; d=json.load(sys.stdin)
for n in d[0]['NetworkSettings']['Networks']: print(n)"
# Doit afficher : guacamole_guacamole-backend ET proxy

# Étape 2 — Tester la connectivité
sudo docker exec guacd ping -c 3 IP_SERVEUR_WINDOWS
sudo docker exec guacd nc -zv IP_SERVEUR_WINDOWS 3389

# Étape 3 — Vérifier la config MySQL
MYSQL_ROOT=$(sudo grep MYSQL_ROOT_PASSWORD /opt/guacamole/.env | cut -d= -f2)
sudo docker exec guac-db mysql -uroot -p"${MYSQL_ROOT}" guacamole_db \
  -e "SELECT cp.parameter_name, cp.parameter_value FROM guacamole_connection_parameter cp JOIN guacamole_connection c ON c.connection_id = cp.connection_id LIMIT 20;"
```

**Solutions** :
- guacd pas sur le réseau `proxy` → voir [Fix réseau guacd](#fix-réseau-guacd)
- Serveur Windows inaccessible → vérifier pare-feu Windows et RDP activé
- Mauvaise IP dans Guacamole → corriger dans l'interface admin

#### Fix réseau guacd
```bash
# Ajouter le réseau proxy à guacd dans docker-compose.yml
sudo sed -i '/container_name: guacd/,/volumes:/{/networks:/,/- guacamole-backend/{s/      - guacamole-backend/      - guacamole-backend\n      - proxy/}}' /opt/guacamole/docker-compose.yml

cd /opt/guacamole
sudo docker compose --env-file .env up -d --force-recreate guacd
```

---

### 🔴 Certificat Let's Encrypt non émis

**Symptôme** : Avertissement de certificat dans le navigateur, pas de certificat valide

**Diagnostic** :
```bash
sudo tail -50 /opt/traefik/logs/traefik.log | grep -i "acme\|cert\|error"
```

**Solutions** :

1. Vérifier que les DNS pointent bien vers le serveur :
```bash
dig +short guac.votre-domaine.com
# Doit retourner l'IP du serveur
```

2. Vider acme.json et redémarrer :
```bash
sudo truncate -s 0 /opt/traefik/certs/acme.json
sudo docker restart traefik
sleep 30
sudo tail -20 /opt/traefik/logs/traefik.log
```

3. Vérifier que le port 80 est ouvert (HTTP challenge) :
```bash
sudo ufw status | grep 80
curl -sk http://guac.votre-domaine.com -o /dev/null -w "%{http_code}\n"
```

---

### 🔴 Variable `${EMAIL}` non substituée dans traefik.yml

**Symptôme** : `acme.email` contient littéralement `${EMAIL}`

**Cause** : Heredoc avec quotes simples empêche la substitution shell

**Solution** :
```bash
sudo sed -i "s|\${EMAIL}|votre@email.com|g" /opt/traefik/traefik.yml
sudo truncate -s 0 /opt/traefik/certs/acme.json
sudo docker restart traefik
```

---

### 🔴 Guacamole — SSLHandshakeException

**Symptôme** dans les logs : `javax.net.ssl.SSLHandshakeException: Remote host terminated the handshake`

**Cause** : Communication SSL entre Guacamole et guacd mal configurée

**Solution** : Ce problème se résout généralement en s'assurant que guacd et Guacamole sont sur le même réseau Docker et communiquent via le hostname `guacd` (pas une IP).

```bash
# Vérifier la variable d'environnement
sudo docker exec guacamole env | grep GUACD
# GUACD_HOSTNAME=guacd  ← correct

# Tester la résolution DNS interne
sudo docker exec guacamole ping -c 2 guacd
```

---

## 📋 Commandes de diagnostic rapide

```bash
# ── Statut général ──────────────────────────────────────────
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# ── Logs en temps réel ──────────────────────────────────────
sudo docker compose -f /opt/guacamole/docker-compose.yml logs -f --tail 20

# ── Logs par service ────────────────────────────────────────
sudo docker logs traefik    --tail 30 2>&1 | grep -i "error\|warn"
sudo docker logs guacamole  --tail 30 2>&1 | grep -i "error\|warn"
sudo docker logs guacd      --tail 30
sudo docker logs guac-db    --tail 10

# ── Réseaux Docker ──────────────────────────────────────────
sudo docker network ls
sudo docker network inspect proxy | python3 -c "
import json,sys; d=json.load(sys.stdin)
for name,info in d[0]['Containers'].items():
    print(info['Name'], '->', info['IPv4Address'])"

# ── Certificats ─────────────────────────────────────────────
sudo docker exec traefik cat /certs/acme.json | python3 -c "
import json,sys
d=json.load(sys.stdin)
try:
    certs = d['letsencrypt']['Certificates']
    for c in certs: print('✅', c['domain']['main'])
except: print('Aucun certificat')"

# ── UFW ─────────────────────────────────────────────────────
sudo ufw status numbered
sudo fail2ban-client status sshd
```
