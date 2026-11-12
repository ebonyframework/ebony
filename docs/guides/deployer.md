# Déployer une application

Ce guide décrit ce qui a été **essayé** pour mettre une application Ebony en service. Ebony n'a pas de commande de déploiement : une application est un projet OWL ordinaire, qui se lance avec `owl serve` ou se package avec `owl-build`. Ce qui n'a pas été essayé est dit en fin de page.

## Deux façons de lancer l'application

| Voie | Sur le serveur | Vérifié |
|---|---|---|
| **Un binaire autonome** (`owl-build`) | rien d'autre que le binaire et ses fichiers de configuration : ni `owl`, ni `ebony` | Windows vers Windows ; Windows vers Linux (binaire statique, lancé sous Ubuntu WSL 2 sans `owl` dans le PATH) |
| **Les sources** et `owl serve` | `owl` 1.8.1, le dossier du projet (avec son `ebony/`) | partout où l'on développe : c'est ce que font les [premiers pas](premiers-pas.md) |

Le binaire est le plus simple à poser sur un serveur. Les sources demandent `owl` sur la machine, mais permettent de relancer `ebony migrate` sur place.

## Produire le binaire

Sur une machine qui a `owl-build` (le dossier d'OWL le contient sous Windows) et le projet complet :

```sh
owl-build . -o boutique                      # la plateforme de la machine
owl-build . -o boutique --target linux-x86_64   # un binaire Linux, même depuis Windows
```

Le résultat est dans `exe/<cible>/` (`exe/linux-x86_64/boutique`). Mesuré sur un projet généré avec une ressource : **47 s** pour le premier build (la documentation d'OWL dit qu'il extrait alors sa chaîne de compilation), **21 s** pour le suivant, environ **101 Mo** par binaire. `owl-build --prepare` paie l'extraction à l'avance, pour une machine de construction qu'on prépare une fois.

Le dossier `ebony/` (la bibliothèque) est **ignoré par git** : sur une machine qui vient de cloner le projet, lancez `ebony restore` **avant** `owl-build` (voir l'[installation](installation.md)).

**Le binaire n'embarque pas la configuration.** Ce qui suit doit se trouver à côté, dans le dossier de travail.

## Le dossier de travail du service

Le service lit ses fichiers **relativement au dossier de travail** (voir la [configuration](configuration.md)). Un dossier de production minimal, pour SQLite :

```text
boutique              le binaire
.env                  la configuration, sans secret
.env.secrets          les secrets
config/env.json       le schéma de la configuration
storage/app.db        la base
```

Essayé ainsi, binaire Windows et binaire Linux : `GET /api/health` répond `{"statut":"ok","base":"ok"}`, une route générée répond **401** sans jeton et **200** avec un jeton créé par `ebony token create`.

**Lancé depuis un autre dossier**, sans ces fichiers, le service **démarre quand même** : `GET /api/health` répond **503** `{"statut":"degrade","base":"indisponible"}`, et tout jeton est refusé (401) puisque la base est introuvable. Un service qui ne trouve pas sa configuration ne s'arrête donc pas, il répond « dégradé » : surveillez `/api/health`, et réglez le dossier de travail de votre superviseur (`WorkingDirectory` pour systemd, « Démarrer dans » pour une tâche Windows).

## Lancer

```sh
./boutique --port 8080 --bind 0.0.0.0
```

- Sans option, le service écoute sur `127.0.0.1:8080` (vérifié) : **inaccessible depuis le réseau**. `--bind 0.0.0.0` l'expose sur toutes les interfaces (vérifié : l'adresse d'écoute devient `0.0.0.0`). `--port` et `--bind` passent au binaire comme à `owl serve` (vérifié) ; `owl serve` refuse toute autre option, le binaire n'a pas été essayé avec d'autres.
- Ne mettez jamais `AUTH_ROUTES=ouvertes` en production : seule cette valeur ouvre les routes générées, toute autre les protège.
- Une configuration invalide arrête le démarrage avec toutes les erreurs listées. Contrôlez-la avant avec `ebony env` si `ebony` est sur la machine.

## Les migrations

Le binaire sert l'application ; il n'applique pas les migrations. Deux voies :

- **Sur le serveur** : `ebony migrate` dans le dossier du projet (il demande `owl` et `ebony` sur la machine). C'est la voie testée de bout en bout dans les [premiers pas](premiers-pas.md).
- **Avant** : appliquer les migrations sur une base, puis copier cette base (`storage/app.db`) sur le serveur. Essayé avec SQLite : le binaire la lit sans autre étape.

Avec PostgreSQL, `ebony migrate` se lance depuis une machine qui atteint la base ; configurez `DB_TLS` (voir [Configuration](configuration.md)) : le défaut, `verifie`, est ce qu'il faut en production.

## Surveiller

- **Santé** : `GET /api/health` est public. 200 si l'application et la base répondent, 503 sinon.
- **Journal** : une ligne JSON par événement sur la sortie standard (`{"ts":"…","niveau":"info","message":"Application démarrée"}`), voir le [journal](journalisation.md). Deux lignes de texte ordinaire (`<nom du projet> : projet créé par ebony`) précèdent les premières lignes JSON au démarrage : un collecteur doit les tolérer. Les refus d'authentification s'écrivent sur la **sortie d'erreur** (`owl serve: rejet auth GET /api/produits : …`), une ligne par requête refusée.
- **Une requête à la fois** : le service ne traite jamais deux requêtes en même temps, voir [limites et performance](performance-et-limites.md). Un déploiement doit en tenir compte avant de promettre un débit.

## Ce qui n'est pas vérifié

- Un **superviseur** (systemd, service Windows, conteneur Docker) : aucun fichier d'exemple n'est fourni parce qu'aucun n'a été essayé.
- **HTTPS** : rien n'a été essayé, ni derrière un proxy inverse ni avec le TLS d'OWL.
- L'**arrêt propre** (signal d'arrêt, fermeture de la base) et le redémarrage après un arrêt brutal.
- Plusieurs instances sur une même base SQLite.
- Un binaire **signé** (`--sign`), un chemin de projet avec des accents ou des espaces.
- Le binaire sur d'autres distributions Linux que l'Ubuntu de mesure, et sur Windows 10.
- PostgreSQL derrière un binaire (le service a été essayé avec SQLite ; PostgreSQL est vérifié sous `owl serve` seulement).
