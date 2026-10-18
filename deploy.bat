@echo off
REM AeroTunis : deploiement automatise (Windows). Prerequis : Docker Desktop demarre.
echo [1/3] Demarrage de l'instance Oracle XE (Docker)...
docker compose up -d --wait
if errorlevel 1 goto erreur

echo [2/3] Installation du schema, securite, logique metier et tests...
docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 aerotunis-db sqlplus -S /nolog @/work/sql/run_all.sql
if errorlevel 1 goto erreur

echo [3/3] Test de connexion distante (depuis un autre conteneur, via le reseau Docker)...
docker run --rm --network aerotunis-net -v "%cd%":/work -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 --entrypoint sqlplus gvenzl/oracle-xe:21-slim -S /nolog @/work/sql/06_test_reseau.sql

echo.
echo Termine. Journaux : docs\journal_installation.log et docs\journal_tests.log
goto fin

:erreur
echo Une etape a echoue. Verifiez que Docker Desktop est demarre.
exit /b 1

:fin
