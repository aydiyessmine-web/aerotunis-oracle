-- =============================================================================
-- STEP 2 : Securite et controle d'acces (execute en SYS dans XEPDB1)
-- =============================================================================
@@00_config.sql
WHENEVER SQLERROR CONTINUE
PROMPT
PROMPT [STEP 2] Securite et controle d'acces

-- 2.1 Profil de maintenance : mot de passe a changer tous les 30 jours (APP_ADMIN)
--     + 2.2 verrouillage apres 3 tentatives de connexion infructueuses
CREATE PROFILE profil_admin_app LIMIT
    PASSWORD_LIFE_TIME    30
    PASSWORD_GRACE_TIME   3
    FAILED_LOGIN_ATTEMPTS 3
    PASSWORD_LOCK_TIME    1;

-- 2.2 Verrouillage automatique pour les autres comptes applicatifs
CREATE PROFILE profil_app LIMIT
    FAILED_LOGIN_ATTEMPTS 3
    PASSWORD_LOCK_TIME    1;

ALTER USER app_admin PROFILE profil_admin_app;
ALTER USER app_user  PROFILE profil_app;
ALTER USER auditeur  PROFILE profil_app;

-- 2.3 Audit de lecture : chaque SELECT sur la vue V_VOLS_DETAIL est consigne (audit unifie)
CREATE AUDIT POLICY pol_audit_v_vols_detail
    ACTIONS SELECT ON aeroport.v_vols_detail;
AUDIT POLICY pol_audit_v_vols_detail;

PROMPT >> Profils et politique d'audit installes :
SELECT username, profile, account_status FROM dba_users
WHERE  username IN ('APP_ADMIN','APP_USER','AUDITEUR') ORDER BY username;
SELECT policy_name, enabled_option FROM audit_unified_enabled_policies
WHERE  policy_name = 'POL_AUDIT_V_VOLS_DETAIL';
