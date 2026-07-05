#!/usr/bin/env bash
# ================================================================
#  fix-vm-internet.sh — Diagnostic + correction de l'accès Internet
#                        pour les VMs OpenStack (floating IP -> ens33)
#
#  Contexte : depuis que ens33 a été détaché du bridge OVS (br-ex)
#  pour récupérer SSH (voir conversation précédente), le chemin
#  10.20.20.0/24 -> ens33 -> VMware NAT -> Internet n'a plus de
#  règle de translation d'adresse (MASQUERADE) côté noyau Linux.
#  Résultat : les floating IP fonctionnent en local (host <-> VM)
#  mais aucune VM ne peut atteindre l'Internet réel.
#
#  Usage : sudo bash fix-vm-internet.sh [--apply]
#    (sans --apply : diagnostic seul, n'effectue aucune modification)
# ================================================================
set -uo pipefail

GRN='\033[0;32m'; YEL='\033[1;33m'; RED='\033[0;31m'; CYN='\033[0;36m'; RST='\033[0m'
ok()  { echo -e "  ${GRN}✔${RST}  $*"; }
war() { echo -e "  ${YEL}⚠${RST}  $*"; }
inf() { echo -e "  ${CYN}ℹ${RST}  $*"; }
err() { echo -e "  ${RED}✘${RST}  $*"; }

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

EXT_NET_CIDR="10.20.20.0/24"   # adapter si votre réseau "external" diffère
UPLINK_IF="ens33"               # interface physique avec sortie Internet réelle

echo ""
echo -e "${CYN}══════════════════════════════════════════${RST}"
echo -e "${CYN}  Diagnostic accès Internet des VMs OpenStack${RST}"
echo -e "${CYN}══════════════════════════════════════════${RST}"
echo ""

# ── 1. ip_forward ────────────────────────────────────────────────
inf "Vérification de net.ipv4.ip_forward..."
FWD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
if [[ "$FWD" == "1" ]]; then
  ok "ip_forward déjà activé"
else
  war "ip_forward désactivé (valeur: ${FWD})"
  if $APPLY; then
    sysctl -w net.ipv4.ip_forward=1
    grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf 2>/dev/null \
      && sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf \
      || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    ok "ip_forward activé et persisté dans /etc/sysctl.conf"
  fi
fi

# ── 2. Règle MASQUERADE pour le réseau external OVN ──────────────
echo ""
inf "Vérification de la règle MASQUERADE pour ${EXT_NET_CIDR} -> ${UPLINK_IF}..."
if iptables -t nat -C POSTROUTING -s "$EXT_NET_CIDR" -o "$UPLINK_IF" -j MASQUERADE 2>/dev/null; then
  ok "Règle MASQUERADE déjà présente"
else
  war "Règle MASQUERADE absente pour ${EXT_NET_CIDR} -> ${UPLINK_IF}"
  if $APPLY; then
    iptables -t nat -A POSTROUTING -s "$EXT_NET_CIDR" -o "$UPLINK_IF" -j MASQUERADE
    ok "Règle MASQUERADE ajoutée"

    if command -v netfilter-persistent &>/dev/null; then
      netfilter-persistent save
      ok "Règles iptables persistées (netfilter-persistent)"
    else
      war "netfilter-persistent non installé — la règle ne survivra PAS à un reboot"
      war "Pour la rendre permanente : sudo apt-get install -y iptables-persistent && sudo netfilter-persistent save"
    fi
  fi
fi

# ── 3. Vérification de la route et de l'interface uplink ─────────
echo ""
inf "Vérification de l'interface ${UPLINK_IF}..."
if ip addr show "$UPLINK_IF" 2>/dev/null | grep -q "inet "; then
  ok "${UPLINK_IF} a une IP active"
else
  err "${UPLINK_IF} n'a pas d'IP — vérifier la config réseau du host avant de continuer"
fi

# ── 4. Test réel depuis le host (référence) ───────────────────────
echo ""
inf "Test ping 8.8.8.8 depuis le host (référence)..."
if ping -c2 -W2 8.8.8.8 &>/dev/null; then
  ok "Le host a bien Internet (référence OK)"
else
  err "Le host lui-même n'a pas Internet — corriger ça d'abord avant les VMs"
fi

# ── Résumé ─────────────────────────────────────────────────────
echo ""
if $APPLY; then
  echo -e "${GRN}Corrections appliquées. Testez maintenant depuis une VM :${RST}"
  echo -e "  ssh -i ~/.ssh/id_rsa user1@10.20.20.141"
  echo -e "  ping -c3 8.8.8.8"
else
  echo -e "${YEL}Mode diagnostic seul — aucune modification effectuée.${RST}"
  echo -e "Relancez avec : ${BOLD:-}sudo bash fix-vm-internet.sh --apply${RST}"
fi
echo ""
