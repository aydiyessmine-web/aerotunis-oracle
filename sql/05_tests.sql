-- =============================================================================
-- JOURNAL DE TESTS : prouve que chaque regle (Steps 1 a 4) est appliquee
-- Chaque test affiche REUSSI ou ECHEC. Les tests modifient la base puis font ROLLBACK.
-- La date systeme est simulee (FIXED_DATE) pour tester le week-end de facon reproductible.
-- =============================================================================
@@00_config.sql
SET SQLBLANKLINES ON
WHENEVER SQLERROR CONTINUE
SPOOL /work/docs/journal_tests.log
PROMPT ============================================================
PROMPT  AEROTUNIS : JOURNAL DE TESTS
PROMPT ============================================================
PROMPT Date reelle d'execution :
SELECT TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS') AS date_reelle FROM dual;


PROMPT
PROMPT ############################ STEP 2 : SECURITE ############################
CONNECT sys/&SYS_PWD@&CONN AS SYSDBA

PROMPT
PROMPT --- T2.1 : mot de passe de APP_ADMIN a changer tous les 30 jours
SELECT u.username, u.profile, p.resource_name, p.limit
FROM   dba_users u JOIN dba_profiles p ON p.profile = u.profile
WHERE  u.username = 'APP_ADMIN' AND p.resource_name IN ('PASSWORD_LIFE_TIME','PASSWORD_GRACE_TIME','FAILED_LOGIN_ATTEMPTS');
SELECT 'T2.1 : ' || CASE WHEN COUNT(*) = 1 THEN 'REUSSI' ELSE 'ECHEC' END ||
       ' - PASSWORD_LIFE_TIME = 30 jours pour APP_ADMIN' AS resultat
FROM   dba_users u JOIN dba_profiles p ON p.profile = u.profile
WHERE  u.username = 'APP_ADMIN' AND p.resource_name = 'PASSWORD_LIFE_TIME' AND p.limit = '30';

PROMPT
PROMPT --- T2.2 : verrouillage apres 3 tentatives de connexion infructueuses (APP_USER)
PROMPT >> 3 connexions avec un mauvais mot de passe :
CONNECT app_user/"Faux1!"@&CONN
CONNECT app_user/"Faux2!"@&CONN
CONNECT app_user/"Faux3!"@&CONN
PROMPT >> 4e connexion avec le BON mot de passe (le compte doit etre verrouille, ORA-28000) :
CONNECT app_user/"Oracle2!"@&CONN
CONNECT sys/&SYS_PWD@&CONN AS SYSDBA
SELECT 'T2.2 : ' || CASE WHEN account_status LIKE 'LOCKED%' THEN 'REUSSI' ELSE 'ECHEC' END ||
       ' - statut de APP_USER = ' || account_status AS resultat
FROM   dba_users WHERE username = 'APP_USER';
ALTER USER app_user ACCOUNT UNLOCK;

PROMPT
PROMPT --- T2.3 : audit de lecture de la vue V_VOLS_DETAIL
CONNECT auditeur/"Oracle3!"@&CONN
SELECT COUNT(*) AS vols_consultes_par_auditeur FROM aeroport.v_vols_detail;
CONNECT sys/&SYS_PWD@&CONN AS SYSDBA
EXEC DBMS_AUDIT_MGMT.FLUSH_UNIFIED_AUDIT_TRAIL
SELECT TO_CHAR(event_timestamp, 'DD/MM/YYYY HH24:MI:SS') AS quand, dbusername AS qui,
       action_name AS action, object_schema || '.' || object_name AS objet
FROM   unified_audit_trail
WHERE  object_name = 'V_VOLS_DETAIL' AND action_name = 'SELECT'
ORDER  BY event_timestamp;
SELECT 'T2.3 : ' || CASE WHEN COUNT(*) >= 1 THEN 'REUSSI' ELSE 'ECHEC' END ||
       ' - ' || COUNT(*) || ' lecture(s) de V_VOLS_DETAIL consignee(s) dans l''audit' AS resultat
FROM   unified_audit_trail
WHERE  object_name = 'V_VOLS_DETAIL' AND action_name = 'SELECT' AND dbusername = 'AUDITEUR';


PROMPT
PROMPT ################### STEP 3 et 4 : LOGIQUE METIER (lundi simule) ###################

CONNECT sys/&SYS_PWD@&CONN_ROOT AS SYSDBA
ALTER SYSTEM SET fixed_date = '2026-10-19-10:00:00' SCOPE=MEMORY;
CONNECT aeroport/"&AERO_PWD"@&CONN
SELECT 'Date systeme simulee : ' || TO_CHAR(SYSDATE, 'DY DD/MM/YYYY HH24:MI', 'NLS_DATE_LANGUAGE=FRENCH') AS date_simulee FROM dual;


PROMPT
PROMPT --- T3.1 : disponibilite des pilotes (pas de chevauchement)

BEGIN
    INSERT INTO vol (volno, dep, arr, hd, ha, avno, pilno)
        VALUES ('TN002', 'Paris-CDG', 'Toulouse-Blagnac',
                TO_DATE('2025-06-15 12:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2025-06-15 14:00', 'YYYY-MM-DD HH24:MI'),
                (SELECT avno FROM avion WHERE avnom = 'ATR 72-600'),
                (SELECT pilno FROM pilote WHERE nom = 'Laroche'));
    DBMS_OUTPUT.PUT_LINE('T3.1a : REUSSI - affectation sans chevauchement acceptee');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T3.1a : ECHEC - erreur inattendue : ' || SQLERRM);
    ROLLBACK;
END;
/

BEGIN
    INSERT INTO vol (volno, dep, arr, hd, ha, avno, pilno)
        VALUES ('TN001', 'Paris-CDG', 'Toulouse-Blagnac',
                TO_DATE('2025-06-15 08:30', 'YYYY-MM-DD HH24:MI'), TO_DATE('2025-06-15 10:00', 'YYYY-MM-DD HH24:MI'),
                (SELECT avno FROM avion WHERE avnom = 'ATR 72-600'),
                (SELECT pilno FROM pilote WHERE nom = 'Laroche'));
    DBMS_OUTPUT.PUT_LINE('T3.1b : ECHEC - aucune erreur levee (chevauchement avec AF101 non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20001 THEN
        DBMS_OUTPUT.PUT_LINE('T3.1b : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T3.1b : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

BEGIN
    INSERT INTO vol (volno, dep, arr, hd, ha, avno, pilno)
        VALUES ('TN003', 'Paris-CDG', 'Paris-Orly',
                TO_DATE('2025-06-16 15:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2025-06-16 17:00', 'YYYY-MM-DD HH24:MI'),
                (SELECT avno FROM avion WHERE avnom = 'ATR 72-600'),
                (SELECT pilno FROM pilote WHERE nom = 'Dupont'));
    INSERT INTO defpilote (volno, pilno, role)
        VALUES ('TN003', (SELECT pilno FROM pilote WHERE nom = 'Ferrand'), 'COPILOTE');
    DBMS_OUTPUT.PUT_LINE('T3.1c : ECHEC - aucune erreur levee (affectation secondaire en conflit avec AF305 non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20001 THEN
        DBMS_OUTPUT.PUT_LINE('T3.1c : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T3.1c : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/


PROMPT
PROMPT --- T3.2 : calculateur de primes (mois de juin 2025)
DECLARE
    v_mois DATE := DATE '2025-06-01';
    PROCEDURE verif(p_nom VARCHAR2, p_attendu NUMBER) IS
        v_pil NUMBER;
        v_h   NUMBER;
        v_p   NUMBER;
    BEGIN
        SELECT pilno INTO v_pil FROM pilote WHERE nom = p_nom;
        v_h := pkg_primes.heures_mois(v_pil, v_mois);
        v_p := pkg_primes.calcul_prime(v_h);
        DBMS_OUTPUT.PUT_LINE('T3.2a : ' ||
            CASE WHEN ABS(v_p - p_attendu) < 0.01 THEN 'REUSSI' ELSE 'ECHEC' END ||
            ' - ' || RPAD(p_nom, 8) || ' heures=' || TO_CHAR(ROUND(v_h, 2), 'FM990.00') ||
            ' prime=' || TO_CHAR(v_p, 'FM9990.00') || ' (attendu ' || TO_CHAR(p_attendu, 'FM9990.00') || ')');
    END;
BEGIN
    verif('Dupont', 156);   -- 19,5 h x 8 EUR
    verif('Martin', 248);   -- 20,67 h x 12 EUR (AF510 copilote + AF612 commandant)
    verif('Ferrand', 68);   -- 8,5 h x 8 EUR
    verif('Albaric', 0);    -- 0,75 h : sous le seuil de 1 h
END;
/
PROMPT >> Calcul et enregistrement des primes de juin 2025 :
BEGIN
    pkg_primes.calculer_mois(DATE '2025-06-15');
    COMMIT;
END;
/
SELECT p.nom, p.prenom, TO_CHAR(r.mois, 'MM/YYYY') AS mois, r.heures_vol, r.prime
FROM   prime_pilote r JOIN pilote p ON p.pilno = r.pilno
ORDER  BY r.prime DESC, p.nom;

BEGIN
    DECLARE v NUMBER; BEGIN v := pkg_primes.heures_mois(999999, DATE '2025-06-01'); END;
    DBMS_OUTPUT.PUT_LINE('T3.2b : ECHEC - aucune erreur levee (pilote inconnu non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20008 THEN
        DBMS_OUTPUT.PUT_LINE('T3.2b : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T3.2b : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

BEGIN
    DECLARE v NUMBER; BEGIN v := pkg_primes.heures_mois(NULL, NULL); END;
    DBMS_OUTPUT.PUT_LINE('T3.2c : ECHEC - aucune erreur levee (parametre manquant non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20009 THEN
        DBMS_OUTPUT.PUT_LINE('T3.2c : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T3.2c : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/


PROMPT
PROMPT --- T3.3 : journalisation silencieuse des salaires
DECLARE
    v_pil  NUMBER;
    v_n1   NUMBER;
    v_n2   NUMBER;
    v_anc  NUMBER;
    v_nouv NUMBER;
    v_aut  VARCHAR2(30);
BEGIN
    SELECT pilno INTO v_pil FROM pilote WHERE nom = 'Nguyen';
    SELECT COUNT(*) INTO v_n1 FROM historique_salaire;
    UPDATE pilote SET adresse = 'Toulouse (test)' WHERE pilno = v_pil;
    SELECT COUNT(*) INTO v_n2 FROM historique_salaire;
    DBMS_OUTPUT.PUT_LINE('T3.3a : ' || CASE WHEN v_n1 = v_n2 THEN 'REUSSI' ELSE 'ECHEC' END ||
                         ' - une modification hors salaire ne cree aucune ligne d''historique');
    UPDATE pilote SET salaire = 4000 WHERE pilno = v_pil;
    SELECT ancien_salaire, nouveau_salaire, auteur INTO v_anc, v_nouv, v_aut
    FROM   historique_salaire WHERE pilno = v_pil;
    DBMS_OUTPUT.PUT_LINE('T3.3b : ' ||
        CASE WHEN v_anc = 3900 AND v_nouv = 4000 AND v_aut = 'AEROPORT' THEN 'REUSSI' ELSE 'ECHEC' END ||
        ' - ancien=' || v_anc || ' nouveau=' || v_nouv || ' auteur=' || v_aut);
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T3.3 : ECHEC - erreur inattendue : ' || SQLERRM);
    ROLLBACK;
END;
/

PROMPT
PROMPT --- T3.4 : rapport de performance des appareils
EXEC prc_rapport_performance
SELECT 'T3.4a : ' || CASE WHEN COUNT(DISTINCT avno) = 6 THEN 'REUSSI' ELSE 'ECHEC' END ||
       ' - ' || COUNT(DISTINCT avno) || ' avions listes (dont ceux sans vol)' AS resultat
FROM   v_perf_appareils;
SELECT 'T3.4b : ' || CASE WHEN MAX(taux_moyen_avion) = 88.9 THEN 'REUSSI' ELSE 'ECHEC' END ||
       ' - taux moyen A320 = ' || MAX(taux_moyen_avion) || ' % (attendu 88,9)' AS resultat
FROM   v_perf_appareils WHERE avnom = 'Airbus A320';

PROMPT
PROMPT --- T3.5 : validation des escales

BEGIN
    INSERT INTO vol (volno, dep, arr, hd, ha, avno, pilno)
        VALUES ('TN010', 'Paris-CDG', 'Atlantis-ATL',
                TO_DATE('2025-07-01 10:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2025-07-01 12:00', 'YYYY-MM-DD HH24:MI'),
                (SELECT avno FROM avion WHERE avnom = 'ATR 72-600'),
                (SELECT pilno FROM pilote WHERE nom = 'Nguyen'));
    DBMS_OUTPUT.PUT_LINE('T3.5a : ECHEC - aucune erreur levee (destination inconnue non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20002 THEN
        DBMS_OUTPUT.PUT_LINE('T3.5a : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T3.5a : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

BEGIN
    INSERT INTO vol (volno, dep, arr, hd, ha, avno, pilno)
        VALUES ('TN011', 'Paris-CDG', 'Kaboul-Hamid Karzai',
                TO_DATE('2025-07-01 10:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2025-07-01 12:00', 'YYYY-MM-DD HH24:MI'),
                (SELECT avno FROM avion WHERE avnom = 'ATR 72-600'),
                (SELECT pilno FROM pilote WHERE nom = 'Nguyen'));
    DBMS_OUTPUT.PUT_LINE('T3.5b : ECHEC - aucune erreur levee (destination desactivee non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20002 THEN
        DBMS_OUTPUT.PUT_LINE('T3.5b : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T3.5b : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

BEGIN
    INSERT INTO vol (volno, dep, arr, hd, ha, avno, pilno)
        VALUES ('TN012', 'Paris-CDG', 'Paris-Orly',
                TO_DATE('2025-07-01 10:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2025-07-01 10:20', 'YYYY-MM-DD HH24:MI'),
                (SELECT avno FROM avion WHERE avnom = 'ATR 72-600'),
                (SELECT pilno FROM pilote WHERE nom = 'Nguyen'));
    DBMS_OUTPUT.PUT_LINE('T3.5c : ECHEC - aucune erreur levee (duree de 20 minutes non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20006 THEN
        DBMS_OUTPUT.PUT_LINE('T3.5c : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T3.5c : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

BEGIN
    INSERT INTO vol (volno, dep, arr, hd, ha, avno, pilno)
        VALUES ('TN013', 'Paris-CDG', 'Tunis-Carthage',
                TO_DATE('2025-07-01 10:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2025-07-01 12:30', 'YYYY-MM-DD HH24:MI'),
                (SELECT avno FROM avion WHERE avnom = 'ATR 72-600'),
                (SELECT pilno FROM pilote WHERE nom = 'Nguyen'));
    DBMS_OUTPUT.PUT_LINE('T3.5d : REUSSI - vol valide vers Tunis-Carthage (2 h 30) accepte');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T3.5d : ECHEC - erreur inattendue : ' || SQLERRM);
    ROLLBACK;
END;
/


PROMPT
PROMPT --- T4.1 : capacite maximale de l'avion

BEGIN
    UPDATE vol SET nbpassagers = 181 WHERE volno = 'AF101';
    DBMS_OUTPUT.PUT_LINE('T4.1a : ECHEC - aucune erreur levee (181 passagers dans un A320 de 180 sieges non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20004 THEN
        DBMS_OUTPUT.PUT_LINE('T4.1a : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T4.1a : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

BEGIN
    UPDATE vol SET nbpassagers = 180 WHERE volno = 'AF101';
    DBMS_OUTPUT.PUT_LINE('T4.1b : REUSSI - 180 passagers dans un A320 de 180 sieges accepte');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T4.1b : ECHEC - erreur inattendue : ' || SQLERRM);
    ROLLBACK;
END;
/

BEGIN
    UPDATE vol SET avno = (SELECT avno FROM avion WHERE avnom = 'ATR 72-600') WHERE volno = 'AF101';
    DBMS_OUTPUT.PUT_LINE('T4.1c : ECHEC - aucune erreur levee (150 passagers affectes a un ATR de 70 sieges non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20004 THEN
        DBMS_OUTPUT.PUT_LINE('T4.1c : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T4.1c : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/


PROMPT
PROMPT --- T4.2 : sequence SEQ_PILOTE utilisee de facon transparente
DECLARE
    v_pil NUMBER;
    v_cur NUMBER;
BEGIN
    INSERT INTO pilote (nom, prenom, age, adresse, salaire)
    VALUES ('Test', 'Sequence', 30, 'Tunis', 3000)
    RETURNING pilno INTO v_pil;
    v_cur := seq_pilote.CURRVAL;
    DBMS_OUTPUT.PUT_LINE('T4.2a : ' || CASE WHEN v_pil = v_cur THEN 'REUSSI' ELSE 'ECHEC' END ||
                         ' - pilno attribue sans le fournir = ' || v_pil || ' (SEQ_PILOTE.CURRVAL = ' || v_cur || ')');
    INSERT INTO pilote (pilno, nom, prenom, age, adresse, salaire)
    VALUES (99999, 'Test', 'Force', 30, 'Tunis', 3000)
    RETURNING pilno INTO v_pil;
    v_cur := seq_pilote.CURRVAL;
    DBMS_OUTPUT.PUT_LINE('T4.2b : ' || CASE WHEN v_pil <> 99999 AND v_pil = v_cur THEN 'REUSSI' ELSE 'ECHEC' END ||
                         ' - pilno force a 99999 remplace par ' || v_pil || ' (valeur de la sequence)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T4.2 : ECHEC - erreur inattendue : ' || SQLERRM);
    ROLLBACK;
END;
/

PROMPT
PROMPT --- T4.3 : nettoyage securise des vols

BEGIN
    prc_supprimer_vol('AF305');
    DBMS_OUTPUT.PUT_LINE('T4.3a : ECHEC - aucune erreur levee (vol AF305 avec affectations secondaires non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20005 THEN
        DBMS_OUTPUT.PUT_LINE('T4.3a : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T4.3a : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

BEGIN
    DELETE FROM vol WHERE volno = 'AF305';
    DBMS_OUTPUT.PUT_LINE('T4.3b : ECHEC - aucune erreur levee (suppression directe de AF305 non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20005 THEN
        DBMS_OUTPUT.PUT_LINE('T4.3b : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T4.3b : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

BEGIN
    INSERT INTO vol (volno, dep, arr, hd, ha, avno, pilno)
        VALUES ('TN020', 'Paris-CDG', 'Paris-Orly',
                TO_DATE('2025-07-05 09:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2025-07-05 10:00', 'YYYY-MM-DD HH24:MI'),
                (SELECT avno FROM avion WHERE avnom = 'ATR 72-600'),
                (SELECT pilno FROM pilote WHERE nom = 'Nguyen'));
    prc_supprimer_vol('TN020');
    DBMS_OUTPUT.PUT_LINE('T4.3c : REUSSI - vol sans affectation secondaire supprime');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T4.3c : ECHEC - erreur inattendue : ' || SQLERRM);
    ROLLBACK;
END;
/

BEGIN
    prc_supprimer_vol('ZZ999');
    DBMS_OUTPUT.PUT_LINE('T4.3d : ECHEC - aucune erreur levee (vol introuvable non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20007 THEN
        DBMS_OUTPUT.PUT_LINE('T4.3d : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T4.3d : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

BEGIN
    prc_supprimer_vol(NULL);
    DBMS_OUTPUT.PUT_LINE('T4.3e : ECHEC - aucune erreur levee (parametre manquant non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20009 THEN
        DBMS_OUTPUT.PUT_LINE('T4.3e : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T4.3e : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/


PROMPT
PROMPT --- T3.6 : fermeture administrative le week-end (table PILOTE)
PROMPT >> Date simulee : SAMEDI 17/10/2026

CONNECT sys/&SYS_PWD@&CONN_ROOT AS SYSDBA
ALTER SYSTEM SET fixed_date = '2026-10-17-10:00:00' SCOPE=MEMORY;
CONNECT aeroport/"&AERO_PWD"@&CONN
SELECT 'Date systeme simulee : ' || TO_CHAR(SYSDATE, 'DY DD/MM/YYYY HH24:MI', 'NLS_DATE_LANGUAGE=FRENCH') AS date_simulee FROM dual;

BEGIN
    UPDATE pilote SET adresse = 'Tunis (test)' WHERE nom = 'Nguyen';
    DBMS_OUTPUT.PUT_LINE('T3.6a : ECHEC - aucune erreur levee (modification un samedi non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20003 THEN
        DBMS_OUTPUT.PUT_LINE('T3.6a : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T3.6a : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

BEGIN
    INSERT INTO pilote (nom, prenom, age, adresse, salaire) VALUES ('Week', 'End', 30, 'Tunis', 3000);
    DBMS_OUTPUT.PUT_LINE('T3.6b : ECHEC - aucune erreur levee (insertion un samedi non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20003 THEN
        DBMS_OUTPUT.PUT_LINE('T3.6b : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T3.6b : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

BEGIN
    DELETE FROM pilote WHERE nom = 'Nguyen';
    DBMS_OUTPUT.PUT_LINE('T3.6c : ECHEC - aucune erreur levee (suppression un samedi non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20003 THEN
        DBMS_OUTPUT.PUT_LINE('T3.6c : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T3.6c : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

PROMPT >> Date simulee : DIMANCHE 18/10/2026

CONNECT sys/&SYS_PWD@&CONN_ROOT AS SYSDBA
ALTER SYSTEM SET fixed_date = '2026-10-18-10:00:00' SCOPE=MEMORY;
CONNECT aeroport/"&AERO_PWD"@&CONN
SELECT 'Date systeme simulee : ' || TO_CHAR(SYSDATE, 'DY DD/MM/YYYY HH24:MI', 'NLS_DATE_LANGUAGE=FRENCH') AS date_simulee FROM dual;

BEGIN
    UPDATE pilote SET adresse = 'Tunis (test)' WHERE nom = 'Nguyen';
    DBMS_OUTPUT.PUT_LINE('T3.6d : ECHEC - aucune erreur levee (modification un dimanche non detecte)');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE = -20003 THEN
        DBMS_OUTPUT.PUT_LINE('T3.6d : REUSSI - rejet attendu : ' || SQLERRM);
    ELSE
        DBMS_OUTPUT.PUT_LINE('T3.6d : ECHEC - erreur inattendue : ' || SQLERRM);
    END IF;
    ROLLBACK;
END;
/

PROMPT >> Retour a un jour ouvrable : LUNDI 19/10/2026

CONNECT sys/&SYS_PWD@&CONN_ROOT AS SYSDBA
ALTER SYSTEM SET fixed_date = '2026-10-19-10:00:00' SCOPE=MEMORY;
CONNECT aeroport/"&AERO_PWD"@&CONN
SELECT 'Date systeme simulee : ' || TO_CHAR(SYSDATE, 'DY DD/MM/YYYY HH24:MI', 'NLS_DATE_LANGUAGE=FRENCH') AS date_simulee FROM dual;

BEGIN
    UPDATE pilote SET adresse = 'Tunis (test)' WHERE nom = 'Nguyen';
    DBMS_OUTPUT.PUT_LINE('T3.6e : REUSSI - modification autorisee un lundi');
    ROLLBACK;
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T3.6e : ECHEC - erreur inattendue : ' || SQLERRM);
    ROLLBACK;
END;
/


PROMPT
PROMPT ############################ FIN DES TESTS ############################
CONNECT sys/&SYS_PWD@&CONN_ROOT AS SYSDBA
ALTER SYSTEM SET fixed_date = NONE SCOPE=MEMORY;
SELECT 'Date systeme restauree : ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI') AS date_reelle FROM dual;
PROMPT
PROMPT Compter les resultats avec : findstr /C:"REUSSI" /C:"ECHEC" docs\journal_tests.log
SPOOL OFF
EXIT
