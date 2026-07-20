#!/usr/bin/env bash
# ================================================================
#  start.sh — Démarrage complet VM2 (API Gateway + Dashboard)
#  Place ce fichier dans /home/user/
#  Usage : bash ~/start.sh
#
#  Ce script fait dans l'ordre :
#   1. Vérifie la connectivité réseau (VM1 + internet)
#   2. Teste Flask API sur VM1
#   3. Génère kong.yml et config.js depuis .env
#   4. Lance Kong Gateway (Docker)
#   5. Teste Kong → Flask (chaîne complète)
#   6. Lance le Dashboard HTML
#   7. Résumé final avec toutes les URLs
# ================================================================
set -uo pipefail

# ── Couleurs & helpers ──────────────────────────────────────────
GRN='\033[0;32m'; YEL='\033[1;33m'; CYN='\033[0;36m'
RED='\033[0;31m'; MAG='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

ok()   { echo -e "  ${GRN}✔${RST}  $*"; }
war()  { echo -e "  ${YEL}⚠${RST}  $*"; }
inf()  { echo -e "  ${CYN}ℹ${RST}  $*"; }
err()  { echo -e "  ${RED}✘${RST}  $*"; }

sep() {
  echo ""
  echo -e "${BOLD}${MAG}▶ $*${RST}"
  echo -e "${DIM}────────────────────────────────────────────────────${RST}"
}

banner() {
  clear
  echo ""
  echo -e "${BOLD}${CYN}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${CYN}║     Cloud Privé OSS — Démarrage VM2 API Gateway          ║${RST}"
  echo -e "${BOLD}${CYN}║     Kong Gateway + OpenStack Dashboard Frontend          ║${RST}"
  echo -e "${BOLD}${CYN}╚══════════════════════════════════════════════════════════╝${RST}"
  echo -e "  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RST}"
  echo ""
}

# ── Compteurs ───────────────────────────────────────────────────
PASS=0; WARN=0; FAIL=0
pass() { ok "$*";  (( PASS++ )) || true; }
warn() { war "$*"; (( WARN++ )) || true; }
fail() { err "$*"; (( FAIL++ )) || true; }

# ── Chemins ─────────────────────────────────────────────────────
FRONTEND_DIR="/home/user/cloud-project/project_terraform/frontend"
DASHBOARD_DIR="${FRONTEND_DIR}/dashboard"
DASHBOARD_LOG="/tmp/dashboard.log"
DASHBOARD_PID="/tmp/dashboard.pid"
DASHBOARD_PORT=8080

# ── IPs depuis .env ou valeurs par défaut ───────────────────────
ENV_FILE="${FRONTEND_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
else
  OPENSTACK_HOST="192.168.128.130"
  OPENSTACK_APP_PORT="5005"
  KONG_HOST="192.168.128.131"
  KONG_PROXY_PORT="8000"
  KONG_ADMIN_PORT="8001"
  API_BASE_URL="http://192.168.128.131:8000/api"
fi

VM2_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

# ================================================================
banner

# ================================================================
#  1. Vérification connectivité réseau
# ================================================================
sep "1. Connectivité réseau"

# Ping VM1 (OpenStack)
if ping -c 2 -W 3 "$OPENSTACK_HOST" > /dev/null 2>&1; then
  pass "VM1 OpenStack accessible (${OPENSTACK_HOST})"
else
  fail "VM1 OpenStack INACCESSIBLE (${OPENSTACK_HOST})"
  war  "Vérifie que VM1 est démarrée et que le réseau VMware fonctionne"
fi

# Ping internet
if ping -c 2 -W 3 8.8.8.8 > /dev/null 2>&1; then
  pass "Internet accessible (8.8.8.8)"
else
  warn "Internet inaccessible — Kong peut quand même fonctionner en local"
fi

# Vérifier que Docker tourne
if docker info > /dev/null 2>&1; then
  DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
  pass "Docker opérationnel — version ${DOCKER_VER}"
else
  fail "Docker non disponible"
  err  "Lancer : sudo systemctl start docker"
fi

# ================================================================
#  2. Test Flask API sur VM1
# ================================================================
sep "2. Test Flask API (VM1 → port 5005)"

inf "Tentative de connexion à http://${OPENSTACK_HOST}:${OPENSTACK_APP_PORT}/api/servers ..."

FLASK_RESPONSE=$(curl -s --max-time 8 \
  "http://${OPENSTACK_HOST}:${OPENSTACK_APP_PORT}/api/servers" 2>/dev/null || echo "")

if echo "$FLASK_RESPONSE" | grep -q '\[' 2>/dev/null; then
  VM_COUNT=$(echo "$FLASK_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "?")
  pass "Flask API répond — ${VM_COUNT} instance(s) OpenStack trouvée(s)"
  echo ""
  echo -e "  ${DIM}Réponse (extrait) :${RST}"
  echo "$FLASK_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for vm in data[:3]:
        name   = vm.get('Name', vm.get('name', '?'))
        status = vm.get('Status', vm.get('status', '?'))
        nets   = vm.get('Networks', vm.get('networks', '?'))
        print(f'    ● {name:20s} {status:10s} {nets}')
except:
    pass
" 2>/dev/null || true
  echo ""
elif [ -z "$FLASK_RESPONSE" ]; then
  warn "Flask API ne répond pas — vérifie que start.sh a été lancé sur VM1"
  inf  "Sur VM1 : bash ~/start.sh"
else
  warn "Flask répond mais réponse inattendue : ${FLASK_RESPONSE:0:100}"
fi

# ================================================================
#  3. Génération kong.yml et config.js depuis .env
# ================================================================
sep "3. Génération des fichiers de configuration"

cd "$FRONTEND_DIR"

if [ ! -f ".env" ]; then
  warn ".env absent — création avec valeurs par défaut"
  cat > .env << ENVEOF
OPENSTACK_HOST=192.168.128.130
OPENSTACK_APP_PORT=5005
KONG_HOST=192.168.128.131
KONG_PROXY_PORT=8000
KONG_ADMIN_PORT=8001
API_BASE_URL=http://192.168.128.131:8000/api
ENVEOF
  pass ".env créé"
fi

# Lancer gen-config.sh
inf "Exécution de gen-config.sh..."
if bash gen-config.sh; then
  pass "kong.yml généré → backend = http://${OPENSTACK_HOST}:${OPENSTACK_APP_PORT}"
  pass "config.js généré → API = ${API_BASE_URL}"
else
  fail "gen-config.sh a échoué"
fi

# Vérifier qu'il n'y a plus de variables non résolues dans kong.yml
if grep -q '\${' kong.yml 2>/dev/null; then
  fail "kong.yml contient encore des variables non résolues !"
  grep '\${' kong.yml
else
  pass "kong.yml propre — aucune variable \${...} résiduelle"
fi

# ================================================================
#  4. Démarrage Kong Gateway
# ================================================================
sep "4. Kong Gateway (Docker)"

# Arrêter l'ancienne instance
inf "Arrêt de l'ancienne instance Kong..."
docker compose down 2>/dev/null || true
sleep 2

# Supprimer la ligne version obsolète si présente
sed -i '/^version:/d' docker-compose.yml 2>/dev/null || true

# Lancer Kong
inf "Démarrage de Kong..."
docker compose up -d

# Attendre que Kong soit healthy
inf "Attente Kong (15 secondes)..."
sleep 15

# Vérifier le statut
KONG_STATUS=$(docker compose ps --format json 2>/dev/null | python3 -c "
import sys, json
try:
    for line in sys.stdin:
        line = line.strip()
        if line:
            d = json.loads(line)
            print(d.get('State', d.get('Status', 'unknown')))
            break
except:
    pass
" 2>/dev/null || docker compose ps | grep kong | awk '{print $4}')

if docker compose ps | grep -q "Up\|running\|healthy"; then
  pass "Kong Gateway opérationnel"
  docker compose ps
else
  fail "Kong ne démarre pas correctement"
  err  "Logs Kong :"
  docker compose logs --tail=10 kong
fi

# ================================================================
#  5. Test chaîne complète Kong → Flask
# ================================================================
sep "5. Test chaîne Kong → Flask"

inf "Test : http://${KONG_HOST}:${KONG_PROXY_PORT}/api/servers ..."
sleep 3

KONG_RESPONSE=$(curl -s --max-time 10 \
  "http://localhost:${KONG_PROXY_PORT}/api/servers" 2>/dev/null || echo "")

if echo "$KONG_RESPONSE" | grep -q '\[' 2>/dev/null; then
  pass "Kong → Flask → OpenStack : chaîne complète OK ✓"
  echo -e "  ${DIM}Kong proxifie correctement les requêtes vers Flask${RST}"
elif [ -z "$KONG_RESPONSE" ]; then
  warn "Pas de réponse via Kong — Flask est peut-être encore en cours de démarrage"
else
  warn "Réponse Kong inattendue : ${KONG_RESPONSE:0:150}"
  inf  "Test dans 30s : curl http://localhost:${KONG_PROXY_PORT}/api/servers"
fi

# ================================================================
#  6. Démarrage Dashboard HTML
# ================================================================
sep "6. Dashboard OpenStack (Frontend)"

# Arrêter l'ancien serveur
if [ -f "$DASHBOARD_PID" ]; then
  OLD_PID=$(cat "$DASHBOARD_PID")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null
    inf "Ancien serveur dashboard arrêté (PID ${OLD_PID})"
    sleep 1
  fi
  rm -f "$DASHBOARD_PID"
fi

# Vérifier que le dashboard existe
if [ ! -f "${DASHBOARD_DIR}/index.html" ]; then
  fail "index.html introuvable dans ${DASHBOARD_DIR}"
else
  cd "$DASHBOARD_DIR"

  # Lancer le serveur HTTP
  nohup python3 -m http.server "$DASHBOARD_PORT" \
    > "$DASHBOARD_LOG" 2>&1 &
  echo $! > "$DASHBOARD_PID"
  sleep 2

  # Vérifier
  if curl -s --max-time 5 "http://localhost:${DASHBOARD_PORT}" > /dev/null 2>&1; then
    pass "Dashboard HTML opérationnel (PID $(cat $DASHBOARD_PID))"
  else
    warn "Serveur dashboard démarre encore..."
  fi
fi

# ================================================================
#  7. Résumé final
# ================================================================
sep "7. Résumé"

echo ""
echo -e "  ${BOLD}Résultats :${RST}"
echo -e "  ${GRN}✔  Succès       : ${PASS}${RST}"
[[ $WARN -gt 0 ]] && echo -e "  ${YEL}⚠  Avertissements : ${WARN}${RST}"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}✘  Erreurs        : ${FAIL}${RST}"

echo ""
echo -e "${BOLD}${CYN}╔══════════════════════════════════════════════════════════════╗${RST}"
echo -e "${BOLD}${CYN}║   URLs de ton infrastructure cloud privé OSS                 ║${RST}"
echo -e "${BOLD}${CYN}╠══════════════════════════════════════════════════════════════╣${RST}"
echo -e "${BOLD}${CYN}║${RST}                                                              ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}  🖥  Dashboard Frontend OSS                                  ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}     ${BOLD}http://${VM2_IP}:${DASHBOARD_PORT}${RST}                           ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}                                                              ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}  🔀  Kong API Gateway                                        ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}     ${BOLD}http://${VM2_IP}:${KONG_PROXY_PORT}/api/servers${RST}              ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}     ${BOLD}http://${VM2_IP}:${KONG_PROXY_PORT}/api/images${RST}               ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}     ${BOLD}http://${VM2_IP}:${KONG_PROXY_PORT}/api/networks${RST}             ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}                                                              ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}  🔧  Kong Admin API                                          ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}     ${BOLD}http://${VM2_IP}:${KONG_ADMIN_PORT}/services${RST}                 ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}                                                              ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}  ☁  Flask API (VM1 direct)                                  ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}     ${BOLD}http://${OPENSTACK_HOST}:${OPENSTACK_APP_PORT}/api/servers${RST}   ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}                                                              ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}  🌐  Horizon OpenStack (VM1)                                 ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}     ${BOLD}https://${OPENSTACK_HOST}${RST}                              ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}                                                              ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}╠══════════════════════════════════════════════════════════════╣${RST}"
echo -e "${BOLD}${CYN}║${RST}  Commandes utiles :                                          ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}  docker compose logs -f kong    → logs Kong en direct        ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}  docker compose ps              → statut Kong                ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}  tail -f ${DASHBOARD_LOG}       → logs dashboard        ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}║${RST}  bash ~/start.sh                → relancer tout              ${BOLD}${CYN}║${RST}"
echo -e "${BOLD}${CYN}╚══════════════════════════════════════════════════════════════╝${RST}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "${BOLD}${GRN}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${GRN}║   ✔  VM2 opérationnelle — Ouvre le dashboard !           ║${RST}"
  echo -e "${BOLD}${GRN}║   →  http://${VM2_IP}:${DASHBOARD_PORT}                          ║${RST}"
  echo -e "${BOLD}${GRN}╚══════════════════════════════════════════════════════════╝${RST}"
else
  echo -e "${BOLD}${YEL}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${YEL}║   ⚠  Démarrage avec avertissements — voir ci-dessus      ║${RST}"
  echo -e "${BOLD}${YEL}╚══════════════════════════════════════════════════════════╝${RST}"
fi
echo ""
