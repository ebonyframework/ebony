# `ebony make` : écrire une ressource ou une migration

Contrat lu par les outils (un IDE, par exemple) et par les utilisateurs. Tout ce qui est écrit ici est testé : `tests/unitaires/commandes/make/` (faux disque) et `tests/integration/lanceur.ps1 -Groupe make` (vrai lanceur, projet généré compilé et testé par le vrai `owl`).

```
ebony make resource <Nom> --champs <liste> [--table <table>] [--dry-run] [--json]
ebony make migration <Nom> --champs <liste> [--table <table>] [--dry-run] [--json]
```

À lancer **dans le dossier d'un projet créé par `ebony new` ou `ebony init`** (un `ebony.conf` dans le dossier courant, pas de remontée vers les parents).
`ebony` sans argument (ou `ebony aide`) liste `make` et ses options : c'est ce que lit un outil pour savoir ce que l'ebony installé sait faire.

## `--champs` : la grammaire

Des champs séparés par des virgules (les espaces autour sont ignorés) : `nom:type[marqueurs]`.

| Partie | Sens |
|---|---|
| `nom` | le nom de la colonne **dans la base**, tel quel (accents, espaces, majuscules : `Date de naissance`). Refusés : `"` `` ` `` `[` `]` `%` `{` `}` `,` `:` et les caractères de commande. |
| `type` | `entier`, `texte`, `reel`, `booleen`, `date`, `dateheure` (accents et majuscules tolérés : `réel`, `Booléen`). |
| `*` | clé primaire, `NOT NULL`. Une seule, de type `entier` (supposée **générée par la base**) ou `texte` (fournie par l'appelant). Pas de clé composée. |
| `?` | la colonne accepte `NULL`. Sans `?`, elle est `NOT NULL` dans la migration. |
| `@table` | clé étrangère vers `table.id` ; `@table.colonne` ou `@schema.table.colonne` pour une autre colonne. Utilisée par la migration. |

Les marqueurs suivent le type, dans n'importe quel ordre, sauf `@` qui vient en dernier (un `*` ou `?` écrit après `@` est refusé : il serait avalé dans le nom de la table) : `id:entier*`, `email:texte?`, `client_id:entier@clients`, `pays:texte?@pays.code`.
Aucun n'est un caractère spécial de `cmd` ni de PowerShell (pas de `>` ni de `&`).

Exemple : `id:entier*,nom:texte,email:texte?,client_id:entier@clients,actif:booleen,note:reel,cree:dateheure?`

**Un type inconnu est refusé** (code 2, le message liste les types) : jamais remplacé par `texte` en silence. C'est à l'IDE de faire la correspondance entre les types du moteur et ceux-ci :

| Types du moteur (exemples) | Type ebony |
|---|---|
| `INTEGER`, `BIGINT`, `SMALLINT`, `serial` | `entier` |
| `TEXT`, `varchar(80)`, `char`, `uuid`, `json` | `texte` |
| `REAL`, `FLOAT`, `DOUBLE PRECISION`, `NUMERIC`, `DECIMAL` | `reel` |
| `BOOLEAN`, `bit`, `tinyint(1)` | `booleen` |
| `DATE` | `date` |
| `timestamp`, `datetime` | `dateheure` |
| aucun type (HFSQL, ODBC) ou inconnu | à choisir par l'utilisateur : ebony ne devine pas |

Limites assumées : un `NULL` est lu comme la valeur par défaut du type (`0`, texte vide, `Faux`) et ebony n'écrit jamais `NULL` ; `date` et `dateheure` sont du texte ISO 8601 (`AAAA-MM-JJ`, `AAAA-MM-JJTHH:MM:SS`), une colonne TEXT sur PostgreSQL aussi (vérifié sur PostgreSQL 16) ; `NUMERIC` en `reel` perd la précision d'un nombre décimal exact.

PowerShell découpe `a:entier*,b:texte` en plusieurs arguments avant de les passer : `--champs` prend **tous les arguments qui suivent, jusqu'à la prochaine option**, joints par des virgules. Les deux écritures sont équivalentes.

## `make resource <Nom>` : entité, repositories, tests

Le nom est libre (`Client`, `BonDeCommande`, `Bon de commande`) ; seuls sont refusés un nom sans lettre ni chiffre latin et un nom dont le dossier déduit dépasse 40 caractères. Dix fichiers, pour `Client` (neuf si un nom de colonne interdit les routes : voir [Les routes](#les-routes-générées)) :

```
app/domaine/client/cClient.owl                      l'entité : objet valeur immuable, accesseurs LitId(), LitNom()…
app/domaine/client/ContratsClient.owl               la Collection qui déclare l'interface iRepoClient
app/donnees/client/cRepoClientMemoire.owl           le repository en mémoire, pour les tests
app/donnees/client/cRepoClientSql.owl               le repository sur la base du projet (cEbBaseResiliente), requêtes paramétrées
app/services/client/cServiceClient.owl              le service : les règles métier, mince au départ ; reçoit le repository par son contrat
tests/unitaires/client/test_cClient.owl
tests/unitaires/client/test_cRepoClientMemoire.owl
tests/integration/client/test_cRepoClientSql.owl    SQLite en mémoire
tests/unitaires/client/test_cServiceClient.owl      le service sur le repository en mémoire
app/http/client/ControleurClient.owl                 le contrôleur : les cinq routes REST ; il appelle le service, jamais le repository (un `ServiceREST` à part)
```

Le repository a six méthodes : `Enumere()`, `Existe(cle)`, `Trouve(cle)`, `Ajoute(entite)`, `Modifie(entite)`, `Supprime(cle)`. Une absence ou un échec **lève** une exception : `404` introuvable, `409` clé texte déjà prise (repositories en mémoire et SQL ; dans le repository SQL, la vérification précède l'`INSERT` et n'est pas atomique : deux ajouts simultanés de la même clé peuvent donner `500`), `500` requête refusée par la base, `503` base injoignable.
Avec une clé entière, `Ajoute` ignore la clé de l'entité reçue et rend celle qui est enregistrée (celle de la base, via `RETURNING`).

**Le service** (`cService<Nom>`) est la couche des règles métier, entre le contrôleur et le repository. Il reçoit le repository par son contrat `iRepo<Nom>` : il ne sait pas s'il parle à SQL ou à la mémoire, donc son test (`test_cService<Nom>.owl`) passe le repository en mémoire. Il est **mince au départ** : chaque méthode (`Enumere`, `Trouve`, `Ajoute`, `Modifie`, `Supprime`) passe l'appel au repository. Vous y ajoutez vos règles (« un client inactif ne peut pas commander ») ; une règle violée lève une exception avec un code (`ExceptionDéclenche(409, "…")`), que le contrôleur traduit en réponse JSON. La **validation** de ce que le client envoie (champ obligatoire vide, forme du corps) reste dans le contrôleur, première couche ; le service n'a pas à connaître la forme d'un corps HTTP.

**La table** : sans `--table`, le nom au pluriel naïf en minuscules (`Client` → `clients`, `BonCommande` → `bon_commandes`). Pour une table qui existe déjà, **`--table`** (`--table crm.Clients` : le schéma est accepté). C'est ce qu'envoie un IDE qui part d'une table existante.

**Identifiants** : le mot de l'utilisateur ne devient jamais tel quel un identifiant OWL. Une colonne `Date` donne le champ privé `sDate`, le paramètre `vDate` et l'accesseur `LitDate()` : OWL refuse `Date`, `Etat`, `Libelle`, `Table`, `Colonne`… comme noms de méthode (mesuré), et la liste complète est inconnue, d'où le préfixe `Lit` pour **tous** les accesseurs. Deux colonnes qui donneraient le même identifiant (`Prénom` et `prenom`) sont refusées.

**Les routes sont branchées** (voir plus bas) : rien à ajouter à votre `ServiceREST`. Pour **vos propres routes** : ne déclarez ni le repository ni le service dans le bloc du `ServiceREST` (`oRepository est un cRepoClientSql(...)` au niveau du service OWL) : dans un projet qui a un `ServiceREST`, une variable de bloc d'une classe du projet fait planter `owl test`. Construisez-les dans la procédure de la route, comme le font les contrôleurs générés, et n'appelez que le service : `oRepository est un cRepoClientSql(cEbServiceBase.Base())`, puis `oService est un cServiceClient(oRepository)`.

## Les routes générées

`app/http/<dossier>/Controleur<Nom>.owl` est un **`ServiceREST` à part** (le type d'OWL pour déclarer des routes ; `UrlBase = ["api"]`) : `owl serve` monte tous les `ServiceREST` du projet (mesuré, OWL 1.7.0), donc ajouter une ressource ne change pas celui de l'application. Ce n'est pas un « service » au sens du glossaire (règles métier). Pour `Client` :

| Route | Succès | Erreurs |
|---|---|---|
| `GET /api/clients` | 200, un tableau JSON | 503, 500 |
| `GET /api/clients/{cle}` | 200 | 404, 503, 500 |
| `POST /api/clients` | 201, l'entité enregistrée (avec sa clé) | 400, 409 (clé texte), 503, 500 |
| `PUT /api/clients/{cle}` | 200, l'entité enregistrée | 400, 404, 503, 500 |
| `DELETE /api/clients/{cle}` | 204 | 404, 503, 500 |

Le segment d'adresse est la dernière partie du nom de la table, en minuscules (`crm.Clients` donne `clients`). Chaque entité est écrite par sa méthode `EnJson()` : une clé par colonne, **au nom de la colonne en minuscules et mots reliés par `_`** (`date_naissance`).

**Les erreurs** sont un JSON `{ "code": "...", "message": "..." }` : `400 invalide`, `404 introuvable`, `409 conflit`, `503 base_indisponible`, `500 erreur_interne` (`execution/http/EbErreurHttp.owl`, que vos routes peuvent appeler). Le message d'un 400, 404 ou 409 ne contient que le nom du champ ou la clé ; **le détail d'un 500 ou d'un 503 va au journal, jamais au client**. L'exception est attrapée **dans la route** (`QUAND EXCEPTION`) : le `surErreur` d'un service ne reçoit ni le code ni le message d'origine (mesuré : code vide, « Exception non gérée : … »).

**Le corps** d'un `POST` ou d'un `PUT` est lu par OWL dans une structure `st<Nom>Corps` (un membre par colonne ; la clé générée par la base n'y est pas, elle vient de l'adresse). OWL le lit de façon **tolérante** (mesuré) : un champ absent, d'un autre type ou inconnu n'est pas une erreur, le membre garde la valeur par défaut du type (texte vide, `0`, `Faux`) ; un corps vide donne tous les défauts. **Un `PUT` remplace toute la ligne** : un champ oublié écrase la colonne par sa valeur par défaut. Un corps qui n'est pas du JSON donne 400 et un autre `Content-Type` donne 415, avec un texte d'OWL (pas du JSON d'ebony), avant que la route ne s'exécute.

**La validation** se limite à ceci : un texte qui n'accepte pas `NULL` (sans `?`) ne peut pas être vide ni fait d'espaces (400, `Le champ « nom » est obligatoire.`) ; pour une clé texte, la clé du corps ne peut pas être vide à la création. Rien sur les nombres, les formats de date ou les longueurs : ajoutez vos contrôles dans `Cree<Nom>` et `Modifie<Nom>` (le fichier est à vous). Une clé entière non numérique dans l'adresse est lue comme `0` par OWL : 404.

**La clé** : entière, elle est donnée par la base (`POST` ignore toute clé du corps) ; texte, elle vient du corps à la création (409 si elle est prise) et de l'adresse à la modification (celle du corps est ignorée).

**Les routes sont protégées par défaut** : le contrôleur déclare `Authentification = httpAuthBearer` et un `surAuthentification` qui décide par `execution/auth/EbAutorisation.owl`. Sans jeton d'accès valable, la réponse est `401 non_autorise` (JSON, message fixe qui ne dit pas pourquoi), **avant** la route. Créez un jeton avec `ebony token create <nom>` (`docs/guides/token.md`) et envoyez-le dans l'en-tête `Authorization: Bearer <jeton>` ; la route peut lire le nom du jeton dans `MoiMême..Requête..Identité`. `/api/health` reste public (il est dans le service de l'application, pas dans le contrôleur).
**Pour ouvrir les routes** en développement ou pour une API publique, mettez `AUTH_ROUTES=ouvertes` dans `.env` : seule cette valeur les ouvre, toute autre les protège. Dans un projet créé par `ebony new`, la variable est déclarée en liste dans `config/env.json` : une autre écriture (`Ouvertes`, une faute de frappe) est refusée par `ebony env` et au démarrage, au lieu de protéger sans le dire.
**Le garde vient des modules du projet**, pas d'ebony : `make resource` lit le membre `routes` des manifestes de `ebony/modules/*.json` et en écrit les lignes telles quelles (le cœur ne sait pas quel module protège, ni comment). **Aucun garde** (aucun manifeste n'a de `routes`, par exemple si `ebony/modules/` est absent) : le contrôleur est écrit **ouvert**, avec un commentaire `ROUTES OUVERTES` dans le fichier et une note à la fin de la commande. Rien n'est refusé ; un manifeste illisible l'est (code 22).

**Quand les routes ne sont pas écrites** : OWL **ignore en silence** 58 mots comme noms de membre d'une structure (le membre est accepté à la compilation, jamais rempli depuis le JSON) : `liste`, `fin`, `pas`, `est`, `et`, `ou`, `local`, `global`, `tout`, `null`, `vrai`, `faux`… (liste : `EbMotsReservesOwl`). Si le nom d'une colonne du corps en fait partie (ou ne commence pas par une lettre minuscule sans accent), `make resource` écrit les sept autres fichiers, **n'écrit pas les routes** et le dit dans une note : renommez la colonne ou écrivez vos routes.

Vérifié : sur **SQLite** (`tests/integration/lanceur.ps1 -Groupe make` : un vrai `owl serve`, cinq routes, 400, 404, 409, 415, clé entière et clé texte) et sur **PostgreSQL 16** (`tests/integration/postgresql.ps1` : cinq routes, 400, 404). Non vérifié : un 503 d'une base qui tombe pendant une requête, HFSQL, la concurrence (deux `POST` simultanés).

## `make migration <Nom>` : la création d'une table

`ebony make migration CreeClients --champs …` écrit `database/migrations/M202611021015_CreeClients.owl` (horodatage UTC à la minute) : une classe qui implémente `iEbMigration` (`Nom()`, `Monte()`, `Descend()`), et, pour SQLite, son test (`tests/integration/migrations/`).
`Monte()` rend le `CREATE TABLE`, `Descend()` le `DROP TABLE`. `ebony migrate` l'applique (voir [migrate.md](migrate.md)) en **lisant ce fichier** : gardez la forme écrite par ebony (une instruction par `TableauAjoute`).

La table vient de `--table`, ou du nom si celui-ci est `Cree<Table>` (`CreeClients` → `clients`). Un autre nom exige `--table`. Seule la **création** d'une table est écrite (pas d'`ALTER`).
Dialectes : `sqlite` et `postgresql` (un autre `base.fournisseur` dans `ebony.conf` est refusé, code 38). **HFSQL est refusé** (code 39) : la syntaxe n'est pas mesurée. Le SQL de PostgreSQL (création de table, repository SQL d'une ressource) est **vérifié sur PostgreSQL 16** (`tests/integration/postgresql.ps1`) ; pas sur les autres versions. Une table d'un schéma (`--table crm.Clients`) est gardée telle quelle pour PostgreSQL ; pour SQLite, les tests générés attachent une base en mémoire sous le nom du schéma, et une clé étrangère y vise la table sans son schéma (SQLite refuse `REFERENCES "crm"."pays"`, mesuré).

| | SQLite | PostgreSQL |
|---|---|---|
| clé entière | `INTEGER PRIMARY KEY AUTOINCREMENT` | `INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY` |
| `reel` | `REAL` | `DOUBLE PRECISION` |
| `booleen` | `INTEGER` (0 ou 1) | `BOOLEAN` |
| `texte`, `date`, `dateheure` | `TEXT` | `TEXT` |

La migration implémente `iEbMigration`, ajouté à la bibliothèque `ebony/` après les premiers projets : si la copie d'`ebony/` du projet est plus ancienne, une note le dit (supprimer `ebony/` à la main puis `ebony restore`).

Relancer la même commande **crée une seconde migration** (l'horodatage change) : ebony ne détecte pas qu'une migration de même nom existe déjà (à faire : il faudrait lister le dossier).

## Ne remplace jamais, `--dry-run`

- Un fichier qui existe est **conservé tel quel** et listé dans `kept`, avec une note par fichier. Seuls les fichiers absents sont créés. Relancer la même commande ne change rien.
- Un chemin occupé autrement (un dossier à la place d'un fichier, un fichier à la place d'un dossier) est un **conflit** : code 28, tous listés, rien d'écrit.
- `--dry-run` renvoie le même résultat (`created` = ce qui serait créé, `dryRun` à `true`) sans toucher au disque.
- Tout est vérifié avant la première écriture. Une écriture qui échoue en route est le code 24.

## Sortie `--json`

Une seule ligne sur la sortie standard, rien d'autre :

```json
{"ok":true,"command":"make resource","name":"Client","table":"clients","dir":"C:\\Projets\\boutique",
 "dryRun":false,"created":["app/domaine/client/cClient.owl", "…"],"kept":[],"notes":["…"]}
```

| Clé | Sens |
|---|---|
| `command` | `make resource` ou `make migration` |
| `name`, `table` | le nom donné et la table visée |
| `dir` | le dossier du projet : les chemins de `created` et `kept` lui sont relatifs, avec des `/` |
| `dryRun` | `true` pour `--dry-run` |
| `created` | les fichiers créés (ou qui le seraient) |
| `kept` | les fichiers qui existaient et n'ont pas été touchés |
| `notes` | ce que l'utilisateur doit savoir ou faire ensuite |

En cas d'échec : `{"ok":false,"error":"…"}`, une ligne, sans pile d'appels. Sans `--json`, la même chose en texte (`ebony : <cause>` pour une erreur).

## Codes de sortie et d'exception

| Sortie | Cas |
|---|---|
| 0 | réussi (y compris tout conservé) |
| 2 | usage incorrect (code 25) : sous-commande, nom, option, `--champs` ou table incorrects |
| 1 | échec : 24 écriture interrompue, 28 conflit de chemin, 29 horloge illisible, 30 OWL mal placé, 31 pas un projet ebony, 38 `ebony.conf` sans base, 39 migration HFSQL |

## Ce qui n'est pas fait

`make entity | repository | service | validator | page | window | auth`, l'authentification, la pagination, le filtrage et le tri de la liste, la validation au-delà des textes obligatoires, les migrations qui modifient une table, les clés composées, HFSQL pour les migrations, la détection d'une migration déjà écrite.

**Un défaut d'OWL à connaître** : `owl test` plante (« Variable inconnue ») dans tout projet dont le `ServiceREST` déclare, dans son bloc, une variable d'une classe du projet (toujours présent en OWL 1.7.0). Le service que génère `ebony new` ne le déclenche plus : il pose son application dans un membre `GLOBAL` (`cEbServiceApplication`) au lieu d'une variable de bloc, et `owl test` passe avec lui en place (vérifié avec OWL 1.7.0 sur un projet généré, avec une ressource `make`). Vos propres variables de bloc le déclencheraient.
