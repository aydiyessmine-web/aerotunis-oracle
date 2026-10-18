-- =============================================================================
--  BASE DE DONNÉES : AEROPORT
--  Script de création complet — Mini projet Administration Oracle
--  Dr. L. BAATI
--
--  Pré-requis : connecté en SYS AS SYSDBA (ou SYSTEM)
--  Compatibilité : Oracle 11g / 12c / 19c / 21c
--
--  Contenu :
--    PARTIE 0  — Nettoyage (idempotent)
--    PARTIE 1  — Tablespaces
--    PARTIE 2  — Schéma AEROPORT (tables + contraintes + index)
--    PARTIE 3  — Séquences
--    PARTIE 4  — Données de test
--    PARTIE 5  — Vues utiles
--    PARTIE 6  — Utilisateurs
--    PARTIE 7  — Rôles
--    PARTIE 8  — Attribution des privilèges et rôles
--    PARTIE 9  — Vérifications
-- =============================================================================

-- Affichage des messages dans SQL*Plus / SQL Developer
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
SET ECHO ON

PROMPT ============================================================
PROMPT  BASE AEROPORT — Installation complète
PROMPT ============================================================


-- =============================================================================
-- PARTIE 0 — NETTOYAGE (DROP si existe déjà)
--            Permet de relancer le script sans erreur
-- =============================================================================
PROMPT
PROMPT [0/9] Nettoyage des objets existants...

-- Utilisateurs  (CASCADE supprime tous leurs objets)
BEGIN
    FOR u IN (SELECT username FROM dba_users
              WHERE  username IN ('AEROPORT','APP_ADMIN','APP_USER','AUDITEUR'))
    LOOP
        EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
        DBMS_OUTPUT.PUT_LINE('  -> Utilisateur supprimé : ' || u.username);
    END LOOP;
END;
/

-- Rôles 
BEGIN
    FOR r IN (SELECT role FROM dba_roles
              WHERE  role IN ('ROLE_LECTEUR','ROLE_OPERATEUR','ROLE_MANAGER'))
    LOOP
        EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
        DBMS_OUTPUT.PUT_LINE('  -> Rôle supprimé : ' || r.role);
    END LOOP;
END;
/

-- Tablespaces dédiés (optionnel — commentez si vous préférez utiliser USERS/TEMP)
BEGIN
    FOR t IN (SELECT tablespace_name FROM dba_tablespaces
              WHERE  tablespace_name IN ('TS_AEROPORT','TS_AEROPORT_TMP'))
    LOOP
        EXECUTE IMMEDIATE
            'DROP TABLESPACE ' || t.tablespace_name ||
            ' INCLUDING CONTENTS AND DATAFILES CASCADE CONSTRAINTS';
        DBMS_OUTPUT.PUT_LINE('  -> Tablespace supprimé : ' || t.tablespace_name);
    END LOOP;
END;
/

PROMPT [0/9] Nettoyage terminé.


-- =============================================================================
-- PARTIE 1 — TABLESPACES DÉDIÉS
-- =============================================================================
PROMPT
PROMPT [1/9] Création des tablespaces...

-- Tablespace permanent pour les données AEROPORT
-- NOTE : adaptez le chemin du datafile à votre environnement Oracle.
--        Sur Oracle 19c/21c avec OMF (Oracle Managed Files) activé,
--        vous pouvez omettre DATAFILE et laisser Oracle gérer le fichier.
CREATE TABLESPACE ts_aeroport
    DATAFILE SIZE 50M
    AUTOEXTEND ON NEXT 10M MAXSIZE 500M
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO;

-- Tablespace temporaire dédié
CREATE TEMPORARY TABLESPACE ts_aeroport_tmp
    TEMPFILE SIZE 20M
    AUTOEXTEND ON NEXT 5M MAXSIZE 100M
    EXTENT MANAGEMENT LOCAL;

PROMPT [1/9] Tablespaces créés : TS_AEROPORT, TS_AEROPORT_TMP


-- =============================================================================
-- PARTIE 2 — UTILISATEUR SCHÉMA AEROPORT
-- =============================================================================
PROMPT
PROMPT [2/9] Création du schéma AEROPORT...

CREATE USER aeroport
    IDENTIFIED BY "Aer0p0rt#"
    DEFAULT   TABLESPACE ts_aeroport  QUOTA UNLIMITED ON ts_aeroport
    TEMPORARY TABLESPACE ts_aeroport_tmp
    ACCOUNT UNLOCK;

-- Privilèges minimaux pour le propriétaire du schéma
GRANT CREATE SESSION,
      CREATE TABLE,
      CREATE VIEW,
      CREATE SEQUENCE,
      CREATE PROCEDURE,
      CREATE TRIGGER,
      CREATE SYNONYM
TO aeroport;

PROMPT [2/9] Utilisateur AEROPORT créé.


-- =============================================================================
-- PARTIE 3 — TABLES ET CONTRAINTES (schéma AEROPORT)
-- =============================================================================
PROMPT
PROMPT [3/9] Création des tables...

-- -----------------------------------------------------------------------------
-- TABLE : PILOTE
-- -----------------------------------------------------------------------------
CREATE TABLE aeroport.pilote (
    pilno    NUMBER(6)        NOT NULL,
    nom      VARCHAR2(30)     NOT NULL,
    prenom   VARCHAR2(30)     NOT NULL,
    age      NUMBER(3),
    adresse  VARCHAR2(100),
    salaire  NUMBER(10,2),
    -- Contraintes
    CONSTRAINT pk_pilote   PRIMARY KEY (pilno),
    CONSTRAINT ck_age_pil  CHECK (age BETWEEN 18 AND 70),
    CONSTRAINT ck_sal_pil  CHECK (salaire > 0)
);

COMMENT ON TABLE  aeroport.pilote          IS 'Pilotes de la compagnie aérienne';
COMMENT ON COLUMN aeroport.pilote.pilno    IS 'Identifiant unique du pilote (brevet)';
COMMENT ON COLUMN aeroport.pilote.nom      IS 'Nom de famille';
COMMENT ON COLUMN aeroport.pilote.prenom   IS 'Prénom';
COMMENT ON COLUMN aeroport.pilote.age      IS 'Âge en années (18-70)';
COMMENT ON COLUMN aeroport.pilote.adresse  IS 'Adresse postale';
COMMENT ON COLUMN aeroport.pilote.salaire  IS 'Salaire mensuel brut en euros';

-- -----------------------------------------------------------------------------
-- TABLE : AVION
-- -----------------------------------------------------------------------------
CREATE TABLE aeroport.avion (
    avno      NUMBER(6)        NOT NULL,
    avnom     VARCHAR2(50)     NOT NULL,
    capacite  NUMBER(4)        NOT NULL,
    loc       VARCHAR2(50),
    -- Contraintes
    CONSTRAINT pk_avion       PRIMARY KEY (avno),
    CONSTRAINT ck_cap_avion   CHECK (capacite BETWEEN 1 AND 1000),
    CONSTRAINT uq_avnom       UNIQUE (avnom)
);

COMMENT ON TABLE  aeroport.avion           IS 'Flotte d''avions de la compagnie';
COMMENT ON COLUMN aeroport.avion.avno      IS 'Identifiant unique de l''avion';
COMMENT ON COLUMN aeroport.avion.avnom     IS 'Désignation commerciale de l''appareil';
COMMENT ON COLUMN aeroport.avion.capacite  IS 'Nombre de sièges passagers';
COMMENT ON COLUMN aeroport.avion.loc       IS 'Aéroport de base (localisation)';

-- -----------------------------------------------------------------------------
-- TABLE : VOL
-- -----------------------------------------------------------------------------
CREATE TABLE aeroport.vol (
    volno   VARCHAR2(10)    NOT NULL,
    dep     VARCHAR2(50)    NOT NULL,
    arr     VARCHAR2(50)    NOT NULL,
    hd      DATE            NOT NULL,
    ha      DATE            NOT NULL,
    avno    NUMBER(6),
    pilno   NUMBER(6),
    -- Contraintes
    CONSTRAINT pk_vol        PRIMARY KEY (volno),
    CONSTRAINT fk_vol_avion  FOREIGN KEY (avno)  REFERENCES aeroport.avion (avno),
    CONSTRAINT fk_vol_pilote FOREIGN KEY (pilno) REFERENCES aeroport.pilote(pilno),
    CONSTRAINT ck_heures_vol CHECK (ha > hd),
    CONSTRAINT ck_dep_arr    CHECK (dep <> arr)
);

COMMENT ON TABLE  aeroport.vol        IS 'Vols programmés de la compagnie';
COMMENT ON COLUMN aeroport.vol.volno  IS 'Numéro de vol (ex : AF101)';
COMMENT ON COLUMN aeroport.vol.dep    IS 'Aéroport de départ (IATA ou nom)';
COMMENT ON COLUMN aeroport.vol.arr    IS 'Aéroport d''arrivée (IATA ou nom)';
COMMENT ON COLUMN aeroport.vol.hd     IS 'Date et heure de départ';
COMMENT ON COLUMN aeroport.vol.ha     IS 'Date et heure d''arrivée prévue';
COMMENT ON COLUMN aeroport.vol.avno   IS 'Avion affecté au vol (FK -> AVION)';
COMMENT ON COLUMN aeroport.vol.pilno  IS 'Pilote commandant de bord (FK -> PILOTE)';

-- -----------------------------------------------------------------------------
-- TABLE : DEFPILOTE  (affectations secondaires : co-pilotes, remplaçants)
-- -----------------------------------------------------------------------------
CREATE TABLE aeroport.defpilote (
    volno   VARCHAR2(10)  NOT NULL,
    pilno   NUMBER(6)     NOT NULL,
    role    VARCHAR2(20)  DEFAULT 'COPILOTE' NOT NULL,
    -- Contraintes
    CONSTRAINT pk_defpilote      PRIMARY KEY (volno, pilno),
    CONSTRAINT fk_def_vol        FOREIGN KEY (volno)  REFERENCES aeroport.vol   (volno)  ON DELETE CASCADE,
    CONSTRAINT fk_def_pilote     FOREIGN KEY (pilno)  REFERENCES aeroport.pilote(pilno),
    CONSTRAINT ck_role_defpilote CHECK (role IN ('COPILOTE','REMPLACANT','INSTRUCTEUR'))
);

COMMENT ON TABLE  aeroport.defpilote       IS 'Affectations secondaires des pilotes sur les vols';
COMMENT ON COLUMN aeroport.defpilote.volno IS 'Numéro de vol (FK -> VOL)';
COMMENT ON COLUMN aeroport.defpilote.pilno IS 'Identifiant pilote secondaire (FK -> PILOTE)';
COMMENT ON COLUMN aeroport.defpilote.role  IS 'Rôle : COPILOTE, REMPLACANT ou INSTRUCTEUR';

PROMPT [3/9] Tables créées : PILOTE, AVION, VOL, DEFPILOTE


-- =============================================================================
-- PARTIE 4 — INDEX COMPLÉMENTAIRES
-- =============================================================================
PROMPT
PROMPT [4/9] Création des index...

-- Index sur les FK pour éviter les full scans lors des jointures
CREATE INDEX aeroport.idx_vol_avno   ON aeroport.vol(avno);
CREATE INDEX aeroport.idx_vol_pilno  ON aeroport.vol(pilno);
CREATE INDEX aeroport.idx_vol_dep    ON aeroport.vol(dep);
CREATE INDEX aeroport.idx_vol_arr    ON aeroport.vol(arr);
CREATE INDEX aeroport.idx_pil_nom    ON aeroport.pilote(nom, prenom);

PROMPT [4/9] Index créés.


-- =============================================================================
-- PARTIE 5 — SÉQUENCES
-- =============================================================================
PROMPT
PROMPT [5/9] Création des séquences...

CREATE SEQUENCE aeroport.seq_pilote
    START WITH 100
    INCREMENT BY 1
    NOCACHE
    NOCYCLE;

CREATE SEQUENCE aeroport.seq_avion
    START WITH 10
    INCREMENT BY 1
    NOCACHE
    NOCYCLE;

PROMPT [5/9] Séquences créées : SEQ_PILOTE, SEQ_AVION


-- =============================================================================
-- PARTIE 6 — DONNÉES DE TEST
-- =============================================================================
PROMPT
PROMPT [6/9] Insertion des données de test...

-- ── PILOTES ──────────────────────────────────────────────────────────────────
INSERT INTO aeroport.pilote VALUES (aeroport.seq_pilote.NEXTVAL, 'Laroche',  'Pierre',   39, 'Montauban',          4800);
INSERT INTO aeroport.pilote VALUES (aeroport.seq_pilote.NEXTVAL, 'Lamothe',  'Sophie',   34, 'Ramonville-St-Agne', 4200);
INSERT INTO aeroport.pilote VALUES (aeroport.seq_pilote.NEXTVAL, 'Albaric',  'Marc',     34, 'Vieille-Toulouse',   4500);
INSERT INTO aeroport.pilote VALUES (aeroport.seq_pilote.NEXTVAL, 'Labat',    'Julie',    33, 'Pau',                4100);
INSERT INTO aeroport.pilote VALUES (aeroport.seq_pilote.NEXTVAL, 'Dupont',   'Jean',     45, 'Paris 15e',          5200);
INSERT INTO aeroport.pilote VALUES (aeroport.seq_pilote.NEXTVAL, 'Martin',   'Carole',   38, 'Lyon 3e',            4900);
INSERT INTO aeroport.pilote VALUES (aeroport.seq_pilote.NEXTVAL, 'Ferrand',  'Thomas',   52, 'Bordeaux',           5600);
INSERT INTO aeroport.pilote VALUES (aeroport.seq_pilote.NEXTVAL, 'Nguyen',   'Linh',     29, 'Toulouse',           3900);

-- ── AVIONS ───────────────────────────────────────────────────────────────────
INSERT INTO aeroport.avion VALUES (aeroport.seq_avion.NEXTVAL, 'Airbus A320',    180, 'Toulouse-Blagnac');
INSERT INTO aeroport.avion VALUES (aeroport.seq_avion.NEXTVAL, 'Airbus A380',    555, 'Paris-CDG');
INSERT INTO aeroport.avion VALUES (aeroport.seq_avion.NEXTVAL, 'Boeing 737-800', 162, 'Lyon-Saint-Exupéry');
INSERT INTO aeroport.avion VALUES (aeroport.seq_avion.NEXTVAL, 'Boeing 777-300', 396, 'Paris-CDG');
INSERT INTO aeroport.avion VALUES (aeroport.seq_avion.NEXTVAL, 'ATR 72-600',      70, 'Toulouse-Blagnac');
INSERT INTO aeroport.avion VALUES (aeroport.seq_avion.NEXTVAL, 'Airbus A350-900', 369, 'Paris-Orly');

-- ── VOLS (utilisation de variables pour éviter les valeurs en dur) ───────────
INSERT INTO aeroport.vol VALUES (
    'AF101',
    'Paris-CDG', 'Toulouse-Blagnac',
    TO_DATE('2025-06-15 08:00','YYYY-MM-DD HH24:MI'),
    TO_DATE('2025-06-15 09:10','YYYY-MM-DD HH24:MI'),
    (SELECT avno FROM aeroport.avion WHERE avnom = 'Airbus A320'),
    (SELECT pilno FROM aeroport.pilote WHERE nom = 'Laroche')
);
INSERT INTO aeroport.vol VALUES (
    'AF202',
    'Toulouse-Blagnac', 'Paris-CDG',
    TO_DATE('2025-06-15 10:30','YYYY-MM-DD HH24:MI'),
    TO_DATE('2025-06-15 11:40','YYYY-MM-DD HH24:MI'),
    (SELECT avno FROM aeroport.avion WHERE avnom = 'Airbus A320'),
    (SELECT pilno FROM aeroport.pilote WHERE nom = 'Lamothe')
);
INSERT INTO aeroport.vol VALUES (
    'AF305',
    'Paris-CDG', 'New York-JFK',
    TO_DATE('2025-06-16 14:00','YYYY-MM-DD HH24:MI'),
    TO_DATE('2025-06-16 22:30','YYYY-MM-DD HH24:MI'),
    (SELECT avno FROM aeroport.avion WHERE avnom = 'Boeing 777-300'),
    (SELECT pilno FROM aeroport.pilote WHERE nom = 'Ferrand')
);
INSERT INTO aeroport.vol VALUES (
    'AF406',
    'Lyon-Saint-Exupéry', 'Marseille-Provence',
    TO_DATE('2025-06-17 07:15','YYYY-MM-DD HH24:MI'),
    TO_DATE('2025-06-17 08:00','YYYY-MM-DD HH24:MI'),
    (SELECT avno FROM aeroport.avion WHERE avnom = 'ATR 72-600'),
    (SELECT pilno FROM aeroport.pilote WHERE nom = 'Albaric')
);
INSERT INTO aeroport.vol VALUES (
    'AF510',
    'Paris-CDG', 'Tokyo-Narita',
    TO_DATE('2025-06-18 11:00','YYYY-MM-DD HH24:MI'),
    TO_DATE('2025-06-19 06:30','YYYY-MM-DD HH24:MI'),
    (SELECT avno FROM aeroport.avion WHERE avnom = 'Airbus A380'),
    (SELECT pilno FROM aeroport.pilote WHERE nom = 'Dupont')
);
INSERT INTO aeroport.vol VALUES (
    'AF612',
    'Bordeaux-Mérignac', 'Paris-CDG',
    TO_DATE('2025-06-18 16:45','YYYY-MM-DD HH24:MI'),
    TO_DATE('2025-06-18 17:55','YYYY-MM-DD HH24:MI'),
    (SELECT avno FROM aeroport.avion WHERE avnom = 'Boeing 737-800'),
    (SELECT pilno FROM aeroport.pilote WHERE nom = 'Martin')
);

-- ── AFFECTATIONS SECONDAIRES (DEFPILOTE) ─────────────────────────────────────
INSERT INTO aeroport.defpilote VALUES (
    'AF305',
    (SELECT pilno FROM aeroport.pilote WHERE nom = 'Labat'),
    'COPILOTE'
);
INSERT INTO aeroport.defpilote VALUES (
    'AF305',
    (SELECT pilno FROM aeroport.pilote WHERE nom = 'Nguyen'),
    'INSTRUCTEUR'
);
INSERT INTO aeroport.defpilote VALUES (
    'AF510',
    (SELECT pilno FROM aeroport.pilote WHERE nom = 'Martin'),
    'COPILOTE'
);
INSERT INTO aeroport.defpilote VALUES (
    'AF101',
    (SELECT pilno FROM aeroport.pilote WHERE nom = 'Lamothe'),
    'COPILOTE'
);

COMMIT;
PROMPT [6/9] Données insérées et validées (COMMIT).


-- =============================================================================
-- PARTIE 7 — VUES UTILES (dans le schéma AEROPORT)
-- =============================================================================
PROMPT
PROMPT [7/9] Création des vues...

-- Vue : récapitulatif des vols avec noms lisibles
CREATE OR REPLACE VIEW aeroport.v_vols_detail AS
    SELECT  v.volno,
            v.dep                               AS depart,
            v.arr                               AS arrivee,
            TO_CHAR(v.hd, 'DD/MM/YYYY HH24:MI') AS heure_depart,
            TO_CHAR(v.ha, 'DD/MM/YYYY HH24:MI') AS heure_arrivee,
            a.avnom                             AS avion,
            a.capacite,
            p.nom  || ' ' || p.prenom           AS commandant_bord
    FROM    aeroport.vol     v
    JOIN    aeroport.avion   a ON a.avno  = v.avno
    JOIN    aeroport.pilote  p ON p.pilno = v.pilno;

-- Vue : liste des affectations secondaires avec détails
CREATE OR REPLACE VIEW aeroport.v_affectations AS
    SELECT  d.volno,
            v.dep || ' → ' || v.arr             AS trajet,
            p.nom || ' ' || p.prenom            AS pilote,
            d.role
    FROM    aeroport.defpilote d
    JOIN    aeroport.pilote    p ON p.pilno = d.pilno
    JOIN    aeroport.vol       v ON v.volno = d.volno
    ORDER BY d.volno, d.role;

PROMPT [7/9] Vues créées : V_VOLS_DETAIL, V_AFFECTATIONS


-- =============================================================================
-- PARTIE 8 — UTILISATEURS 
-- =============================================================================
PROMPT
PROMPT [8/9] Création des utilisateurs ...

-- ── APP_ADMIN : administrateur applicatif ────────────────────────────────────
CREATE USER app_admin
    IDENTIFIED BY "Oracle1!"
    DEFAULT   TABLESPACE ts_aeroport  QUOTA 50M ON ts_aeroport
    TEMPORARY TABLESPACE ts_aeroport_tmp
    PASSWORD EXPIRE
    ACCOUNT UNLOCK;

-- ── APP_USER : utilisateur applicatif standard ───────────────────────────────
CREATE USER app_user
    IDENTIFIED BY "Oracle2!"
    DEFAULT   TABLESPACE ts_aeroport  QUOTA 10M ON ts_aeroport
    TEMPORARY TABLESPACE ts_aeroport_tmp
    ACCOUNT LOCK;

-- ── AUDITEUR : consultation uniquement ───────────────────────────────────────
CREATE USER auditeur
    IDENTIFIED BY "Oracle3!"
    DEFAULT   TABLESPACE ts_aeroport
    TEMPORARY TABLESPACE ts_aeroport_tmp
    ACCOUNT UNLOCK;

-- Déverrouillage et augmentation de quota pour APP_USER (exercice 1, Q4)
ALTER USER app_user ACCOUNT UNLOCK;
ALTER USER app_user QUOTA 20M ON ts_aeroport;

PROMPT [8/9] Utilisateurs créés : APP_ADMIN, APP_USER, AUDITEUR


-- =============================================================================
-- PARTIE 9 — RÔLES ET ATTRIBUTION DES PRIVILÈGES
-- =============================================================================
PROMPT
PROMPT [9/9] Création des rôles et attribution des privilèges...

-- ── Privilèges système ───────────────────────────────────────────────────────
GRANT CREATE SESSION,
      CREATE TABLE,
      CREATE VIEW,
      CREATE PROCEDURE,
      CREATE SEQUENCE
TO app_admin;

GRANT CREATE SESSION TO app_user;

GRANT CREATE SESSION,
      SELECT ANY DICTIONARY
TO auditeur;

-- ── Rôles personnalisés ──────────────────────────────────────────────────────

-- Rôle 1 : lecture seule sur toutes les tables
CREATE ROLE role_lecteur NOT IDENTIFIED;

GRANT SELECT ON aeroport.pilote    TO role_lecteur;
GRANT SELECT ON aeroport.avion     TO role_lecteur;
GRANT SELECT ON aeroport.vol       TO role_lecteur;
GRANT SELECT ON aeroport.defpilote TO role_lecteur;
GRANT SELECT ON aeroport.v_vols_detail  TO role_lecteur;
GRANT SELECT ON aeroport.v_affectations TO role_lecteur;

-- Rôle 2 : opérations de saisie/modification
CREATE ROLE role_operateur NOT IDENTIFIED;

GRANT INSERT, UPDATE ON aeroport.pilote    TO role_operateur;
GRANT INSERT, UPDATE ON aeroport.vol       TO role_operateur;
GRANT INSERT, UPDATE ON aeroport.defpilote TO role_operateur;
GRANT INSERT, UPDATE ON aeroport.avion     TO role_operateur;

-- Rôle 3 : rôle composite (lecteur + opérateur + suppression)
CREATE ROLE role_manager NOT IDENTIFIED;

GRANT role_lecteur, role_operateur TO role_manager;
GRANT DELETE ON aeroport.vol       TO role_manager;
GRANT DELETE ON aeroport.pilote    TO role_manager;
GRANT DELETE ON aeroport.defpilote TO role_manager;

-- ── Attribution des rôles aux utilisateurs ───────────────────────────────────
GRANT role_lecteur   TO auditeur;
GRANT role_operateur TO app_user;
GRANT role_manager   TO app_admin;

-- ── Privilèges objets directs supplémentaires ────────────────────────────────
-- APP_ADMIN peut sélectionner dans toutes les séquences
GRANT SELECT ON aeroport.seq_pilote TO app_admin;
GRANT SELECT ON aeroport.seq_avion  TO app_admin;

-- Privilège de colonne spécifique (exercice 2, Q5)
-- APP_USER ne peut modifier que nom et prenom sur PILOTE
GRANT UPDATE(nom, prenom) ON aeroport.pilote TO app_user;

PROMPT [9/9] Rôles et privilèges configurés.


-- =============================================================================
-- VÉRIFICATIONS FINALES
-- =============================================================================
PROMPT
PROMPT ============================================================
PROMPT  VÉRIFICATIONS
PROMPT ============================================================

PROMPT
PROMPT >> Utilisateurs créés :
SELECT username,
       account_status,
       default_tablespace,
       TO_CHAR(created, 'DD/MM/YYYY') AS created
FROM   dba_users
WHERE  username IN ('AEROPORT','APP_ADMIN','APP_USER','AUDITEUR')
ORDER  BY username;

PROMPT
PROMPT >> Quotas par tablespace :
SELECT username, tablespace_name,
       DECODE(max_bytes, -1, 'UNLIMITED',
              TO_CHAR(ROUND(max_bytes/1048576,1)) || ' Mo') AS quota_max,
       ROUND(bytes/1048576, 3)                              AS utilise_mo
FROM   dba_ts_quotas
WHERE  username IN ('AEROPORT','APP_ADMIN','APP_USER','AUDITEUR')
ORDER  BY username, tablespace_name;

PROMPT
PROMPT >> Rôles définis :
SELECT role, authentication_type
FROM   dba_roles
WHERE  role IN ('ROLE_LECTEUR','ROLE_OPERATEUR','ROLE_MANAGER')
ORDER  BY role;

PROMPT
PROMPT >> Attribution des rôles :
SELECT grantee, granted_role, admin_option, default_role
FROM   dba_role_privs
WHERE  grantee IN ('APP_ADMIN','APP_USER','AUDITEUR',
                   'ROLE_MANAGER','ROLE_OPERATEUR')
ORDER  BY grantee, granted_role;

PROMPT
PROMPT >> Privilèges système des utilisateurs :
SELECT grantee, privilege, admin_option
FROM   dba_sys_privs
WHERE  grantee IN ('APP_ADMIN','APP_USER','AUDITEUR')
ORDER  BY grantee, privilege;

PROMPT
PROMPT >> Tables du schéma AEROPORT :
SELECT object_name, object_type,
       TO_CHAR(created,'DD/MM/YYYY HH24:MI') AS cree_le,
       status
FROM   dba_objects
WHERE  owner = 'AEROPORT'
ORDER  BY object_type, object_name;

PROMPT
PROMPT >> Nombre de lignes par table :
SELECT 'PILOTE'    AS table_name, COUNT(*) AS nb_lignes FROM aeroport.pilote    UNION ALL
SELECT 'AVION',                   COUNT(*)              FROM aeroport.avion     UNION ALL
SELECT 'VOL',                     COUNT(*)              FROM aeroport.vol       UNION ALL
SELECT 'DEFPILOTE',               COUNT(*)              FROM aeroport.defpilote;

PROMPT
PROMPT >> Test de la vue V_VOLS_DETAIL :
SELECT volno, depart, arrivee, heure_depart, avion, commandant_bord
FROM   aeroport.v_vols_detail
ORDER  BY volno;

PROMPT
PROMPT ============================================================
PROMPT  Installation terminée avec succès !
PROMPT  Schéma AEROPORT prêt
PROMPT ============================================================


-- =============================================================================
-- MÉMO CONNEXIONS 
-- =============================================================================
-- 
--  Connexion DBA :         CONNECT sys/[password] AS SYSDBA
--  Schéma données :        CONNECT aeroport/"Aer0p0rt#"
--  Utilisateur admin :     CONNECT app_admin/"Oracle1!"  (mdp à changer 1ère connexion)
--  Utilisateur standard :  CONNECT app_user/"Oracle2!"
--  Utilisateur auditeur :  CONNECT auditeur/"Oracle3!"
--
-- =============================================================================
