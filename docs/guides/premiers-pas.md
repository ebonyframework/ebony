# Premiers pas : de `ebony new` à une API qui répond

Un projet, une table, une API REST protégée par un jeton, en quelques commandes. Chaque commande de ce guide a été rejouée telle quelle, sur la version 0.1.0 publiée, sous Windows avec OWL 1.8.1 et SQLite ; les sorties citées sont celles du programme. Sous Linux : `cp` à la place de `Copy-Item`, `curl` à la place de `curl.exe` (la commande `ebony` est le lien posé par `install.sh`).

Prérequis : OWL et ebony installés (voir [l'installation](installation.md)). `ebony doctor` le vérifie.

## 1. Créer le projet

```powershell
ebony new boutique
cd boutique
Copy-Item .env.exemple .env
Copy-Item .env.secrets.exemple .env.secrets
ebony doctor        # doit finir par « 0 erreur(s) »
```

`ebony new` écrit le projet (service REST, bibliothèque `ebony/`, configuration). Le nom est libre (`ebony new "Café de la Gare"` crée le dossier `cafe-de-la-gare`). Les deux fichiers `.env` ne sont pas versionnés : ils sont à vous.

## 2. Écrire la table et la ressource

```powershell
ebony make migration CreeProduits --champs 'id:entier*,nom:texte,prix:reel,actif:booleen'
ebony make resource Produit --champs 'id:entier*,nom:texte,prix:reel,actif:booleen' --table produits
```

La première écrit une migration (`database/migrations/M<horodatage>_CreeProduits.owl`) ; la seconde écrit l'entité, deux repositories (SQL et mémoire), le service (les règles métier), le contrôleur REST et leurs tests. Aucun fichier existant n'est remplacé : relancée, la commande les conserve tels quels.

La grammaire de `--champs` : `nom:type[*][?][@table[.colonne]]`, séparés par des virgules.

| Élément | Sens |
|---|---|
| types | `entier`, `texte`, `reel`, `booleen`, `date`, `dateheure` |
| `*` | clé primaire (pour un entier : générée par la base) |
| `?` | la colonne accepte NULL |
| `@table.colonne` | clé étrangère |

Pour comprendre ce qui a été écrit et où ajouter votre code, lisez [le chemin d'une requête](architecture.md).

## 3. Créer les tables

```powershell
ebony migrate
```

Sont appliquées la migration des jetons (fournie par le module `auth`) et la vôtre, chacune dans une transaction. `ebony migrate status` les liste, `ebony migrate rollback` défait la dernière.

## 4. Demander un jeton

Les routes générées sont **protégées** : sans jeton, 401.

```powershell
ebony token create essai
```

Le secret (`eb_…`) n'est affiché qu'une fois : copiez-le. Il se révoque avec `ebony token revoke <identifiant>`. Pour travailler sans jeton en développement, mettez `AUTH_ROUTES=ouvertes` dans `.env`.

## 5. Lancer le service et l'interroger

Dans un premier terminal :

```powershell
owl serve --port 8080
```

Dans un second (le secret du jeton à la place de `eb_…`) :

```powershell
curl.exe -s http://127.0.0.1:8080/api
# {"statut":"ok","sante":"/api/health"}

curl.exe -s http://127.0.0.1:8080/api/health
# {"statut":"ok","base":"ok"}

curl.exe -s -i http://127.0.0.1:8080/api/produits
# 401 : {"code":"non_autorise","message":"Un jeton d'accès valable est exigé (Authorization: Bearer ...)."}

curl.exe -s -H "Authorization: Bearer eb_…" http://127.0.0.1:8080/api/produits
# []
```

Pour créer un produit, **écrivez le corps JSON dans un fichier** : PowerShell 5.1 retire les guillemets d'un JSON passé en argument.

```powershell
Set-Content corps.json '{"nom":"Cahier","prix":2.5,"actif":true}' -Encoding ascii
curl.exe -s -X POST -H "Authorization: Bearer eb_…" -H "Content-Type: application/json" --data-binary "@corps.json" http://127.0.0.1:8080/api/produits
# {"id":1,"nom":"Cahier","prix":2.5,"actif":true}
```

Les cinq routes de la ressource : `GET` et `POST /api/produits`, `GET`, `PUT` et `DELETE /api/produits/<id>`. `GET /api` et `GET /api/health` restent publics.

## À savoir

- **Un `PUT` remplace toute la ressource.** Un champ absent du corps est remis à la valeur par défaut de son type (voir [le corps d'une requête](architecture.md#le-corps-dune-requête--une-lecture-tolérante)). Envoyez tous les champs.
- **Les erreurs ont une forme unique** : `{"code":"…","message":"…"}`. Voir [les erreurs](erreurs.md).
- **`owl serve` traite les requêtes une par une** : ne l'exposez pas à une charge imprévisible.
- Les tests générés se lancent avec `owl test` : les 5 suites de ce guide passent en une quinzaine de secondes. OWL recompile le projet pour chaque suite, donc le temps croît avec la taille du projet.
- Vos propres routes vont dans le contrôleur de la ressource ou dans `app/http/`, sur le modèle des routes générées.

## Ce qui n'est pas fait

Pas de `seed` ni de fabriques, pas de connexion par mot de passe (les jetons identifient un nom), pas de validation au-delà des champs texte obligatoires (un module de validation est prévu).
