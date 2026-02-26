#!/bin/bash
set -euo pipefail

# ============================================================
#  THEME GUACAMOLE — Extension branding Selest Informatique
#  Usage : sudo bash 3_theme_guacamole.sh
#  Installe un thème sombre moderne avec logo personnalisé
# ============================================================

# ---- CONFIG ------------------------------------------------
COMPANY_NAME="Selest Informatique"
COMPANY_SUBTITLE="Accès distant sécurisé"
PRIMARY_COLOR="#2563eb"       # Bleu principal
ACCENT_COLOR="#3b82f6"        # Bleu accent
DARK_BG="#0f172a"             # Fond sombre
CARD_BG="#1e293b"             # Fond carte
TEXT_COLOR="#f1f5f9"          # Texte clair
GUAC_EXTENSIONS_DIR="/opt/guacamole-home/extensions"
THEME_BUILD_DIR="/tmp/guac-theme-build"
THEME_JAR="selest-theme.jar"
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
section "1. Préparation des répertoires"
# ════════════════════════════════════════
rm -rf "$THEME_BUILD_DIR"
mkdir -p "$THEME_BUILD_DIR/images"
mkdir -p "$GUAC_EXTENSIONS_DIR"
log "Répertoires créés"

# ════════════════════════════════════════
section "2. Génération du logo SVG"
# ════════════════════════════════════════
cat > "$THEME_BUILD_DIR/images/logo.svg" <<LOGOSVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 80" width="320" height="80">
  <defs>
    <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" style="stop-color:${PRIMARY_COLOR};stop-opacity:1" />
      <stop offset="100%" style="stop-color:${ACCENT_COLOR};stop-opacity:1" />
    </linearGradient>
  </defs>
  <!-- Icône réseau/écran -->
  <rect x="8" y="12" width="44" height="32" rx="4" fill="url(#grad)"/>
  <rect x="24" y="44" width="12" height="8" fill="url(#grad)"/>
  <rect x="18" y="52" width="24" height="4" rx="2" fill="url(#grad)"/>
  <!-- Petits écrans/serveurs -->
  <rect x="14" y="18" width="32" height="20" rx="2" fill="${DARK_BG}" opacity="0.6"/>
  <rect x="17" y="21" width="10" height="6" rx="1" fill="${ACCENT_COLOR}" opacity="0.8"/>
  <rect x="29" y="21" width="10" height="6" rx="1" fill="${PRIMARY_COLOR}" opacity="0.8"/>
  <rect x="17" y="29" width="22" height="3" rx="1" fill="${TEXT_COLOR}" opacity="0.3"/>
  <!-- Texte -->
  <text x="64" y="34" font-family="'Segoe UI', Arial, sans-serif" font-size="22" font-weight="700" fill="${TEXT_COLOR}">${COMPANY_NAME}</text>
  <text x="65" y="54" font-family="'Segoe UI', Arial, sans-serif" font-size="13" fill="${ACCENT_COLOR}" opacity="0.9">${COMPANY_SUBTITLE}</text>
</svg>
LOGOSVG

# Convertir SVG en PNG via Python (sans dépendances externes)
python3 << PYEOF
# On encode le SVG en base64 pour l'utiliser directement
import base64, os

with open("${THEME_BUILD_DIR}/images/logo.svg", "rb") as f:
    svg_data = f.read()

# Créer un PNG minimal via header PNG (fallback)
# On garde le SVG et on crée aussi une version PNG via rsvg si disponible
import subprocess
try:
    result = subprocess.run(
        ["rsvg-convert", "-w", "320", "-h", "80",
         "${THEME_BUILD_DIR}/images/logo.svg",
         "-o", "${THEME_BUILD_DIR}/images/logo.png"],
        capture_output=True
    )
    if result.returncode == 0:
        print("PNG généré via rsvg-convert")
    else:
        raise Exception("rsvg failed")
except:
    try:
        result = subprocess.run(
            ["convert", "${THEME_BUILD_DIR}/images/logo.svg",
             "${THEME_BUILD_DIR}/images/logo.png"],
            capture_output=True
        )
        if result.returncode == 0:
            print("PNG généré via ImageMagick")
        else:
            raise Exception("convert failed")
    except:
        # Copier le SVG comme fallback — Guacamole accepte les SVG comme ressource
        import shutil
        shutil.copy("${THEME_BUILD_DIR}/images/logo.svg",
                    "${THEME_BUILD_DIR}/images/logo.png")
        print("Fallback: SVG utilisé comme logo")
PYEOF

log "Logo généré"

# ════════════════════════════════════════
section "3. Fichier CSS du thème"
# ════════════════════════════════════════
cat > "$THEME_BUILD_DIR/theme.css" <<'THEMECSS'
/* ============================================================
   SELEST INFORMATIQUE — Thème Guacamole sombre moderne
   ============================================================ */

/* Import Google Fonts */
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');

/* ── Variables globales ── */
:root {
  --primary:    #2563eb;
  --accent:     #3b82f6;
  --primary-hover: #1d4ed8;
  --dark-bg:    #0f172a;
  --card-bg:    #1e293b;
  --card-border:#334155;
  --text:       #f1f5f9;
  --text-muted: #94a3b8;
  --input-bg:   #0f172a;
  --success:    #10b981;
  --danger:     #ef4444;
  --radius:     12px;
  --shadow:     0 25px 60px rgba(0,0,0,0.5);
  --transition: all 0.25s cubic-bezier(0.4,0,0.2,1);
}

/* ── Reset & base ── */
*, *::before, *::after { box-sizing: border-box; }

body, html {
  font-family: 'Inter', 'Segoe UI', system-ui, sans-serif !important;
  background-color: var(--dark-bg) !important;
  color: var(--text) !important;
  margin: 0;
  min-height: 100vh;
}

/* ── Page de login ── */
.login-ui {
  background: var(--dark-bg) !important;
  background-image:
    radial-gradient(ellipse 80% 60% at 50% -20%, rgba(37,99,235,0.25) 0%, transparent 70%),
    radial-gradient(ellipse 60% 40% at 90% 90%, rgba(59,130,246,0.12) 0%, transparent 60%) !important;
  min-height: 100vh !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
}

.login-ui .login-dialog {
  background: var(--card-bg) !important;
  border: 1px solid var(--card-border) !important;
  border-radius: var(--radius) !important;
  box-shadow: var(--shadow) !important;
  padding: 40px !important;
  width: 100% !important;
  max-width: 420px !important;
  backdrop-filter: blur(20px) !important;
  animation: slideUp 0.4s cubic-bezier(0.4,0,0.2,1) !important;
}

@keyframes slideUp {
  from { opacity: 0; transform: translateY(24px); }
  to   { opacity: 1; transform: translateY(0); }
}

/* ── Logo ── */
.login-ui .login-dialog .logo {
  width: 240px !important;
  height: 60px !important;
  background-size: contain !important;
  background-repeat: no-repeat !important;
  background-position: center !important;
  margin: 0 auto 32px !important;
  display: block !important;
}

/* ── Titres ── */
.login-ui h1, .login-ui h2 {
  color: var(--text) !important;
  font-weight: 600 !important;
  text-align: center !important;
  margin-bottom: 24px !important;
}

/* ── Champs de saisie ── */
.login-ui .login-fields .labeled-field {
  margin-bottom: 16px !important;
  position: relative !important;
}

.login-ui .login-fields .labeled-field input,
.login-ui .login-fields .labeled-field input[type="text"],
.login-ui .login-fields .labeled-field input[type="password"] {
  background: var(--input-bg) !important;
  border: 1.5px solid var(--card-border) !important;
  border-radius: 8px !important;
  color: var(--text) !important;
  font-family: inherit !important;
  font-size: 15px !important;
  padding: 12px 16px !important;
  width: 100% !important;
  transition: var(--transition) !important;
  outline: none !important;
}

.login-ui .login-fields .labeled-field input:focus {
  border-color: var(--accent) !important;
  box-shadow: 0 0 0 3px rgba(59,130,246,0.15) !important;
}

.login-ui .login-fields .labeled-field.empty input {
  background: var(--input-bg) !important;
  color: var(--text-muted) !important;
}

/* Placeholder label */
.login-ui .login-fields .labeled-field .placeholder {
  color: var(--text-muted) !important;
  font-size: 14px !important;
  pointer-events: none !important;
  padding: 12px 16px !important;
}

/* ── Bouton de connexion ── */
.login-ui input[type="submit"],
.login-ui button[type="submit"],
.login-ui button.login {
  background: linear-gradient(135deg, var(--primary), var(--accent)) !important;
  border: none !important;
  border-radius: 8px !important;
  color: #ffffff !important;
  cursor: pointer !important;
  font-family: inherit !important;
  font-size: 15px !important;
  font-weight: 600 !important;
  letter-spacing: 0.3px !important;
  padding: 13px 24px !important;
  width: 100% !important;
  margin-top: 8px !important;
  transition: var(--transition) !important;
  position: relative !important;
  overflow: hidden !important;
}

.login-ui input[type="submit"]:hover,
.login-ui button[type="submit"]:hover,
.login-ui button.login:hover {
  background: linear-gradient(135deg, var(--primary-hover), var(--primary)) !important;
  box-shadow: 0 8px 24px rgba(37,99,235,0.4) !important;
  transform: translateY(-1px) !important;
}

.login-ui input[type="submit"]:active,
.login-ui button[type="submit"]:active {
  transform: translateY(0) !important;
}

/* ── Messages d'erreur ── */
.login-ui .login-fields .error {
  color: var(--danger) !important;
  font-size: 13px !important;
  margin-top: 8px !important;
  padding: 8px 12px !important;
  background: rgba(239,68,68,0.1) !important;
  border-radius: 6px !important;
  border-left: 3px solid var(--danger) !important;
}

/* ── Interface principale (après login) ── */

/* Barre de navigation */
.app-controls, header.header {
  background: var(--card-bg) !important;
  border-bottom: 1px solid var(--card-border) !important;
  box-shadow: 0 2px 16px rgba(0,0,0,0.3) !important;
}

/* Fond principal */
.main-content, .connection-list-parent, .user-menu {
  background: var(--dark-bg) !important;
}

/* Cartes de connexion */
.connection-list .connection,
.connection-group,
.connection-group-contents .connection {
  background: var(--card-bg) !important;
  border: 1px solid var(--card-border) !important;
  border-radius: 10px !important;
  color: var(--text) !important;
  transition: var(--transition) !important;
  margin: 6px !important;
}

.connection-list .connection:hover,
.connection-group:hover {
  border-color: var(--accent) !important;
  box-shadow: 0 4px 20px rgba(59,130,246,0.2) !important;
  transform: translateY(-2px) !important;
}

/* Icônes de connexion */
.connection .caption .protocol-icon {
  color: var(--accent) !important;
}

/* Nom des connexions */
.connection .caption .name {
  color: var(--text) !important;
  font-weight: 500 !important;
}

/* Menus et dropdowns */
.menu, .dropdown-menu, .context-menu {
  background: var(--card-bg) !important;
  border: 1px solid var(--card-border) !important;
  border-radius: 8px !important;
  box-shadow: 0 8px 32px rgba(0,0,0,0.4) !important;
}

.menu a, .menu button,
.dropdown-menu a, .dropdown-menu button {
  color: var(--text) !important;
  transition: var(--transition) !important;
}

.menu a:hover, .menu button:hover {
  background: rgba(59,130,246,0.15) !important;
  color: var(--accent) !important;
}

/* Boutons généraux */
input[type="submit"], button, a.button {
  background: var(--primary) !important;
  border: none !important;
  border-radius: 6px !important;
  color: #ffffff !important;
  cursor: pointer !important;
  font-family: inherit !important;
  transition: var(--transition) !important;
}

input[type="submit"]:hover, button:hover, a.button:hover {
  background: var(--primary-hover) !important;
}

/* Boutons secondaires / cancel */
button.cancel, a.cancel, .button.cancel {
  background: var(--card-border) !important;
  color: var(--text-muted) !important;
}

button.cancel:hover {
  background: #475569 !important;
  color: var(--text) !important;
}

/* Tableaux */
table {
  color: var(--text) !important;
}

table th {
  background: var(--card-bg) !important;
  color: var(--text-muted) !important;
  font-weight: 500 !important;
  font-size: 12px !important;
  text-transform: uppercase !important;
  letter-spacing: 0.5px !important;
  border-bottom: 1px solid var(--card-border) !important;
}

table tr:hover {
  background: rgba(59,130,246,0.05) !important;
}

table td {
  border-bottom: 1px solid rgba(51,65,85,0.5) !important;
  color: var(--text) !important;
}

/* Formulaires admin */
.form-field input[type="text"],
.form-field input[type="password"],
.form-field input[type="email"],
.form-field input[type="number"],
.form-field select,
.form-field textarea {
  background: var(--input-bg) !important;
  border: 1.5px solid var(--card-border) !important;
  border-radius: 6px !important;
  color: var(--text) !important;
  font-family: inherit !important;
  padding: 8px 12px !important;
  transition: var(--transition) !important;
}

.form-field input:focus,
.form-field select:focus,
.form-field textarea:focus {
  border-color: var(--accent) !important;
  outline: none !important;
  box-shadow: 0 0 0 3px rgba(59,130,246,0.15) !important;
}

/* Scrollbars */
::-webkit-scrollbar { width: 6px; height: 6px; }
::-webkit-scrollbar-track { background: var(--dark-bg); }
::-webkit-scrollbar-thumb { background: var(--card-border); border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: var(--accent); }

/* Sélection */
::selection {
  background: rgba(59,130,246,0.3);
  color: var(--text);
}

/* ── Indicateur de chargement ── */
.loading-text {
  color: var(--text-muted) !important;
}

/* ── Guacamole client toolbar ── */
.client .notification {
  background: var(--card-bg) !important;
  border: 1px solid var(--card-border) !important;
  color: var(--text) !important;
  border-radius: 8px !important;
}

THEMECSS

log "CSS du thème créé"

# ════════════════════════════════════════
section "4. Page de login personnalisée"
# ════════════════════════════════════════
cat > "$THEME_BUILD_DIR/loginPage.html" <<'LOGINHTML'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<!-- Injecter un footer sur la page de login -->
<meta name="guac:replace" content=".login-ui .login-dialog">
</head>
<body>
<div class="login-ui-wrapper" style="
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-direction: column;
">
  <div class="login-dialog">
    <!-- Le contenu original de Guacamole sera ici -->
  </div>
  <p style="
    color: #475569;
    font-size: 12px;
    margin-top: 24px;
    font-family: 'Inter', sans-serif;
  ">
    © 2025 Selest Informatique — Accès sécurisé
  </p>
</div>
</body>
</html>
LOGINHTML

# ════════════════════════════════════════
section "5. Manifeste de l'extension"
# ════════════════════════════════════════
cat > "$THEME_BUILD_DIR/guac-manifest.json" <<'MANIFEST'
{
  "guacamoleVersion" : "*",
  "name"             : "Selest Informatique Theme",
  "namespace"        : "selest-theme",
  "css"              : [ "theme.css" ],
  "resources"        : {
    "images/logo.svg" : "image/svg+xml"
  }
}
MANIFEST

log "Manifeste créé"

# ════════════════════════════════════════
section "6. Création du fichier .jar"
# ════════════════════════════════════════
cd "$THEME_BUILD_DIR"
zip -r "/tmp/${THEME_JAR}" . -x "*.DS_Store" > /dev/null
log "Fichier .jar créé : /tmp/${THEME_JAR}"

# ════════════════════════════════════════
section "7. Installation de l'extension"
# ════════════════════════════════════════

# Trouver le GUACAMOLE_HOME dans le conteneur
GUAC_HOME=$(docker exec guacamole env | grep GUACAMOLE_HOME | cut -d= -f2 2>/dev/null || echo "")

if [ -z "$GUAC_HOME" ]; then
  # Chercher dans les volumes montés
  GUAC_HOME=$(docker inspect guacamole 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
mounts = d[0].get('Mounts', [])
for m in mounts:
    if 'guacamole' in m.get('Destination','').lower():
        print(m['Destination'])
        break
" 2>/dev/null || echo "")
fi

# Créer le répertoire d'extensions dans le volume Docker
# On utilise un volume dédié monté dans le conteneur
log "Création du répertoire d'extensions..."
mkdir -p /opt/guacamole-extensions

# Copier le .jar dans le répertoire
cp "/tmp/${THEME_JAR}" "/opt/guacamole-extensions/${THEME_JAR}"
chmod 644 "/opt/guacamole-extensions/${THEME_JAR}"
log "Extension copiée dans /opt/guacamole-extensions/"

# ════════════════════════════════════════
section "8. Mise à jour du docker-compose"
# ════════════════════════════════════════

# Vérifier si le volume extensions est déjà monté
if grep -q "guacamole-extensions" /opt/guacamole/docker-compose.yml; then
  warn "Volume extensions déjà configuré dans docker-compose.yml"
else
  log "Ajout du volume extensions dans docker-compose.yml..."
  python3 << 'PYEOF'
content = open('/opt/guacamole/docker-compose.yml').read()

# Ajouter le volume dans le service guacamole
old = '    environment:\n      GUACD_HOSTNAME: guacd'
new = '    volumes:\n      - /opt/guacamole-extensions:/etc/guacamole/extensions:ro\n    environment:\n      GUACD_HOSTNAME: guacd'
content = content.replace(old, new)

# Ajouter GUACAMOLE_HOME si pas déjà présent
if 'GUACAMOLE_HOME' not in content:
    old2 = '      TOTP_ENABLED: "true"'
    new2 = '      GUACAMOLE_HOME: /etc/guacamole\n      TOTP_ENABLED: "true"'
    content = content.replace(old2, new2)

open('/opt/guacamole/docker-compose.yml', 'w').write(content)
print("docker-compose.yml mis à jour")
PYEOF
fi

# ════════════════════════════════════════
section "9. Redémarrage de Guacamole"
# ════════════════════════════════════════
cd /opt/guacamole
docker compose --env-file .env up -d --force-recreate guacamole
log "Guacamole redémarré"

log "Attente du démarrage (~20s)..."
sleep 20

# Vérifier que l'extension est chargée
docker logs guacamole 2>&1 | grep -i "selest\|theme\|extension\|loaded" | tail -5 || true

# ════════════════════════════════════════
section "Résumé"
# ════════════════════════════════════════
echo ""
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  Thème installé avec succès !${NC}"
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo ""
echo -e "  🎨 Extension : /opt/guacamole-extensions/${THEME_JAR}"
echo -e "  🌐 Vérifier  : https://guac.selest.info/guacamole/"
echo ""
echo -e "${YELLOW}  Personnalisation :${NC}"
echo -e "  - Modifier les couleurs : éditer les variables CSS dans"
echo -e "    /tmp/guac-theme-build/theme.css puis relancer ce script"
echo -e "  - Changer le logo : remplacer"
echo -e "    /tmp/guac-theme-build/images/logo.svg"
echo ""
echo -e "${BLUE}  Pour supprimer le thème :${NC}"
echo -e "  sudo rm /opt/guacamole-extensions/${THEME_JAR}"
echo -e "  cd /opt/guacamole && sudo docker compose --env-file .env up -d --force-recreate guacamole"
echo ""
