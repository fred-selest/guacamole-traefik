#!/bin/bash
set -euo pipefail

# ============================================================
#  INTEGRATION LDAP / ACTIVE DIRECTORY — Guacamole
#  Usage : sudo bash 5_configure_ldap.sh
#
#  Ce script configure Guacamole pour s'authentifier
#  via un annuaire LDAP ou Active Directory.
#
#  Prérequis : avoir déployé avec 2_deploy_guacamole.sh
# ============================================================

# ---- CONFIG LDAP (à renseigner avant de lancer) ------------
#
#  Active Directory (Windows Server) :
#    LDAP_HOSTNAME          → IP ou FQDN du contrôleur de domaine
#    LDAP_PORT              → 389 (LDAP) ou 636 (LDAPS)
#    LDAP_ENCRYPTION_METHOD → none | starttls | ssl
#    LDAP_USER_BASE_DN      → OU où se trouvent les utilisateurs
#    LDAP_USERNAME_ATTRIBUTE → sAMAccountName (AD) ou uid (OpenLDAP)
#    LDAP_SEARCH_BIND_DN    → compte de service (ex: CN=guac-svc,OU=Services,DC=domaine,DC=com)
#    LDAP_SEARCH_BIND_PASSWORD → mot de passe du compte de service
#    LDAP_GROUP_BASE_DN     → OU des groupes (optionnel)
#
#  OpenLDAP :
#    LDAP_USERNAME_ATTRIBUTE → uid
#    LDAP_USER_BASE_DN       → ou=users,dc=domaine,dc=com
# ------------------------------------------------------------
LDAP_HOSTNAME="${LDAP_HOSTNAME:-}"
LDAP_PORT="${LDAP_PORT:-389}"
LDAP_ENCRYPTION_METHOD="${LDAP_ENCRYPTION_METHOD:-none}"    # none | starttls | ssl
LDAP_USER_BASE_DN="${LDAP_USER_BASE_DN:-}"
LDAP_USERNAME_ATTRIBUTE="${LDAP_USERNAME_ATTRIBUTE:-sAMAccountName}"
LDAP_SEARCH_BIND_DN="${LDAP_SEARCH_BIND_DN:-}"
LDAP_SEARCH_BIND_PASSWORD="${LDAP_SEARCH_BIND_PASSWORD:-}"
LDAP_GROUP_BASE_DN="${LDAP_GROUP_BASE_DN:-}"
LDAP_GROUP_SEARCH_FILTER="${LDAP_GROUP_SEARCH_FILTER:-}"
LDAP_MEMBER_ATTRIBUTE="${LDAP_MEMBER_ATTRIBUTE:-member}"
LDAP_FOLLOW_REFERRALS="${LDAP_FOLLOW_REFERRALS:-false}"
LDAP_MAX_REFERRAL_HOPS="${LDAP_MAX_REFERRAL_HOPS:-5}"

BASE_DIR="/opt/guacamole"
# ------------------------------------------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}══ $1 ══${NC}"; }

[[ $EUID -ne 0 ]] && err "Lance ce script en root : sudo bash $0"
command -v docker &>/dev/null || err "Docker non installé"
[ -f "$BASE_DIR/docker-compose.yml" ] || err "docker-compose.yml introuvable — déployer d'abord avec 2_deploy_guacamole.sh"

# ════════════════════════════════════════
section "1. Collecte des paramètres LDAP"
# ════════════════════════════════════════

# Demander les paramètres interactivement si non fournis via env
prompt_if_empty() {
  local var_name=$1
  local prompt_text=$2
  local default_val=${3:-}
  local current_val
  current_val=$(eval echo "\${$var_name}")

  if [ -z "$current_val" ]; then
    if [ -n "$default_val" ]; then
      read -rp "  ${prompt_text} [${default_val}] : " INPUT
      eval "${var_name}=\"\${INPUT:-$default_val}\""
    else
      while [ -z "$current_val" ]; do
        read -rp "  ${prompt_text} : " INPUT
        eval "${var_name}=\"${INPUT}\""
        current_val=$(eval echo "\${$var_name}")
        [ -z "$current_val" ] && warn "Ce champ est obligatoire"
      done
    fi
  fi
}

echo ""
echo -e "${BLUE}Configuration LDAP / Active Directory${NC}"
echo -e "Laissez vide pour utiliser la valeur par défaut entre crochets."
echo ""

prompt_if_empty "LDAP_HOSTNAME"         "Hostname LDAP / IP du contrôleur de domaine"
prompt_if_empty "LDAP_PORT"             "Port LDAP" "389"
prompt_if_empty "LDAP_ENCRYPTION_METHOD" "Chiffrement (none/starttls/ssl)" "none"
prompt_if_empty "LDAP_USER_BASE_DN"     "Base DN des utilisateurs (ex: OU=Users,DC=domaine,DC=com)"
prompt_if_empty "LDAP_USERNAME_ATTRIBUTE" "Attribut nom d'utilisateur" "sAMAccountName"

echo ""
echo -e "${YELLOW}Compte de service (optionnel, recommandé pour AD) :${NC}"
read -rp "  DN du compte de service (ou Entrée pour ignorer) : " LDAP_SEARCH_BIND_DN
if [ -n "$LDAP_SEARCH_BIND_DN" ]; then
  read -rsp "  Mot de passe du compte de service : " LDAP_SEARCH_BIND_PASSWORD
  echo ""
fi

echo ""
echo -e "${YELLOW}Groupes (optionnel) :${NC}"
read -rp "  Base DN des groupes (ou Entrée pour ignorer) : " LDAP_GROUP_BASE_DN
if [ -n "$LDAP_GROUP_BASE_DN" ]; then
  read -rp "  Filtre de recherche des groupes [${LDAP_GROUP_SEARCH_FILTER}] : " INPUT
  LDAP_GROUP_SEARCH_FILTER="${INPUT:-$LDAP_GROUP_SEARCH_FILTER}"
fi

# ════════════════════════════════════════
section "2. Validation des paramètres"
# ════════════════════════════════════════

echo ""
echo -e "  Hostname       : ${LDAP_HOSTNAME}"
echo -e "  Port           : ${LDAP_PORT}"
echo -e "  Chiffrement    : ${LDAP_ENCRYPTION_METHOD}"
echo -e "  User Base DN   : ${LDAP_USER_BASE_DN}"
echo -e "  Attribut user  : ${LDAP_USERNAME_ATTRIBUTE}"
[ -n "$LDAP_SEARCH_BIND_DN" ] && echo -e "  Compte service : ${LDAP_SEARCH_BIND_DN}"
[ -n "$LDAP_GROUP_BASE_DN"  ] && echo -e "  Groupe Base DN : ${LDAP_GROUP_BASE_DN}"
echo ""

read -rp "Ces paramètres sont-ils corrects ? (oui/non) : " CONFIRM
[ "$CONFIRM" != "oui" ] && { warn "Configuration annulée"; exit 0; }

# ════════════════════════════════════════
section "3. Test de connectivité LDAP"
# ════════════════════════════════════════

if docker exec guacamole sh -c "nc -z -w5 ${LDAP_HOSTNAME} ${LDAP_PORT} 2>/dev/null"; then
  log "Connectivité LDAP OK : ${LDAP_HOSTNAME}:${LDAP_PORT}"
else
  warn "Impossible de joindre ${LDAP_HOSTNAME}:${LDAP_PORT} depuis le conteneur Guacamole"
  warn "Vérifier : firewall, réseau Docker, hostname DNS"
  read -rp "Continuer quand même ? (oui/non) : " FORCE
  [ "$FORCE" != "oui" ] && exit 1
fi

# ════════════════════════════════════════
section "4. Mise à jour du docker-compose.yml"
# ════════════════════════════════════════

# Construire le bloc de variables LDAP à insérer
LDAP_BLOCK="      LDAP_HOSTNAME: ${LDAP_HOSTNAME}
      LDAP_PORT: \"${LDAP_PORT}\"
      LDAP_ENCRYPTION_METHOD: ${LDAP_ENCRYPTION_METHOD}
      LDAP_USER_BASE_DN: \"${LDAP_USER_BASE_DN}\"
      LDAP_USERNAME_ATTRIBUTE: ${LDAP_USERNAME_ATTRIBUTE}
      LDAP_FOLLOW_REFERRALS: \"${LDAP_FOLLOW_REFERRALS}\"
      LDAP_MAX_REFERRAL_HOPS: \"${LDAP_MAX_REFERRAL_HOPS}\""

if [ -n "$LDAP_SEARCH_BIND_DN" ]; then
  LDAP_BLOCK="${LDAP_BLOCK}
      LDAP_SEARCH_BIND_DN: \"${LDAP_SEARCH_BIND_DN}\"
      LDAP_SEARCH_BIND_PASSWORD: \"${LDAP_SEARCH_BIND_PASSWORD}\""
fi

if [ -n "$LDAP_GROUP_BASE_DN" ]; then
  LDAP_BLOCK="${LDAP_BLOCK}
      LDAP_GROUP_BASE_DN: \"${LDAP_GROUP_BASE_DN}\"
      LDAP_MEMBER_ATTRIBUTE: ${LDAP_MEMBER_ATTRIBUTE}"
  if [ -n "$LDAP_GROUP_SEARCH_FILTER" ]; then
    LDAP_BLOCK="${LDAP_BLOCK}
      LDAP_GROUP_SEARCH_FILTER: \"${LDAP_GROUP_SEARCH_FILTER}\""
  fi
fi

# Sauvegarder le docker-compose actuel
BACKUP_COMPOSE="${BASE_DIR}/docker-compose.yml.bak.$(date +%Y%m%d-%H%M%S)"
cp "${BASE_DIR}/docker-compose.yml" "$BACKUP_COMPOSE"
log "Backup docker-compose.yml → ${BACKUP_COMPOSE}"

# Injecter les variables LDAP via Python (robuste aux indentations)
python3 - "$LDAP_BLOCK" <<'PYEOF'
import sys, re

ldap_block = sys.argv[1]
compose_file = "/opt/guacamole/docker-compose.yml"

content = open(compose_file).read()

# Supprimer l'ancien bloc LDAP s'il existe déjà
content = re.sub(
    r'(\s+LDAP_[A-Z_]+:.*\n)+',
    '',
    content
)

# Injecter après TOTP_ENABLED
marker = 'TOTP_ENABLED: "true"'
if marker not in content:
    # Chercher TOTP_ISSUER à la place
    marker = 'TOTP_ISSUER:'
    if marker not in content:
        print("ERREUR: marqueur TOTP introuvable dans docker-compose.yml")
        sys.exit(1)

# Trouver la ligne du marqueur et insérer après
lines = content.split('\n')
new_lines = []
for line in lines:
    new_lines.append(line)
    if marker in line:
        # Ajouter les variables LDAP après cette ligne
        for ldap_line in ldap_block.split('\n'):
            new_lines.append(ldap_line)

content = '\n'.join(new_lines)
open(compose_file, 'w').write(content)
print("docker-compose.yml mis à jour avec la configuration LDAP")
PYEOF

log "docker-compose.yml mis à jour"

# ════════════════════════════════════════
section "5. Validation YAML"
# ════════════════════════════════════════
docker compose -f "${BASE_DIR}/docker-compose.yml" --env-file "${BASE_DIR}/.env" config --quiet \
  && log "YAML valide" \
  || { err "Erreur YAML — restauration du backup..."; cp "$BACKUP_COMPOSE" "${BASE_DIR}/docker-compose.yml"; exit 1; }

# ════════════════════════════════════════
section "6. Redémarrage de Guacamole"
# ════════════════════════════════════════
cd "$BASE_DIR"
docker compose --env-file .env up -d --force-recreate guacamole
log "Guacamole redémarré avec la configuration LDAP"

log "Attente du démarrage (~15s)..."
sleep 15

# Vérifier les logs pour détecter des erreurs LDAP
echo ""
echo -e "${BLUE}Derniers logs Guacamole :${NC}"
docker logs guacamole 2>&1 | grep -i "ldap\|error\|warn\|started" | tail -10 || true

# ════════════════════════════════════════
section "Résumé de la configuration LDAP"
# ════════════════════════════════════════
echo ""
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  LDAP/AD configuré !${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo ""
echo -e "  Serveur LDAP   : ${LDAP_HOSTNAME}:${LDAP_PORT} (${LDAP_ENCRYPTION_METHOD})"
echo -e "  Base DN users  : ${LDAP_USER_BASE_DN}"
echo -e "  Attribut       : ${LDAP_USERNAME_ATTRIBUTE}"
[ -n "$LDAP_SEARCH_BIND_DN" ] && echo -e "  Compte service : ${LDAP_SEARCH_BIND_DN}"
[ -n "$LDAP_GROUP_BASE_DN"  ] && echo -e "  Groupes        : ${LDAP_GROUP_BASE_DN}"
echo ""
echo -e "${YELLOW}  Actions à effectuer :${NC}"
echo -e "  1. Se connecter à Guacamole avec un compte AD/LDAP"
echo -e "  2. Vérifier que l'utilisateur apparaît dans Guacamole"
echo -e "  3. Assigner les connexions aux utilisateurs/groupes LDAP"
echo ""
echo -e "${BLUE}  Diagnostic en cas de problème :${NC}"
echo -e "  sudo docker logs guacamole 2>&1 | grep -i ldap"
echo -e "  sudo docker exec guacamole nc -zv ${LDAP_HOSTNAME} ${LDAP_PORT}"
echo ""
echo -e "${YELLOW}  Désactiver le LDAP :${NC}"
echo -e "  Restaurer le backup : sudo cp ${BACKUP_COMPOSE} ${BASE_DIR}/docker-compose.yml"
echo -e "  Puis : cd ${BASE_DIR} && sudo docker compose --env-file .env up -d --force-recreate guacamole"
echo ""
