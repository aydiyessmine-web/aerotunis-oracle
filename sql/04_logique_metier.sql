-- =============================================================================
-- STEP 3 et STEP 4 : logique metier PL/SQL et robustesse (schema AEROPORT)
--
-- Codes d'erreur applicatifs
--   -20001 pilote indisponible (chevauchement d'horaires)
--   -20002 escale refusee (destination inconnue ou desactivee)
--   -20003 fermeture administrative (week-end) sur PILOTE
--   -20004 capacite de l'avion depassee
--   -20005 suppression de vol refusee (affectations secondaires)
--   -20006 duree de vol incoherente (< 30 minutes)
--   -20007 vol introuvable
--   -20008 pilote inconnu
--   -20009 parametre manquant
--   -20010 avion introuvable
-- =============================================================================
@@00_config.sql
SET SQLBLANKLINES ON
WHENEVER SQLERROR CONTINUE
CONNECT aeroport/"&AERO_PWD"@&CONN
PROMPT
PROMPT [STEP 3 et 4] Creation des objets metier dans le schema AEROPORT

-- -----------------------------------------------------------------------------
-- 0. Evolution du schema
-- -----------------------------------------------------------------------------
-- Passagers par vol : necessaire au taux de remplissage (3.4) et au controle de capacite (4.1)
ALTER TABLE vol ADD (nbpassagers NUMBER(4));
ALTER TABLE vol ADD CONSTRAINT ck_nbpass CHECK (nbpassagers >= 0);

-- Destinations valides (3.5)
CREATE TABLE destination (
    nom    VARCHAR2(50) NOT NULL,
    pays   VARCHAR2(40) NOT NULL,
    actif  CHAR(1)      DEFAULT 'O' NOT NULL,
    CONSTRAINT pk_destination PRIMARY KEY (nom),
    CONSTRAINT ck_dest_actif  CHECK (actif IN ('O','N'))
);
INSERT INTO destination VALUES ('Paris-CDG',            'France',      'O');
INSERT INTO destination VALUES ('Paris-Orly',           'France',      'O');
INSERT INTO destination VALUES ('Toulouse-Blagnac',     'France',      'O');
INSERT INTO destination VALUES ('Lyon-Saint-Exupéry',   'France',      'O');
INSERT INTO destination VALUES ('Marseille-Provence',   'France',      'O');
INSERT INTO destination VALUES ('Bordeaux-Mérignac',    'France',      'O');
INSERT INTO destination VALUES ('New York-JFK',         'Etats-Unis',  'O');
INSERT INTO destination VALUES ('Tokyo-Narita',         'Japon',       'O');
INSERT INTO destination VALUES ('Tunis-Carthage',       'Tunisie',     'O');
INSERT INTO destination VALUES ('Kaboul-Hamid Karzai',  'Afghanistan', 'N');

-- Taux de remplissage des vols existants (valeurs de demonstration, toutes <= capacite)
UPDATE vol SET nbpassagers = 150 WHERE volno = 'AF101';
UPDATE vol SET nbpassagers = 170 WHERE volno = 'AF202';
UPDATE vol SET nbpassagers = 380 WHERE volno = 'AF305';
UPDATE vol SET nbpassagers =  55 WHERE volno = 'AF406';
UPDATE vol SET nbpassagers = 540 WHERE volno = 'AF510';
UPDATE vol SET nbpassagers = 140 WHERE volno = 'AF612';

-- Journal des salaires (3.3) : pas de cle etrangere, l'historique survit a la suppression d'un pilote
CREATE TABLE historique_salaire (
    id               NUMBER GENERATED ALWAYS AS IDENTITY,
    pilno            NUMBER(6)    NOT NULL,
    ancien_salaire   NUMBER(10,2),
    nouveau_salaire  NUMBER(10,2),
    date_modif       DATE         NOT NULL,
    auteur           VARCHAR2(30) NOT NULL,
    CONSTRAINT pk_hist_salaire PRIMARY KEY (id)
);

-- Primes mensuelles (3.2)
CREATE TABLE prime_pilote (
    pilno        NUMBER(6)    NOT NULL,
    mois         DATE         NOT NULL,
    heures_vol   NUMBER(8,2)  NOT NULL,
    prime        NUMBER(10,2) NOT NULL,
    date_calcul  DATE         NOT NULL,
    CONSTRAINT pk_prime_pilote PRIMARY KEY (pilno, mois),
    CONSTRAINT fk_prime_pilote FOREIGN KEY (pilno) REFERENCES pilote (pilno)
);
COMMIT;

-- -----------------------------------------------------------------------------
-- 3.1 Disponibilite des pilotes (aucun chevauchement d'horaires)
--     Un pilote est affecte a un vol soit comme commandant (VOL.PILNO), soit via DEFPILOTE.
--     Triggers composes : la verification se fait APRES l'instruction, ce qui evite l'erreur
--     ORA-04091 (table en mutation) quand on relit VOL.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_regles AS
    -- Retourne le numero d'un vol deja programme pour ce pilote qui chevauche [p_hd, p_ha[, sinon NULL
    FUNCTION vol_en_conflit(p_pilno NUMBER, p_volno VARCHAR2, p_hd DATE, p_ha DATE) RETURN VARCHAR2;
END pkg_regles;
/
CREATE OR REPLACE PACKAGE BODY pkg_regles AS
    FUNCTION vol_en_conflit(p_pilno NUMBER, p_volno VARCHAR2, p_hd DATE, p_ha DATE) RETURN VARCHAR2 IS
        v_res vol.volno%TYPE;
    BEGIN
        SELECT MIN(x.volno) INTO v_res
        FROM (
            SELECT v.volno, v.hd, v.ha FROM vol v WHERE v.pilno = p_pilno
            UNION ALL
            SELECT v.volno, v.hd, v.ha
            FROM   defpilote d JOIN vol v ON v.volno = d.volno
            WHERE  d.pilno = p_pilno
        ) x
        WHERE x.volno <> p_volno
          AND x.hd < p_ha
          AND x.ha > p_hd;
        RETURN v_res;
    END vol_en_conflit;
END pkg_regles;
/
SHOW ERRORS

CREATE OR REPLACE TRIGGER trg_dispo_pilote_vol
FOR INSERT OR UPDATE OF pilno, hd, ha ON vol
COMPOUND TRIGGER
    TYPE t_rec IS RECORD (volno vol.volno%TYPE, pilno vol.pilno%TYPE, hd DATE, ha DATE);
    TYPE t_tab IS TABLE OF t_rec INDEX BY PLS_INTEGER;
    g_vols t_tab;

    AFTER EACH ROW IS
        n PLS_INTEGER;
    BEGIN
        n := g_vols.COUNT + 1;
        g_vols(n).volno := :NEW.volno;
        g_vols(n).pilno := :NEW.pilno;
        g_vols(n).hd    := :NEW.hd;
        g_vols(n).ha    := :NEW.ha;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_conflit vol.volno%TYPE;
    BEGIN
        FOR i IN 1 .. g_vols.COUNT LOOP
            IF g_vols(i).pilno IS NOT NULL THEN
                v_conflit := pkg_regles.vol_en_conflit(g_vols(i).pilno, g_vols(i).volno,
                                                       g_vols(i).hd, g_vols(i).ha);
                IF v_conflit IS NOT NULL THEN
                    RAISE_APPLICATION_ERROR(-20001,
                        'Affectation refusée : le pilote n° ' || g_vols(i).pilno ||
                        ' est déjà programmé sur le vol ' || v_conflit ||
                        ' dont les horaires chevauchent le vol ' || g_vols(i).volno || '.');
                END IF;
            END IF;
        END LOOP;
    END AFTER STATEMENT;
END trg_dispo_pilote_vol;
/
SHOW ERRORS

CREATE OR REPLACE TRIGGER trg_dispo_pilote_def
FOR INSERT OR UPDATE OF volno, pilno ON defpilote
COMPOUND TRIGGER
    TYPE t_rec IS RECORD (volno defpilote.volno%TYPE, pilno defpilote.pilno%TYPE);
    TYPE t_tab IS TABLE OF t_rec INDEX BY PLS_INTEGER;
    g_aff t_tab;

    AFTER EACH ROW IS
        n PLS_INTEGER;
    BEGIN
        n := g_aff.COUNT + 1;
        g_aff(n).volno := :NEW.volno;
        g_aff(n).pilno := :NEW.pilno;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_hd      DATE;
        v_ha      DATE;
        v_conflit vol.volno%TYPE;
    BEGIN
        FOR i IN 1 .. g_aff.COUNT LOOP
            BEGIN
                SELECT hd, ha INTO v_hd, v_ha FROM vol WHERE volno = g_aff(i).volno;
                v_conflit := pkg_regles.vol_en_conflit(g_aff(i).pilno, g_aff(i).volno, v_hd, v_ha);
                IF v_conflit IS NOT NULL THEN
                    RAISE_APPLICATION_ERROR(-20001,
                        'Affectation refusée : le pilote n° ' || g_aff(i).pilno ||
                        ' est déjà programmé sur le vol ' || v_conflit ||
                        ' dont les horaires chevauchent le vol ' || g_aff(i).volno || '.');
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN NULL;  -- vol inexistant : la cle etrangere rejettera la ligne
            END;
        END LOOP;
    END AFTER STATEMENT;
END trg_dispo_pilote_def;
/
SHOW ERRORS

-- -----------------------------------------------------------------------------
-- 3.2 Calculateur de primes
--     Heures effectuees = vols termines (HA <= SYSDATE) du mois, comme commandant ou via DEFPILOTE.
--     Bareme : >= 20 h : 12 EUR/h | >= 8 h : 8 EUR/h | >= 1 h : 5 EUR/h | sinon 0
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_primes AS
    FUNCTION  heures_mois(p_pilno NUMBER, p_mois DATE) RETURN NUMBER;
    FUNCTION  calcul_prime(p_heures NUMBER) RETURN NUMBER;
    PROCEDURE calculer_mois(p_mois DATE DEFAULT SYSDATE);
END pkg_primes;
/
CREATE OR REPLACE PACKAGE BODY pkg_primes AS
    FUNCTION heures_mois(p_pilno NUMBER, p_mois DATE) RETURN NUMBER IS
        v_nb NUMBER;
        v_h  NUMBER;
    BEGIN
        IF p_pilno IS NULL OR p_mois IS NULL THEN
            RAISE_APPLICATION_ERROR(-20009, 'Paramètre manquant : pilote et mois sont obligatoires.');
        END IF;
        SELECT COUNT(*) INTO v_nb FROM pilote WHERE pilno = p_pilno;
        IF v_nb = 0 THEN
            RAISE_APPLICATION_ERROR(-20008, 'Pilote inconnu : n° ' || p_pilno || '.');
        END IF;
        SELECT NVL(SUM((v.ha - v.hd) * 24), 0) INTO v_h
        FROM   vol v
        WHERE  v.ha <= SYSDATE
          AND  v.hd >= TRUNC(p_mois, 'MM')
          AND  v.hd <  ADD_MONTHS(TRUNC(p_mois, 'MM'), 1)
          AND ( v.pilno = p_pilno
                OR EXISTS (SELECT 1 FROM defpilote d WHERE d.volno = v.volno AND d.pilno = p_pilno) );
        RETURN v_h;
    END heures_mois;

    FUNCTION calcul_prime(p_heures NUMBER) RETURN NUMBER IS
    BEGIN
        IF p_heures IS NULL OR p_heures < 0 THEN
            RAISE_APPLICATION_ERROR(-20009, 'Paramètre invalide : nombre d''heures manquant ou négatif.');
        END IF;
        RETURN ROUND(p_heures * CASE WHEN p_heures >= 20 THEN 12
                                     WHEN p_heures >= 8  THEN 8
                                     WHEN p_heures >= 1  THEN 5
                                     ELSE 0 END, 2);
    END calcul_prime;

    PROCEDURE calculer_mois(p_mois DATE DEFAULT SYSDATE) IS
        v_mois DATE;
        v_h    NUMBER;
        v_p    NUMBER;
    BEGIN
        IF p_mois IS NULL THEN
            RAISE_APPLICATION_ERROR(-20009, 'Paramètre manquant : mois.');
        END IF;
        v_mois := TRUNC(p_mois, 'MM');
        DELETE FROM prime_pilote WHERE mois = v_mois;
        FOR r IN (SELECT pilno, nom, prenom FROM pilote ORDER BY nom) LOOP
            v_h := heures_mois(r.pilno, v_mois);
            v_p := calcul_prime(v_h);
            INSERT INTO prime_pilote (pilno, mois, heures_vol, prime, date_calcul)
            VALUES (r.pilno, v_mois, ROUND(v_h, 2), v_p, SYSDATE);
            DBMS_OUTPUT.PUT_LINE(RPAD(r.nom || ' ' || r.prenom, 20) ||
                                 ' heures: ' || LPAD(TO_CHAR(ROUND(v_h, 2), 'FM990.00'), 7) ||
                                 '  prime: ' || LPAD(TO_CHAR(v_p, 'FM9990.00'), 8));
        END LOOP;
    END calculer_mois;
END pkg_primes;
/
SHOW ERRORS

-- -----------------------------------------------------------------------------
-- 3.3 Journalisation silencieuse des salaires
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_hist_salaire
AFTER UPDATE OF salaire ON pilote
FOR EACH ROW
WHEN (   (OLD.salaire IS NULL AND NEW.salaire IS NOT NULL)
      OR (OLD.salaire IS NOT NULL AND NEW.salaire IS NULL)
      OR (OLD.salaire <> NEW.salaire) )
BEGIN
    INSERT INTO historique_salaire (pilno, ancien_salaire, nouveau_salaire, date_modif, auteur)
    VALUES (:OLD.pilno, :OLD.salaire, :NEW.salaire, SYSDATE, SYS_CONTEXT('USERENV', 'SESSION_USER'));
END trg_hist_salaire;
/
SHOW ERRORS

-- -----------------------------------------------------------------------------
-- 3.4 Rapport de performance des appareils (detail par vol + taux de remplissage moyen)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_perf_appareils AS
SELECT a.avno,
       a.avnom,
       a.capacite,
       v.volno,
       v.dep || ' -> ' || v.arr AS trajet,
       v.hd,
       v.nbpassagers,
       CASE WHEN v.nbpassagers IS NOT NULL
            THEN ROUND(v.nbpassagers * 100 / a.capacite, 1) END AS taux_remplissage,
       ROUND(AVG(CASE WHEN v.nbpassagers IS NOT NULL
                      THEN v.nbpassagers * 100 / a.capacite END)
             OVER (PARTITION BY a.avno), 1) AS taux_moyen_avion,
       COUNT(v.volno) OVER (PARTITION BY a.avno) AS nb_vols
FROM   avion a
LEFT JOIN vol v ON v.avno = a.avno;

CREATE OR REPLACE PROCEDURE prc_rapport_performance IS
    v_prec avion.avno%TYPE := -1;
BEGIN
    DBMS_OUTPUT.PUT_LINE('==== RAPPORT DE PERFORMANCE DES APPAREILS ====');
    FOR r IN (SELECT * FROM v_perf_appareils ORDER BY avnom, hd) LOOP
        IF r.avno <> v_prec THEN
            DBMS_OUTPUT.PUT_LINE(CHR(10) || r.avnom || ' (capacité ' || r.capacite || ' sièges)  vols: ' ||
                                 r.nb_vols || '  taux de remplissage moyen: ' ||
                                 NVL(TO_CHAR(r.taux_moyen_avion, 'FM990.0') || ' %', 'n/d'));
            v_prec := r.avno;
        END IF;
        IF r.volno IS NULL THEN
            DBMS_OUTPUT.PUT_LINE('    Aucun vol assuré');
        ELSE
            DBMS_OUTPUT.PUT_LINE('    ' || RPAD(r.volno, 7) || RPAD(r.trajet, 46) ||
                                 TO_CHAR(r.hd, 'DD/MM/YYYY HH24:MI') || '  passagers: ' ||
                                 LPAD(NVL(TO_CHAR(r.nbpassagers), 'n/d'), 4) || '  taux: ' ||
                                 NVL(TO_CHAR(r.taux_remplissage, 'FM990.0') || ' %', 'n/d'));
        END IF;
    END LOOP;
END prc_rapport_performance;
/
SHOW ERRORS

-- -----------------------------------------------------------------------------
-- 3.5 Validation des escales : destination valide et duree >= 30 minutes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_vol_validation
BEFORE INSERT OR UPDATE OF arr, hd, ha ON vol
FOR EACH ROW
DECLARE
    v_actif destination.actif%TYPE;
BEGIN
    BEGIN
        SELECT actif INTO v_actif FROM destination WHERE nom = :NEW.arr;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20002,
                'Escale refusée : l''aéroport d''arrivée "' || :NEW.arr ||
                '" n''est pas une destination valide.');
    END;
    IF v_actif <> 'O' THEN
        RAISE_APPLICATION_ERROR(-20002,
            'Escale refusée : la destination "' || :NEW.arr || '" est désactivée.');
    END IF;
    IF (:NEW.ha - :NEW.hd) * 24 * 60 < 30 THEN
        RAISE_APPLICATION_ERROR(-20006,
            'Durée de vol incohérente : ' || ROUND((:NEW.ha - :NEW.hd) * 24 * 60) ||
            ' minute(s), minimum autorisé : 30 minutes.');
    END IF;
END trg_vol_validation;
/
SHOW ERRORS

-- -----------------------------------------------------------------------------
-- 3.6 Fermeture administrative : aucune modification de PILOTE le samedi et le dimanche
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_pilote_weekend
BEFORE INSERT OR UPDATE OR DELETE ON pilote
BEGIN
    IF TO_CHAR(SYSDATE, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT', 'SUN') THEN
        RAISE_APPLICATION_ERROR(-20003,
            'Fermeture administrative : la table PILOTE ne peut pas être modifiée le samedi et le dimanche.');
    END IF;
END trg_pilote_weekend;
/
SHOW ERRORS

-- -----------------------------------------------------------------------------
-- 4.1 Capacite maximale de l'avion
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_vol_capacite
BEFORE INSERT OR UPDATE OF nbpassagers, avno ON vol
FOR EACH ROW
WHEN (NEW.avno IS NOT NULL AND NEW.nbpassagers IS NOT NULL)
DECLARE
    v_cap avion.capacite%TYPE;
    v_nom avion.avnom%TYPE;
BEGIN
    BEGIN
        SELECT capacite, avnom INTO v_cap, v_nom FROM avion WHERE avno = :NEW.avno;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20010, 'Avion introuvable : n° ' || :NEW.avno || '.');
    END;
    IF :NEW.nbpassagers > v_cap THEN
        RAISE_APPLICATION_ERROR(-20004,
            'Capacité dépassée : le vol ' || :NEW.volno || ' compte ' || :NEW.nbpassagers ||
            ' passagers, mais l''avion "' || v_nom || '" ne peut en accueillir que ' || v_cap || '.');
    END IF;
END trg_vol_capacite;
/
SHOW ERRORS

-- -----------------------------------------------------------------------------
-- 4.2 Integrite des sequences : SEQ_PILOTE est toujours utilisee, de facon transparente
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_pilote_seq
BEFORE INSERT ON pilote
FOR EACH ROW
BEGIN
    :NEW.pilno := seq_pilote.NEXTVAL;
END trg_pilote_seq;
/
SHOW ERRORS

-- -----------------------------------------------------------------------------
-- 4.3 Nettoyage securise : un vol n'est supprime que sans affectation secondaire (DEFPILOTE)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_vol_suppression
BEFORE DELETE ON vol
FOR EACH ROW
DECLARE
    v_nb NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_nb FROM defpilote WHERE volno = :OLD.volno;
    IF v_nb > 0 THEN
        RAISE_APPLICATION_ERROR(-20005,
            'Suppression refusée : le vol ' || :OLD.volno || ' a ' || v_nb ||
            ' affectation(s) secondaire(s) dans DEFPILOTE. Retirez-les d''abord.');
    END IF;
END trg_vol_suppression;
/
SHOW ERRORS

CREATE OR REPLACE PROCEDURE prc_supprimer_vol(p_volno IN VARCHAR2) IS
    v_nb NUMBER;
BEGIN
    IF p_volno IS NULL THEN
        RAISE_APPLICATION_ERROR(-20009, 'Paramètre manquant : numéro de vol.');
    END IF;
    SELECT COUNT(*) INTO v_nb FROM vol WHERE volno = p_volno;
    IF v_nb = 0 THEN
        RAISE_APPLICATION_ERROR(-20007, 'Vol introuvable : ' || p_volno || '.');
    END IF;
    DELETE FROM vol WHERE volno = p_volno;   -- le trigger TRG_VOL_SUPPRESSION controle DEFPILOTE
    DBMS_OUTPUT.PUT_LINE('Vol ' || p_volno || ' supprimé.');
END prc_supprimer_vol;
/
SHOW ERRORS

-- -----------------------------------------------------------------------------
-- Droits sur les nouveaux objets (roles definis dans le script de base)
-- -----------------------------------------------------------------------------
GRANT SELECT  ON destination        TO role_lecteur;
GRANT SELECT  ON historique_salaire TO role_lecteur;
GRANT SELECT  ON prime_pilote       TO role_lecteur;
GRANT SELECT  ON v_perf_appareils   TO role_lecteur;
GRANT EXECUTE ON pkg_primes             TO role_manager;
GRANT EXECUTE ON prc_supprimer_vol      TO role_manager;
GRANT EXECUTE ON prc_rapport_performance TO role_lecteur;

PROMPT >> Objets invalides eventuels (doit etre vide) :
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';
PROMPT >> Triggers du schema :
SELECT trigger_name, trigger_type, triggering_event, status FROM user_triggers ORDER BY trigger_name;
