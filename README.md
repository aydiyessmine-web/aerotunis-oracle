# AeroTunis : modernisation du système d'information (Oracle, PL/SQL)

Mini-projet du module **Administration SGBD** (ISG Tunis, Dr. Baati). La base `AEROPORT` fournie est déployée automatiquement dans une instance Oracle XE isolée (Docker), puis enrichie de règles de gestion, d'une sécurité renforcée et d'automatismes PL/SQL.

Réalisé par Aydi Yassmine, Guesmi Farah et Kaabi Ghada.

## Lancer le projet

Prérequis : **Docker Desktop** démarré.

```
deploy.bat          (Windows)
./deploy.sh         (Linux / macOS)
```

Le script démarre Oracle XE 21c, installe le schéma, applique la sécurité et la logique métier, exécute les tests et teste une connexion distante. Les journaux sont écrits dans `docs/` :

| Fichier | Contenu |
|---|---|
| `docs/journal_installation.log` | installation du schéma, de la sécurité et des objets PL/SQL |
| `docs/journal_tests.log` | journal de tests : une ligne `REUSSI` ou `ECHEC` par règle |

Connexion depuis l'hôte (simulation d'un accès distant) : `localhost:1521`, service `XEPDB1`, par exemple avec SQL Developer, DBeaver ou `sqlplus auditeur/"Oracle3!"@//localhost:1521/XEPDB1`.

## Contenu du dépôt

```
aerotunis-oracle/
├── docker-compose.yml        Instance Oracle XE isolée, port 1521, volume persistant
├── deploy.bat / deploy.sh    Déploiement automatisé
├── sql/
│   ├── 00_config.sql         Paramètres communs
│   ├── 01_pre_nettoyage.sql  Rend l'installation rejouable
│   ├── 02_aeroport_setup.sql Script de base fourni (tables, séquences, données, utilisateurs)
│   ├── 03_securite.sql       Step 2 : profils, verrouillage, audit
│   ├── 04_logique_metier.sql Steps 3 et 4 : PL/SQL
│   ├── 05_tests.sql          Journal de tests
│   ├── 06_test_reseau.sql    Connexion distante depuis un autre conteneur
│   └── run_all.sql           Enchaîne les scripts
└── docs/                     Journaux générés
```

## Ce qui est réalisé

### Step 1 : infrastructure
- Instance Oracle XE 21c dans un conteneur Docker isolé (`docker-compose.yml`).
- Exécution automatique de `aeroport_setup.sql` (tables, séquences, données, utilisateurs) par `deploy.bat`.
- Accès réseau : port 1521 publié, et test de connexion depuis un second conteneur via le réseau `aerotunis-net` (`06_test_reseau.sql`).

### Step 2 : sécurité
| Exigence | Réalisation |
|---|---|
| Changement de mot de passe tous les 30 jours (administrateur) | profil `PROFIL_ADMIN_APP` : `PASSWORD_LIFE_TIME 30`, affecté à `APP_ADMIN` |
| Blocage après 3 échecs de connexion | `FAILED_LOGIN_ATTEMPTS 3` dans `PROFIL_ADMIN_APP` et `PROFIL_APP` (`APP_USER`, `AUDITEUR`) |
| Audit de lecture de `V_VOLS_DETAIL` | politique d'audit unifié `POL_AUDIT_V_VOLS_DETAIL`, consultable dans `UNIFIED_AUDIT_TRAIL` |

### Step 3 : logique métier
| # | Règle | Objet |
|---|---|---|
| 3.1 | Pas de chevauchement d'horaires pour un pilote (commandant ou affectation secondaire) | triggers composés `TRG_DISPO_PILOTE_VOL`, `TRG_DISPO_PILOTE_DEF`, package `PKG_REGLES` |
| 3.2 | Prime mensuelle selon les heures de vol | package `PKG_PRIMES`, table `PRIME_PILOTE` |
| 3.3 | Journal des modifications de salaire (ancien, nouveau, date, auteur) | trigger `TRG_HIST_SALAIRE`, table `HISTORIQUE_SALAIRE` |
| 3.4 | Rapport de performance : vols par avion et taux de remplissage moyen | vue `V_PERF_APPAREILS`, procédure `PRC_RAPPORT_PERFORMANCE` |
| 3.5 | Escale valide et durée d'au moins 30 minutes | trigger `TRG_VOL_VALIDATION`, table `DESTINATION` |
| 3.6 | Aucune modification de `PILOTE` le week-end | trigger `TRG_PILOTE_WEEKEND` |

### Step 4 : robustesse
| # | Règle | Objet |
|---|---|---|
| 4.1 | Capacité de l'avion non dépassée, message explicite | trigger `TRG_VOL_CAPACITE` |
| 4.2 | `SEQ_PILOTE` toujours utilisée, de façon transparente | trigger `TRG_PILOTE_SEQ` |
| 4.3 | Suppression d'un vol refusée s'il a des affectations dans `DEFPILOTE` | trigger `TRG_VOL_SUPPRESSION`, procédure `PRC_SUPPRIMER_VOL` |

Codes d'erreur applicatifs : `-20001` chevauchement, `-20002` destination invalide, `-20003` week-end, `-20004` capacité, `-20005` suppression refusée, `-20006` durée incohérente, `-20007` vol introuvable, `-20008` pilote inconnu, `-20009` paramètre manquant, `-20010` avion introuvable.

## Choix de conception

- **Passagers par vol** : la table `VOL` ne contenait pas le nombre de passagers. La colonne `NBPASSAGERS` a été ajoutée, car elle est nécessaire au taux de remplissage (3.4) et au contrôle de capacité (4.1).
- **Destination valide** : la table `DESTINATION` liste les aéroports acceptés (colonne `ACTIF`). Un vol vers un aéroport absent ou désactivé est refusé.
- **Barème des primes** : 20 h ou plus : 12 €/h ; 8 h ou plus : 8 €/h ; 1 h ou plus : 5 €/h ; sinon 0. Seuls les vols terminés du mois comptent, comme commandant ou via `DEFPILOTE`.
- **Triggers composés** pour 3.1 : la vérification se fait après l'instruction, ce qui évite l'erreur `ORA-04091` (table en mutation).
- **Tests du week-end** : la date système est simulée avec `FIXED_DATE`, puis rétablie à la fin des tests.

## Limites et évolutions possibles

- Le barème des primes est fixé dans le code : il pourrait être déplacé dans une table de paramètres.
- Le calcul mensuel est lancé à la demande : un job `DBMS_SCHEDULER` pourrait l'automatiser.
- Les mots de passe de démonstration sont dans les scripts : à remplacer par des secrets pour un usage réel.
- Les affectations d'avions ne vérifient pas encore les chevauchements d'horaires d'un même appareil.
