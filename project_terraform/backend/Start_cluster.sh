#!/usr/bin/env bash
# ================================================================
#  start-cluster.sh — Démarrage du cluster K8s + Flask + validation
#  Place ce fichier dans /home/microstack/
#  Usage manuelle : bash ~/start-cluster.sh
#  Usage automatique : prévu pour être lancé au boot de la VM
#                       (voir section systemd en bas de ce fichier
#                       en commentaire, ou crontab @reboot)
#
#  Ce script fait dans l'ordre :
#   1. Affiche les identifiants Horizon
#   2. Vérifie les services OpenStack
#   3. Affiche les stats hyperviseur
#   4. Affiche l'inventaire complet (instances, réseaux, IPs, etc.)
#   5. Démarre les instances Kubernetes (Nova) si elles sont éteintes,
#      en attendant activement que le port SSH réponde
#   6. Démarre Flask (API Backend)
#   7. Valide la connectivité ping + SSH du cluster K8s migré
#   8. Menu interactif de connexion SSH (ignoré automatiquement
#      si le script tourne sans terminal, ex: au boot via systemd)
#   9. Résumé final avec toutes les URLs
#
#  Pré-requis : MicroStack doit déjà être opérationnel.
#  En cas de problème MicroStack/Internet, lancer d'abord :
#      bash ~/microstack-repair.sh
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
  echo ""
  echo -e "${BOLD}${CYN}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${CYN}║     Cloud Privé OSS — Démarrage du Cluster K8s            ║${RST}"
  echo -e "${BOLD}${CYN}║     Instances Nova + Flask API                            ║${RST}"
  echo -e "${BOLD}${CYN}╚══════════════════════════════════════════════════════════╝${RST}"
  echo -e "  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RST}"
  echo ""
}

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
declare -A K8S_NODES=(
  [master]="user1:10.20.20.141"
  [worker1]="user2:10.20.20.108"
  [worker2]="user3:10.20.20.126"
)
K8S_NODE_ORDER=(master worker1 worker2)

declare -A NODE_VM_NAME=(
  [master]="k8s-master"
  [worker1]="k8s-worker1"
  [worker2]="k8s-worker2"
)

# Détecte si le script tourne dans un vrai terminal interactif
# (faux par exemple quand systemd ou cron @reboot le lance)
IS_INTERACTIVE=false
[[ -t 0 ]] && IS_INTERACTIVE=true

# ================================================================
banner

# ================================================================
#  1. Identifiants Horizon Dashboard
# ================================================================
sep "1. Identifiants Dashboard Horizon"

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
  warn "Mot de passe Keystone non disponible — lancer microstack-repair.sh si besoin"
fi

# ================================================================
#  2. Services OpenStack
# ================================================================
sep "2. Services OpenStack"

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
#  3. Statistiques Hyperviseur
# ================================================================
sep "3. Hyperviseur Nova"

echo ""
if sudo microstack.openstack hypervisor stats show 2>/dev/null; then
  pass "Statistiques hyperviseur OK"
else
  warn "hypervisor stats show indisponible"
fi

# ================================================================
#  4. Inventaire OpenStack
# ================================================================
sep "4. Inventaire OpenStack"

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
#  5. Démarrage des instances Kubernetes (Nova)
# ================================================================
sep "5. Démarrage des instances Kubernetes"

# Démarre une instance Nova si elle n'est pas déjà ACTIVE,
# puis attend (avec timeout) qu'elle passe à l'état ACTIVE.
start_instance() {
  local vm_name="$1"
  local status
  status=$(sudo microstack.openstack server show "$vm_name" -f value -c status 2>/dev/null)

  if [[ -z "$status" ]]; then
    fail "Instance ${vm_name} introuvable"
    return 1
  fi

  if [[ "$status" == "ACTIVE" ]]; then
    pass "${vm_name} déjà ACTIVE"
    return 0
  fi

  inf "Démarrage de ${vm_name} (état actuel : ${status})..."
  if ! sudo microstack.openstack server start "$vm_name" 2>/dev/null; then
    warn "Commande 'server start' renvoyée en erreur pour ${vm_name} (peut être normal si déjà en transition)"
  fi

  local tries=0
  local max_tries=20   # 20 x 3s = 60s max d'attente par instance
  while (( tries < max_tries )); do
    status=$(sudo microstack.openstack server show "$vm_name" -f value -c status 2>/dev/null)
    if [[ "$status" == "ACTIVE" ]]; then
      pass "${vm_name} est ACTIVE"
      return 0
    fi
    if [[ "$status" == "ERROR" ]]; then
      fail "${vm_name} est passé en état ERROR"
      return 1
    fi
    sleep 3
    ((tries++))
  done

  fail "${vm_name} n'est pas passé à ACTIVE après $(( max_tries * 3 ))s (dernier état : ${status})"
  return 1
}

# Poll actif sur le port TCP donné jusqu'à ce qu'il réponde, ou jusqu'au timeout.
# Plus fiable qu'une pause fixe : certaines VMs (ex: master k8s) mettent
# largement plus de temps que d'autres avant que sshd accepte des connexions.
wait_for_port() {
  local ip="$1"
  local port="${2:-22}"
  local max_wait="${3:-180}"   # secondes, 3 minutes max par VM par défaut
  local interval=5
  local elapsed=0

  while (( elapsed < max_wait )); do
    if timeout 2 bash -c "echo > /dev/tcp/${ip}/${port}" 2>/dev/null; then
      return 0
    fi
    sleep "$interval"
    (( elapsed += interval ))
    if (( elapsed % 15 == 0 )); then
      echo -ne "  ${DIM}... toujours en attente (${elapsed}s/${max_wait}s)${RST}\r"
    fi
  done
  echo ""
  return 1
}

for node in "${K8S_NODE_ORDER[@]}"; do
  vm_name="${NODE_VM_NAME[$node]}"
  entry="${K8S_NODES[$node]}"
  node_ip="${entry##*:}"

  echo ""
  echo -e "  ${BOLD}${CYN}── ${node} (${vm_name}) ──${RST}"

  if start_instance "$vm_name"; then
    inf "Attente de la disponibilité SSH (port 22) sur ${node_ip}..."
    if wait_for_port "$node_ip" 22 180; then
      pass "${node} : port 22 disponible sur ${node_ip}"
    else
      warn "${node} : port 22 toujours fermé sur ${node_ip} après 180s — la validation suivante pourra échouer"
    fi
  else
    warn "${node} : démarrage non confirmé, vérification SSH ignorée pour cette VM"
  fi
done

# ================================================================
#  6. Démarrage Flask (API Backend)
# ================================================================
sep "6. Démarrage Flask API Backend"

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

    if [ ! -d "$VENV_DIR" ] || [ ! -f "${VENV_DIR}/bin/activate" ]; then
      if [ -d "$VENV_DIR" ]; then
        warn "Venv existant mais incomplet (bin/activate manquant) — recréation..."
        rm -rf "$VENV_DIR"
      fi
      inf "Création de l'environnement virtuel Python..."
      python3 -m venv "$VENV_DIR"
      if [ -f "${VENV_DIR}/bin/activate" ]; then
        pass "Venv créé"
      else
        fail "Création du venv échouée (bin/activate toujours absent) — vérifier : sudo apt install python3-venv"
      fi
    else
      pass "Venv existant trouvé"
    fi

    if [ -f "${VENV_DIR}/bin/activate" ]; then
      source "${VENV_DIR}/bin/activate"
    else
      warn "Utilisation du python3 système en repli (hors venv)"
    fi

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
      cat > "${BACKEND_DIR}/.env" << ENVEOF
FLASK_HOST=0.0.0.0
FLASK_PORT=5005
FLASK_DEBUG=false
OPENSTACK_HOST=${VM_IP}
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
#  7. Validation du cluster K8s migré (ping + SSH)
# ================================================================
sep "7. Validation cluster Kubernetes migré (ping + SSH)"

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

  # --- SSH (avec une seconde tentative en cas d'échec) ---
  if [[ -f "$SSH_KEY" ]]; then
    SSH_OUT=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=20 \
      "${ssh_user}@${ip}" "echo '✔ OK' && hostname" 2>&1)

    if ! echo "$SSH_OUT" | grep -q "✔ OK"; then
      warn "SSH : première tentative échouée, nouvel essai dans 15s..."
      sleep 15
      SSH_OUT=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=20 \
        "${ssh_user}@${ip}" "echo '✔ OK' && hostname" 2>&1)
    fi

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
#  8. Menu interactif de connexion SSH
#      (ignoré automatiquement si pas de terminal interactif,
#       ex: lancé via systemd ou cron @reboot au démarrage de la VM)
# ================================================================
sep "8. Connexion SSH au cluster"

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

if [[ "$IS_INTERACTIVE" == true ]]; then
  read -rp "  Souhaites-tu te connecter en SSH à une VM maintenant ? [y/N] " want_ssh
  if [[ "$want_ssh" =~ ^[Yy]$ ]]; then
    ssh_menu
  else
    skip "Menu SSH ignoré"
  fi
else
  skip "Menu SSH ignoré (exécution non interactive — probablement lancé au boot)"
fi

# ================================================================
#  9. Résumé final
# ================================================================
sep "9. Résumé"

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
echo -e "  ${BOLD}${CYN}├──────────────────────────────────────────────────────┤${RST}"
echo -e "  ${BOLD}${CYN}│${RST}  Flask logs   : tail -f ${FLASK_LOG}"
echo -e "  ${BOLD}${CYN}│${RST}  Flask stop   : kill \$(cat ${FLASK_PID})"
echo -e "  ${BOLD}${CYN}│${RST}  Flask start  : bash ~/start-cluster.sh"
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
  echo -e "${BOLD}${GRN}║   ✔  Cluster opérationnel — Bonne session !              ║${RST}"
  echo -e "${BOLD}${GRN}╚══════════════════════════════════════════════════════════╝${RST}"
else
  echo -e "${BOLD}${YEL}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${YEL}║   ⚠  Démarrage avec avertissements — voir ci-dessus       ║${RST}"
  echo -e "${BOLD}${YEL}╚══════════════════════════════════════════════════════════╝${RST}"
fi
echo ""

# ================================================================
#  Pour lancer ce script automatiquement à l'ouverture de la VM :
#
#  Option 1 — systemd (recommandé) :
#    sudo tee /etc/systemd/system/start-cluster.service << 'UNIT'
#    [Unit]
#    Description=Démarrage automatique du cluster K8s OpenStack
#    After=network-online.target snapd.service
#    Wants=network-online.target
#
#    [Service]
#    Type=oneshot
#    User=microstack
#    ExecStart=/bin/bash /home/microstack/start-cluster.sh
#    StandardOutput=append:/var/log/start-cluster.log
#    StandardError=append:/var/log/start-cluster.log
#
#    [Install]
#    WantedBy=multi-user.target
#    UNIT
#    sudo systemctl daemon-reload
#    sudo systemctl enable start-cluster.service
#
#  Option 2 — crontab @reboot (plus simple) :
#    crontab -e
#    @reboot sleep 30 && /bin/bash /home/microstack/start-cluster.sh >> /var/log/start-cluster.log 2>&1
# ================================================================
