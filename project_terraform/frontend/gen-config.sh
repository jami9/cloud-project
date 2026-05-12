#!/bin/bash
# Génère dashboard/config.js depuis .env
# Usage: bash gen-config.sh

set -a
source .env
set +a

mkdir -p dashboard

cat > dashboard/config.js << JSEOF
// ⚠️ Fichier AUTO-GÉNÉRÉ depuis .env — ne pas éditer manuellement
// Regénérer avec: bash gen-config.sh
const CONFIG = {
  API_BASE_URL:      "${API_BASE_URL}",
  OPENSTACK_HOST:    "${OPENSTACK_HOST}",
  KONG_HOST:         "${KONG_HOST}",
  KONG_PROXY_PORT:   "${KONG_PROXY_PORT}",
};

// Freeze pour éviter les modifications accidentelles
Object.freeze(CONFIG);
JSEOF

echo "[OK] dashboard/config.js généré depuis .env"
echo "     API_BASE_URL = ${API_BASE_URL}"
