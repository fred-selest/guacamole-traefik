#!/bin/bash
set -euo pipefail

# ============================================================
#  BACKUP AUTOMATIQUE MYSQL — Guacamole
#  Usage : sudo bash 4_backup_mysql.sh [install|backup|restore|list]
#
#  Modes :
#    install  — installe le cron quotidien (défaut si aucun argument)
#    backup   — lance un backup immédiat
#    restore  — restaure un backup (interactif)
#    list     — liste les backups disponibles
# ============================================================

# ---- CONFIG (à adapter si besoin) --------------------------
BASE_DIR="/opt/guacamole"
BACKUP_DIR="${BACKUP_DIR:-/opt/guacamole-backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"         # Nombre de jours de rétention
BACKUP_TIME="${BACKUP_TIME:-02:30}"            # Heure du backup quotidien (HH:MM)
COMPRESS="${COMPRESS:-true}"                   # Compression gzip
DB_CONTAINER="guac-db"
DB_NAME="guacamole_db"
# ------------------------------------------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}══ $1 ══${NC}"; }

[[ $EUID -ne 0 ]] && err "Lance ce script en root : sudo bash $0"

# Charger les credentials MySQL depuis .env
load_mysql_creds() {
  if [ -f "$BASE_DIR/.env" ]; then
    MYSQL_ROOT_PASS=$(grep "^MYSQL_ROOT_PASSWORD=" "$BASE_DIR/.env" | cut -d= -f2)
    [ -z "$MYSQL_ROOT_PASS" ] && err "MYSQL_ROOT_PASSWORD introuvable dans $BASE_DIR/.env"
  else
    err "Fichier $BASE_DIR/.env introuvable — déployer d'abord avec 2_deploy_guacamole.sh"
  fi
}

# ════════════════════════════════════════════════════════════
do_backup() {
# ════════════════════════════════════════════════════════════
  load_mysql_creds

  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"

  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  DUMP_FILE="${BACKUP_DIR}/guacamole_db_${TIMESTAMP}.sql"

  # Vérifier que le conteneur MySQL tourne
  if ! docker inspect --format='{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null | grep -q "running"; then
    err "Conteneur ${DB_CONTAINER} non démarré — impossible de faire un backup"
  fi

  log "Démarrage du backup MySQL → ${DUMP_FILE}"

  # Dump MySQL via docker exec
  docker exec "$DB_CONTAINER" \
    mysqldump \
      -uroot \
      -p"${MYSQL_ROOT_PASS}" \
      --single-transaction \
      --routines \
      --triggers \
      --add-drop-table \
      "${DB_NAME}" > "$DUMP_FILE" 2>/dev/null

  # Vérifier que le dump n'est pas vide
  if [ ! -s "$DUMP_FILE" ]; then
    rm -f "$DUMP_FILE"
    err "Backup vide — vérifier les credentials MySQL"
  fi

  DUMP_SIZE=$(du -sh "$DUMP_FILE" | cut -f1)
  log "Dump SQL créé : ${DUMP_SIZE}"

  # Compression
  if [ "$COMPRESS" = "true" ]; then
    gzip "$DUMP_FILE"
    DUMP_FILE="${DUMP_FILE}.gz"
    DUMP_SIZE=$(du -sh "$DUMP_FILE" | cut -f1)
    log "Compressé : ${DUMP_FILE} (${DUMP_SIZE})"
  fi

  chmod 600 "$DUMP_FILE"

  # Rotation — supprimer les backups plus vieux que RETENTION_DAYS
  DELETED=$(find "$BACKUP_DIR" -name "guacamole_db_*.sql*" \
    -mtime +"${RETENTION_DAYS}" -delete -print | wc -l)
  [ "$DELETED" -gt 0 ] && log "Rotation : ${DELETED} ancien(s) backup(s) supprimé(s)"

  # Résumé
  TOTAL_BACKUPS=$(find "$BACKUP_DIR" -name "guacamole_db_*.sql*" | wc -l)
  TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
  log "Backup terminé — ${TOTAL_BACKUPS} backup(s) en stock, ${TOTAL_SIZE} au total"

  echo "$DUMP_FILE"
}

# ════════════════════════════════════════════════════════════
do_restore() {
# ════════════════════════════════════════════════════════════
  load_mysql_creds

  # Lister les backups disponibles
  mapfile -t BACKUPS < <(find "$BACKUP_DIR" -name "guacamole_db_*.sql*" | sort -r 2>/dev/null)

  if [ ${#BACKUPS[@]} -eq 0 ]; then
    err "Aucun backup trouvé dans ${BACKUP_DIR}"
  fi

  echo ""
  echo -e "${BLUE}Backups disponibles :${NC}"
  for i in "${!BACKUPS[@]}"; do
    SIZE=$(du -sh "${BACKUPS[$i]}" | cut -f1)
    DATE=$(basename "${BACKUPS[$i]}" | sed 's/guacamole_db_//;s/\.sql.*//;s/-/ /')
    printf "  [%2d] %s (%s)  %s\n" "$i" "$DATE" "$SIZE" "$(basename "${BACKUPS[$i]}")"
  done
  echo ""

  read -rp "Numéro du backup à restaurer (ou 'q' pour annuler) : " CHOICE
  [ "$CHOICE" = "q" ] && { warn "Restauration annulée"; exit 0; }

  if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -ge "${#BACKUPS[@]}" ]; then
    err "Choix invalide"
  fi

  RESTORE_FILE="${BACKUPS[$CHOICE]}"
  echo ""
  warn "⚠️  La restauration va ÉCRASER la base ${DB_NAME} actuelle !"
  warn "Fichier : ${RESTORE_FILE}"
  read -rp "Confirmer ? (oui/non) : " CONFIRM
  [ "$CONFIRM" != "oui" ] && { warn "Restauration annulée"; exit 0; }

  # Décompresser si nécessaire
  RESTORE_SQL="$RESTORE_FILE"
  if [[ "$RESTORE_FILE" == *.gz ]]; then
    log "Décompression..."
    RESTORE_SQL="${RESTORE_FILE%.gz}"
    gunzip -c "$RESTORE_FILE" > "$RESTORE_SQL"
    CLEANUP_SQL=true
  else
    CLEANUP_SQL=false
  fi

  log "Restauration en cours..."

  # Arrêter Guacamole pendant la restauration
  log "Arrêt du conteneur Guacamole..."
  docker stop guacamole 2>/dev/null || true

  # Restaurer la base
  docker exec -i "$DB_CONTAINER" \
    mysql -uroot -p"${MYSQL_ROOT_PASS}" "${DB_NAME}" < "$RESTORE_SQL" 2>/dev/null \
    && log "Base de données restaurée" \
    || { err "Echec de la restauration"; docker start guacamole; }

  # Nettoyer le fichier décompressé temporaire
  [ "$CLEANUP_SQL" = "true" ] && rm -f "$RESTORE_SQL"

  # Redémarrer Guacamole
  log "Redémarrage de Guacamole..."
  docker start guacamole
  sleep 5

  log "Restauration terminée depuis : $(basename "$RESTORE_FILE")"
}

# ════════════════════════════════════════════════════════════
do_list() {
# ════════════════════════════════════════════════════════════
  if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
    warn "Aucun backup trouvé dans ${BACKUP_DIR}"
    return
  fi

  echo ""
  echo -e "${BLUE}══ Backups MySQL disponibles ══${NC}"
  echo -e "  Répertoire : ${BACKUP_DIR}"
  echo -e "  Rétention  : ${RETENTION_DAYS} jours"
  echo ""
  printf "  %-32s  %-8s  %s\n" "Fichier" "Taille" "Date"
  printf "  %-32s  %-8s  %s\n" "-------" "------" "----"

  find "$BACKUP_DIR" -name "guacamole_db_*.sql*" | sort -r | while read -r f; do
    SIZE=$(du -sh "$f" | cut -f1)
    MOD=$(date -r "$f" "+%Y-%m-%d %H:%M")
    printf "  %-32s  %-8s  %s\n" "$(basename "$f")" "$SIZE" "$MOD"
  done

  echo ""
  TOTAL=$(find "$BACKUP_DIR" -name "guacamole_db_*.sql*" | wc -l)
  TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
  echo -e "  Total : ${TOTAL} backup(s) — ${TOTAL_SIZE}"
  echo ""
}

# ════════════════════════════════════════════════════════════
do_install() {
# ════════════════════════════════════════════════════════════
  section "Installation du cron de backup automatique"

  # Créer le répertoire de backup
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
  log "Répertoire backup : ${BACKUP_DIR}"

  # Copier ce script dans /usr/local/sbin pour qu'il soit accessible via cron
  SCRIPT_DEST="/usr/local/sbin/guacamole-backup"
  cp "$0" "$SCRIPT_DEST"
  chmod 700 "$SCRIPT_DEST"
  log "Script copié dans : ${SCRIPT_DEST}"

  # Générer la configuration des variables d'environnement pour cron
  ENV_CONF="/etc/guacamole-backup.conf"
  cat > "$ENV_CONF" <<ENVCONF
BACKUP_DIR=${BACKUP_DIR}
RETENTION_DAYS=${RETENTION_DAYS}
COMPRESS=${COMPRESS}
ENVCONF
  chmod 600 "$ENV_CONF"
  log "Configuration sauvegardée dans : ${ENV_CONF}"

  # Extraire heure et minute pour le cron
  CRON_HOUR=$(echo "$BACKUP_TIME" | cut -d: -f1)
  CRON_MIN=$(echo "$BACKUP_TIME" | cut -d: -f2)

  # Créer l'entrée cron
  CRON_ENTRY="${CRON_MIN} ${CRON_HOUR} * * * root . ${ENV_CONF} && ${SCRIPT_DEST} backup >> /var/log/guacamole-backup.log 2>&1"
  echo "$CRON_ENTRY" > /etc/cron.d/guacamole-backup
  chmod 644 /etc/cron.d/guacamole-backup
  log "Cron configuré : backup quotidien à ${BACKUP_TIME}"

  # Créer la rotation des logs de backup avec logrotate
  cat > /etc/logrotate.d/guacamole-backup <<LOGROTATE
/var/log/guacamole-backup.log {
  weekly
  rotate 4
  compress
  missingok
  notifempty
}
LOGROTATE
  log "Logrotate configuré pour /var/log/guacamole-backup.log"

  # Lancer un premier backup immédiatement
  echo ""
  read -rp "Lancer un backup immédiat maintenant ? (oui/non) : " RUN_NOW
  if [ "$RUN_NOW" = "oui" ]; then
    section "Backup immédiat"
    do_backup
  fi

  echo ""
  echo -e "${GREEN}════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  ✅  Backup automatique configuré !${NC}"
  echo -e "${GREEN}════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  Répertoire  : ${BACKUP_DIR}"
  echo -e "  Planification : tous les jours à ${BACKUP_TIME}"
  echo -e "  Rétention   : ${RETENTION_DAYS} jours"
  echo -e "  Compression : ${COMPRESS}"
  echo ""
  echo -e "${BLUE}  Commandes utiles :${NC}"
  echo -e "  sudo ${SCRIPT_DEST} list     — lister les backups"
  echo -e "  sudo ${SCRIPT_DEST} backup   — backup immédiat"
  echo -e "  sudo ${SCRIPT_DEST} restore  — restaurer un backup"
  echo -e "  sudo tail -f /var/log/guacamole-backup.log"
  echo ""
}

# ════════════════════════════════════════════════════════════
# Point d'entrée principal
# ════════════════════════════════════════════════════════════
ACTION="${1:-install}"

case "$ACTION" in
  install)
    do_install
    ;;
  backup)
    section "Backup MySQL"
    # Charger la config si lancé via cron
    [ -f /etc/guacamole-backup.conf ] && . /etc/guacamole-backup.conf
    DUMP=$(do_backup)
    log "Backup créé : $DUMP"
    ;;
  restore)
    section "Restauration MySQL"
    do_restore
    ;;
  list)
    do_list
    ;;
  *)
    echo "Usage : sudo bash $0 [install|backup|restore|list]"
    echo ""
    echo "  install  — Installe le cron de backup automatique (défaut)"
    echo "  backup   — Lance un backup immédiat"
    echo "  restore  — Restaure un backup (interactif)"
    echo "  list     — Liste les backups disponibles"
    exit 1
    ;;
esac
