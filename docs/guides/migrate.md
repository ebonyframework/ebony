# `ebony migrate` : appliquer, lister et défaire les migrations

```
ebony migrate [--dry-run] [--json]                      applique les migrations en attente, dans l'ordre
ebony migrate status [--json]                           liste les migrations et leur état
ebony migrate rollback [--pas N] [--dry-run] [--json]   défait la dernière migration appliquée (ou les N dernières)
```

À lancer dans le dossier d'un projet ebony (un `ebony.conf`), après `ebony make migration`. La base est celle de la configuration du projet (`config/env.json`, `.env`, `.env.secrets` : `ebony env` la montre) : `DB_FICHIER` pour SQLite ; `DB_HOTE`, `DB_PORT`, `DB_NOM`, `DB_UTILISATEUR`, `DB_MOT_DE_PASSE` pour PostgreSQL (et `DB_TLS`, `DB_CERTIFICAT_CA` : voir [configuration.md](configuration.md)). **SQLite et PostgreSQL 16 sont vérifiés** ; HFSQL est refusé (code 39).

## Comment ça marche

- Les migrations sont les fichiers `database/migrations/M<horodatage>_<Intention>.owl` écrits par `ebony make migration`. Les autres fichiers du dossier sont ignorés. L'ordre est celui des **noms** (l'horodatage est à la minute : deux migrations écrites dans la même minute passent dans l'ordre alphabétique de leur intention).
- **ebony lit le SQL dans le fichier, il n'exécute pas la classe** : une migration est du code OWL de *votre* projet, et ebony (un autre projet OWL) ne peut ni le charger ni l'évaluer. Il reconnaît donc une forme, celle que `make migration` écrit :

  ```
  PROCEDURE PUBLIQUE Monte() : tableau de chaînes
      tabSql est un tableau de chaînes
      TableauAjoute(tabSql, `texte SQL, sur une ou plusieurs lignes`)    (ou "texte SQL" entre guillemets)
      RENVOYER tabSql
  FIN
  ```

  Même chose pour `Descend()`. Une instruction par `TableauAjoute`, dans l'ordre d'envoi. **Une migration qui calcule son SQL** (concaténation, condition, appel) **est refusée** (code 44, avec le fichier et la ligne) : ebony ne l'applique jamais à moitié. Pour ajouter une colonne à la main, écrivez une migration de cette forme.
- Chaque instruction est envoyée **seule** : OWL n'exécute que la première de deux instructions séparées par `;` dans un même envoi, en annonçant un succès (mesuré sur SQLite).
- **Une migration = une transaction** : `BEGIN`, ses instructions, son inscription dans le suivi, `COMMIT`. Si une instruction est refusée, tout est annulé (`ROLLBACK`), les migrations précédentes restent appliquées et la commande s'arrête (code 1, message avec la migration, le numéro de l'instruction et la cause de la base). Mesuré sur SQLite : un `ROLLBACK` défait un `CREATE TABLE` et un `INSERT`.
- **Le suivi** est la table `eb_migrations` (`nom`, `applique_le`, date UTC ISO 8601), créée au premier `migrate` qui a quelque chose à appliquer.
- **Tout est lu avant la première instruction** : une migration illisible (code 44), ou le fichier manquant d'une migration à défaire (code 47), arrête la commande sans toucher à la base.

## Les trois commandes

| Commande | Ce qu'elle fait |
|---|---|
| `migrate` | applique, dans l'ordre, chaque migration absente de `eb_migrations`. Rien en attente : code 0, « Rien à appliquer ». |
| `migrate --dry-run` | dit lesquelles seraient appliquées, sans envoyer d'instruction (ni créer `eb_migrations`). |
| `migrate status` | liste toutes les migrations : `applied`, `pending`, ou `missing` (appliquée, mais son fichier n'est plus dans le projet). N'écrit rien. |
| `migrate rollback` | exécute le `Descend()` de la dernière migration appliquée et retire son inscription. `--pas N` : les N dernières, de la plus récente à la plus ancienne. Si le fichier de l'une d'elles manque : code 47, rien n'est défait. |

**Effet de bord à connaître** : `status` et `--dry-run` ouvrent la base. Avec SQLite, si le fichier n'existe pas (`storage/app.db`), SQLite le crée **vide** (le dossier `storage/` aussi). Aucune table n'est créée.

## Sortie `--json`

Une seule ligne sur la sortie standard, rien d'autre :

```json
{"ok":true,"command":"migrate","base":"sqlite","dir":"C:\\Projets\\boutique","dryRun":false,
 "done":["M202611021015_CreeClients"],
 "migrations":[{"name":"M202611021015_CreeClients","status":"applied","appliedAt":"2026-11-07T09:30:00Z"}],
 "notes":[]}
```

| Clé | Sens |
|---|---|
| `command` | `migrate`, `migrate status` ou `migrate rollback` |
| `base` | le fournisseur de `ebony.conf` (`sqlite`, `postgresql`) |
| `dir` | le dossier du projet |
| `dryRun` | `true` pour `--dry-run` |
| `done` | les migrations appliquées ou défaites par la commande (avec `--dry-run` : celles qui le seraient ; vide pour `status`) |
| `migrations` | toutes, dans l'ordre, **telles qu'elles sont après la commande** ; `status` vaut `applied`, `pending` ou `missing` ; `appliedAt` est vide si elle n'est pas appliquée |
| `notes` | ce que l'utilisateur doit regarder (une migration sans fichier, PostgreSQL vérifié sur la version 16 seulement) |

En cas d'échec : `{"ok":false,"error":"…"}`, une ligne, sans pile d'appels. Sans `--json`, la même chose en texte (`ebony : <cause>` pour une erreur).

## Codes de sortie et d'exception

| Sortie | Cas |
|---|---|
| 0 | réussi (y compris « rien à faire ») |
| 2 | usage incorrect (code 25) : sous-commande ou option inconnue, `--pas` invalide ou sans `rollback`, `--dry-run` avec `status` |
| 1 | échec : 30 OWL mal placé, 31 pas un projet ebony, 38 `ebony.conf` sans base, 39 HFSQL, 44 migration non reconnue, 45 base injoignable, 46 instruction ou suivi refusés par la base (migration annulée), 47 rollback impossible (fichier absent), 60 configuration invalide |

## Ce qui n'est pas fait

- **PostgreSQL : seule la version 16 est vérifiée** (`tests/integration/postgresql.ps1`, contre un conteneur jetable) : le suivi, les transactions, le `Descend()` et le DDL annulé avec la transaction (`CREATE TABLE` défait par le `ROLLBACK`). Pas les autres versions, ni un PostgreSQL géré par un hébergeur.
- **TLS** : OWL exige un TLS vérifié par défaut, donc un PostgreSQL local sans TLS est refusé tant qu'on n'écrit pas `DB_TLS=desactive` dans `.env` (le message d'erreur le dit). Le niveau `verifie` avec le magasin de confiance d'OWL (un certificat signé par une autorité publique, Let's Encrypt par exemple) n'a pas été essayé : seul un certificat d'autorité de test (`DB_CERTIFICAT_CA`) l'a été.
- Les migrations qui calculent leur SQL, les migrations qui ne sont pas des fichiers `M<horodatage>_…owl`, un ordre différent de l'ordre alphabétique, les migrations « groupées par lot » : rien de cela.
- Une migration appliquée dont vous avez **modifié le fichier** après coup n'est pas détectée (pas de somme de contrôle).
- Aucun verrou : deux `ebony migrate` lancés en même temps sur la même base ne sont pas protégés l'un de l'autre.
