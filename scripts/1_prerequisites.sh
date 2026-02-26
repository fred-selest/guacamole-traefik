#!/bin/bash
set -euo pipefail

# ============================================================
#  PRÉREQUIS — Ubuntu 22.04 / 24.04 vierge
#  Usage : sudo bash 1_prerequisites.sh
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}══ $1 ══${NC}"; }

[[ $EUID -ne 0 ]] && err "Lance ce script en root : sudo bash $0"

. /etc/os-release
log "Système détecté : $PRETTY_NAME"
[[ "$ID" != "ubuntu" ]] && warn "Ce script est prévu pour Ubuntu"

# ════════════════════════════════════════
section "1. Mise à jour du système"
# ════════════════════════════════════════
apt-get update -qq
apt-get upgrade -y -qq
apt-get autoremove -y -qq

# ════════════════════════════════════════
section "2. Paquets essentiels"
# ════════════════════════════════════════
apt-get install -y -qq \
  curl wget git \
  ca-certificates gnupg \
  openssl \
  apache2-utils \
  ufw \
  fail2ban \
  unattended-upgrades \
  apt-transport-https \
  software-properties-common \
  lsb-release \
  htop iotop \
  net-tools \
  jq \
  tzdata \
  python3

# ════════════════════════════════════════
section "3. Timezone"
# ════════════════════════════════════════
timedatectl set-timezone Europe/Paris
log "Timezone : $(timedatectl | grep 'Time zone')"

# ════════════════════════════════════════
section "4. Installation Docker CE"
# ════════════════════════════════════════
if command -v docker &>/dev/null; then
  warn "Docker déjà installé : $(docker --version)"
else
  log "Ajout du dépôt officiel Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  systemctl enable --now docker
  log "Docker installé : $(docker --version)"
  log "Docker Compose  : $(docker compose version)"
fi

# ════════════════════════════════════════
section "5. Firewall UFW"
# ════════════════════════════════════════
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

SSH_PORT=${SSH_PORT:-22}
ufw allow "$SSH_PORT/tcp"  comment "SSH"
ufw allow 80/tcp           comment "HTTP Let's Encrypt"
ufw allow 443/tcp          comment "HTTPS Traefik"

# Empêcher Docker de bypasser UFW
UFW_AFTER=/etc/ufw/after.rules
if ! grep -q "DOCKER-USER" "$UFW_AFTER" 2>/dev/null; then
  cat >> "$UFW_AFTER" <<'UFWRULES'

# Règles DOCKER-USER — protection UFW/Docker
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -i eth0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A DOCKER-USER -i eth0 -j DROP
COMMIT
UFWRULES
fi

ufw --force enable
log "UFW activé"

# ════════════════════════════════════════
section "6. Fail2ban"
# ════════════════════════════════════════
cat > /etc/fail2ban/jail.local <<FAIL2BAN
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ${SSH_PORT}
maxretry = 3
bantime  = 24h
FAIL2BAN

systemctl enable --now fail2ban
log "Fail2ban actif"

# ════════════════════════════════════════
section "7. Mises à jour de sécurité automatiques"
# ════════════════════════════════════════
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'AUTOUPGRADE'
Unattended-Upgrade::Allowed-Origins {
  "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
AUTOUPGRADE

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTOTRIGGER'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOTRIGGER

systemctl enable --now unattended-upgrades
log "Mises à jour de sécurité automatiques activées"

# ════════════════════════════════════════
section "8. Hardening SSH"
# ════════════════════════════════════════
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d)"

apply_ssh() {
  local key=$1 val=$2
  if grep -qE "^#?\\s*${key}" "$SSHD_CONFIG"; then
    sed -i "s|^#\\?\\s*${key}.*|${key} ${val}|" "$SSHD_CONFIG"
  else
    echo "${key} ${val}" >> "$SSHD_CONFIG"
  fi
}

apply_ssh "PermitRootLogin"        "no"
apply_ssh "PasswordAuthentication" "yes"   # passer à "no" si clés SSH configurées
apply_ssh "X11Forwarding"          "no"
apply_ssh "MaxAuthTries"           "3"
apply_ssh "LoginGraceTime"         "30"
apply_ssh "ClientAliveInterval"    "300"
apply_ssh "ClientAliveCountMax"    "2"
apply_ssh "AllowTcpForwarding"     "no"
apply_ssh "PrintLastLog"           "yes"

sshd -t && systemctl reload sshd
log "SSH durci (backup : ${SSHD_CONFIG}.bak.*)"
warn "PermitRootLogin=no — assure-toi d'avoir un user sudo avant de déconnecter !"

# ════════════════════════════════════════
section "9. Paramètres kernel sysctl"
# ════════════════════════════════════════
cat > /etc/sysctl.d/99-hardening.conf <<'SYSCTL'
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
vm.swappiness = 10
SYSCTL

sysctl --system -q
log "Paramètres kernel appliqués"

# ════════════════════════════════════════
section "10. Bilan final"
# ════════════════════════════════════════
SERVER_IP=$(curl -s ifconfig.me)
echo ""
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  Prérequis installés avec succès !${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo ""
echo -e "  Docker         : $(docker --version)"
echo -e "  Docker Compose : $(docker compose version)"
echo -e "  UFW            : $(ufw status | head -1)"
echo -e "  Fail2ban       : $(fail2ban-client status 2>/dev/null | head -1 || echo 'actif')"
echo -e "  Timezone       : $(timedatectl | grep 'Time zone' | xargs)"
echo ""
echo -e "${YELLOW}  ⚠️  Avant de lancer le script 2, configure les DNS :${NC}"
echo -e "  Type A  |  guac.selest.info        |  ${SERVER_IP}"
echo -e "  Type A  |  traefik.selest.info     |  ${SERVER_IP}"
echo -e "  Type A  |  portainer.selest.info   |  ${SERVER_IP}"
echo ""
warn "Redémarre le serveur : sudo reboot"
echo ""
