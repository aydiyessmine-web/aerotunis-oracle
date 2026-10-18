#!/usr/bin/env bash
# AeroTunis : deploiement automatise (Linux / macOS). Prerequis : Docker.
set -e
chmod -R a+w docs
echo "[1/3] Demarrage de l'instance Oracle XE (Docker)..."
docker compose up -d --wait
echo "[2/3] Installation du schema, securite, logique metier et tests..."
docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 aerotunis-db sqlplus -S /nolog @/work/sql/run_all.sql
echo "[3/3] Test de connexion distante (autre conteneur, reseau Docker)..."
docker run --rm --network aerotunis-net -v "$(pwd)":/work -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 --entrypoint sqlplus gvenzl/oracle-xe:21-slim -S /nolog @/work/sql/06_test_reseau.sql
echo "Termine. Journaux : docs/journal_installation.log et docs/journal_tests.log"
