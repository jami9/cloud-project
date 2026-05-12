#!/usr/bin/env bash
# ================================================================
#  microstack_boot_check.sh
#  Vérification et démarrage automatique de MicroStack au boot
#  Lancer au démarrage de la VM pour s'assurer que OpenStack est prêt
#  Usage : bash microstack_boot_check.sh
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
  local line="────────────────────────────────────────────────────"
  echo ""
  echo -e "${BOLD}${MAG}▶ ${title}${RST}"
  echo -e "${DIM}${line}${RST}"
}

banner() {
  echo ""
  echo -e "${BOLD}${CYN}╔══════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${CYN}║      MicroStack Boot Check — OpenStack Ready         ║${RST}"
  echo -e "${BOLD}${CYN}╚══════════════════════════════════════════════════════╝${RST}"
  echo -e "  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RST}"
  echo ""
}

# ── Compteurs résumé ────────────────────────────────────────────
PASS=0; WARN=0; FAIL=0
pass() { ok "$*";  (( PASS++ )) || true; }
warn() { war "$*"; (( WARN++ )) || true; }
fail() { err "$*"; (( FAIL++ )) || true; }

# ================================================================
#  DÉBUT
# ================================================================
banner

# ================================================================
#  1. Vérifier si MicroStack est installé
# ================================================================
sep "1. Vérification de l'installation MicroStack"

if snap list microstack &>/dev/null 2>&1; then
  SNAP_VER=$(snap list microstack 2>/dev/null | awk 'NR==2{print $2}')
  pass "MicroStack installé — version : ${SNAP_VER}"
else
  fail "MicroStack n'est PAS installé (snap list microstack introuvable)"
  echo ""
  echo -e "  ${YEL}Pour installer MicroStack :${RST}"
  echo "    sudo snap install microstack --devmode --beta"
  echo "    sudo microstack init --auto --control"
  echo ""
  echo -e "  ${RED}Arrêt du script — MicroStack requis.${RST}"
  exit 1
fi

# ================================================================
#  2. Relancer les services MicroStack
# ================================================================
sep "2. Redémarrage des services MicroStack"

inf "Exécution : sudo snap restart microstack ..."
if sudo snap restart microstack 2>/dev/null; then
  pass "snap restart microstack — OK"
else
  warn "snap restart microstack — retour non-zéro (peut être normal)"
fi

inf "Attente de 10 secondes pour la stabilisation des services..."
sleep 10
pass "Services relancés"

# ================================================================
#  3. État des services MicroStack
# ================================================================
sep "3. État des services"

echo ""
printf "  ${BOLD}%-50s %-12s %-10s${RST}\n" "SERVICE" "ACTIVÉ" "ÉTAT"
printf "  ${DIM}%s${RST}\n" "$(printf '─%.0s' {1..75})"

snap services microstack 2>/dev/null | tail -n +2 | while IFS= read -r line; do
  SVC=$(echo "$line"  | awk '{print $1}')
  ENA=$(echo "$line"  | awk '{print $2}')
  STA=$(echo "$line"  | awk '{print $3}')
  case "$STA" in
    active)   COLOR="${GRN}" ICON="●" ;;
    inactive) COLOR="${RED}" ICON="○" ;;
    *)        COLOR="${YEL}" ICON="?" ;;
  esac
  printf "  ${COLOR}${ICON}${RST} %-49s %-12s ${COLOR}%-10s${RST}\n" "$SVC" "$ENA" "$STA"
done

echo ""

# ================================================================
#  4. Token OpenStack
# ================================================================
sep "4. Token OpenStack (Keystone)"

# Tentative avec microstack.openstack
if TOKEN=$(sudo microstack.openstack token issue -f value -c id 2>/dev/null | head -1) && [[ -n "$TOKEN" ]]; then
  pass "Token généré avec microstack.openstack"
  echo -e "  ${DIM}Token (20 premiers cars) : ${TOKEN:0:20}...${RST}"
else
  warn "microstack.openstack token issue échoué"

  # Fallback : admin-openrc.sh classique
  OPENRC="${HOME}/admin-openrc.sh"
  if [[ -f "$OPENRC" ]]; then
    inf "Chargement de ${OPENRC} ..."
    # shellcheck source=/dev/null
    source "$OPENRC"
    if openstack --insecure token issue &>/dev/null 2>&1; then
      pass "Token généré via admin-openrc.sh"
    else
      fail "Impossible de générer un token — Keystone inaccessible"
    fi
  else
    skip "admin-openrc.sh absent : ${OPENRC} (non bloquant)"
  fi
fi

# ================================================================
#  5. Récupérer le mot de passe Keystone
# ================================================================
sep "5. Identifiants Dashboard (Horizon)"

KS_PASS=$(sudo snap get microstack config.credentials.keystone-password 2>/dev/null || echo "")
VM_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

if [[ -n "$KS_PASS" ]]; then
  pass "Mot de passe Keystone récupéré"
  echo ""
  echo -e "  ${BOLD}Dashboard Horizon :${RST}  http://${VM_IP}/"
  echo -e "  ${BOLD}Username          :${RST}  admin"
  echo -e "  ${BOLD}Password          :${RST}  ${KS_PASS}"
  echo ""
else
  warn "Impossible de récupérer le mot de passe Keystone"
fi

# ================================================================
#  6. Catalogue des services OpenStack
# ================================================================
sep "6. Services OpenStack"

echo ""
if sudo microstack.openstack service list 2>/dev/null; then
  echo ""
  pass "Liste des services récupérée"
else
  fail "Impossible de lister les services — OpenStack inaccessible"
fi

# Services attendus
EXPECTED_SERVICES=("nova" "neutron" "glance" "keystone" "placement" "cinderv3")
echo ""
inf "Vérification des services essentiels :"
for SVC in "${EXPECTED_SERVICES[@]}"; do
  if sudo microstack.openstack service list 2>/dev/null | grep -qi "$SVC"; then
    pass "  $SVC"
  else
    warn "  $SVC — absent ou non enregistré"
  fi
done

# ================================================================
#  7. Statistiques Hyperviseur
# ================================================================
sep "7. Hyperviseur"

echo ""
sudo microstack.openstack hypervisor stats show 2>/dev/null \
  && pass "Statistiques hyperviseur OK" \
  || warn "hypervisor stats show indisponible"

# ================================================================
#  8. Inventaire complet
# ================================================================
sep "8. Inventaire OpenStack"

run_cmd() {
  local label="$1"; shift
  echo ""
  echo -e "  ${BOLD}${CYN}── $label ──${RST}"
  if sudo microstack.openstack "$@" 2>/dev/null; then
    : # succès silencieux
  else
    echo -e "  ${YEL}(aucun résultat ou erreur)${RST}"
  fi
}

run_cmd "Projets"              project list
run_cmd "Utilisateurs"         user list
run_cmd "Rôles"                role list
run_cmd "Instances"            server list
run_cmd "Réseaux"              network list
run_cmd "Sous-réseaux"         subnet list
run_cmd "Routeurs"             router list
run_cmd "IPs flottantes"       floating ip list
run_cmd "Ports"                port list
run_cmd "Groupes de sécurité"  security group list
run_cmd "Règles de sécu."      security group rule list

# ================================================================
#  9. Résumé final
# ================================================================
sep "9. Résumé"

echo ""
echo -e "  ${BOLD}Résultats :${RST}"
echo -e "  ${GRN}✔  Succès  : ${PASS}${RST}"
[[ $WARN -gt 0 ]] && echo -e "  ${YEL}⚠  Avertissements : ${WARN}${RST}"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}✘  Erreurs : ${FAIL}${RST}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "${BOLD}${GRN}╔══════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${GRN}║    ✔  MicroStack est OPÉRATIONNEL — Bonne session !  ║${RST}"
  echo -e "${BOLD}${GRN}╚══════════════════════════════════════════════════════╝${RST}"
else
  echo -e "${BOLD}${RED}╔══════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${RED}║    ✘  Des erreurs ont été détectées — voir ci-dessus  ║${RST}"
  echo -e "${BOLD}${RED}╚══════════════════════════════════════════════════════╝${RST}"
fi
echo ""
