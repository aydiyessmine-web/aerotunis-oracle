-- Rend l'installation rejouable : retire la politique d'audit et les profils d'une execution precedente
WHENEVER SQLERROR CONTINUE
PROMPT [PRE] Nettoyage de l'audit et des profils (les erreurs "n'existe pas" sont normales a la 1re execution)
NOAUDIT POLICY pol_audit_v_vols_detail;
DROP AUDIT POLICY pol_audit_v_vols_detail;
DROP PROFILE profil_admin_app CASCADE;
DROP PROFILE profil_app CASCADE;
