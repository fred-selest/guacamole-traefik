#!/bin/bash
set -euo pipefail

# ============================================================
#  THEME GUACAMOLE — Corporate Blue Edition (Révisé)
#  Usage : sudo bash 3_theme_guacamole.sh
#
#  Ce script :
#   1. Inspecte le container pour trouver les vraies classes HTML
#   2. Génère un CSS ciblé + badge de vérification visible
#   3. Supprime TOUS les anciens .jar de thème
#   4. Installe le nouveau thème et redémarre Guacamole
#   5. Vérifie que l'extension est bien chargée
# ============================================================

# ---- CONFIG (personnalisable via variables d'env) ----------
COMPANY_NAME="${COMPANY_NAME:-Selest Informatique}"
COMPANY_SUBTITLE="${COMPANY_SUBTITLE:-Accès distant sécurisé}"
PRIMARY_COLOR="${PRIMARY_COLOR:-#1d4ed8}"
ACCENT_COLOR="${ACCENT_COLOR:-#3b82f6}"
THEME_BUILD_DIR="/tmp/guac-theme-build"
THEME_JAR="corporate-theme.jar"
EXTENSIONS_DIR="/opt/guacamole-extensions"
GUACAMOLE_DIR="/opt/guacamole"
# ------------------------------------------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}══ $1 ══${NC}"; }
ok()      { echo -e "  ${GREEN}✓${NC} $1"; }
nok()     { echo -e "  ${RED}✗${NC} $1"; }

[[ $EUID -ne 0 ]] && err "Lance ce script en root : sudo bash $0"
command -v zip    &>/dev/null || apt-get install -y -qq zip
command -v docker &>/dev/null || err "Docker manquant"

# Fonction pour vérifier si Guacamole est en cours d'exécution
check_guacamole_running() {
    if [[ -d "$GUACAMOLE_DIR" ]] && [[ -f "$GUACAMOLE_DIR/.env" ]]; then
        cd "$GUACAMOLE_DIR"
        if docker compose --env-file .env ps | grep -q "guacamole.*Up"; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# ════════════════════════════════════════
section "0. Inspection du container Guacamole"
# ════════════════════════════════════════
# Variables qui seront remplies par l'inspection
GUAC_CTR=""
GUAC_VERSION="inconnue"
GUAC_WEBAPP=""
GUAC_CLASSES=""
# Sélecteurs par défaut (couvrent Guacamole 1.3 à 1.5+)
NAV_SELECTOR="header"
HOME_SELECTOR=".home-page, .connection-list-parent"

# Trouver le container guacamole (pas guacd)
for _ctr in $(docker ps --format '{{.Names}}' 2>/dev/null || true); do
    if echo "$_ctr" | grep -qi 'guacamole' && ! echo "$_ctr" | grep -qi 'guacd'; then
        GUAC_CTR="$_ctr"
        break
    fi
done

if [[ -z "$GUAC_CTR" ]]; then
    warn "Aucun container Guacamole trouvé en cours d'exécution"
    warn "Sélecteurs par défaut seront utilisés"
else
    log "Container : $GUAC_CTR"

    # Version depuis les labels de l'image
    GUAC_VERSION=$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' \
        "$GUAC_CTR" 2>/dev/null || echo "inconnue")
    log "Version   : $GUAC_VERSION"

    # Trouver le répertoire webapp dans le container
    for _p in \
        "/usr/local/tomcat/webapps/guacamole" \
        "/usr/local/tomcat/webapps/ROOT" \
        "/opt/guacamole/webapp"; do
        if docker exec "$GUAC_CTR" test -d "$_p/app" 2>/dev/null; then
            GUAC_WEBAPP="$_p"
            break
        fi
    done

    if [[ -n "$GUAC_WEBAPP" ]]; then
        log "Webapp    : $GUAC_WEBAPP"

        # Extraire toutes les classes HTML des templates Angular
        _INSPECT_FILE="/tmp/guac-classes.txt"
        docker exec "$GUAC_CTR" \
            find "$GUAC_WEBAPP/app" -name "*.html" 2>/dev/null \
            | while read -r _f; do
                docker exec "$GUAC_CTR" cat "$_f" 2>/dev/null || true
            done \
            | grep -oP '(?<=class=")[^"]+' \
            | tr ' ' '\n' \
            | sort -u \
            | grep -v '^$' \
            > "$_INSPECT_FILE" 2>/dev/null || true

        if [[ -s "$_INSPECT_FILE" ]]; then
            GUAC_CLASSES=$(cat "$_INSPECT_FILE")
            CLASS_COUNT=$(wc -l < "$_INSPECT_FILE")
            log "Classes trouvées : $CLASS_COUNT"

            # Détecter le sélecteur de nav réel
            if grep -qx "menu" "$_INSPECT_FILE"; then
                NAV_SELECTOR="header, .menu"
            fi
            if grep -qx "guac-menu" "$_INSPECT_FILE"; then
                NAV_SELECTOR="header, .guac-menu"
            fi

            # Détecter le sélecteur de la page d'accueil
            if grep -qx "home-page" "$_INSPECT_FILE"; then
                HOME_SELECTOR=".home-page"
            fi

            log "Sélecteur nav    : $NAV_SELECTOR"
            log "Sélecteur home   : $HOME_SELECTOR"
        else
            warn "Templates HTML non accessibles — sélecteurs par défaut"
        fi
    else
        warn "Webapp non trouvée dans le container"
    fi
fi

# ════════════════════════════════════════
section "Configuration du thème"
# ════════════════════════════════════════
ask() {
  local prompt="$1" default="$2" varname="$3" val
  printf "  ${BLUE}?${NC} %-40s ${YELLOW}[%s]${NC} : " "$prompt" "$default"
  read -r val </dev/tty
  printf -v "$varname" '%s' "${val:-$default}"
}

echo ""
echo -e "  Appuyez sur Entrée pour conserver la valeur par défaut."
echo ""
echo -e "${BLUE}  ── Identité ─────────────────────────────────────────────${NC}"
ask "Nom affiché sur le logo"       "$COMPANY_NAME"     COMPANY_NAME
ask "Sous-titre du logo"            "$COMPANY_SUBTITLE" COMPANY_SUBTITLE
echo ""
echo -e "${BLUE}  ── Couleurs (format hex ex: #1d4ed8) ────────────────────${NC}"
ask "Couleur principale"            "$PRIMARY_COLOR"    PRIMARY_COLOR
ask "Couleur accent"                "$ACCENT_COLOR"     ACCENT_COLOR
echo ""
echo -e "${BLUE}  ── Récapitulatif ──────────────────────────────────────${NC}"
echo -e "  Nom              : ${GREEN}${COMPANY_NAME}${NC}"
echo -e "  Sous-titre       : ${GREEN}${COMPANY_SUBTITLE}${NC}"
echo -e "  Couleur princ.   : ${GREEN}${PRIMARY_COLOR}${NC}"
echo -e "  Couleur accent   : ${GREEN}${ACCENT_COLOR}${NC}"
[[ -n "$GUAC_CTR" ]] && \
echo -e "  Container        : ${GREEN}${GUAC_CTR} (v${GUAC_VERSION})${NC}"
echo -e "${BLUE}  ────────────────────────────────────────────────────────${NC}"
echo ""
printf "  Générer et installer le thème ? [O/n] : "
read -r _confirm </dev/tty
[[ "${_confirm,,}" =~ ^(n|non|no)$ ]] && { echo "Annulé."; exit 0; }

# ════════════════════════════════════════
section "1. Préparation"
# ════════════════════════════════════════
rm -rf "$THEME_BUILD_DIR"
mkdir -p "$THEME_BUILD_DIR/images"
mkdir -p "$EXTENSIONS_DIR"
log "Répertoires préparés"

# ════════════════════════════════════════
section "2. Logo SVG corporate"
# ════════════════════════════════════════
cat > "$THEME_BUILD_DIR/images/logo.svg" <<LOGOSVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 340 72" width="340" height="72">
  <defs>
    <linearGradient id="g1" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${PRIMARY_COLOR}"/>
      <stop offset="100%" stop-color="${ACCENT_COLOR}"/>
    </linearGradient>
    <filter id="shadow">
      <feDropShadow dx="0" dy="2" stdDeviation="3" flood-color="${PRIMARY_COLOR}" flood-opacity="0.3"/>
    </filter>
  </defs>
  <rect x="4" y="8" width="52" height="36" rx="6" fill="url(#g1)" filter="url(#shadow)"/>
  <rect x="10" y="14" width="40" height="24" rx="3" fill="rgba(255,255,255,0.12)"/>
  <rect x="14" y="19" width="18" height="2.5" rx="1.2" fill="rgba(255,255,255,0.7)"/>
  <rect x="14" y="24" width="28" height="2.5" rx="1.2" fill="rgba(255,255,255,0.45)"/>
  <rect x="14" y="29" width="22" height="2.5" rx="1.2" fill="rgba(255,255,255,0.45)"/>
  <rect x="24" y="44" width="12" height="7" fill="url(#g1)"/>
  <rect x="18" y="51" width="24" height="3.5" rx="1.5" fill="url(#g1)"/>
  <text x="68" y="30" font-family="'Segoe UI', 'Helvetica Neue', sans-serif"
        font-size="22" font-weight="700" letter-spacing="-0.3"
        fill="#0f172a">${COMPANY_NAME}</text>
  <rect x="68" y="36" width="200" height="1.5" rx="1" fill="${PRIMARY_COLOR}" opacity="0.25"/>
  <text x="69" y="52" font-family="'Segoe UI', 'Helvetica Neue', sans-serif"
        font-size="12.5" font-weight="500" letter-spacing="0.8"
        fill="${ACCENT_COLOR}">${COMPANY_SUBTITLE}</text>
</svg>
LOGOSVG
log "Logo SVG généré"

# ════════════════════════════════════════
section "3. CSS Corporate Blue"
# ════════════════════════════════════════
# Passer les sélecteurs découverts au générateur Python
export GUAC_NAV_SELECTOR="$NAV_SELECTOR"
export GUAC_HOME_SELECTOR="$HOME_SELECTOR"
export GUAC_VERSION_EXPORT="$GUAC_VERSION"

python3 << 'PYEOF'
import os

nav  = os.environ.get('GUAC_NAV_SELECTOR',  'header')
home = os.environ.get('GUAC_HOME_SELECTOR', '.home-page, .connection-list-parent')
ver  = os.environ.get('GUAC_VERSION_EXPORT', 'inconnue')

css = f"""/* ============================================================
   CORPORATE BLUE THEME — Apache Guacamole v{ver}
   Généré automatiquement par 3_theme_guacamole.sh
   Sélecteurs nav  : {nav}
   Sélecteurs home : {home}

   Règles d'or appliquées :
   - Pas de sélecteurs globaux (button, a, input...) jamais
   - Pas de reset de margin sur *
   - Boutons stylisés UNIQUEMENT dans leur contexte précis
   ============================================================ */
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:opsz,wght@9..40,300;9..40,400;9..40,500;9..40,600;9..40,700&display=swap');

/* ══════════════════════════════════════════
   VARIABLES
   ══════════════════════════════════════════ */
:root {{
  --blue-800:  #1e40af;
  --blue-700:  #1d4ed8;
  --blue-600:  #2563eb;
  --blue-500:  #3b82f6;
  --blue-400:  #60a5fa;
  --blue-300:  #93c5fd;
  --blue-50:   #eff6ff;

  --bg-page:   #f0f4f8;
  --bg-card:   #ffffff;
  --bg-input:  #f8fafc;
  --bg-hover:  #f0f7ff;
  --bg-active: #dbeafe;
  --border:     #e2e8f0;
  --border-card:#e8edf5;

  --text-primary:   #0f172a;
  --text-secondary: #475569;
  --text-muted:     #94a3b8;

  --shadow-sm:  0 1px 3px rgba(15,23,42,0.06), 0 1px 2px rgba(15,23,42,0.04);
  --shadow-md:  0 4px 16px rgba(15,23,42,0.08), 0 2px 6px rgba(15,23,42,0.05);
  --shadow-lg:  0 12px 40px rgba(15,23,42,0.12), 0 4px 12px rgba(15,23,42,0.06);
  --shadow-blue:0 8px 32px rgba(37,99,235,0.18), 0 2px 8px rgba(37,99,235,0.1);

  --radius-sm: 6px;
  --radius-md: 10px;
  --radius-lg: 16px;
  --radius-xl: 20px;
  --ease:      cubic-bezier(0.4, 0, 0.2, 1);
  --spring:    cubic-bezier(0.34, 1.56, 0.64, 1);
}}

/* ══════════════════════════════════════════
   BADGE DE VÉRIFICATION
   Visible dans TOUS les coins bas-droite.
   Prouve que le thème est chargé par Guacamole.
   Supprimer ce bloc une fois confirmé.
   ══════════════════════════════════════════ */
body::after {{
  content: 'Corporate Blue ✓' !important;
  position: fixed !important;
  bottom: 10px !important;
  right: 10px !important;
  z-index: 2147483647 !important;
  background: #1d4ed8 !important;
  color: #fff !important;
  font-family: 'DM Sans', monospace !important;
  font-size: 11px !important;
  font-weight: 600 !important;
  padding: 4px 10px !important;
  border-radius: 20px !important;
  box-shadow: 0 2px 8px rgba(29,78,216,0.4) !important;
  pointer-events: none !important;
  letter-spacing: 0.3px !important;
}}

/* ══════════════════════════════════════════
   BASE — box-sizing seulement, PAS de margin reset
   ══════════════════════════════════════════ */
*, *::before, *::after {{ box-sizing: border-box; }}

html, body {{
  font-family: 'DM Sans', 'Segoe UI', system-ui, sans-serif !important;
  background: var(--bg-page) !important;
  color: var(--text-primary) !important;
  -webkit-font-smoothing: antialiased !important;
}}

/* ══════════════════════════════════════════
   PAGE DE LOGIN
   ══════════════════════════════════════════ */
.login-ui {{
  min-height: 100vh !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  background: linear-gradient(145deg, #eff6ff 0%, #f0f4f8 50%, #e8f0fe 100%) !important;
  position: relative !important;
  overflow: hidden !important;
}}

.login-ui::before {{
  content: '' !important;
  position: fixed !important;
  inset: 0 !important;
  background-image:
    radial-gradient(circle at 20% 20%, rgba(37,99,235,0.08) 0%, transparent 50%),
    radial-gradient(circle at 80% 80%, rgba(29,78,216,0.06) 0%, transparent 50%) !important;
  pointer-events: none !important;
  z-index: 0 !important;
}}

.login-ui::after {{
  content: '' !important;
  position: fixed !important;
  inset: 0 !important;
  background-image:
    linear-gradient(rgba(37,99,235,0.025) 1px, transparent 1px),
    linear-gradient(90deg, rgba(37,99,235,0.025) 1px, transparent 1px) !important;
  background-size: 48px 48px !important;
  pointer-events: none !important;
  z-index: 0 !important;
}}

/* Carte de login */
.login-ui .login-dialog {{
  background: var(--bg-card) !important;
  border: 1px solid var(--border-card) !important;
  border-radius: var(--radius-xl) !important;
  box-shadow: var(--shadow-lg) !important;
  padding: 48px 44px !important;
  width: 100% !important;
  max-width: 420px !important;
  position: relative !important;
  z-index: 1 !important;
  animation: loginAppear 0.5s var(--spring) !important;
}}

/* Bande bleue décorative en haut de la carte */
.login-ui .login-dialog::before {{
  content: '' !important;
  position: absolute !important;
  top: 0 !important; left: 0 !important; right: 0 !important;
  height: 4px !important;
  background: linear-gradient(90deg, #1d4ed8, #60a5fa) !important;
  border-radius: var(--radius-xl) var(--radius-xl) 0 0 !important;
}}

@keyframes loginAppear {{
  from {{ opacity: 0; transform: translateY(28px) scale(0.97); }}
  to   {{ opacity: 1; transform: translateY(0)    scale(1); }}
}}

/* Logo */
.login-ui .login-dialog .logo {{
  width: 260px !important;
  height: 64px !important;
  background-size: contain !important;
  background-repeat: no-repeat !important;
  background-position: left center !important;
  margin: 0 auto 36px !important;
  display: block !important;
}}

/* Champs */
.login-ui .login-fields .labeled-field {{
  margin-bottom: 18px !important;
  position: relative !important;
}}

.login-ui .login-fields .labeled-field input,
.login-ui .login-fields .labeled-field input[type="text"],
.login-ui .login-fields .labeled-field input[type="password"] {{
  background: var(--bg-input) !important;
  border: 1.5px solid var(--border) !important;
  border-radius: var(--radius-md) !important;
  color: var(--text-primary) !important;
  font-family: inherit !important;
  font-size: 15px !important;
  padding: 13px 16px !important;
  width: 100% !important;
  transition: border-color 0.2s var(--ease), box-shadow 0.2s var(--ease) !important;
  outline: none !important;
}}

.login-ui .login-fields .labeled-field input:focus {{
  border-color: var(--blue-500) !important;
  background: #fff !important;
  box-shadow: 0 0 0 4px rgba(59,130,246,0.12) !important;
}}

.login-ui .login-fields .labeled-field.empty input {{
  color: var(--text-muted) !important;
}}

.login-ui .login-fields .labeled-field .placeholder {{
  color: var(--text-muted) !important;
  font-size: 14px !important;
  padding: 13px 16px !important;
  pointer-events: none !important;
}}

/* Bouton connexion — scopé à .login-ui uniquement */
.login-ui input[type="submit"],
.login-ui button[type="submit"],
.login-ui button.login {{
  background: linear-gradient(135deg, var(--blue-700) 0%, var(--blue-600) 100%) !important;
  border: none !important;
  border-radius: var(--radius-md) !important;
  color: #fff !important;
  cursor: pointer !important;
  font-family: inherit !important;
  font-size: 15px !important;
  font-weight: 600 !important;
  letter-spacing: 0.2px !important;
  padding: 14px !important;
  width: 100% !important;
  margin-top: 10px !important;
  box-shadow: 0 4px 14px rgba(29,78,216,0.3) !important;
  transition: all 0.2s var(--ease) !important;
}}

.login-ui input[type="submit"]:hover,
.login-ui button[type="submit"]:hover,
.login-ui button.login:hover {{
  background: linear-gradient(135deg, var(--blue-800) 0%, var(--blue-700) 100%) !important;
  box-shadow: 0 6px 20px rgba(29,78,216,0.4) !important;
  transform: translateY(-1px) !important;
}}

.login-ui input[type="submit"]:active {{ transform: translateY(0) !important; }}

/* Erreur login */
.login-ui .error {{
  background: #fef2f2 !important;
  border: 1px solid #fecaca !important;
  border-left: 3px solid #ef4444 !important;
  border-radius: var(--radius-sm) !important;
  color: #dc2626 !important;
  font-size: 13.5px !important;
  padding: 10px 14px !important;
  margin-top: 8px !important;
}}

/* ══════════════════════════════════════════
   BARRE DE NAVIGATION
   Sélecteurs auto-détectés : {nav}
   IMPORTANT : NE PAS grouper avec .context-menu
   ou .dropdown-menu — ils ont un style différent.
   ══════════════════════════════════════════ */
{nav} {{
  background: #ffffff !important;
  border-bottom: 1px solid var(--border) !important;
  box-shadow: var(--shadow-sm) !important;
  /* Pas de border-radius — c'est une barre pleine largeur */
}}

/* Liens dans la nav — transparents, jamais de bg coloré */
{nav} a {{
  color: var(--text-secondary) !important;
  background: transparent !important;
  text-decoration: none !important;
  font-weight: 500 !important;
  transition: color 0.18s var(--ease) !important;
}}

{nav} a:hover {{
  color: var(--blue-700) !important;
  background: var(--bg-hover) !important;
}}

/* Zone utilisateur (guacadmin) — fond transparent sur nav blanche */
.user-menu,
.user-menu > span,
.user-menu > a,
.user-menu > button,
.user-menu .username {{
  background: transparent !important;
  color: var(--text-secondary) !important;
  border: none !important;
  box-shadow: none !important;
  font-weight: 500 !important;
}}

.user-menu > a:hover,
.user-menu > button:hover {{
  background: var(--bg-hover) !important;
  color: var(--blue-700) !important;
  border-radius: var(--radius-sm) !important;
}}

/* ══════════════════════════════════════════
   DROPDOWNS ET MENUS CONTEXTUELS
   Séparés de la nav — style carte flottante
   ══════════════════════════════════════════ */
.user-menu-dropdown,
.context-menu,
.dropdown-menu {{
  background: var(--bg-card) !important;
  border: 1px solid var(--border) !important;
  border-radius: var(--radius-md) !important;
  box-shadow: var(--shadow-md) !important;
  overflow: hidden !important;
}}

.user-menu-dropdown a,
.user-menu-dropdown button,
.context-menu a,
.context-menu li,
.dropdown-menu a,
.dropdown-menu button {{
  color: var(--text-secondary) !important;
  font-size: 14px !important;
  font-weight: 500 !important;
  text-decoration: none !important;
  background: transparent !important;
  transition: background 0.15s var(--ease), color 0.15s var(--ease) !important;
}}

.user-menu-dropdown a:hover,
.user-menu-dropdown button:hover,
.context-menu li:hover,
.dropdown-menu a:hover,
.dropdown-menu button:hover {{
  background: var(--bg-hover) !important;
  color: var(--blue-700) !important;
}}

.user-menu-dropdown hr,
.context-menu hr,
.dropdown-menu hr {{
  border: none !important;
  border-top: 1px solid var(--border) !important;
  margin: 4px 0 !important;
}}

/* ══════════════════════════════════════════
   PAGE D'ACCUEIL — fond et cartes
   Sélecteurs : {home}
   ══════════════════════════════════════════ */
{home} {{
  background: var(--bg-page) !important;
}}

/* Cartes de connexion */
.connection {{
  background: var(--bg-card) !important;
  border: 1px solid var(--border-card) !important;
  border-radius: var(--radius-lg) !important;
  box-shadow: var(--shadow-sm) !important;
  overflow: hidden !important;
  position: relative !important;
  transition: transform 0.28s var(--spring), box-shadow 0.28s var(--spring), border-color 0.2s var(--ease) !important;
}}

/* Bande bleue en haut de chaque carte */
.connection::before {{
  content: '' !important;
  position: absolute !important;
  top: 0 !important; left: 0 !important; right: 0 !important;
  height: 3px !important;
  background: linear-gradient(90deg, #1d4ed8, #60a5fa) !important;
  z-index: 1 !important;
}}

.connection:hover {{
  border-color: var(--blue-300) !important;
  box-shadow: var(--shadow-blue) !important;
  transform: translateY(-4px) !important;
}}

.connection .name {{
  color: var(--text-primary) !important;
  font-size: 14px !important;
  font-weight: 600 !important;
}}

.connection .protocol {{
  color: var(--text-muted) !important;
  font-size: 11px !important;
  font-weight: 600 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.6px !important;
}}

/* Groupes de connexions */
.connection-group-label {{
  color: var(--text-secondary) !important;
  font-size: 11.5px !important;
  font-weight: 700 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.8px !important;
  border-bottom: 2px solid var(--border) !important;
  padding-bottom: 8px !important;
  margin-bottom: 12px !important;
}}

/* ══════════════════════════════════════════
   BOUTONS — UNIQUEMENT dans les dialogues
   NE PAS créer de règle "button {{}}" globale.
   ══════════════════════════════════════════ */
.dialog button, .dialog input[type="submit"],
.prompt button, .prompt input[type="submit"],
.notification-actions button {{
  font-family: inherit !important;
  font-size: 14px !important;
  font-weight: 600 !important;
  border-radius: var(--radius-md) !important;
  cursor: pointer !important;
  padding: 9px 18px !important;
  transition: all 0.18s var(--ease) !important;
  background: var(--blue-600) !important;
  color: #fff !important;
  border: none !important;
}}

.dialog button:hover,
.dialog input[type="submit"]:hover {{
  background: var(--blue-700) !important;
}}

.dialog button.cancel {{
  background: var(--bg-input) !important;
  color: var(--text-secondary) !important;
  border: 1px solid var(--border) !important;
}}

.dialog button.danger, .dialog button.delete {{
  background: #ef4444 !important;
}}

.dialog button.danger:hover, .dialog button.delete:hover {{
  background: #dc2626 !important;
}}

/* ══════════════════════════════════════════
   FORMULAIRES (pages admin)
   ══════════════════════════════════════════ */
.form-field input[type="text"],
.form-field input[type="password"],
.form-field input[type="email"],
.form-field input[type="number"],
.form-field select,
.form-field textarea {{
  background: var(--bg-input) !important;
  border: 1.5px solid var(--border) !important;
  border-radius: var(--radius-md) !important;
  color: var(--text-primary) !important;
  font-family: inherit !important;
  font-size: 14px !important;
  transition: border-color 0.18s var(--ease), box-shadow 0.18s var(--ease) !important;
  outline: none !important;
}}

.form-field input:focus,
.form-field select:focus,
.form-field textarea:focus {{
  border-color: var(--blue-500) !important;
  background: #fff !important;
  box-shadow: 0 0 0 3px rgba(59,130,246,0.12) !important;
}}

/* ══════════════════════════════════════════
   TABLEAUX
   ══════════════════════════════════════════ */
table {{
  width: 100% !important;
  border-collapse: collapse !important;
  background: var(--bg-card) !important;
  border-radius: var(--radius-lg) !important;
  overflow: hidden !important;
  box-shadow: var(--shadow-sm) !important;
  border: 1px solid var(--border-card) !important;
}}

table thead tr {{ background: var(--bg-page) !important; }}

table th {{
  color: var(--text-muted) !important;
  font-size: 11.5px !important;
  font-weight: 700 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.7px !important;
  padding: 12px 16px !important;
  text-align: left !important;
  border-bottom: 1px solid var(--border) !important;
}}

table td {{
  color: var(--text-primary) !important;
  font-size: 14px !important;
  padding: 13px 16px !important;
  border-bottom: 1px solid rgba(226,232,240,0.6) !important;
}}

table tr:last-child td {{ border-bottom: none !important; }}

table tbody tr:hover {{ background: var(--bg-hover) !important; }}

/* ══════════════════════════════════════════
   NOTIFICATIONS ET MODALES
   ══════════════════════════════════════════ */
.notification, .alert {{
  background: var(--bg-card) !important;
  border: 1px solid var(--border) !important;
  border-radius: var(--radius-lg) !important;
  box-shadow: var(--shadow-md) !important;
  padding: 18px 22px !important;
}}

.notification.error   {{ border-left: 4px solid #ef4444 !important; background: #fef2f2 !important; }}
.notification.success {{ border-left: 4px solid #10b981 !important; background: #f0fdf4 !important; }}
.notification.info    {{ border-left: 4px solid var(--blue-500) !important; background: var(--blue-50) !important; }}

.dialog, .modal {{
  background: var(--bg-card) !important;
  border-radius: var(--radius-xl) !important;
  box-shadow: var(--shadow-lg) !important;
  border: 1px solid var(--border) !important;
}}

.overlay, .modal-backdrop {{
  background: rgba(15, 23, 42, 0.35) !important;
  backdrop-filter: blur(4px) !important;
}}

/* ══════════════════════════════════════════
   BARRE LATÉRALE ADMIN
   ══════════════════════════════════════════ */
.settings-menu {{
  background: var(--bg-card) !important;
  border-right: 1px solid var(--border) !important;
}}

.settings-menu a {{
  color: var(--text-secondary) !important;
  font-size: 14px !important;
  font-weight: 500 !important;
  border-radius: var(--radius-sm) !important;
  text-decoration: none !important;
  transition: background 0.15s var(--ease), color 0.15s var(--ease) !important;
}}

.settings-menu a:hover {{ background: var(--bg-hover) !important; color: var(--blue-700) !important; }}
.settings-menu a.active {{ background: var(--bg-active) !important; color: var(--blue-700) !important; font-weight: 600 !important; }}

/* ══════════════════════════════════════════
   TOOLBAR SESSION ACTIVE
   ══════════════════════════════════════════ */
.client-controls, .client-toolbar {{
  background: rgba(255,255,255,0.96) !important;
  backdrop-filter: blur(8px) !important;
  border-bottom: 1px solid var(--border) !important;
  box-shadow: var(--shadow-sm) !important;
}}

/* ══════════════════════════════════════════
   SCROLLBARS
   ══════════════════════════════════════════ */
::-webkit-scrollbar {{ width: 7px; height: 7px; }}
::-webkit-scrollbar-track {{ background: transparent; }}
::-webkit-scrollbar-thumb {{ background: #cbd5e1; border-radius: 4px; }}
::-webkit-scrollbar-thumb:hover {{ background: #94a3b8; }}

::selection {{ background: rgba(59,130,246,0.2); color: var(--text-primary); }}

input[type="checkbox"] {{
  width: 16px !important; height: 16px !important;
  accent-color: var(--blue-600) !important;
}}
input[type="radio"] {{ accent-color: var(--blue-600) !important; }}
"""

with open('/tmp/guac-theme-build/theme.css', 'w') as f:
    f.write(css)
print(f"CSS écrit : {len(css)} caractères — nav='{nav}' home='{home}'")
PYEOF
log "CSS Corporate Blue généré"

# ════════════════════════════════════════
section "4. Manifeste"
# ════════════════════════════════════════
cat > "$THEME_BUILD_DIR/guac-manifest.json" <<MANIFEST
{
  "guacamoleVersion" : "*",
  "name"             : "Corporate Blue Theme",
  "namespace"        : "corporate-blue",
  "css"              : [ "theme.css" ],
  "resources"        : {
    "images/logo.svg" : "image/svg+xml"
  }
}
MANIFEST
log "Manifeste créé"

# ════════════════════════════════════════
section "5. Création du .jar"
# ════════════════════════════════════════
cd "$THEME_BUILD_DIR"
zip -r "/tmp/${THEME_JAR}" . -x "*.DS_Store" > /dev/null
log "Extension : /tmp/${THEME_JAR} ($(du -sh /tmp/${THEME_JAR} | cut -f1))"

# ════════════════════════════════════════
section "6. Nettoyage et installation"
# ════════════════════════════════════════
mkdir -p "$EXTENSIONS_DIR"

# Lister ce qui est dans le dossier extensions avant nettoyage
_OLD_JARS=$(find "$EXTENSIONS_DIR" -name "*.jar" 2>/dev/null | grep -v "guacamole-auth" || true)
if [[ -n "$_OLD_JARS" ]]; then
    warn "Anciens .jar non-auth trouvés — suppression :"
    echo "$_OLD_JARS" | while read -r j; do
        echo -e "    ${RED}✗${NC} $(basename "$j")"
        rm -f "$j"
    done
else
    log "Aucun ancien thème à supprimer"
fi

# Installer le nouveau thème
cp "/tmp/${THEME_JAR}" "$EXTENSIONS_DIR/${THEME_JAR}"
chmod 644 "$EXTENSIONS_DIR/${THEME_JAR}"
log "Installé dans $EXTENSIONS_DIR/"

# Ajouter le volume dans docker-compose si absent
if [[ -f "$GUACAMOLE_DIR/docker-compose.yml" ]]; then
  if ! grep -q "guacamole-extensions" "$GUACAMOLE_DIR/docker-compose.yml" 2>/dev/null; then
    warn "Ajout du volume extensions dans docker-compose.yml..."
    python3 << 'PYEOF'
content = open('/opt/guacamole/docker-compose.yml').read()
old = '    environment:\n      GUACD_HOSTNAME: guacd'
new = '    volumes:\n      - /opt/guacamole-extensions:/etc/guacamole/extensions:ro\n    environment:\n      GUACD_HOSTNAME: guacd'
if old in content:
    open('/opt/guacamole/docker-compose.yml', 'w').write(content.replace(old, new))
    print("OK")
PYEOF
  fi
else
  err "Fichier docker-compose.yml introuvable dans $GUACAMOLE_DIR"
fi

# ════════════════════════════════════════
section "7. Redémarrage Guacamole"
# ════════════════════════════════════════
cd "$GUACAMOLE_DIR"

# Vérifier si Guacamole est en cours d'exécution avant de tenter le redémarrage
if check_guacamole_running; then
    log "Arrêt du service Guacamole..."
    docker compose --env-file .env down
else
    warn "Guacamole n'était pas en cours d'exécution"
fi

log "Démarrage du service Guacamole avec le nouveau thème..."
docker compose --env-file .env up -d --force-recreate guacamole
log "Guacamole redémarré, attente 25s pour que le service soit pleinement opérationnel..."
sleep 25

# Vérifier que le service est bien démarré
if check_guacamole_running; then
    log "Guacamole est opérationnel"
else
    warn "Guacamole semble avoir des difficultés à démarrer"
fi

# ════════════════════════════════════════
section "Résumé"
# ════════════════════════════════════════
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Thème Corporate Blue installé${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Style       : Fond clair · Cartes blanches · Bleu corporate"
echo -e "  Police      : DM Sans (professionnelle)"
echo -e "  Extension   : $EXTENSIONS_DIR/${THEME_JAR}"
echo -e "  Nav CSS     : ${NAV_SELECTOR}"
echo ""
echo -e "${YELLOW}  Pour confirmer que le thème est actif :${NC}"
echo -e "  → Ouvrir Guacamole dans le navigateur"
echo -e "  → Un badge bleu '${GREEN}Corporate Blue ✓${NC}' doit apparaître en bas à droite"
echo -e "  → Si le badge est absent = l'extension n'est pas chargée"
echo ""
echo -e "${BLUE}  Diagnostics si le badge est absent :${NC}"
echo -e "  sudo docker logs guacamole 2>&1 | grep -i 'extension\\|error\\|warn'"
echo -e "  sudo docker inspect guacamole | grep guacamole-extensions"
echo -e "  unzip -p $EXTENSIONS_DIR/${THEME_JAR} theme.css | head -5"
echo ""
echo -e "${YELLOW}  Personnalisation :${NC}"
echo -e "  COMPANY_NAME='Mon Entreprise' PRIMARY_COLOR='#0ea5e9' sudo bash $0"
echo ""
echo -e "${BLUE}  Désinstaller :${NC}"
echo -e "  sudo rm $EXTENSIONS_DIR/${THEME_JAR}"
echo -e "  cd $COMPOSE_DIR && sudo docker compose --env-file .env up -d --force-recreate guacamole"
echo ""
