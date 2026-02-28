#!/bin/bash
set -euo pipefail

# ============================================================
#  THEME GUACAMOLE — Corporate Blue Edition
#  Usage : sudo bash 3_theme_guacamole.sh
#  Style : Bleu corporate professionnel, cartes redessinées,
#          animations fluides, typographie soignée (DM Sans)
# ============================================================

# ---- CONFIG (personnalisable via variables d'env) ----------
COMPANY_NAME="${COMPANY_NAME:-Selest Informatique}"
COMPANY_SUBTITLE="${COMPANY_SUBTITLE:-Accès distant sécurisé}"
PRIMARY_COLOR="${PRIMARY_COLOR:-#1d4ed8}"
ACCENT_COLOR="${ACCENT_COLOR:-#3b82f6}"
THEME_BUILD_DIR="/tmp/guac-theme-build"
THEME_JAR="corporate-theme.jar"
EXTENSIONS_DIR="/opt/guacamole-extensions"
# ------------------------------------------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}══ $1 ══${NC}"; }

[[ $EUID -ne 0 ]] && err "Lance ce script en root : sudo bash $0"
command -v zip    &>/dev/null || apt-get install -y -qq zip
command -v docker &>/dev/null || err "Docker manquant"

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
echo -e "${BLUE}  ── Couleurs du logo (format hex ex: #1d4ed8) ───────────${NC}"
ask "Couleur principale"            "$PRIMARY_COLOR"    PRIMARY_COLOR
ask "Couleur accent"                "$ACCENT_COLOR"     ACCENT_COLOR

echo ""
echo -e "${BLUE}  ── Récapitulatif ──────────────────────────────────────${NC}"
echo -e "  Nom              : ${GREEN}${COMPANY_NAME}${NC}"
echo -e "  Sous-titre       : ${GREEN}${COMPANY_SUBTITLE}${NC}"
echo -e "  Couleur principale : ${GREEN}${PRIMARY_COLOR}${NC}"
echo -e "  Couleur accent   : ${GREEN}${ACCENT_COLOR}${NC}"
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
log "Répertoires créés"

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
# Écrire le CSS via Python pour éviter les problèmes d'interpolation shell
python3 << 'PYEOF'
css = """/* ============================================================
   CORPORATE BLUE THEME — Apache Guacamole
   Règle de base : NE PAS toucher au layout natif de Guacamole.
   On stylise uniquement les couleurs, bordures, ombres,
   typographie et animations — jamais display/grid/padding
   sur les conteneurs parents.
   ============================================================ */
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:opsz,wght@9..40,300;9..40,400;9..40,500;9..40,600;9..40,700&display=swap');

/* ── Variables ──────────────────────────────────────────── */
:root {
  --blue-950:   #172554;
  --blue-900:   #1e3a8a;
  --blue-800:   #1e40af;
  --blue-700:   #1d4ed8;
  --blue-600:   #2563eb;
  --blue-500:   #3b82f6;
  --blue-400:   #60a5fa;
  --blue-300:   #93c5fd;
  --blue-100:   #dbeafe;
  --blue-50:    #eff6ff;

  --bg-page:    #f0f4f8;
  --bg-card:    #ffffff;
  --bg-input:   #f8fafc;
  --bg-hover:   #f0f7ff;
  --bg-active:  #dbeafe;
  --border:      #e2e8f0;
  --border-card: #e8edf5;
  --text-primary:   #0f172a;
  --text-secondary: #475569;
  --text-muted:     #94a3b8;

  --shadow-sm:  0 1px 3px rgba(15,23,42,0.06), 0 1px 2px rgba(15,23,42,0.04);
  --shadow-md:  0 4px 16px rgba(15,23,42,0.08), 0 2px 6px rgba(15,23,42,0.05);
  --shadow-lg:  0 12px 40px rgba(15,23,42,0.12), 0 4px 12px rgba(15,23,42,0.06);
  --shadow-blue: 0 8px 32px rgba(37,99,235,0.18), 0 2px 8px rgba(37,99,235,0.1);

  --radius-sm: 6px;
  --radius-md: 10px;
  --radius-lg: 16px;
  --radius-xl: 20px;
  --transition: all 0.22s cubic-bezier(0.4, 0, 0.2, 1);
  --transition-spring: all 0.35s cubic-bezier(0.34, 1.56, 0.64, 1);
}

/* ── Base ───────────────────────────────────────────────── */
*, *::before, *::after { box-sizing: border-box; margin: 0; }

html, body {
  font-family: 'DM Sans', 'Segoe UI', system-ui, sans-serif !important;
  background: var(--bg-page) !important;
  color: var(--text-primary) !important;
  font-size: 15px !important;
  line-height: 1.6 !important;
  -webkit-font-smoothing: antialiased !important;
}

/* ═══════════════════════════════════════════
   PAGE DE LOGIN
   ═══════════════════════════════════════════ */
.login-ui {
  min-height: 100vh !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  background: linear-gradient(145deg, #eff6ff 0%, #f0f4f8 50%, #e8f0fe 100%) !important;
  position: relative !important;
  overflow: hidden !important;
}

/* Fond géométrique décoratif */
.login-ui::before {
  content: '' !important;
  position: fixed !important;
  inset: 0 !important;
  background-image:
    radial-gradient(circle at 20% 20%, rgba(37,99,235,0.08) 0%, transparent 50%),
    radial-gradient(circle at 80% 80%, rgba(29,78,216,0.06) 0%, transparent 50%) !important;
  pointer-events: none !important;
}

.login-ui::after {
  content: '' !important;
  position: fixed !important;
  inset: 0 !important;
  background-image:
    linear-gradient(rgba(37,99,235,0.025) 1px, transparent 1px),
    linear-gradient(90deg, rgba(37,99,235,0.025) 1px, transparent 1px) !important;
  background-size: 48px 48px !important;
  pointer-events: none !important;
}

/* Carte de login */
.login-ui .login-dialog {
  background: var(--bg-card) !important;
  border: 1px solid var(--border-card) !important;
  border-radius: var(--radius-xl) !important;
  box-shadow: var(--shadow-lg) !important;
  padding: 48px 44px !important;
  width: 100% !important;
  max-width: 420px !important;
  position: relative !important;
  z-index: 1 !important;
  animation: loginAppear 0.5s cubic-bezier(0.34, 1.2, 0.64, 1) !important;
}

/* Bande bleue décorative */
.login-ui .login-dialog::before {
  content: '' !important;
  position: absolute !important;
  top: 0 !important; left: 0 !important; right: 0 !important;
  height: 4px !important;
  background: linear-gradient(90deg, #1d4ed8, #60a5fa) !important;
  border-radius: var(--radius-xl) var(--radius-xl) 0 0 !important;
}

@keyframes loginAppear {
  from { opacity: 0; transform: translateY(28px) scale(0.97); }
  to   { opacity: 1; transform: translateY(0) scale(1); }
}

/* Logo */
.login-ui .login-dialog .logo {
  width: 260px !important;
  height: 64px !important;
  background-size: contain !important;
  background-repeat: no-repeat !important;
  background-position: left center !important;
  margin: 0 auto 36px !important;
  display: block !important;
}

/* Champs de saisie */
.login-ui .login-fields .labeled-field {
  margin-bottom: 18px !important;
  position: relative !important;
}

.login-ui .login-fields .labeled-field input,
.login-ui .login-fields .labeled-field input[type="text"],
.login-ui .login-fields .labeled-field input[type="password"] {
  background: var(--bg-input) !important;
  border: 1.5px solid var(--border) !important;
  border-radius: var(--radius-md) !important;
  color: var(--text-primary) !important;
  font-family: inherit !important;
  font-size: 15px !important;
  padding: 13px 16px !important;
  width: 100% !important;
  transition: var(--transition) !important;
  outline: none !important;
}

.login-ui .login-fields .labeled-field input:focus {
  border-color: var(--blue-500) !important;
  background: #fff !important;
  box-shadow: 0 0 0 4px rgba(59,130,246,0.12) !important;
}

.login-ui .login-fields .labeled-field.empty input {
  color: var(--text-muted) !important;
}

.login-ui .login-fields .labeled-field .placeholder {
  color: var(--text-muted) !important;
  font-size: 14px !important;
  padding: 13px 16px !important;
  pointer-events: none !important;
}

/* Bouton connexion */
.login-ui input[type="submit"],
.login-ui button[type="submit"],
.login-ui button.login {
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
  transition: var(--transition) !important;
}

.login-ui input[type="submit"]:hover,
.login-ui button[type="submit"]:hover {
  background: linear-gradient(135deg, var(--blue-800) 0%, var(--blue-700) 100%) !important;
  box-shadow: 0 6px 20px rgba(29,78,216,0.4) !important;
  transform: translateY(-1px) !important;
}

.login-ui input[type="submit"]:active {
  transform: translateY(0) !important;
}

/* Erreur */
.login-ui .error {
  background: #fef2f2 !important;
  border: 1px solid #fecaca !important;
  border-left: 3px solid #ef4444 !important;
  border-radius: var(--radius-sm) !important;
  color: #dc2626 !important;
  font-size: 13.5px !important;
  padding: 10px 14px !important;
  margin-top: 8px !important;
}

/* ═══════════════════════════════════════════
   NAVIGATION PRINCIPALE
   ═══════════════════════════════════════════ */
header, .app-controls {
  background: #fff !important;
  border-bottom: 1px solid var(--border) !important;
  box-shadow: var(--shadow-sm) !important;
}

.app-controls a, header a {
  color: var(--text-secondary) !important;
  font-weight: 500 !important;
  font-size: 14px !important;
  transition: var(--transition) !important;
}

.app-controls a:hover, header a:hover {
  color: var(--blue-700) !important;
}

/* ═══════════════════════════════════════════
   FOND DE LA LISTE DE CONNEXIONS
   On ne touche PAS au display/padding/grid natif
   ═══════════════════════════════════════════ */
.connection-list-parent, .main-content {
  background: var(--bg-page) !important;
}

/* ── CARTES DE CONNEXION ──────────────────── */
.connection {
  background: var(--bg-card) !important;
  border: 1px solid var(--border-card) !important;
  border-radius: var(--radius-lg) !important;
  box-shadow: var(--shadow-sm) !important;
  overflow: hidden !important;
  position: relative !important;
  transition: var(--transition-spring) !important;
}

/* Bande bleue en haut de chaque carte (absolute = pas d'impact layout) */
.connection::before {
  content: '' !important;
  position: absolute !important;
  top: 0 !important;
  left: 0 !important;
  right: 0 !important;
  height: 3px !important;
  background: linear-gradient(90deg, #1d4ed8, #60a5fa) !important;
  z-index: 1 !important;
}

/* Hover : élévation + ombre bleue */
.connection:hover {
  border-color: var(--blue-300) !important;
  box-shadow: var(--shadow-blue) !important;
  transform: translateY(-4px) !important;
}

/* Nom connexion */
.connection .name {
  color: var(--text-primary) !important;
  font-size: 14px !important;
  font-weight: 600 !important;
}

/* Protocole */
.connection .protocol {
  color: var(--text-muted) !important;
  font-size: 11px !important;
  font-weight: 600 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.6px !important;
}

/* ── GROUPES ──────────────────────────────── */
.connection-group-label {
  color: var(--text-secondary) !important;
  font-size: 12px !important;
  font-weight: 700 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.8px !important;
  border-bottom: 2px solid var(--border) !important;
  padding-bottom: 8px !important;
  margin-bottom: 12px !important;
}

/* ═══════════════════════════════════════════
   MENUS ET DROPDOWNS
   ═══════════════════════════════════════════ */
.menu, .context-menu, .dropdown-menu {
  background: var(--bg-card) !important;
  border: 1px solid var(--border) !important;
  border-radius: var(--radius-md) !important;
  box-shadow: var(--shadow-md) !important;
}

@keyframes menuAppear {
  from { opacity: 0; transform: translateY(-6px) scale(0.98); }
  to   { opacity: 1; transform: translateY(0) scale(1); }
}

.menu a, .menu button,
.dropdown-menu a, .dropdown-menu button,
.context-menu a, .context-menu li {
  color: var(--text-secondary) !important;
  font-size: 14px !important;
  font-weight: 500 !important;
  border-radius: var(--radius-sm) !important;
  text-decoration: none !important;
  transition: var(--transition) !important;
}

.menu a:hover, .menu button:hover,
.dropdown-menu a:hover, .dropdown-menu button:hover,
.context-menu li:hover {
  background: var(--bg-hover) !important;
  color: var(--blue-700) !important;
}

.menu hr, .dropdown-menu hr {
  border: none !important;
  border-top: 1px solid var(--border) !important;
}

/* ═══════════════════════════════════════════
   BOUTONS GÉNÉRAUX
   ═══════════════════════════════════════════ */
button, input[type="submit"] {
  font-family: inherit !important;
  font-size: 14px !important;
  font-weight: 600 !important;
  border-radius: var(--radius-md) !important;
  cursor: pointer !important;
  transition: var(--transition) !important;
  background: var(--blue-600) !important;
  color: #fff !important;
  border: none !important;
}

button:hover, input[type="submit"]:hover {
  background: var(--blue-700) !important;
}

button.cancel, a.cancel {
  background: var(--bg-input) !important;
  color: var(--text-secondary) !important;
  border: 1px solid var(--border) !important;
}

button.danger, button.delete {
  background: #ef4444 !important;
}
button.danger:hover, button.delete:hover {
  background: #dc2626 !important;
}

/* ═══════════════════════════════════════════
   FORMULAIRES
   ═══════════════════════════════════════════ */
.form-field input[type="text"],
.form-field input[type="password"],
.form-field input[type="email"],
.form-field input[type="number"],
.form-field select,
.form-field textarea {
  background: var(--bg-input) !important;
  border: 1.5px solid var(--border) !important;
  border-radius: var(--radius-md) !important;
  color: var(--text-primary) !important;
  font-family: inherit !important;
  font-size: 14px !important;
  transition: var(--transition) !important;
  outline: none !important;
}

.form-field input:focus,
.form-field select:focus,
.form-field textarea:focus {
  border-color: var(--blue-500) !important;
  background: #fff !important;
  box-shadow: 0 0 0 3px rgba(59,130,246,0.12) !important;
}

/* ═══════════════════════════════════════════
   TABLEAUX
   ═══════════════════════════════════════════ */
table {
  width: 100% !important;
  border-collapse: collapse !important;
  background: var(--bg-card) !important;
  border-radius: var(--radius-lg) !important;
  overflow: hidden !important;
  box-shadow: var(--shadow-sm) !important;
  border: 1px solid var(--border-card) !important;
}

table thead tr { background: var(--bg-page) !important; }

table th {
  color: var(--text-muted) !important;
  font-size: 11.5px !important;
  font-weight: 700 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.7px !important;
  padding: 12px 16px !important;
  text-align: left !important;
  border-bottom: 1px solid var(--border) !important;
}

table td {
  color: var(--text-primary) !important;
  font-size: 14px !important;
  padding: 13px 16px !important;
  border-bottom: 1px solid rgba(226,232,240,0.6) !important;
}

table tr:last-child td { border-bottom: none !important; }
table tbody tr { transition: var(--transition) !important; }
table tbody tr:hover { background: var(--bg-hover) !important; }

/* ═══════════════════════════════════════════
   NOTIFICATIONS ET MODALES
   ═══════════════════════════════════════════ */
.notification, .alert {
  background: var(--bg-card) !important;
  border: 1px solid var(--border) !important;
  border-radius: var(--radius-lg) !important;
  box-shadow: var(--shadow-md) !important;
  padding: 18px 22px !important;
  animation: slideInRight 0.3s cubic-bezier(0.34, 1.2, 0.64, 1) !important;
}

@keyframes slideInRight {
  from { opacity: 0; transform: translateX(20px); }
  to   { opacity: 1; transform: translateX(0); }
}

.notification.error   { border-left: 4px solid #ef4444 !important; background: #fef2f2 !important; }
.notification.success { border-left: 4px solid #10b981 !important; background: #f0fdf4 !important; }
.notification.info    { border-left: 4px solid var(--blue-500) !important; background: var(--blue-50) !important; }

.dialog, .modal {
  background: var(--bg-card) !important;
  border-radius: var(--radius-xl) !important;
  box-shadow: var(--shadow-lg) !important;
  border: 1px solid var(--border) !important;
  animation: modalAppear 0.3s cubic-bezier(0.34, 1.1, 0.64, 1) !important;
}

@keyframes modalAppear {
  from { opacity: 0; transform: scale(0.95) translateY(10px); }
  to   { opacity: 1; transform: scale(1) translateY(0); }
}

.overlay, .modal-backdrop {
  background: rgba(15, 23, 42, 0.35) !important;
  backdrop-filter: blur(4px) !important;
}

/* ═══════════════════════════════════════════
   BARRE LATÉRALE ADMIN
   ═══════════════════════════════════════════ */
.settings-menu {
  background: var(--bg-card) !important;
  border-right: 1px solid var(--border) !important;
}

.settings-menu a {
  color: var(--text-secondary) !important;
  font-size: 14px !important;
  font-weight: 500 !important;
  border-radius: var(--radius-sm) !important;
  text-decoration: none !important;
  transition: var(--transition) !important;
}

.settings-menu a:hover {
  background: var(--bg-hover) !important;
  color: var(--blue-700) !important;
}

.settings-menu a.active {
  background: var(--bg-active) !important;
  color: var(--blue-700) !important;
  font-weight: 600 !important;
}

/* ═══════════════════════════════════════════
   TOOLBAR SESSION ACTIVE
   ═══════════════════════════════════════════ */
.client-controls, .client-toolbar {
  background: rgba(255,255,255,0.96) !important;
  backdrop-filter: blur(8px) !important;
  border-bottom: 1px solid var(--border) !important;
  box-shadow: var(--shadow-sm) !important;
}

/* ═══════════════════════════════════════════
   SCROLLBARS ET SÉLECTION
   ═══════════════════════════════════════════ */
::-webkit-scrollbar { width: 7px; height: 7px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #cbd5e1; border-radius: 4px; }
::-webkit-scrollbar-thumb:hover { background: #94a3b8; }

::selection { background: rgba(59,130,246,0.2); color: var(--text-primary); }

input[type="checkbox"] {
  width: 16px !important;
  height: 16px !important;
  accent-color: var(--blue-600) !important;
}

input[type="radio"] { accent-color: var(--blue-600) !important; }
"""
with open('/tmp/guac-theme-build/theme.css', 'w') as f:
    f.write(css)
print(f"CSS écrit : {len(css)} caractères")
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
section "6. Installation"
# ════════════════════════════════════════
mkdir -p "$EXTENSIONS_DIR"

# Supprimer anciens thèmes
rm -f "$EXTENSIONS_DIR"/*theme*.jar "$EXTENSIONS_DIR"/corporate*.jar
cp "/tmp/${THEME_JAR}" "$EXTENSIONS_DIR/${THEME_JAR}"
chmod 644 "$EXTENSIONS_DIR/${THEME_JAR}"
log "Installé dans $EXTENSIONS_DIR/"

# Ajouter le volume dans docker-compose si absent
if ! grep -q "guacamole-extensions" /opt/guacamole/docker-compose.yml 2>/dev/null; then
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

# ════════════════════════════════════════
section "7. Redémarrage Guacamole"
# ════════════════════════════════════════
cd /opt/guacamole
docker compose --env-file .env up -d --force-recreate guacamole
log "Guacamole redémarré, attente 20s..."
sleep 20

# ════════════════════════════════════════
section "Résumé"
# ════════════════════════════════════════
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  Thème Corporate Blue installé !${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  🎨  Style      : Fond clair · Cartes blanches · Bleu corporate"
echo -e "  🔤  Police     : DM Sans (professionnelle, lisible)"
echo -e "  ✨  Animations : Hover cartes (+élévation), menus, modales"
echo -e "  📦  Extension  : $EXTENSIONS_DIR/${THEME_JAR}"
echo ""
echo -e "${YELLOW}  Personnalisation :${NC}"
echo -e "  COMPANY_NAME='Mon Entreprise' PRIMARY_COLOR='#0ea5e9' sudo bash $0"
echo ""
echo -e "${BLUE}  Désinstaller :${NC}"
echo -e "  sudo rm $EXTENSIONS_DIR/${THEME_JAR}"
echo -e "  cd /opt/guacamole && sudo docker compose --env-file .env up -d --force-recreate guacamole"
echo ""