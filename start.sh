#!/usr/bin/env bash
# ================================================================
#  start.sh — Démarrage complet de la VM OpenStack
#  Place ce fichier dans /home/microstack/
#  Usage : bash ~/start.sh
#
#  Ce script fait dans l'ordre :
#   1. Vérifie MicroStack installé
#   2. Redémarre les services MicroStack
#   3. Affiche l'état des services
#   4. Vérifie le token OpenStack
#   5. Affiche les identifiants Horizon
#   6. Vérifie les services OpenStack
#   7. Affiche les stats hyperviseur
#   8. Affiche l'inventaire complet
#   9. Démarre Flask (API Backend)
#  10. Résumé final avec toutes les URLs
# ================================================================
set -uo pipefail

# ── Couleurs & helpers ──────────────────────────────────────────
GRN='\033[0;32m'; YEL='\033[1;33m'; CYN='\033[0;36m'
RED='\033[0;31m'; MAG='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

ok()   { echo -e "  ${GRN}✔${RST}  $*"; }
war()  { echo -e "  ${YEL}⚠${RST}  $*"; }
inf()  { echo -e "  ${CYN}ℹ${RST}  $*"; }
err()  { echo -e "  ${RED}✘${RST}  $*"; }
skip() { echo -e "  ${DIM}–  $*${RST}"; }

sep() {
  local title="$*"
  echo ""
  echo -e "${BOLD}${MAG}▶ ${title}${RST}"
  echo -e "${DIM}────────────────────────────────────────────────────${RST}"
}

banner() {
  clear
  echo ""
  echo -e "${BOLD}${CYN}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${CYN}║     Cloud Privé OSS — Démarrage VM OpenStack             ║${RST}"
  echo -e "${BOLD}${CYN}║     MicroStack + Kubernetes + Flask API                  ║${RST}"
  echo -e "${BOLD}${CYN}╚══════════════════════════════════════════════════════════╝${RST}"
  echo -e "  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RST}"
  echo ""
}

# ── Compteurs résumé ────────────────────────────────────────────
PASS=0; WARN=0; FAIL=0
pass() { ok "$*";  (( PASS++ )) || true; }
warn() { war "$*"; (( WARN++ )) || true; }
fail() { err "$*"; (( FAIL++ )) || true; }

# ── Chemins ─────────────────────────────────────────────────────
BACKEND_DIR="/home/microstack/cloud-project/project_terraform/backend"
VENV_DIR="${BACKEND_DIR}/venv"
APP_FILE="${BACKEND_DIR}/app.py"
FLASK_LOG="/tmp/flask.log"
FLASK_PID="/tmp/flask.pid"
VM_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

# ================================================================
banner

# ================================================================
#  1. Vérifier si MicroStack est installé
# ================================================================
sep "1. Vérification MicroStack"

if snap list microstack &>/dev/null 2>&1; then
  SNAP_VER=$(snap list microstack 2>/dev/null | awk 'NR==2{print $2}')
  pass "MicroStack installé — version : ${SNAP_VER}"
else
  fail "MicroStack n'est PAS installé"
  echo ""
  echo -e "  ${YEL}Pour installer :${RST}"
  echo "    sudo snap install microstack --devmode --beta"
  echo "    sudo microstack init --auto --control"
  echo ""
  echo -e "  ${RED}Arrêt — MicroStack requis.${RST}"
  exit 1
fi

# ================================================================
#  2. Redémarrer les services MicroStack
# ================================================================
sep "2. Redémarrage des services MicroStack"

inf "Exécution : sudo snap restart microstack ..."
if sudo snap restart microstack 2>/dev/null; then
  pass "snap restart microstack — OK"
else
  warn "snap restart microstack — retour non-zéro (peut être normal)"
fi

inf "Attente stabilisation des services (15 secondes)..."
sleep 15
pass "Services stabilisés"

# ================================================================
#  3. État des services
# ================================================================
sep "3. État des services MicroStack"

echo ""
printf "  ${BOLD}%-50s %-12s %-10s${RST}\n" "SERVICE" "ACTIVÉ" "ÉTAT"
printf "  ${DIM}%s${RST}\n" "──────────────────────────────────────────────────────────────────────────"

snap services microstack 2>/dev/null | tail -n +2 | while IFS= read -r line; do
  SVC=$(echo "$line" | awk '{print $1}')
  ENA=$(echo "$line" | awk '{print $2}')
  STA=$(echo "$line" | awk '{print $3}')
  case "$STA" in
    active)   COLOR="${GRN}" ICON="●" ;;
    inactive) COLOR="${RED}" ICON="○" ;;
    *)        COLOR="${YEL}" ICON="?" ;;
  esac
  printf "  ${COLOR}${ICON}${RST} %-49s %-12s ${COLOR}%-10s${RST}\n" "$SVC" "$ENA" "$STA"
done
echo ""

# ================================================================
#  4. Token OpenStack (Keystone)
# ================================================================
sep "4. Authentification OpenStack"

if TOKEN=$(sudo microstack.openstack token issue -f value -c id 2>/dev/null | head -1) && [[ -n "$TOKEN" ]]; then
  pass "Token Keystone généré avec succès"
  echo -e "  ${DIM}Token (20 premiers chars) : ${TOKEN:0:20}...${RST}"
else
  warn "Token Keystone indisponible — Keystone peut encore démarrer"
fi

# ================================================================
#  5. Identifiants Horizon Dashboard
# ================================================================
sep "5. Identifiants Dashboard Horizon"

KS_PASS=$(sudo snap get microstack config.credentials.keystone-password 2>/dev/null || echo "")

if [[ -n "$KS_PASS" ]]; then
  pass "Mot de passe Keystone récupéré"
  echo ""
  echo -e "  ${BOLD}┌─────────────────────────────────────────┐${RST}"
  echo -e "  ${BOLD}│  Horizon Dashboard                      │${RST}"
  echo -e "  ${BOLD}├─────────────────────────────────────────┤${RST}"
  echo -e "  ${BOLD}│  URL      :${RST}  https://${VM_IP}/"
  echo -e "  ${BOLD}│  Username :${RST}  admin"
  echo -e "  ${BOLD}│  Password :${RST}  ${KS_PASS}"
  echo -e "  ${BOLD}└─────────────────────────────────────────┘${RST}"
  echo ""
else
  warn "Mot de passe Keystone non disponible"
fi

# ================================================================
#  6. Services OpenStack
# ================================================================
sep "6. Services OpenStack"

EXPECTED_SERVICES=("nova" "neutron" "glance" "keystone" "placement" "cinderv3")

echo ""
inf "Vérification des services essentiels :"
for SVC in "${EXPECTED_SERVICES[@]}"; do
  if sudo microstack.openstack service list 2>/dev/null | grep -qi "$SVC"; then
    pass "$SVC"
  else
    warn "$SVC — absent ou non enregistré"
  fi
done

# ================================================================
#  7. Statistiques Hyperviseur
# ================================================================
sep "7. Hyperviseur Nova"

echo ""
if sudo microstack.openstack hypervisor stats show 2>/dev/null; then
  pass "Statistiques hyperviseur OK"
else
  warn "hypervisor stats show indisponible"
fi

# ================================================================
#  8. Inventaire OpenStack
# ================================================================
sep "8. Inventaire OpenStack"

run_cmd() {
  local label="$1"; shift
  echo ""
  echo -e "  ${BOLD}${CYN}── ${label} ──${RST}"
  if sudo microstack.openstack "$@" 2>/dev/null; then
    :
  else
    echo -e "  ${YEL}(aucun résultat)${RST}"
  fi
}

run_cmd "Instances"       server list
run_cmd "Réseaux"         network list
run_cmd "IPs flottantes"  floating ip list
run_cmd "Images"          image list
run_cmd "Flavors"         flavor list
run_cmd "Keypairs"        keypair list

# ================================================================
#  9. Démarrage Flask (API Backend)
# ================================================================
sep "9. Démarrage Flask API Backend"

# Vérifier que le dossier backend existe
if [ ! -d "$BACKEND_DIR" ]; then
  fail "Dossier backend introuvable : $BACKEND_DIR"
  warn "Vérifie que le repo est cloné dans ~/cloud-project/"
  (( FAIL++ )) || true
else
  pass "Dossier backend trouvé : $BACKEND_DIR"
  cd "$BACKEND_DIR"

  # Vérifier app.py
  if [ ! -f "$APP_FILE" ]; then
    fail "app.py introuvable dans $BACKEND_DIR"
    (( FAIL++ )) || true
  else
    pass "app.py trouvé"

    # Créer le venv si absent
    if [ ! -d "$VENV_DIR" ]; then
      inf "Création de l'environnement virtuel Python..."
      python3 -m venv "$VENV_DIR"
      pass "Venv créé"
    else
      pass "Venv existant trouvé"
    fi

    # Activer le venv
    source "${VENV_DIR}/bin/activate"

    # Installer les dépendances si nécessaire
    if ! python3 -c "import flask" 2>/dev/null; then
      inf "Installation des dépendances Python..."
      pip install --quiet flask flask-cors python-dotenv
      pass "Dépendances installées"
    else
      FLASK_VER=$(python3 -c "import importlib.metadata; print(importlib.metadata.version('flask'))" 2>/dev/null || echo "?")
      pass "Flask ${FLASK_VER} déjà installé"
    fi

    # Arrêter une ancienne instance Flask si elle tourne
    if [ -f "$FLASK_PID" ]; then
      OLD_PID=$(cat "$FLASK_PID")
      if kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        inf "Ancienne instance Flask arrêtée (PID ${OLD_PID})"
        sleep 1
      fi
      rm -f "$FLASK_PID"
    fi

    # Vérifier le .env
    if [ ! -f "${BACKEND_DIR}/.env" ]; then
      warn ".env absent — création avec valeurs par défaut"
      cat > "${BACKEND_DIR}/.env" << 'ENVEOF'
FLASK_HOST=0.0.0.0
FLASK_PORT=5005
FLASK_DEBUG=false
OPENSTACK_HOST=192.168.128.130
ENVEOF
    fi

    # Lancer Flask en arrière-plan
    inf "Lancement de Flask..."
    nohup python3 "$APP_FILE" > "$FLASK_LOG" 2>&1 &
    echo $! > "$FLASK_PID"
    sleep 3

    # Vérifier que Flask répond
    FLASK_PORT=$(grep FLASK_PORT "${BACKEND_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "5005")
    if curl -s --max-time 5 "http://localhost:${FLASK_PORT}/api/servers" > /dev/null 2>&1; then
      pass "Flask opérationnel (PID $(cat $FLASK_PID))"
      (( PASS++ )) || true
    else
      warn "Flask démarre encore — vérifier dans 10 secondes"
      warn "Logs : tail -f ${FLASK_LOG}"
    fi
  fi
fi

# ================================================================
#  10. Résumé final
# ================================================================
sep "10. Résumé"

echo ""
echo -e "  ${BOLD}Résultats :${RST}"
echo -e "  ${GRN}✔  Succès       : ${PASS}${RST}"
[[ $WARN -gt 0 ]] && echo -e "  ${YEL}⚠  Avertissements : ${WARN}${RST}"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}✘  Erreurs        : ${FAIL}${RST}"

echo ""
echo -e "  ${BOLD}${CYN}┌──────────────────────────────────────────────────────┐${RST}"
echo -e "  ${BOLD}${CYN}│  URLs de ton infrastructure                          │${RST}"
echo -e "  ${BOLD}${CYN}├──────────────────────────────────────────────────────┤${RST}"
echo -e "  ${BOLD}${CYN}│${RST}  Horizon Dashboard : ${BOLD}https://${VM_IP}/${RST}"
echo -e "  ${BOLD}${CYN}│${RST}  Flask API         : ${BOLD}http://${VM_IP}:5005/api/servers${RST}"
echo -e "  ${BOLD}${CYN}│${RST}  Flask API images  : ${BOLD}http://${VM_IP}:5005/api/images${RST}"
echo -e "  ${BOLD}${CYN}│${RST}  Kong Gateway      : ${BOLD}http://192.168.128.131:8000/api/servers${RST}"
echo -e "  ${BOLD}${CYN}│${RST}  Dashboard Web     : ${BOLD}http://192.168.128.131:8080${RST}"
echo -e "  ${BOLD}${CYN}├──────────────────────────────────────────────────────┤${RST}"
echo -e "  ${BOLD}${CYN}│${RST}  Flask logs   : tail -f ${FLASK_LOG}"
echo -e "  ${BOLD}${CYN}│${RST}  Flask stop   : kill \$(cat ${FLASK_PID})"
echo -e "  ${BOLD}${CYN}│${RST}  Flask start  : bash ~/start.sh"
echo -e "  ${BOLD}${CYN}└──────────────────────────────────────────────────────┘${RST}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "${BOLD}${GRN}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${GRN}║   ✔  Infrastructure opérationnelle — Bonne session !     ║${RST}"
  echo -e "${BOLD}${GRN}╚══════════════════════════════════════════════════════════╝${RST}"
else
  echo -e "${BOLD}${YEL}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${YEL}║   ⚠  Démarrage avec avertissements — voir ci-dessus      ║${RST}"
  echo -e "${BOLD}${YEL}╚══════════════════════════════════════════════════════════╝${RST}"
fi
echo ""
