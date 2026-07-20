#!/usr/bin/env bash
#
# monitoring.sh — Automatise l'accès à Prometheus/Grafana (port-forward + ouverture
# du navigateur) et le nettoyage des fichiers de manifestes obsolètes sur api-gateway.
#
# Usage :
#   ./monitoring.sh start    # démarre les port-forwards et ouvre/affiche les URLs
#   ./monitoring.sh stop     # arrête les port-forwards en arrière-plan
#   ./monitoring.sh status   # indique si Prometheus/Grafana sont accessibles
#   ./monitoring.sh clean    # supprime les manifestes YAML devenus inutiles
#
set -euo pipefail

NAMESPACE="monitoring"
PROM_SVC="prometheus"
GRAF_SVC="grafana"
PROM_PORT=9090
GRAF_PORT=3000
PID_DIR="${HOME}/.monitoring-portforward"
mkdir -p "${PID_DIR}"

# ---------------------------------------------------------------------------
# Adresse IP de la VM api-gateway (celle utilisée dans les sessions précédentes)
# ---------------------------------------------------------------------------
vm_ip() {
  hostname -I | awk '{print $1}'
}

# ---------------------------------------------------------------------------
# Vérifie qu'un port local répond, sans dépendre de nc/curl (utilise /dev/tcp)
# ---------------------------------------------------------------------------
is_port_open() {
  local port="$1"
  (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null && exec 3>&- 3<&-
}

wait_for_port() {
  local port="$1" tries=0
  until is_port_open "${port}"; do
    tries=$((tries + 1))
    if [ "${tries}" -ge 30 ]; then
      echo "  ! Le port ${port} ne répond toujours pas après 15s." >&2
      return 1
    fi
    sleep 0.5
  done
}

# ---------------------------------------------------------------------------
# Ouvre l'URL automatiquement si un ouvreur graphique existe, sinon la copie
# dans le presse-papiers si possible, et l'affiche systématiquement.
# ---------------------------------------------------------------------------
open_url() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "${url}" >/dev/null 2>&1 &
  elif command -v wslview >/dev/null 2>&1; then
    wslview "${url}" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then
    open "${url}" >/dev/null 2>&1 &
  fi
  if command -v xclip >/dev/null 2>&1; then
    printf '%s' "${url}" | xclip -selection clipboard
    echo "    (URL copiée dans le presse-papiers)"
  elif command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "${url}" | wl-copy
    echo "    (URL copiée dans le presse-papiers)"
  fi
  echo "    -> ${url}"
}

# ---------------------------------------------------------------------------
# Démarre un port-forward en tâche de fond avec suivi de PID (idempotent)
# ---------------------------------------------------------------------------
start_forward() {
  local svc="$1" port="$2" name="$3"
  local pidfile="${PID_DIR}/${name}.pid"

  if [ -f "${pidfile}" ] && kill -0 "$(cat "${pidfile}")" 2>/dev/null; then
    echo "[${name}] déjà actif (PID $(cat "${pidfile}"))."
    return 0
  fi

  nohup kubectl port-forward --address 0.0.0.0 -n "${NAMESPACE}" "svc/${svc}" "${port}:${port}" \
    >"${PID_DIR}/${name}.log" 2>&1 &
  echo $! > "${pidfile}"

  echo "[${name}] port-forward démarré (PID $(cat "${pidfile}")), attente de disponibilité..."
  wait_for_port "${port}"
}

stop_forward() {
  local name="$1"
  local pidfile="${PID_DIR}/${name}.pid"
  if [ -f "${pidfile}" ]; then
    kill "$(cat "${pidfile}")" 2>/dev/null || true
    rm -f "${pidfile}"
    echo "[${name}] arrêté."
  else
    echo "[${name}] aucun processus actif."
  fi
}

status_forward() {
  local name="$1" port="$2"
  local pidfile="${PID_DIR}/${name}.pid"
  if [ -f "${pidfile}" ] && kill -0 "$(cat "${pidfile}")" 2>/dev/null && is_port_open "${port}"; then
    echo "[${name}] actif  (PID $(cat "${pidfile}"), port ${port})"
  else
    echo "[${name}] inactif"
  fi
}

# ---------------------------------------------------------------------------
# Nettoyage des manifestes devenus inutiles (superseded dans la session réelle
# par grafana.yaml, prometheus.yaml, node-exporter.yaml/-service.yaml)
# ---------------------------------------------------------------------------
clean_files() {
  local targets=(
    "grafana-minimal.yaml"     # rejeté par kubectl (apiVersion/kind absents) — remplacé par grafana.yaml
    "prometheus-minimal.yaml"  # jamais appliqué — remplacé par prometheus.yaml
    "values-grafana.yaml"      # fichier de values Helm — abandonné (helm list -n monitoring est vide)
    "values-prometheus.yaml"   # idem, approche Helm non retenue
  )

  echo "Fichiers identifiés comme obsolètes dans ${HOME} :"
  local found=()
  for f in "${targets[@]}"; do
    if [ -f "${HOME}/${f}" ]; then
      echo "  - ${f}"
      found+=("${f}")
    fi
  done

  if [ "${#found[@]}" -eq 0 ]; then
    echo "  (aucun de ces fichiers n'est présent, rien à faire)"
    return 0
  fi

  read -r -p "Confirmer la suppression de ces ${#found[@]} fichier(s) ? [y/N] " confirm
  if [[ "${confirm}" =~ ^[Yy]$ ]]; then
    for f in "${found[@]}"; do
      rm -fv "${HOME}/${f}"
    done
  else
    echo "Suppression annulée."
  fi

  echo
  echo "Non touchés par prudence (usage incertain, à vérifier manuellement) :"
  echo "  - start.sh        (jamais invoqué dans les logs de session)"
  echo "  - cloud-project/  (contient le kubeconfig utilisé par kubectl, à conserver)"
}

# ---------------------------------------------------------------------------
case "${1:-start}" in
  start)
    start_forward "${PROM_SVC}" "${PROM_PORT}" "prometheus"
    start_forward "${GRAF_SVC}" "${GRAF_PORT}" "grafana"
    IP="$(vm_ip)"
    echo
    echo "Prometheus :"
    open_url "http://${IP}:${PROM_PORT}"
    echo "Grafana :"
    open_url "http://${IP}:${GRAF_PORT}"
    ;;
  stop)
    stop_forward "prometheus"
    stop_forward "grafana"
    ;;
  status)
    status_forward "prometheus" "${PROM_PORT}"
    status_forward "grafana" "${GRAF_PORT}"
    ;;
  clean)
    clean_files
    ;;
  *)
    echo "Usage: $0 {start|stop|status|clean}"
    exit 1
    ;;
esac
