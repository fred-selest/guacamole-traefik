#!/bin/bash
set -euo pipefail

# ============================================================
#  AUTO-DÉPLOIEMENT GUACAMOLE — Mise à jour automatique
#  Usage : sudo bash 6_auto_deploy_setup.sh
#
#  Ce script installe un timer systemd qui surveille le dépôt
#  git toutes les 2 minutes et relance automatiquement le
#  script de thème si de nouveaux commits sont détectés.
#
#  Commandes utiles après installation :
#    sudo systemctl status guac-autodeploy.timer
#    sudo journalctl -u guac-autodeploy -f
#    cat /var/log/guac-autodeploy.log
#    sudo systemctl stop guac-autodeploy.timer   # pause
#    sudo systemctl start guac-autodeploy.timer  # reprendre
# ============================================================

# ── Config (personnalisable via variables d'env) ────────────
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT:-${REPO_DIR}/scripts/3_theme_guacamole.sh}"
INTERVAL="${INTERVAL:-2min}"   # fréquence de vérification
LOG_FILE="/var/log/guac-autodeploy.log"
DEPLOY_BIN="/usr/local/bin/guac-autodeploy"
SERVICE_NAME="guac-autodeploy"
# ───────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}══ $1 ══${NC}"; }

[[ $EUID -ne 0 ]] && err "Lance ce script en root : sudo bash $0"

# Détecter l'utilisateur propriétaire du repo
REPO_OWNER=$(stat -c '%U' "$REPO_DIR")
REPO_OWNER_HOME=$(getent passwd "$REPO_OWNER" | cut -d: -f6)

section "1. Vérification du dépôt"
[[ -d "$REPO_DIR/.git" ]] || err "Pas un dépôt git : $REPO_DIR"
[[ -f "$DEPLOY_SCRIPT" ]] || err "Script introuvable : $DEPLOY_SCRIPT"
BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
REMOTE_URL=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo "?")
log "Dépôt  : $REPO_DIR"
log "Branch : $BRANCH"
log "Remote : $REMOTE_URL"
log "Owner  : $REPO_OWNER"

# ════════════════════════════════════════
section "2. Script de déploiement"
# ════════════════════════════════════════
cat > "$DEPLOY_BIN" << DEPLOY_SCRIPT_EOF
#!/bin/bash
# ── guac-autodeploy ─────────────────────────────────────────
# Vérifie les nouveaux commits et relance le thème si besoin.
# Généré par 6_auto_deploy_setup.sh — ne pas éditer manuellement.
# ───────────────────────────────────────────────────────────
REPO_DIR="$REPO_DIR"
DEPLOY_SCRIPT="$DEPLOY_SCRIPT"
LOG_FILE="$LOG_FILE"
REPO_OWNER="$REPO_OWNER"
BRANCH="$BRANCH"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log_it() { echo "[\$(ts)] \$1" | tee -a "\$LOG_FILE"; }

# Taille max du log : 5 Mo — rotation simple
if [[ -f "\$LOG_FILE" ]] && [[ \$(stat -c%s "\$LOG_FILE") -gt 5242880 ]]; then
    mv "\$LOG_FILE" "\${LOG_FILE}.old"
fi

# Fetch en tant qu'utilisateur propriétaire du repo
if ! sudo -u "\$REPO_OWNER" git -C "\$REPO_DIR" fetch origin "\$BRANCH" --quiet 2>&1 | tee -a "\$LOG_FILE"; then
    log_it "ERREUR : git fetch a échoué — vérifier la connectivité réseau"
    exit 1
fi

LOCAL=\$(git -C "\$REPO_DIR" rev-parse HEAD)
REMOTE=\$(git -C "\$REPO_DIR" rev-parse "origin/\$BRANCH")

if [[ "\$LOCAL" == "\$REMOTE" ]]; then
    log_it "OK (aucun changement) — commit: \${LOCAL:0:8}"
    exit 0
fi

# Nouveaux commits détectés
NEW_COMMITS=\$(git -C "\$REPO_DIR" log --oneline "\$LOCAL".."origin/\$BRANCH" 2>/dev/null | head -5)
log_it "━━━ Nouveaux commits détectés ━━━"
echo "\$NEW_COMMITS" | while read line; do log_it "  • \$line"; done >> "\$LOG_FILE" 2>&1

log_it "Pull origin/\$BRANCH..."
sudo -u "\$REPO_OWNER" git -C "\$REPO_DIR" pull --ff-only origin "\$BRANCH" >> "\$LOG_FILE" 2>&1 || {
    log_it "ERREUR : git pull a échoué"
    exit 1
}

log_it "Lancement du déploiement : \$DEPLOY_SCRIPT"
if bash "\$DEPLOY_SCRIPT" >> "\$LOG_FILE" 2>&1; then
    DEPLOYED=\$(git -C "\$REPO_DIR" rev-parse HEAD)
    log_it "✓ Déploiement réussi — commit: \${DEPLOYED:0:8}"
else
    log_it "✗ Déploiement ÉCHOUÉ (code: \$?)"
    exit 1
fi
DEPLOY_SCRIPT_EOF

chmod +x "$DEPLOY_BIN"
log "Script déployé : $DEPLOY_BIN"

# ════════════════════════════════════════
section "3. Service systemd"
# ════════════════════════════════════════
cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Guacamole Auto-Deploy — mise à jour thème depuis git
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$DEPLOY_BIN
StandardOutput=journal
StandardError=journal
# Pas de timeout strict pour laisser le temps au build
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

log "Service créé : /etc/systemd/system/${SERVICE_NAME}.service"

# ════════════════════════════════════════
section "4. Timer systemd (toutes les ${INTERVAL})"
# ════════════════════════════════════════
cat > "/etc/systemd/system/${SERVICE_NAME}.timer" << EOF
[Unit]
Description=Guacamole Auto-Deploy — timer de surveillance git
Requires=${SERVICE_NAME}.service

[Timer]
OnBootSec=30sec
OnUnitActiveSec=${INTERVAL}
AccuracySec=10sec
Unit=${SERVICE_NAME}.service

[Install]
WantedBy=timers.target
EOF

log "Timer créé    : /etc/systemd/system/${SERVICE_NAME}.timer"

# ════════════════════════════════════════
section "5. Activation"
# ════════════════════════════════════════
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.timer"
log "Timer activé et démarré"

# ════════════════════════════════════════
section "6. Premier déploiement"
# ════════════════════════════════════════
touch "$LOG_FILE"
log "Lancement immédiat du premier déploiement..."
systemctl start "${SERVICE_NAME}.service"
sleep 3
tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'

# ════════════════════════════════════════
section "Résumé"
# ════════════════════════════════════════
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  Auto-déploiement configuré !${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  🔁  Fréquence : toutes les ${INTERVAL}"
echo -e "  🌿  Branche   : ${BRANCH}"
echo -e "  📁  Dépôt     : ${REPO_DIR}"
echo -e "  📜  Logs      : ${LOG_FILE}"
echo ""
echo -e "${BLUE}  Commandes utiles :${NC}"
echo -e "  sudo systemctl status ${SERVICE_NAME}.timer      # état du timer"
echo -e "  sudo journalctl -u ${SERVICE_NAME} -f            # logs systemd en direct"
echo -e "  sudo tail -f ${LOG_FILE}                         # logs déploiement"
echo -e "  sudo systemctl stop ${SERVICE_NAME}.timer        # pause"
echo -e "  sudo systemctl disable ${SERVICE_NAME}.timer     # désinstaller"
echo ""
echo -e "${YELLOW}  Désinstaller complètement :${NC}"
echo -e "  sudo systemctl disable --now ${SERVICE_NAME}.timer"
echo -e "  sudo rm /etc/systemd/system/${SERVICE_NAME}.{service,timer}"
echo -e "  sudo rm ${DEPLOY_BIN}"
echo -e "  sudo systemctl daemon-reload"
echo ""
