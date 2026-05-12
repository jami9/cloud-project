#!/bin/bash
# deploy.sh — Script de déploiement après git clone
# Usage: bash deploy.sh vm1   ou   bash deploy.sh vm2

set -e
ROLE=${1:-"vm1"}

echo "=== Déploiement cloud-project (rôle: $ROLE) ==="

# 1. Cloner le repo (si pas déjà fait)
if [ ! -d "cloud-project" ]; then
  git clone https://github.com/jami9/cloud-project.git
fi
cd cloud-project

# 2. Vérifier que .env existe
if [ ! -f ".env" ]; then
  echo ""
  echo "⚠️  ATTENTION: .env introuvable !"
  echo "   Copie .env.example vers .env et remplis les vraies IPs :"
  echo ""
  cp .env.example .env
  echo "   Fichier .env créé depuis .env.example"
  echo "   Édite-le maintenant : nano .env"
  echo ""
  read -p "   Appuie sur Entrée une fois le .env configuré..."
fi

# 3. Installation selon le rôle
if [ "$ROLE" = "vm1" ]; then
  echo "--- Installation VM1 (Flask + OpenStack) ---"
  pip install -r requirements.txt --break-system-packages
  echo "[OK] python-dotenv installé"
  python3 app.py &
  echo "[OK] app.py démarré sur port $(grep FLASK_PORT .env | cut -d= -f2)"

elif [ "$ROLE" = "vm2" ]; then
  echo "--- Installation VM2 (Dashboard + Kong) ---"
  bash gen-config.sh
  echo "[OK] config.js généré"
  docker compose up -d
  echo "[OK] Kong démarré"
fi

echo ""
echo "=== Déploiement terminé ==="
