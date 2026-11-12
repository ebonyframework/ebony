# Dépanner

Les pannes ci-dessous ont été **provoquées** sur Ebony 0.1.0 (Windows 11, OWL 1.8.1) et les messages sont ceux qui s'affichent. Une entrée marquée « non rejouée » vient d'une mesure plus ancienne. Pour un diagnostic général, commencez par `ebony doctor` dans le dossier du projet : cinq contrôles (accès au dossier, installation d'ebony, écriture, version d'OWL, état du projet), un bilan, et pour chaque problème ce qu'il faut faire.

## Les commandes d'Ebony et d'OWL

### `'owl' n'est pas reconnu en tant que commande interne ou externe`

`owl` n'est pas dans le PATH du terminal (code de sortie 9009 sous Windows). Installez OWL ou ouvrez un **nouveau** terminal si vous venez de le faire : un PATH modifié n'est lu qu'au démarrage d'un terminal. Contrôle : `owl --version` (Ebony est vérifié avec la 1.8.1 ; une autre version donne un avertissement de `ebony doctor`).

### `ebony : Ce dossier n'est pas un projet ebony : ebony.conf est introuvable dans …`

Vous n'êtes pas dans le dossier d'un projet. `ebony migrate`, `make`, `token` et `env` se lancent à la racine du projet, là où est `ebony.conf` (il n'y a pas de remontée vers les dossiers parents). Pour créer un projet : `ebony new <nom>`.

### `'cEbServiceApplication' : variable inconnue ou inaccessible` (dans `app/http/Service….owl`)

Le dossier `ebony/` (la bibliothèque) manque : c'est l'état normal après un `git clone`, car `ebony/` n'est pas versionné. `ebony doctor` le dit (« état normal après un git clone ») ; lancez **`ebony restore`**, puis `owl --check projet.owl` passe.

### Une erreur de syntaxe dans un de vos fichiers

`owl --check projet.owl` répond en JSON, avec le fichier et la ligne : `{"errors":[{"file":"app/services/Casse.owl","line":1,…,"message":"app/services/Casse.owl:3 : Expression attendue."}],…}`, code de sortie 65. Le numéro de la ligne en cause est dans le texte du message.

### `ebony make migration …` : `--champs : il faut au moins un champ en plus de la clé « id »`

Une migration décrit une table : donnez la clé et au moins une autre colonne (`id:entier*,nom:texte`). Code de sortie 2.

## La configuration

### `ebony env` : une variable est en erreur

`ebony env` lit `config/env.json`, `.env` et `.env.secrets` comme le fait l'application, et dit pour chaque variable d'où vient sa valeur. Exemple avec `AUTH_ROUTES=Ouvertes` :

```text
  ERREUR AUTH_ROUTES (liste) : .env

Erreurs (1) :
  - AUTH_ROUTES : l'une de ces valeurs : protegees, ouvertes attendu, reçu « Ouvertes » (lu dans .env).
```

Code de sortie 1. Une valeur d'une liste s'écrit exactement comme dans le schéma, en minuscules. Au démarrage, la même erreur arrête le service avec le code 60 (voir [Configuration](configuration.md)).

### Le service démarre mais `/api/health` répond 503 `{"statut":"degrade","base":"indisponible"}`

L'application n'a pas trouvé sa base. Cause la plus fréquente : le service est lancé **depuis un autre dossier** que celui du projet, donc sans `.env` ni `config/env.json`. Le service démarre quand même (le journal dit `Base injoignable au démarrage`), et tout jeton est alors refusé. Lancez-le depuis la racine du projet ; avec un superviseur, réglez son dossier de travail. Voir [Déployer](deployer.md).

### `ebony migrate` applique de nouveau des migrations déjà jouées

Vous êtes sur **une autre base**. Une faute dans `DB_FICHIER` ne provoque aucune erreur : avec `DB_FICHIER=nexiste/pas/app.db`, `ebony migrate` a **créé les dossiers `nexiste/pas/` et une base neuve et vide**, puis appliqué toutes les migrations dessus. Un service lancé ainsi tourne sur une base vide. Vérifiez la valeur avec `ebony env`, cherchez un `app.db` inattendu dans le projet, et supprimez-le à la main une fois la bonne valeur remise.

## Les jetons et les routes

### `Le jeton n'a pas pu être enregistré. Cause : … no such table: eb_jetons`

La table des jetons n'existe pas encore : lancez `ebony migrate` (sa migration, `M…_CreeEbJetons`, est dans `database/migrations/`). Code de sortie 1. Même ordre dans les [premiers pas](premiers-pas.md) : `migrate` avant `token create`.

### Une route générée répond 401

La réponse est volontairement la même dans tous les cas, sans dire pourquoi : `401 non_autorise`. Vérifiez dans l'ordre :

1. L'en-tête est exactement `Authorization: Bearer eb_…` (le secret entier, 46 caractères).
2. Le jeton existe et n'est pas révoqué ou expiré : `ebony token list` (colonne « état »). Un jeton révoqué est refusé à la requête suivante.
3. La base répond : `GET /api/health` doit donner 200 (sans base, tout jeton est refusé).

Le secret ne se relit pas : un jeton perdu se remplace (`ebony token revoke`, puis `ebony token create`). Le service écrit une ligne `owl serve: rejet auth GET /api/… : authentification refusée par le hook` sur sa **sortie d'erreur** pour chaque refus.

### Sous PowerShell : `curl` ne se comporte pas comme prévu

Utilisez `curl.exe` (`curl` est un alias de `Invoke-WebRequest`), et pour lire le corps d'une réponse d'erreur, `curl.exe -i`. PowerShell 5.1 retire les guillemets d'un JSON passé en argument : écrivez le corps dans un fichier et envoyez-le avec `--data-binary @fichier`.

## Le lancement du service

### `owl serve : ecoute impossible sur 127.0.0.1:18200 (bind (code 10048))`

Le port est déjà pris, souvent par une instance précédente du service. Choisissez un autre port (`owl serve --port 8081`) ou arrêtez le processus qui l'occupe (sous Windows : `Get-NetTCPConnection -LocalPort 18200` donne son identifiant). Le second service s'arrête aussitôt ; le premier n'est pas touché.

## Les tests

### `owl test` : `Type inconnu 'cM…_CreeX'` dans `tests/integration/migrations/test_M…_CreeX.owl`

Vous avez supprimé une migration (`database/migrations/M…_CreeX.owl`) mais pas son test : `ebony make migration` écrit les deux. Supprimez aussi `tests/integration/migrations/test_M…_CreeX.owl`. Code de sortie 1, la suite est comptée en `CRASH`.

### `ALL CLEAR (0 suites, 0 assertions)`

Ce n'est pas une réussite : rien n'a été exécuté. Un projet sans ressource générée n'a pas de test d'application ; avec `--filter`, un nom qui ne correspond à aucun **nom de fichier** (la casse compte) donne aussi 0 suite et le code 0. Vérifiez toujours le nombre de suites, et utilisez `owl test -vv` pour voir quelle assertion échoue.

## Les chemins avec des accents

Un projet dans un dossier accentué (`Café\boutique`) a été essayé : `ebony new`, `ebony migrate`, `owl --check projet.owl` et `owl serve` (`/api/health` 200) y fonctionnent. Ce qui échoue est limité : sous Windows, l'exécutable `owl` n'ouvre pas **un fichier donné par un chemin absolu accentué** (`owl "C:\…\Café\x.owl"` : « cannot open file », code 65, mesuré avec OWL 1.8.1). Lancez `owl` depuis le dossier du projet, avec des chemins relatifs. Sous Linux, un chemin accentué n'a pas été essayé.

## PostgreSQL : `ssl : serveur refuse TLS, anti-downgrade` (non rejouée)

OWL exige par défaut un TLS vérifié vers PostgreSQL et refuse un serveur qui n'en propose pas. Pour un serveur **local de développement** sans TLS : `DB_TLS=desactive` dans `.env` ; en production, gardez `verifie`. Détail des quatre niveaux dans [Configuration](configuration.md).

## Si rien de cela ne correspond

Lancez la commande avec `--json` quand elle l'accepte (une ligne, `{"ok":false,"error":"…"}`), relevez le code de sortie ([Erreurs](erreurs.md), [Commandes](commandes.md)) et ouvrez un [ticket](https://github.com/ebonyframework/ebony/issues) avec la commande, la sortie complète, `ebony --version`, `owl --version` et votre système.
