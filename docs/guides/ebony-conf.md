# `ebony.conf` : le fichier qui désigne un projet

`ebony.conf` est un fichier JSON à la **racine** du projet. C'est lui qui fait d'un dossier un projet Ebony : `ebony migrate`, `make`, `token`, `env` et `upgrade` le cherchent dans le dossier courant (pas dans les dossiers parents) et répondent « Ce dossier n'est pas un projet ebony : ebony.conf est introuvable » sans lui. `ebony new` et `ebony init` l'écrivent ; **il se versionne avec git**, contrairement à `ebony/`.

Ce guide décrit ce qui a été essayé avec Ebony 0.1.0 (Windows 11, OWL 1.8.1), en modifiant le fichier à la main et en relançant les commandes.

## Un exemple

Celui d'un projet créé par `ebony new boutique` (kit `api`) :

```json
{
	"ebony": {
		"version": "0.1.0"
	},
	"projet": {
		"Nom": "boutique",
		"dossier": "boutique",
		"identifiant": "AppBoutique",
		"type": "api",
		"kit": "api"
	},
	"modules": [
		"db",
		"auth"
	],
	"base": {
		"fournisseur": "sqlite"
	}
}
```

| Membre | Rôle | Lu par |
|---|---|---|
| `ebony.version` | version **minimale** de la bibliothèque `ebony/` que le projet demande | `ebony restore`, `ebony upgrade`, `ebony doctor` |
| `modules` | les modules du projet, hors cœur (`["db","auth"]` pour le kit `api`, `[]` pour `slim`) | `migrate`, `make`, `token`, `restore`, `upgrade` |
| `base.fournisseur` | `sqlite`, `postgresql` ou `hfsql` | `migrate`, `make`, `token` |
| `projet.Nom`, `dossier`, `identifiant` | le nom libre, le dossier déduit (`Café de la Gare` donne `cafe-de-la-gare`) et l'identifiant OWL (`AppCafeDeLaGare`) | informatifs |
| `projet.type`, `projet.kit` | le type d'application (toujours `"api"`) et le kit | informatifs (un outil, comme un IDE, peut les lire) |
| `auth` | présent avec `--auth` : `{"jetons":true,"table":"utilisateurs","mode":"opaque"}` | informatif |

« Informatif » veut dire : d'après le code, aucune commande d'Ebony ne relit ces membres. Les modifier ne change rien à leur comportement. Un projet slim n'a ni `base` ni `auth`.

## `ebony.version` : une version minimale

Comme un `^0.1.0` dans un `package.json` : le projet demande une bibliothèque **au moins aussi récente, de la même génération**, c'est-à-dire le même numéro majeur, et le même mineur tant que le majeur est 0. La 0.1.3 satisfait `0.1.0` ; la 0.0.9 et une 0.9.0 non (règle couverte par les tests unitaires d'Ebony).

Ce qui se passe, essayé avec l'ebony 0.1.0 installé :

| `ebony.version` | Résultat |
|---|---|
| `0.1.0` | tout va bien |
| une version de la génération suivante (plus récente que l'installation) | `ebony doctor` avertit (« ne satisfait pas le minimum … demandé par ebony.conf ») ; `ebony restore` **refuse** (code de sortie 1) : « Installez un ebony d'au moins la version demandée ». `ebony upgrade` ne rétrograde jamais un projet. |
| `0.0.5` (autre génération, plus ancienne) | `ebony doctor` avertit et conseille `ebony upgrade` ; `ebony upgrade` écrit `ebony.version` = `0.1.0` et laisse tous les autres membres tels quels |
| `abc` ou absente | `ebony doctor` donne une **erreur** (code 1) : « ebony.version entre guillemets, par exemple 0.1.0 » |

`ebony upgrade` réécrit le fichier **en entier** dans la forme d'`ebony new` (tabulations, fins de ligne LF, saut de ligne final) : le JSON n'a pas de commentaires, il n'y en a donc pas à perdre, mais une mise en forme personnelle serait refaite.

## `modules` : ce que le projet a

Les modules sont choisis à la création par le kit (voir [Modules et kits](modules.md)). Avec `"modules": ["db"]`, `ebony token create` refuse : « Ce projet n'a pas le module « auth » : « ebony token » en dépend » (code de sortie 1). Un `ebony.conf` **sans** le membre `modules` (celui d'un projet plus ancien) est lu comme « tous les modules de l'installation » : `ebony token list` y fonctionne.

Ajouter un nom à la main ne **copie** pas le module : seules `ebony restore` et `ebony upgrade` recopient les modules listés dans `ebony/`. Pour ajouter un module à un projet qui existe, utilisez [`ebony add`](ajouter-un-module.md) : il copie la bibliothèque du module, écrit ses fichiers et note le module ici, en dernier. Le `kit` noté ne change pas (il dit le point de départ du projet, `modules` dit ce qu'il a). Il n'y a pas de commande pour retirer un module (non essayé).

## `base.fournisseur` : la base

Avec `"mysql"`, `ebony migrate` et `ebony make migration` refusent : « ebony.conf n'indique pas une base connue (base.fournisseur : « mysql » ; attendu : sqlite, postgresql ou hfsql) », code de sortie 1. Avec `"hfsql"`, `ebony migrate` refuse aussi : « n'applique pas encore de migration sur HFSQL ». Un texte qui n'est pas du JSON donne le même refus (la valeur lue est vide). `ebony env` ne regarde pas ce membre : il contrôle les variables de `.env` (voir [Configuration](configuration.md)).

Le fournisseur d'`ebony.conf` doit être le même que celui du registre des composants : `cEbServiceBase("sqlite")` dans `app/Composants.owl`, que `ebony new`, `ebony init` et `ebony add` écrivent d'après `ebony.conf` ([Adopter Ebony](adopter-un-projet.md)). Changer l'un à la main sans l'autre n'est pas détecté.

## Éditer à la main

- Du **JSON strict** : guillemets doubles, pas de virgule finale, pas de commentaire.
- Après une modification, `ebony doctor` relit `ebony.version` ; `ebony migrate` ou `ebony make` relisent `base.fournisseur` et `modules`. Un fichier abîmé donne un message à la lecture de `ebony.version` (`doctor`) et de `base.fournisseur` (`migrate`, `make`), comme ci-dessus ; la lecture d'un membre `modules` mal formé n'a pas été essayée.
- Sans `ebony.conf`, `ebony doctor` dit « sans objet : ce dossier n'est pas un projet ebony » et les autres commandes refusent.

## Ce qui n'est pas vérifié

- Un `ebony.conf` aux fins de ligne CRLF ou avec une mise en forme différente (la lecture est celle d'un JSON ordinaire, mais ce n'est pas essayé).
- Le comportement de `ebony restore` et `ebony upgrade` quand `modules` liste un module que l'installation n'a pas.
- Les mêmes essais sous Linux.
