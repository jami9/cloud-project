#!/usr/bin/env bash
# ================================================================
#  microstack-repair.sh — Outil de diagnostic / réparation MicroStack
#  Place ce fichier dans /home/microstack/
#  Usage : bash ~/microstack-repair.sh
#
#  À lancer MANUELLEMENT quand quelque chose ne fonctionne pas :
#   1. Vérifie que MicroStack est installé
#   2. Redémarre les services MicroStack
#   3. Affiche l'état des services
#   4. Vérifie/régénère le token Keystone
#   5. Diagnostique ET corrige l'accès Internet des VMs OpenStack
#      (ip_forward, NAT/MASQUERADE, SNAT du routeur, security groups)
#   6. Résumé
#
#  Le démarrage des VMs K8s, Flask, et la validation se trouvent
#  dans le second script : start-cluster.sh (prévu pour le boot).
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
  local title="$*"
  echo ""
  echo -e "${BOLD}${MAG}▶ ${title}${RST}"
  echo -e "${DIM}────────────────────────────────────────────────────${RST}"
}

banner() {
  clear
  echo ""
  echo -e "${BOLD}${CYN}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${CYN}║     MicroStack — Diagnostic & Réparation                 ║${RST}"
  echo -e "${BOLD}${CYN}╚══════════════════════════════════════════════════════════╝${RST}"
  echo -e "  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RST}"
  echo ""
}

PASS=0; WARN=0; FAIL=0
pass() { ok "$*";  (( PASS++ )) || true; }
warn() { war "$*"; (( WARN++ )) || true; }
fail() { err "$*"; (( FAIL++ )) || true; }

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
  echo ""
  echo -e "  ${YEL}Pistes de résolution :${RST}"
  echo "    sudo snap logs microstack.keystone-uwsgi -n 50"
  echo "    sudo snap restart microstack.keystone-uwsgi"
fi

# ================================================================
#  5. Connectivité Internet des VMs (NAT / Forwarding / Sécurité)
# ================================================================
sep "5. Connectivité Internet des VMs (NAT / Forwarding / Sécurité)"

# 5.1 — Détecter l'interface de sortie réelle vers Internet
EGRESS_IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}')
if [[ -z "$EGRESS_IFACE" ]]; then
  fail "Impossible de déterminer l'interface de sortie Internet du host — vérifier la route par défaut (ip route)"
else
  pass "Interface de sortie Internet détectée : ${EGRESS_IFACE}"
fi

# 5.2 — IP forwarding
CURRENT_FWD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
if [[ "$CURRENT_FWD" == "1" ]]; then
  pass "IP forwarding (net.ipv4.ip_forward) déjà activé"
else
  warn "IP forwarding désactivé — activation..."
  sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
  if ! grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf >/dev/null
  fi
  pass "IP forwarding activé et persisté dans /etc/sysctl.conf"
fi

# 5.3 — Découvrir le(s) CIDR du réseau externe OpenStack
EXTERNAL_NET_CIDRS=""
EXT_SUBNETS=$(sudo microstack.openstack subnet list --network external -f value -c Subnet 2>/dev/null)
if [[ -n "$EXT_SUBNETS" ]]; then
  for SUB in $EXT_SUBNETS; do
    CIDR=$(sudo microstack.openstack subnet show "$SUB" -f value -c cidr 2>/dev/null)
    [[ -n "$CIDR" ]] && EXTERNAL_NET_CIDRS+="$CIDR "
  done
fi
if [[ -z "$EXTERNAL_NET_CIDRS" ]]; then
  warn "CIDR du réseau externe non détecté automatiquement — utilisation de la valeur connue 10.20.20.0/24"
  EXTERNAL_NET_CIDRS="10.20.20.0/24"
else
  pass "CIDR(s) externe(s) détecté(s) : ${EXTERNAL_NET_CIDRS}"
fi

# 5.4 — Règle MASQUERADE pour chaque CIDR externe
if [[ -n "$EGRESS_IFACE" ]]; then
  for CIDR in $EXTERNAL_NET_CIDRS; do
    if sudo iptables -t nat -C POSTROUTING -s "$CIDR" -o "$EGRESS_IFACE" -j MASQUERADE 2>/dev/null; then
      pass "Règle MASQUERADE déjà présente : ${CIDR} → ${EGRESS_IFACE}"
    else
      warn "Règle MASQUERADE absente pour ${CIDR} — ajout..."
      if sudo iptables -t nat -A POSTROUTING -s "$CIDR" -o "$EGRESS_IFACE" -j MASQUERADE; then
        pass "Règle MASQUERADE ajoutée : ${CIDR} → ${EGRESS_IFACE}"
      else
        fail "Échec de l'ajout de la règle MASQUERADE pour ${CIDR}"
      fi
    fi
  done
else
  warn "Étape MASQUERADE ignorée (interface de sortie inconnue)"
fi

# 5.5 — Politique de la chaîne FORWARD
FWD_POLICY=$(sudo iptables -L FORWARD -n 2>/dev/null | head -1 | grep -oP '(?<=policy )\w+')
if [[ "$FWD_POLICY" == "DROP" || "$FWD_POLICY" == "REJECT" ]]; then
  warn "Politique FORWARD = ${FWD_POLICY} — ajout d'une règle ACCEPT large (à restreindre en prod)"
  sudo iptables -I FORWARD -j ACCEPT
  pass "Règle FORWARD ACCEPT ajoutée"
else
  pass "Politique FORWARD : ${FWD_POLICY:-ACCEPT (par défaut)} — OK"
fi

# 5.6 — Service microstack.external-bridge (gère normalement ce NAT automatiquement)
EB_STATUS=$(snap services microstack.external-bridge 2>/dev/null | tail -1 | awk '{print $3}')
inf "État du service microstack.external-bridge : ${EB_STATUS:-inconnu}"
if [[ "$EB_STATUS" != "active" ]]; then
  inf "Tentative de relance pour ré-appliquer sa configuration réseau..."
  if sudo snap restart microstack.external-bridge 2>/dev/null; then
    pass "external-bridge relancé"
  else
    warn "Impossible de relancer external-bridge (normal si service de type oneshot déjà exécuté)"
  fi
fi

# 5.7 — Vérifier / activer le SNAT sur le(s) routeur(s) Neutron
ROUTERS=$(sudo microstack.openstack router list -f value -c Name 2>/dev/null)
if [[ -z "$ROUTERS" ]]; then
  warn "Aucun routeur Neutron trouvé"
else
  while IFS= read -r RTR; do
    [[ -z "$RTR" ]] && continue
    ROUTER_JSON=$(sudo microstack.openstack router show "$RTR" -f json 2>/dev/null)
    SNAT=$(echo "$ROUTER_JSON" | grep -oP '"enable_snat":\s*\K(true|false)')
    if [[ "$SNAT" == "true" ]]; then
      pass "Routeur '${RTR}' : SNAT déjà activé"
    elif [[ "$SNAT" == "false" ]]; then
      warn "Routeur '${RTR}' : SNAT désactivé — activation..."
      if sudo microstack.openstack router set --enable-snat "$RTR" 2>/dev/null; then
        pass "SNAT activé sur '${RTR}'"
      else
        fail "Échec de l'activation du SNAT sur '${RTR}'"
      fi
    else
      warn "Routeur '${RTR}' : état SNAT indéterminé (pas de passerelle externe configurée ?)"
    fi
  done <<< "$ROUTERS"
fi

# 5.8 — Vérifier les règles d'egress des security groups
SEC_GROUPS=$(sudo microstack.openstack security group list -f value -c Name 2>/dev/null)
if [[ -z "$SEC_GROUPS" ]]; then
  warn "Aucun security group trouvé"
else
  while IFS= read -r SG; do
    [[ -z "$SG" ]] && continue
    EGRESS_RULE=$(sudo microstack.openstack security group rule list "$SG" -f value 2>/dev/null | grep -i "egress" | grep -E "0\.0\.0\.0/0")
    if [[ -n "$EGRESS_RULE" ]]; then
      pass "Security group '${SG}' : règle egress 0.0.0.0/0 présente"
    else
      warn "Security group '${SG}' : aucune règle egress 0.0.0.0/0 trouvée — ajout..."
      if sudo microstack.openstack security group rule create --egress --ethertype IPv4 --remote-ip 0.0.0.0/0 "$SG" 2>/dev/null; then
        pass "Règle egress IPv4 ajoutée sur '${SG}'"
      else
        warn "Échec de l'ajout (la règle existe peut-être déjà sous une autre forme)"
      fi
    fi
  done <<< "$SEC_GROUPS"
fi

inf "Test final recommandé : connecte-toi en SSH à une VM puis lance 'ping -c3 8.8.8.8'"

# ================================================================
#  6. Résumé
# ================================================================
sep "6. Résumé"

echo ""
echo -e "  ${BOLD}Résultats :${RST}"
echo -e "  ${GRN}✔  Succès         : ${PASS}${RST}"
[[ $WARN -gt 0 ]] && echo -e "  ${YEL}⚠  Avertissements : ${WARN}${RST}"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}✘  Erreurs        : ${FAIL}${RST}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "${BOLD}${GRN}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${GRN}║   ✔  MicroStack opérationnel — Internet OK côté host     ║${RST}"
  echo -e "${BOLD}${GRN}╚══════════════════════════════════════════════════════════╝${RST}"
else
  echo -e "${BOLD}${YEL}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${BOLD}${YEL}║   ⚠  Réparation terminée avec des erreurs — voir ci-dessus║${RST}"
  echo -e "${BOLD}${YEL}╚══════════════════════════════════════════════════════════╝${RST}"
fi
echo ""
echo -e "  ${DIM}Prochaine étape : bash ~/start-cluster.sh pour démarrer les VMs K8s${RST}"
echo ""
