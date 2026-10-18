-- Execute toute la chaine : nettoyage, installation, securite, logique metier, tests
@@00_config.sql
WHENEVER SQLERROR CONTINUE
SPOOL /work/docs/journal_installation.log
PROMPT ============================================================
PROMPT  AEROTUNIS : installation complete
PROMPT ============================================================
CONNECT sys/&SYS_PWD@&CONN AS SYSDBA
@@01_pre_nettoyage.sql
@@02_aeroport_setup.sql
@@03_securite.sql
@@04_logique_metier.sql
SPOOL OFF
@@05_tests.sql
EXIT
