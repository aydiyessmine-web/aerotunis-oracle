-- Step 1.3 : connexion distante depuis un AUTRE conteneur via le reseau Docker (hote oracle-db)
@@00_config.sql
WHENEVER SQLERROR CONTINUE
PROMPT ============================================================
PROMPT  TEST RESEAU : connexion distante a oracle-db:1521
PROMPT ============================================================
CONNECT auditeur/"Oracle3!"@//oracle-db:1521/XEPDB1
SELECT 'T1.3 : REUSSI - connexion distante OK : utilisateur ' || USER ||
       ' depuis ' || SYS_CONTEXT('USERENV','IP_ADDRESS') AS resultat
FROM   dual;
SELECT COUNT(*) AS nb_vols_visibles FROM aeroport.v_vols_detail;
EXIT
