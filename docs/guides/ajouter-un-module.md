# Ajouter un module à un projet

`ebony add <module>` ajoute un [module](modules.md) (`db`, `auth`) à un projet qui existe déjà : créé avec `ebony new` (le kit `slim`, par exemple, qui n'a ni base ni jetons) ou adopté avec [`ebony init`](adopter-un-projet.md). C'est le même chemin que `ebony new --kit api` : le projet obtenu est celui qu'un `ebony new` avec ce module aurait écrit. Ce guide a été rejoué sous Windows et sous Linux (Ubuntu, WSL 2) avec OWL 1.8.1 et SQLite ; PostgreSQL et HFSQL ne l'ont pas été (voir la fin).

## Un exemple : de `slim` à `api`

```powershell
ebony new boutique --kit slim
cd boutique
ebony add db
ebony add auth
ebony migrate
```

`ebony add db` ajoute la base de données (SQLite par défaut) :

```text
Module ajouté au projet : db (…\boutique)
  Modules     : db
  Base        : sqlite
  Créés       : ebony/ (module db)
  Réécrits    : config/env.json, .env.exemple, .env.secrets.exemple, app/Composants.owl, ebony.conf (tels qu'ebony les avait écrits)

Pour continuer :
  ebony env
```

`ebony add auth` ajoute les jetons d'accès, et écrit la migration qui crée leur table :

```text
Module ajouté au projet : auth (…\boutique)
  Modules     : db, auth
  Base        : sqlite
  Créés       : ebony/ (module auth), database/migrations/M202611100000_CreeEbJetons.owl
  Réécrits    : .env.exemple, ebony.conf (tels qu'ebony les avait écrits)

Pour continuer :
  ebony migrate
  ebony env
```

Le résultat a été comparé à celui de `ebony new boutique` (kit `api`) : **les mêmes fichiers, octet pour octet**, à trois exceptions près, qui portent le kit d'origine : le membre `kit` de `ebony.conf` (`slim` reste noté), `README.md` et `AGENTS.md`. Le projet compile, `ebony migrate` applique la migration des jetons et `GET /api/health` répond `{"statut":"ok","base":"ok"}`.

## Ce que `ebony add` écrit

- **La bibliothèque du module** dans `ebony/` (rien d'autre n'y est touché), puis le module dans `modules` de [`ebony.conf`](ebony-conf.md), avec `base.fournisseur` quand le module en a besoin. `ebony.conf` est écrit **en dernier** : sa présence dans `modules` dit que l'ajout est terminé.
- **Les fichiers et migrations que le module déclare** (la migration des jetons, par exemple), sans jamais écraser un fichier qui existe.
- **Les fichiers qu'Ebony gère** : `config/env.json`, `.env.exemple`, `.env.secrets.exemple` (les variables du module) et `app/Composants.owl` (le registre des composants : la base y est déclarée, voir [la structure](structure.md)).

**Votre service n'est jamais modifié.** Il appelle le registre `app/Composants.owl` au démarrage : ajouter un module ne le change donc pas.

### Les fichiers que vous avez modifiés

Ebony réécrit un fichier qu'il gère **seulement s'il est encore tel qu'il l'avait écrit** pour les modules d'avant. Si vous l'avez modifié (même d'un caractère), il n'y touche pas : il le liste sous « Conservés » et dit ce qu'il faut y ajouter. Par exemple, après une modification de `config/env.json` :

```text
  Conservés   : config/env.json (modifiés par vous : non touchés)

À faire vous-même :
  - Votre config/env.json n'a pas été modifié (il n'est plus tel qu'ebony l'avait écrit). Ajoutez-y les variables : AUTH_ROUTES, puis vérifiez avec « ebony env ».
```

Le module est ajouté malgré tout (bibliothèque, `ebony.conf`) : c'est à vous de recopier ce que la note indique, puis de lancer `ebony env` pour contrôler la configuration.

## Choisir la base

`ebony add db` prend **SQLite** par défaut. `--base sqlite|postgresql|hfsql` en choisit une autre :

```powershell
ebony add db --base postgresql
```

La base choisie est notée dans `ebony.conf` (`base.fournisseur`) et dans le registre. **`ebony add` ne change jamais la base d'un projet** : `ebony add auth --base postgresql` sur un projet déjà en SQLite est refusé (code de sortie 2), de même que `--base` pour un module qui n'a pas besoin de base.

## Ce qu'il refuse

Toutes les vérifications ont lieu **avant** d'écrire : un refus ne laisse rien derrière lui. Code de sortie 1, sauf une option incorrecte (2).

| Situation | Message |
|---|---|
| Le module dépend d'un autre qui manque | « Le module « auth » a besoin de : db. Ajoutez-le d'abord (par exemple « ebony add db »). » |
| Le module n'existe pas | « Le module « validation » n'existe pas dans l'ebony installé. Modules qu'on peut ajouter : auth, db. » |
| Le module est déjà dans le projet | « … est déjà dans ce projet … » |
| `ebony/` n'est pas la bibliothèque de l'Ebony installé (un projet créé avec une version plus ancienne, par exemple) | supprimez ce dossier (Ebony ne supprime rien), lancez `ebony upgrade`, puis relancez `ebony add` |
| Un dossier du module existe déjà et n'est pas vide dans `ebony/` | la liste des éléments en conflit, sans rien écrire |
| Un `ebony.conf` ancien, sans la liste `modules` | rien à ajouter : un tel projet a déjà tous les modules |
| Ce n'est pas un projet Ebony | placez-vous dans le dossier d'un projet |
| `--base` inconnu | « Valeur refusée pour --base … Valeurs possibles : sqlite, postgresql, hfsql. » (code 2) |

Si l'écriture est interrompue en route (disque plein, accès refusé), `ebony.conf` n'a pas été modifié : le message dit ce qui a pu être laissé ; supprimez-le (le dossier du module dans `ebony/` d'abord), puis relancez.

## Un projet adopté ou créé avant le registre

Un projet adopté avec `ebony init` a déjà son registre `app/Composants.owl` et un service à lui, qui doit l'appeler (voir [adopter Ebony](adopter-un-projet.md)). Rejoué : `ebony init --kit slim`, un service qui appelle le registre, puis `ebony add db` ; le service est resté identique octet pour octet et `GET /api/health` est passé de `{"statut":"ok"}` à `{"statut":"ok","base":"ok"}`. Pour un projet qui n'a **pas** de registre, `ebony add` en écrit un quand le module apporte un composant (la base), et une note dit les lignes à ajouter au service : `POUR TOUT oFabrique DE …Fabriques()`, puis `oApp.Ajoute(oFabrique)` et `FIN`. Si ce service crée déjà la base lui-même, retirez ces lignes : elle démarrerait deux fois.

### Un projet créé par la 0.1.0

C'est le cas d'un projet créé avant le registre. Rejoué avec l'archive de la 0.1.0 publiée, puis celle-ci : un projet `ebony new boutique --kit slim` de la 0.1.0 n'a pas de `app/Composants.owl`, et son `ebony/` est celui de la 0.1.0. `ebony add db` le refuse (la bibliothèque n'est pas celle de l'Ebony installé) et `ebony upgrade` aussi tant que l'ancien `ebony/` est là : **supprimez le dossier `ebony/`** (Ebony ne supprime rien), lancez `ebony upgrade`, puis `ebony add db`. Il réécrit alors `config/env.json`, `.env.exemple` et `.env.secrets.exemple` (ils étaient tels que la 0.1.0 les avait écrits), crée `app/Composants.owl` et dit d'y brancher le service : après avoir ajouté la boucle `POUR TOUT oFabrique DE AppBoutiqueFabriques()` à `FinInitialisation`, le service démarre avec la base (`GET /api/health` : `{"statut":"ok","base":"ok"}`).

## Pour un outil : `--json`

`ebony add db --json` écrit une seule ligne :

```json
{"ok":true,"dir":"…","module":"db","modules":["db"],"base":"sqlite","files":["ebony/ (module db)"],"updated":["config/env.json",".env.exemple",".env.secrets.exemple","app/Composants.owl","ebony.conf"],"kept":[],"notes":[],"next":["ebony env"]}
```

`files` : ce qui est créé ; `updated` : ce que Ebony a réécrit ; `kept` : ce que vous aviez modifié et qu'il n'a pas touché ; `notes` : ce que vous devez faire ; `next` : les commandes à lancer ensuite. En cas d'échec : `{"ok":false,"error":…}`.

## Ce qui n'est pas essayé

Les refus d'un `ebony/` d'une autre version, d'un conflit et d'un `ebony.conf` ancien sont contrôlés par des tests sur un faux disque, pas rejoués sur un vrai projet. `ebony add` avec **PostgreSQL ou HFSQL** contre un vrai serveur (seul SQLite l'a été ; pour PostgreSQL, les fichiers écrits sont contrôlés par des tests sur un faux disque, pas par un serveur). Les options `--auth` et `--table` de `ebony new` n'ont pas d'équivalent : `ebony add auth` ajoute les jetons, pas la table des utilisateurs. `README.md` et `AGENTS.md` ne sont pas réécrits : ils parlent du kit d'origine.
