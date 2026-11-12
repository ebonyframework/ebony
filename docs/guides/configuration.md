# Configuration et secrets

OWL ne lit pas les variables d'environnement, et `owl serve` n'accepte que les options `--port` et `--bind`. Un service ne reçoit donc ni variable d'environnement ni chemin de configuration en argument : la seule voie est de **lire des fichiers à des emplacements convenus, relatifs au dossier de travail** du service. C'est ce que `ebony new` et `ebony init` mettent en place.

## Les deux fichiers

| Fichier | Contenu | Versionné |
|---|---|---|
| `.env` | configuration **sans secret** : hôte, port, nom de la base, mode | non |
| `.env.secrets` | les **secrets** et rien d'autre : mots de passe, clés | non |

- Format : une ligne `CLÉ=valeur` ; `#` en début de ligne commence un commentaire (pas en fin de ligne : un `#` dans un mot de passe reste dans la valeur) ; les guillemets simples ou doubles autour de la valeur sont facultatifs.
- Ordre de lecture : `.env` d'abord, puis `.env.secrets` ; une clé présente dans les deux prend la valeur de `.env.secrets`. Une valeur **vide** compte comme absente.
- Deux fichiers parce que ce ne sont pas les mêmes mains : la configuration se décrit dans un dépôt de déploiement, les secrets viennent du coffre de l'hébergeur et se montent seuls.

## Ce que `ebony new` écrit

- `config/env.json` : le **schéma** de la configuration (voir plus bas), avec les variables de la base choisie.
- `.env.exemple` : le modèle de `.env`, une ligne `CLE=défaut` par variable non secrète.
- `.env.secrets.exemple` : le modèle de `.env.secrets`, une ligne par variable secrète (PostgreSQL et HFSQL : `DB_MOT_DE_PASSE`). Avec SQLite il n'y a aucun secret ; le fichier est écrit quand même, pour que l'emplacement à monter soit toujours le même.
- `.gitignore` : `.env` et `.env.secrets` n'y sont jamais commités.

Pour commencer : copiez `.env.exemple` en `.env` et `.env.secrets.exemple` en `.env.secrets`, puis adaptez. `ebony init` ajoute les mêmes fichiers à un projet existant, sans toucher à ceux qui existent déjà.

## Les variables courantes

| Variable | Rôle |
|---|---|
| `DB_FICHIER` | fichier de la base SQLite |
| `DB_HOTE`, `DB_PORT`, `DB_NOM`, `DB_UTILISATEUR`, `DB_MOT_DE_PASSE` | connexion PostgreSQL ou HFSQL (le mot de passe va dans `.env.secrets`) |
| `DB_TLS` | niveau TLS vers PostgreSQL : voir plus bas |
| `DB_CERTIFICAT_CA` | fichier PEM d'une autorité de certification interne |
| `LOG_NIVEAU` | seuil du journal : `debug`, `info` (défaut), `warn`, `error` |
| `AUTH_ROUTES` | `protegees` (défaut) ou `ouvertes` : les routes générées exigent-elles un jeton ? |

## En production

L'hébergeur lance le service avec le dossier de travail du projet et **monte les fichiers à ces deux emplacements** :

```text
<dossier de travail>/.env
<dossier de travail>/.env.secrets
```

Aucune modification du code n'est nécessaire. Un secret de conteneur (par exemple monté sous `/run/secrets/`) se rattache à `.env.secrets` par un montage ou un lien, pas par un argument.

## TLS vers PostgreSQL : `DB_TLS`

OWL exige par défaut un TLS **vérifié** vers un PostgreSQL : c'est sûr, mais un serveur local sans TLS est refusé. `DB_TLS` règle le niveau (PostgreSQL seulement) :

| `DB_TLS` | Effet |
|---|---|
| `verifie` (défaut) | TLS exigé, certificat **et nom du serveur** vérifiés : ce qu'il faut en production. |
| `ca` | TLS exigé, chaîne de certificats vérifiée, **pas le nom** du serveur. |
| `accepte` | TLS exigé, certificat **non vérifié** : chiffré, sans garantie sur l'identité du serveur. |
| `desactive` | **Aucun TLS** : serveur local de développement seulement. |

`DB_CERTIFICAT_CA` (facultatif) est le chemin d'un fichier PEM : l'autorité de certification du serveur quand elle n'est pas publique. Une valeur hors de la liste est refusée au démarrage, jamais lue comme un niveau plus faible. Un projet créé avant ces variables garde le TLS vérifié ; ajoutez-les à `config/env.json` (type `liste`) pour les régler.

## Le schéma `config/env.json`

Un fichier de **données** (jamais du code : on le lit sans rien exécuter) qui déclare chaque variable. Il est contrôlé au démarrage ; une valeur absente ou du mauvais type arrête le service avec un message clair.

```json
{
	"variables": [
		{ "cle": "DB_HOTE", "type": "texte", "obligatoire": true, "description": "Hôte de la base" },
		{ "cle": "DB_PORT", "type": "port", "defaut": "5432" },
		{ "cle": "DB_MOT_DE_PASSE", "type": "texte", "obligatoire": true, "secret": true },
		{ "cle": "APP_ENV", "type": "liste", "valeurs": ["development", "production"], "defaut": "development" }
	]
}
```

| Membre | Rôle |
|---|---|
| `cle` | nom de la variable : lettres ASCII, chiffres, soulignés, sans commencer par un chiffre ; unique |
| `type` | `texte`, `entier`, `booleen`, `port` (1 à 65535), `chemin` ou `liste` (avec `valeurs`) |
| `obligatoire` | faux par défaut ; ne se combine pas avec `defaut` |
| `defaut` | texte ou entier, contrôlé comme les autres valeurs |
| `secret` | faux par défaut ; la valeur d'un secret n'apparaît jamais dans un message |
| `description` | facultative |

Une variable de `.env` que le schéma ne déclare pas reste lisible, sans contrôle. **Sans schéma, rien n'est contrôlé.** Un booléen s'écrit `true`, `false`, `1`, `0`, `oui` ou `non`.

Une configuration invalide arrête le démarrage (code 60) en listant **toutes** les erreurs :

```text
Configuration invalide (2 erreur(s)) :
- DB_PORT : un port (entier de 1 à 65535) attendu, reçu « abc » (lu dans .env).
- DB_HOTE : obligatoire, mais absente de .env et de .env.secrets (et sans valeur par défaut).
```

Pour un secret, le message dit « valeur d'un secret, non affichée » : la valeur n'est jamais écrite.

## Examiner la configuration : `ebony env`

```text
ebony env           # texte lisible
ebony env --json    # une ligne JSON, pour un outil
```

À lancer dans le dossier d'un projet. Rien n'est démarré ni écrit : la commande lit `config/env.json`, `.env` et `.env.secrets` avec le **même lecteur que l'application**, donc le même verdict. Code de sortie 0 si la configuration est valide, 1 sinon. Pour chaque variable : sa source (`.env`, `.env.secrets`, `defaut` ou `absente`), sa validité et l'erreur éventuelle. **Pour une variable `secret`, la valeur n'apparaît jamais**, ni en texte ni en JSON.
