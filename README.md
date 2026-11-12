<div align="center">

<img src="assets/logo-ebony.png" width="200" alt="Logo Ebony : une tête d'éléphant souriant, oreilles orange">

# Ebony

**Le cœur du framework Ebony : des applications OWL structurées, générées par une commande.**

Inspiré d'AdonisJS, pour le langage [OWL](https://github.com/followthewhiteowl/neowl).

[![Licence MIT](https://img.shields.io/badge/licence-MIT-3b82f6?style=flat-square&labelColor=2b2b2b)](LICENSE)
[![Version 0.1.0](https://img.shields.io/badge/version-0.1.0-f28c28?style=flat-square&labelColor=2b2b2b)](https://github.com/ebonyframework/ebony/releases)
[![Statut : préversion](https://img.shields.io/badge/statut-pr%C3%A9version-eab308?style=flat-square&labelColor=2b2b2b)](#statut-et-limites-connues)
[![OWL 1.8.1](https://img.shields.io/badge/OWL-1.8.1-7c4dbd?style=flat-square&labelColor=2b2b2b)](https://github.com/followthewhiteowl/neowl)
[![Plateformes : Windows et Linux](https://img.shields.io/badge/plateformes-Windows%20%7C%20Linux-6b7280?style=flat-square&labelColor=2b2b2b)](docs/guides/installation.md#linux)

[Démarrage rapide](#démarrage-rapide) ·
[Modules](#les-modules-officiels) ·
[Philosophie](#philosophie) ·
[Documentation](#documentation) ·
[Contribuer](#contribuer)

</div>

---

## Présentation

**Ebony** donne à OWL ce que les frameworks web donnent à leur langage : une façon **cohérente** de démarrer un projet, de décrire ses données, d'exposer une application et de la protéger. Ce dépôt en est le **cœur** : la commande `ebony`, les générateurs et la petite bibliothèque d'exécution (`Eb*`) que chaque projet généré embarque.

Une commande crée un projet qui compile et démarre sous `owl serve`. Une autre écrit, pour une table, l'entité, les repositories, le service métier, le contrôleur REST et les tests, avec des routes protégées par jeton. Le code généré est lisible et reste le vôtre.

> **Préversion 0.1.0.** Un socle de démarrage pour une petite API OWL, pas encore un framework complet. Lisez le [statut et les limites](#statut-et-limites-connues) avant de l'adopter.

### L'écosystème Ebony

Le framework se construit en couches : le cœur d'abord, puis un type de projet à la fois.

| Projet | Ce que c'est | État |
|---|---|---|
| **Ebony** (ce dépôt) | Le cœur : commande `ebony`, générateurs, bibliothèque d'exécution, modules. | Disponible (préversion) |
| **API REST** | Un service HTTP : routes, contrôleurs, services métier, repositories, migrations, jetons. `ebony new` (kit `api`, par défaut) ; `ebony new <nom> --kit slim` pour le cœur seul, sans base de données (voir [les kits](docs/guides/modules.md#les-kits)). | Disponible (préversion), fourni par le cœur |
| **Web** | Des applications avec pages rendues côté serveur (moteur de gabarits). | Prévu |
| **Desktop** | Des applications de bureau. | Prévu |
| **Mobile** | Des applications mobiles. | À l'étude |

## Démarrage rapide

Prérequis : [OWL](https://github.com/followthewhiteowl/neowl) **1.8.1** (`owl` dans le PATH, la version prise en charge ; une autre version donne un avertissement de `ebony doctor`), Windows ou Linux. Installez Ebony **en une commande** (elle vérifie que `owl` est là, télécharge la dernière release, contrôle sa somme SHA-256 et installe ; elle n'installe pas OWL) :

```powershell
irm https://github.com/ebonyframework/ebony/releases/latest/download/install.ps1 | iex      # Windows (PowerShell)
```
```sh
curl -fsSL https://github.com/ebonyframework/ebony/releases/latest/download/install.sh | sh   # Linux
```

Ouvrez ensuite un nouveau terminal et lancez `ebony doctor`. Autres voies (archive, clone) et détail de ce que fait l'installateur : le [guide d'installation](docs/guides/installation.md).

```powershell
ebony new boutique ; cd boutique
Copy-Item .env.exemple .env ; Copy-Item .env.secrets.exemple .env.secrets
ebony make migration CreeProduits --champs 'id:entier*,nom:texte,prix:reel,actif:booleen'
ebony make resource Produit --champs 'id:entier*,nom:texte,prix:reel,actif:booleen' --table produits
ebony migrate
ebony token create essai          # le secret (eb_…) n'est affiché qu'une fois : copiez-le
owl serve --port 8080
```

Puis, dans un second terminal (le secret du jeton à la place de `eb_…`) :

```powershell
curl.exe -s -H "Authorization: Bearer eb_…" http://127.0.0.1:8080/api/produits       # []
```

Sans jeton, la même requête répond **401**. Sous Linux : `cp` à la place de `Copy-Item` (la commande `ebony` est le lien posé par `install.sh`). Le [parcours détaillé](docs/guides/premiers-pas.md) explique chaque étape.

### Une route à vous

Les fichiers générés sont les vôtres. Pour ajouter une route, ajoutez une `OpérationHTTP` au contrôleur de la ressource (`app/http/produit/ControleurProduit.owl`), sur le modèle des routes générées. Celle-ci renvoie le nombre de produits ; elle est protégée par jeton comme les autres.

```owl
CompteProduit est une OpérationHTTP
	PROPRIETES
		Méthode  = httpGet
		Chemin   = ["compte-produits"]
		Réponses = [httpOK, httpServiceIndisponible, httpErreurServeur]
		CodeÉtat = httpOK
	FIN
	PROCEDURE surRequête() : chaîne
		oRepository est un cRepoProduitSql(cEbServiceBase.Base())
		oService    est un cServiceProduit(oRepository)
		sCode       est une chaîne                                                     = ""
		QUAND EXCEPTION DANS
			tabProduits est un tableau de cProduit = oService.Enumere()
			j           est un JSON
			j["compte"] = tabProduits..Occurrence
			MoiMême..Réponse..TypeContenu = "application/json"
			MoiMême..Réponse..Corps       = JSONVersChaîne(j, psdMinifie)
		FAIRE
			sCode = ExceptionInfo(errCode)
			EbJournaliseErreurHttp(sCode, ExceptionInfo(errMessage))
			MoiMême..Réponse..CodeÉtat    = EbStatutHttpDeCode(sCode)
			MoiMême..Réponse..TypeContenu = "application/json"
			MoiMême..Réponse..Corps       = EbCorpsErreurHttp(sCode, ExceptionInfo(errMessage))
		FIN
		RENVOYER ""
	FIN
FIN
```

`GET /api/compte-produits` répond `{"compte":2}` avec un jeton, 401 sans. La route passe par le **service**, jamais par le repository, et traduit toute exception en réponse JSON : voir [le chemin d'une requête](docs/guides/architecture.md) et [les erreurs](docs/guides/erreurs.md).

### Ce que le projet contient

```text
boutique/
├── ebony.conf                    nom, base, modules, options, version minimale d'ebony
├── projet.owl                    le projet OWL (point d'entrée)
├── .env.exemple                  modèles de configuration : copiez-les en .env et .env.secrets
├── .env.secrets.exemple
├── AGENTS.md                     consignes pour un assistant de code (conventions, pièges d'OWL) : adaptez-le
├── config/
│   ├── env.json                  le schéma de la configuration (des données, pas du code)
│   └── Auth.owl                  l'authentification du projet (avec --auth) : à vous
├── app/
│   ├── http/                     le service REST et les contrôleurs : les routes
│   ├── services/produit/         les règles métier
│   ├── donnees/produit/          les repositories : SQL et mémoire
│   └── domaine/produit/          l'entité et les contrats (interfaces)
├── database/migrations/          une migration par fichier, jouée par « ebony migrate »
├── tests/                        unitaires (sans base) et d'intégration (vraie base)
├── storage/                      la base SQLite locale (ignorée par git)
└── ebony/                        la bibliothèque d'exécution (ignorée par git, restaurée par « ebony restore »)
```

`ebony/` n'est pas à vous : c'est la bibliothèque, que `ebony upgrade` aligne sur la version installée. Tout le reste est à vous.

## Les modules officiels

Les fonctionnalités d'Ebony sont réparties en modules : chacun apporte du code d'exécution, des commandes et, au besoin, un manifeste de données.

| Besoin | Module | État |
|---|---|---|
| Cycle de vie, configuration, journal, HTTP, commandes | `core` | Disponible |
| Jetons d'accès, routes protégées, `ebony token` | `auth` | Disponible |
| Connexion, migrations, repositories SQL | `db` | Prévu : aujourd'hui dans `core` |
| Vérification de ce que le client envoie | `validation` | Prévu : aujourd'hui limitée aux champs texte obligatoires |

Le détail est dans [les modules](docs/guides/modules.md).

## Adopter Ebony progressivement

Vous n'avez pas à repartir de zéro. `ebony init` ajoute Ebony à un **projet OWL existant**, sans rien écraser : la bibliothèque `ebony/`, `ebony.conf`, la configuration (`config/env.json` et les modèles `.env`) et, pour les modules présents, leurs fichiers et leurs migrations. Vos fichiers ne sont pas touchés. Il n'écrit pas le service REST que `ebony new` génère : il faut l'ajouter pour que les contrôleurs générés fonctionnent, ce que le guide [Adopter Ebony dans un projet existant](docs/guides/adopter-un-projet.md) explique pas à pas.

Dans un projet cloné avec git, `ebony restore` rétablit `ebony/` (ignoré par git, comme `node_modules`) d'après la version minimale de `ebony.conf`, et `ebony upgrade` l'aligne sur l'Ebony installé.

## Philosophie

Ebony fait des choix, et les assume.

- **Votre code vous appartient.** Ebony *génère* du code OWL lisible dans votre projet ; il ne le cache pas derrière une bibliothèque. `ebony make` ne remplace jamais un fichier existant, et Ebony ne supprime jamais rien (la seule exception est `ebony uninstall`, bornée et annoncée).
- **Explicite plutôt que magique.** OWL n'a ni espaces de noms ni paquets : chaque nom global de la bibliothèque porte le préfixe `Eb`. Rien n'est deviné : une route est protégée parce que le contrôleur le dit.
- **Sûr par défaut.** Les routes générées exigent un jeton. Un secret est affiché une seule fois, la base n'en garde que l'empreinte, et la configuration n'expose jamais la valeur d'un secret. Rendre une route publique est un choix (`AUTH_ROUTES=ouvertes`), pas un oubli.
- **Des couches nettes.** Un contrôleur parle HTTP et vérifie ce que le client envoie, un service porte les règles métier, un repository parle à la base. Chaque accès au système passe par un **port** avec un adaptateur réel et un adaptateur de test : on teste sans base ni disque.
- **Un cœur modulaire.** Le cœur ne connaît pas les modules ; un module déclare ce qu'il apporte dans un manifeste.
- **Honnête sur ses limites.** Ce qu'OWL ne permet pas (hachage lent, fils d'exécution, lancement de programmes…) est dit tel quel plutôt que contourné en silence.

## Documentation

Les guides d'usage sont dans [`docs/guides/`](docs/guides) :

- [Installation](docs/guides/installation.md) : Windows et Linux.
- [Adopter Ebony dans un projet existant](docs/guides/adopter-un-projet.md) : `ebony init` et le service à ajouter.
- [Premiers pas](docs/guides/premiers-pas.md) : du projet à l'API protégée, pas à pas.
- [Tutoriel : une petite boutique](docs/guides/tutoriel.md) : deux tables liées, validation, règle métier, route personnalisée, test.
- [Le chemin d'une requête](docs/guides/architecture.md) : les couches, où écrire quoi, le corps d'une requête, les tests.
- [Les erreurs](docs/guides/erreurs.md) : codes, format JSON, lever une erreur depuis son code.
- [Référence des commandes](docs/guides/commandes.md) : options, `--json`, codes de sortie.
- [Les modules](docs/guides/modules.md) : `core`, `auth`, le manifeste, ce qui est prévu.
- [Configuration et secrets](docs/guides/configuration.md) : `.env`, `config/env.json`, TLS, production.

## Statut et limites connues

Ebony 0.1.0 est une **préversion**. À savoir avant de l'adopter :

- **Une requête à la fois.** Un service OWL traite les requêtes une par une (quatre requêtes d'une seconde envoyées ensemble prennent environ quatre secondes) : ne l'exposez pas à une charge imprévisible. OWL n'a ni thread ni asynchrone.
- **Bases** : SQLite et PostgreSQL 16 pour `ebony migrate` (essayés contre un vrai serveur) ; HFSQL est refusé pour les migrations.
- **Authentification** : des jetons d'accès pour des clients ; pas de connexion d'utilisateur (mot de passe, session, rôles).
- **Un `PUT` remplace toute la ressource** : un champ absent du corps est remis à la valeur par défaut de son type, et il n'y a pas de mise à jour partielle générée (voir [le chemin d'une requête](docs/guides/architecture.md#le-corps-dune-requête--une-lecture-tolérante)).
- **Validation minimale** : seuls les champs texte obligatoires sont vérifiés ; un module de validation est prévu.
- **SQLite et clés étrangères** : une clé étrangère déclarée dans une migration n'est pas vérifiée par la connexion SQLite (un produit d'une catégorie inexistante est accepté) ; vérifiez-le dans le service.
- **Pas encore** : fabriques et `seed`, routes déclarées dans un fichier à la AdonisJS, pages web, bureau, mobile. Ce qui est utilisable aujourd'hui est le projet API décrit plus haut.
- **Plateformes** : Windows ; Linux (`install.sh` à la place d'`ebony install`).
- **Lenteur au lancement** : une commande `ebony` prend 1 à 7 secondes depuis l'archive ou une copie installée, mais 20 à 25 secondes depuis un clone tant que les points d'entrée réduits n'ont pas été générés : OWL analyse tout le projet à chaque lancement.

## Contribuer

Les contributions sont les bienvenues, même petites : un rapport de bug clair aide autant qu'une correction. Avant de commencer, lisez le [guide de contribution](https://github.com/ebonyframework/.github/blob/main/CONTRIBUTING.md) et le [code de conduite](https://github.com/ebonyframework/.github/blob/main/CODE_OF_CONDUCT.md). Pour signaler une faille de sécurité, suivez la [politique de sécurité](https://github.com/ebonyframework/.github/blob/main/SECURITY.md) : pas de ticket public.

Ebony est un projet indépendant, **non affilié** à l'équipe du langage OWL (NeOwl) : il s'appuie sur la commande `owl` publiée par ce projet, sans la modifier ni l'embarquer.

## Licence

[MIT](LICENSE), au nom d'ElmiraLabs.
