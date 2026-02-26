#!/bin/bash
set -euo pipefail

# ============================================================
#  DEPLOY GUACAMOLE + TRAEFIK + PORTAINER
#  Usage : sudo bash 2_deploy_guacamole.sh
#  Prérequis : avoir exécuté 1_prerequisites.sh + reboot
#              DNS configurés avant de lancer ce script
# ============================================================

# ---- CONFIG (à adapter avant de lancer) --------------------
DOMAIN_GUAC="${DOMAIN_GUAC:-guac.votre-domaine.com}"
DOMAIN_TRAEFIK="${DOMAIN_TRAEFIK:-traefik.votre-domaine.com}"
DOMAIN_PORTAINER="${DOMAIN_PORTAINER:-portainer.votre-domaine.com}"
EMAIL="${EMAIL:-admin@votre-domaine.com}"
TIMEZONE="${TIMEZONE:-Europe/Paris}"
BASE_DIR="/opt/guacamole"
TRAEFIK_DIR="/opt/traefik"
CRED_FILE="/root/credentials-$(date +%Y%m%d-%H%M).txt"

# ---- LDAP / Active Directory (optionnel) -------------------
# Mettre LDAP_ENABLED=true et renseigner les variables pour activer
LDAP_ENABLED="${LDAP_ENABLED:-false}"
LDAP_HOSTNAME="${LDAP_HOSTNAME:-ldap.votre-domaine.com}"
LDAP_PORT="${LDAP_PORT:-389}"                        # 389=LDAP, 636=LDAPS
LDAP_ENCRYPTION_METHOD="${LDAP_ENCRYPTION_METHOD:-none}"  # none | starttls | ssl
LDAP_USER_BASE_DN="${LDAP_USER_BASE_DN:-ou=Users,dc=domaine,dc=com}"
LDAP_USERNAME_ATTRIBUTE="${LDAP_USERNAME_ATTRIBUTE:-sAMAccountName}"  # uid pour OpenLDAP
LDAP_SEARCH_BIND_DN="${LDAP_SEARCH_BIND_DN:-}"       # compte de service (optionnel)
LDAP_SEARCH_BIND_PASSWORD="${LDAP_SEARCH_BIND_PASSWORD:-}"
LDAP_GROUP_BASE_DN="${LDAP_GROUP_BASE_DN:-}"         # ou=Groups,dc=domaine,dc=com (optionnel)
LDAP_GROUP_SEARCH_FILTER="${LDAP_GROUP_SEARCH_FILTER:-}"
# ------------------------------------------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}══ $1 ══${NC}"; }

[[ $EUID -ne 0 ]] && err "Lance ce script en root : sudo bash $0"

command -v docker     &>/dev/null || err "Docker non installé — lance d'abord 1_prerequisites.sh"
command -v openssl    &>/dev/null || err "openssl manquant"
command -v htpasswd   &>/dev/null || err "htpasswd manquant — lance d'abord 1_prerequisites.sh"
command -v python3    &>/dev/null || err "python3 manquant"
docker compose version &>/dev/null 2>&1 || err "docker compose plugin manquant"

# ════════════════════════════════════════
section "1. Génération des mots de passe"
# ════════════════════════════════════════
gen_pass() { openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c ${1:-32}; }

MYSQL_ROOT_PASS=$(gen_pass 32)
MYSQL_GUAC_PASS=$(gen_pass 32)
GUAC_ADMIN_PASS=$(gen_pass 24)
TRAEFIK_PASS=$(gen_pass 32)
TRAEFIK_HASH=$(htpasswd -nbm admin "$TRAEFIK_PASS")

log "Mots de passe générés"

# ════════════════════════════════════════
section "2. Structure des répertoires"
# ════════════════════════════════════════
mkdir -p "$TRAEFIK_DIR"/{certs,config,logs}
mkdir -p "$BASE_DIR"/{init,drive,record}
mkdir -p /opt/portainer/data
log "Répertoires créés"

# ════════════════════════════════════════
section "3. Fichier .env"
# ════════════════════════════════════════
cat > "$BASE_DIR/.env" <<ENVFILE
# Guacamole — généré le $(date)
DOMAIN_GUAC=${DOMAIN_GUAC}
EMAIL=${EMAIL}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASS}
MYSQL_DATABASE=guacamole_db
MYSQL_USER=guacamole_user
MYSQL_PASSWORD=${MYSQL_GUAC_PASS}
ENVFILE
chmod 600 "$BASE_DIR/.env"
log "Fichier .env créé (chmod 600)"

# ════════════════════════════════════════
section "4. Schéma SQL Guacamole"
# ════════════════════════════════════════
log "Génération du schéma SQL..."
docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --mysql \
  > "$BASE_DIR/init/initdb.sql" 2>/dev/null
log "Schéma SQL généré"

# ════════════════════════════════════════
section "5. Configuration Traefik"
# ════════════════════════════════════════

# traefik.yml — config statique
cat > "$TRAEFIK_DIR/traefik.yml" <<TRAEFIKYML
global:
  checkNewVersion: false
  sendAnonymousUsage: false

log:
  level: WARN
  filePath: /var/log/traefik/traefik.log

accessLog:
  filePath: /var/log/traefik/access.log
  bufferingSize: 100

api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt
      middlewares:
        - secHeaders@file

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${EMAIL}
      storage: /certs/acme.json
      httpChallenge:
        entryPoint: web

providers:
  docker:
    exposedByDefault: false
    network: proxy
  file:
    filename: /config/dynamic.yml
    watch: true
TRAEFIKYML

# dynamic.yml — middlewares + route dashboard Traefik
# Le hash htpasswd doit avoir des $ simples dans le fichier (pas $$)
python3 - "$TRAEFIK_HASH" "$DOMAIN_TRAEFIK" <<'PYEOF'
import sys

traefik_hash = sys.argv[1]
domain_traefik = sys.argv[2]

content = """http:
  middlewares:

    secHeaders:
      headers:
        browserXssFilter: true
        contentTypeNosniff: true
        frameDeny: true
        sslRedirect: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        referrerPolicy: "strict-origin-when-cross-origin"
        customResponseHeaders:
          X-Robots-Tag: "noindex, nofollow"
          server: ""

    rateLimit:
      rateLimit:
        average: 30
        burst: 60
        period: 1m

    compress:
      compress: {}

    traefik-auth:
      basicAuth:
        users:
          - \"""" + traefik_hash + """\"

  routers:
    traefik-dashboard:
      rule: "Host(`""" + domain_traefik + """`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))"
      entrypoints:
        - websecure
      tls:
        certResolver: letsencrypt
      service: api@internal
      middlewares:
        - traefik-auth
        - secHeaders
"""

with open('/opt/traefik/config/dynamic.yml', 'w') as f:
    f.write(content)
print("dynamic.yml écrit")
PYEOF

# acme.json
touch "$TRAEFIK_DIR/certs/acme.json"
chmod 600 "$TRAEFIK_DIR/certs/acme.json"
log "Configuration Traefik générée"

# ════════════════════════════════════════
section "6. Réseau Docker proxy"
# ════════════════════════════════════════
if ! docker network ls --format '{{.Name}}' | grep -q '^proxy$'; then
  docker network create proxy
  log "Réseau Docker 'proxy' créé"
else
  log "Réseau Docker 'proxy' déjà existant"
fi

# ════════════════════════════════════════
section "7. docker-compose.yml"
# ════════════════════════════════════════
python3 - "$BASE_DIR" "$DOMAIN_GUAC" "$DOMAIN_PORTAINER" "$TIMEZONE" "$LDAP_ENABLED" \
          "$LDAP_HOSTNAME" "$LDAP_PORT" "$LDAP_ENCRYPTION_METHOD" \
          "$LDAP_USER_BASE_DN" "$LDAP_USERNAME_ATTRIBUTE" \
          "$LDAP_SEARCH_BIND_DN" "$LDAP_SEARCH_BIND_PASSWORD" \
          "$LDAP_GROUP_BASE_DN" "$LDAP_GROUP_SEARCH_FILTER" <<'PYEOF'
import sys

base_dir              = sys.argv[1]
domain_guac           = sys.argv[2]
domain_portainer      = sys.argv[3]
timezone              = sys.argv[4]
ldap_enabled          = sys.argv[5].lower() == "true"
ldap_hostname         = sys.argv[6]
ldap_port             = sys.argv[7]
ldap_encryption       = sys.argv[8]
ldap_user_base_dn     = sys.argv[9]
ldap_username_attr    = sys.argv[10]
ldap_search_bind_dn   = sys.argv[11]
ldap_search_bind_pass = sys.argv[12]
ldap_group_base_dn    = sys.argv[13]
ldap_group_filter     = sys.argv[14]

# Construire le bloc LDAP optionnel
ldap_env = ""
if ldap_enabled:
    ldap_env += "      LDAP_HOSTNAME: " + ldap_hostname + "\n"
    ldap_env += "      LDAP_PORT: \"" + ldap_port + "\"\n"
    ldap_env += "      LDAP_ENCRYPTION_METHOD: " + ldap_encryption + "\n"
    ldap_env += "      LDAP_USER_BASE_DN: \"" + ldap_user_base_dn + "\"\n"
    ldap_env += "      LDAP_USERNAME_ATTRIBUTE: " + ldap_username_attr + "\n"
    if ldap_search_bind_dn:
        ldap_env += "      LDAP_SEARCH_BIND_DN: \"" + ldap_search_bind_dn + "\"\n"
        ldap_env += "      LDAP_SEARCH_BIND_PASSWORD: \"" + ldap_search_bind_pass + "\"\n"
    if ldap_group_base_dn:
        ldap_env += "      LDAP_GROUP_BASE_DN: \"" + ldap_group_base_dn + "\"\n"
    if ldap_group_filter:
        ldap_env += "      LDAP_GROUP_SEARCH_FILTER: \"" + ldap_group_filter + "\"\n"

compose = """networks:
  proxy:
    external: true
  guacamole-backend:
    internal: true

volumes:
  guac-db-data:
  guac-drive:
  guac-record:
  portainer-data:

services:

  # ─── Traefik ────────────────────────────────────────────
  traefik:
    image: traefik:v2.11
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/traefik/traefik.yml:/traefik.yml:ro
      - /opt/traefik/config/dynamic.yml:/config/dynamic.yml:ro
      - /opt/traefik/certs:/certs
      - /opt/traefik/logs:/var/log/traefik
    networks:
      - proxy
    environment:
      - TZ=""" + timezone + """

  # ─── Portainer ──────────────────────────────────────────
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer-data:/data
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(`""" + domain_portainer + """`)"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"

  # ─── guacd ──────────────────────────────────────────────
  guacd:
    image: guacamole/guacd:latest
    container_name: guacd
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - guacamole-backend
      - proxy
    volumes:
      - guac-drive:/drive:rw
      - guac-record:/record:rw
    environment:
      - GUACD_LOG_LEVEL=warning

  # ─── MySQL ──────────────────────────────────────────────
  guac-db:
    image: mysql:8.4
    container_name: guac-db
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - guacamole-backend
    volumes:
      - guac-db-data:/var/lib/mysql
      - """ + base_dir + """/init:/docker-entrypoint-initdb.d:ro
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 15s
      timeout: 5s
      retries: 5

  # ─── Guacamole ──────────────────────────────────────────
  guacamole:
    image: guacamole/guacamole:latest
    container_name: guacamole
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    depends_on:
      guac-db:
        condition: service_healthy
      guacd:
        condition: service_started
    networks:
      - proxy
      - guacamole-backend
    environment:
      GUACD_HOSTNAME: guacd
      GUACD_PORT: "4822"
      MYSQL_HOSTNAME: guac-db
      MYSQL_PORT: "3306"
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      TOTP_ENABLED: "true"
      TOTP_ISSUER: "Guacamole - """ + domain_guac + """"
""" + ldap_env + """    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.guacamole.rule=Host(`""" + domain_guac + """`)"
      - "traefik.http.routers.guacamole.entrypoints=websecure"
      - "traefik.http.routers.guacamole.tls.certresolver=letsencrypt"
      - "traefik.http.routers.guacamole.middlewares=secHeaders@file,rateLimit@file,compress@file,guac-addprefix@docker"
      - "traefik.http.services.guacamole.loadbalancer.server.port=8080"
      - "traefik.http.middlewares.guac-addprefix.addprefix.prefix=/guacamole"
"""

with open(base_dir + "/docker-compose.yml", "w") as f:
    f.write(compose)
print("docker-compose.yml écrit")
PYEOF

log "docker-compose.yml généré"

# ════════════════════════════════════════
section "8. Validation YAML"
# ════════════════════════════════════════
docker compose -f "$BASE_DIR/docker-compose.yml" --env-file "$BASE_DIR/.env" config --quiet \
  && log "YAML valide" \
  || err "Erreur YAML dans docker-compose.yml"

# ════════════════════════════════════════
section "9. Démarrage des conteneurs"
# ════════════════════════════════════════
cd "$BASE_DIR"
docker compose --env-file .env up -d
log "Conteneurs démarrés"

# ════════════════════════════════════════
section "10. Attente MySQL + changement mot de passe admin"
# ════════════════════════════════════════
log "Attente de la disponibilité MySQL..."
for i in $(seq 1 16); do
  sleep 5
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' guac-db 2>/dev/null || echo "unknown")
  if [ "$STATUS" = "healthy" ]; then
    log "MySQL prêt (${i}x5s)"
    break
  fi
  echo -n "."
done
echo ""

log "Mise à jour du mot de passe admin Guacamole..."
docker exec guac-db mysql \
  -uroot -p"${MYSQL_ROOT_PASS}" guacamole_db \
  -e "UPDATE guacamole_user SET password_hash = UNHEX(SHA2(CONCAT('${GUAC_ADMIN_PASS}', HEX(password_salt)), 256)) WHERE entity_id = (SELECT entity_id FROM guacamole_entity WHERE name = 'guacadmin');" \
  2>/dev/null \
  && log "Mot de passe Guacamole mis à jour" \
  || warn "Echec MAJ mot de passe Guacamole — voir credentials"

# ════════════════════════════════════════
section "11. Sauvegarde des credentials"
# ════════════════════════════════════════
cat > "$CRED_FILE" <<CREDS
======================================================
  CREDENTIALS COMPLETS — $(date)
======================================================

── GUACAMOLE ──────────────────────────────────────
URL            : https://${DOMAIN_GUAC}/guacamole
Login          : guacadmin
Password       : ${GUAC_ADMIN_PASS}
2FA TOTP       : à configurer à la 1ère connexion

── TRAEFIK DASHBOARD ──────────────────────────────
URL            : https://${DOMAIN_TRAEFIK}/dashboard/
Login          : admin
Password       : ${TRAEFIK_PASS}

── PORTAINER ──────────────────────────────────────
URL            : https://${DOMAIN_PORTAINER}
Login          : à créer à la 1ère connexion
                 (délai de 5 min après démarrage)

── MYSQL ──────────────────────────────────────────
Root password  : ${MYSQL_ROOT_PASS}
User password  : ${MYSQL_GUAC_PASS}

── FICHIERS ───────────────────────────────────────
Compose        : ${BASE_DIR}/docker-compose.yml
Env            : ${BASE_DIR}/.env
Traefik config : ${TRAEFIK_DIR}/traefik.yml
Dynamic config : ${TRAEFIK_DIR}/config/dynamic.yml
Logs Traefik   : ${TRAEFIK_DIR}/logs/
======================================================
CREDS
chmod 600 "$CRED_FILE"
log "Credentials sauvegardés dans : $CRED_FILE"

# ════════════════════════════════════════
section "Résumé final"
# ════════════════════════════════════════
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  Déploiement complet avec succès !${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  🖥️  Guacamole    : https://${DOMAIN_GUAC}/guacamole"
echo -e "  👤  Login        : guacadmin / ${GUAC_ADMIN_PASS}"
echo ""
echo -e "  🔀  Traefik      : https://${DOMAIN_TRAEFIK}/dashboard/"
echo -e "  👤  Login        : admin / ${TRAEFIK_PASS}"
echo ""
echo -e "  🐳  Portainer    : https://${DOMAIN_PORTAINER}"
echo -e "  👤  Login        : à créer à la 1ère connexion"
echo ""
echo -e "  📋  Credentials  : ${CRED_FILE}"
echo ""
if [ "$LDAP_ENABLED" = "true" ]; then
  echo -e "  🔗  LDAP         : activé → ${LDAP_HOSTNAME}:${LDAP_PORT}"
  echo ""
fi
echo -e "${YELLOW}  ⚠️  Actions post-déploiement :${NC}"
echo -e "  1. Guacamole  → changer le mot de passe admin"
echo -e "  2. Guacamole  → configurer le TOTP (2FA)"
echo -e "  3. Portainer  → créer le compte admin (dans les 5 min)"
echo -e "  4. Portainer  → sélectionner 'Get Started' > 'local'"
if [ "$LDAP_ENABLED" = "true" ]; then
  echo -e "  5. LDAP       → tester la connexion avec un compte AD"
fi
echo ""
echo -e "${BLUE}  Commandes utiles :${NC}"
echo -e "  sudo docker compose -f ${BASE_DIR}/docker-compose.yml ps"
echo -e "  sudo docker compose -f ${BASE_DIR}/docker-compose.yml logs -f"
echo -e "  sudo tail -f ${TRAEFIK_DIR}/logs/traefik.log"
echo ""
