#!/usr/bin/env bash
# ================================================================
#  start.sh — Démarrage complet de la VM OpenStack + Cluster K8s
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
#  10. Valide la connectivité ping + SSH du cluster K8s migré
#  11. Menu interactif de connexion SSH
#  12. Résumé final avec toutes les URLs
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
SSH_KEY="$HOME/.ssh/id_rsa"

# ── Inventaire du cluster K8s migré ──────────────────────────────
# name | user | floating_ip
declare -A K8S_NODES=(
  [master]="user1:10.20.20.141"
  [worker1]="user2:10.20.20.108"
  [worker2]="user3:10.20.20.126"
)
K8S_NODE_ORDER=(master worker1 worker2)

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

if [ ! -d "$BACKEND_DIR" ]; then
  fail "Dossier backend introuvable : $BACKEND_DIR"
  warn "Vérifie que le repo est cloné dans ~/cloud-project/"
else
  pass "Dossier backend trouvé : $BACKEND_DIR"
  cd "$BACKEND_DIR"

  if [ ! -f "$APP_FILE" ]; then
    fail "app.py introuvable dans $BACKEND_DIR"
  else
    pass "app.py trouvé"

    if [ ! -d "$VENV_DIR" ]; then
      inf "Création de l'environnement virtuel Python..."
      python3 -m venv "$VENV_DIR"
      pass "Venv créé"
    else
      pass "Venv existant trouvé"
    fi

    source "${VENV_DIR}/bin/activate"

    if ! python3 -c "import flask" 2>/dev/null; then
      inf "Installation des dépendances Python..."
      pip install --quiet flask flask-cors python-dotenv
      pass "Dépendances installées"
    else
      FLASK_VER=$(python3 -c "import importlib.metadata; print(importlib.metadata.version('flask'))" 2>/dev/null || echo "?")
      pass "Flask ${FLASK_VER} déjà installé"
    fi

    if [ -f "$FLASK_PID" ]; then
      OLD_PID=$(cat "$FLASK_PID")
      if kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        inf "Ancienne instance Flask arrêtée (PID ${OLD_PID})"
        sleep 1
      fi
      rm -f "$FLASK_PID"
    fi

    if [ ! -f "${BACKEND_DIR}/.env" ]; then
      warn ".env absent — création avec valeurs par défaut"
      cat > "${BACKEND_DIR}/.env" << 'ENVEOF'
FLASK_HOST=0.0.0.0
FLASK_PORT=5005
FLASK_DEBUG=false
OPENSTACK_HOST=192.168.128.130
ENVEOF
    fi

    inf "Lancement de Flask..."
    nohup python3 "$APP_FILE" > "$FLASK_LOG" 2>&1 &
    echo $! > "$FLASK_PID"
    sleep 3

    FLASK_PORT=$(grep FLASK_PORT "${BACKEND_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "5005")
    if curl -s --max-time 5 "http://localhost:${FLASK_PORT}/api/servers" > /dev/null 2>&1; then
      pass "Flask opérationnel (PID $(cat $FLASK_PID))"
    else
      warn "Flask démarre encore — vérifier dans 10 secondes"
      warn "Logs : tail -f ${FLASK_LOG}"
    fi
  fi
fi

# ================================================================
#  10. Validation du cluster K8s migré (ping + SSH)
# ================================================================
sep "10. Validation cluster Kubernetes migré (ping + SSH)"

declare -A NODE_REACHABLE

for node in "${K8S_NODE_ORDER[@]}"; do
  entry="${K8S_NODES[$node]}"
  ssh_user="${entry%%:*}"
  ip="${entry##*:}"

  echo ""
  echo -e "  ${BOLD}${CYN}═══ ${node^^} (${ssh_user}@${ip}) ═══${RST}"

  # --- Ping ---
  if ping -c 3 -W 2 "$ip" > /tmp/ping_${node}.log 2>&1; then
    LOSS=$(grep -oP '\d+(?=% packet loss)' /tmp/ping_${node}.log || echo "100")
    if [[ "$LOSS" == "0" ]]; then
      ok "Ping : 0% perte"
    else
      warn "Ping : ${LOSS}% de perte"
    fi
  else
    err "Ping : injoignable"
  fi

  # --- SSH ---
  if [[ -f "$SSH_KEY" ]]; then
    SSH_OUT=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=20 \
      "${ssh_user}@${ip}" "echo '✔ OK' && hostname" 2>&1)
    if echo "$SSH_OUT" | grep -q "✔ OK"; then
      HOSTNAME_REMOTE=$(echo "$SSH_OUT" | tail -1)
      pass "SSH : connecté (hostname distant: ${HOSTNAME_REMOTE})"
      NODE_REACHABLE[$node]="OK"
    else
      fail "SSH : échec — ${SSH_OUT}"
      NODE_REACHABLE[$node]="FAIL"
    fi
  else
    warn "Clé SSH introuvable : $SSH_KEY"
    NODE_REACHABLE[$node]="NO_KEY"
  fi
done

echo ""
echo -e "  ${BOLD}── Résumé validation cluster ──${RST}"
for node in "${K8S_NODE_ORDER[@]}"; do
  status="${NODE_REACHABLE[$node]:-INCONNU}"
  case "$status" in
    OK)   echo -e "  ${GRN}●${RST} ${node} : ${GRN}opérationnel${RST}" ;;
    FAIL) echo -e "  ${RED}●${RST} ${node} : ${RED}injoignable${RST}" ;;
    *)    echo -e "  ${YEL}●${RST} ${node} : ${YEL}${status}${RST}" ;;
  esac
done

# ================================================================
#  11. Menu interactif de connexion SSH
# ================================================================
sep "11. Connexion SSH au cluster"

ssh_menu() {
  while true; do
    echo ""
    echo -e "  ${BOLD}${CYN}┌─────────────────────────────────────────┐${RST}"
    echo -e "  ${BOLD}${CYN}│  Choisir une VM pour connexion SSH      │${RST}"
    echo -e "  ${BOLD}${CYN}├─────────────────────────────────────────┤${RST}"
    local i=1
    local -a menu_nodes=()
    for node in "${K8S_NODE_ORDER[@]}"; do
      entry="${K8S_NODES[$node]}"
      ssh_user="${entry%%:*}"
      ip="${entry##*:}"
      status="${NODE_REACHABLE[$node]:-?}"
      icon="${YEL}?${RST}"
      [[ "$status" == "OK" ]] && icon="${GRN}✔${RST}"
      [[ "$status" == "FAIL" ]] && icon="${RED}✘${RST}"
      printf "  ${BOLD}${CYN}│${RST}  %d) %-10s ${icon} %-10s %-15s ${BOLD}${CYN}│${RST}\n" \
        "$i" "$node" "$ssh_user" "$ip"
      menu_nodes+=("$node")
      ((i++))
    done
    echo -e "  ${BOLD}${CYN}│${RST}  0) Quitter / continuer le script        ${BOLD}${CYN}│${RST}"
    echo -e "  ${BOLD}${CYN}└─────────────────────────────────────────┘${RST}"
    echo ""
    read -rp "  Choix [0-${#menu_nodes[@]}] : " choice

    if [[ "$choice" == "0" || -z "$choice" ]]; then
      inf "Sortie du menu SSH"
      break
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#menu_nodes[@]} )); then
      sel_node="${menu_nodes[$((choice-1))]}"
      entry="${K8S_NODES[$sel_node]}"
      ssh_user="${entry%%:*}"
      ip="${entry##*:}"
      echo ""
      inf "Connexion à ${sel_node} (${ssh_user}@${ip})…"
      echo -e "  ${DIM}(tape 'exit' pour revenir au menu)${RST}"
      echo ""
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${ssh_user}@${ip}"
    else
      warn "Choix invalide"
    fi
  done
}

read -rp "  Souhaites-tu te connecter en SSH à une VM maintenant ? [y/N] " want_ssh
if [[ "$want_ssh" =~ ^[Yy]$ ]]; then
  ssh_menu
else
  skip "Menu SSH ignoré"
fi

# ================================================================
#  12. Résumé final
# ================================================================
sep "12. Résumé"

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
echo -e "  ${BOLD}${CYN}├──────────────────────────────────────────────────────┤${RST}"
echo -e "  ${BOLD}${CYN}│  Cluster Kubernetes migré                            │${RST}"
for node in "${K8S_NODE_ORDER[@]}"; do
  entry="${K8S_NODES[$node]}"
  ssh_user="${entry%%:*}"
  ip="${entry##*:}"
  printf "  ${BOLD}${CYN}│${RST}  %-9s ssh -i ~/.ssh/id_rsa %s@%-15s\n" "${node}:" "$ssh_user" "$ip"
done
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
