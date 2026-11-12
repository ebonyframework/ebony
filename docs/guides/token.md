# `ebony token` : créer, lister et révoquer les jetons d'accès

```
ebony token create <nom> [--expire AAAA-MM-JJ] [--json]   crée un jeton et l'affiche une seule fois
ebony token list [--json]                                 liste les jetons (jamais leur secret)
ebony token revoke <identifiant> [--json]                 révoque un jeton
```

À lancer dans le dossier d'un projet ebony (un `ebony.conf`). La base est celle de la configuration du projet, comme pour [`ebony migrate`](migrate.md) (`ebony env` la montre). **SQLite et PostgreSQL 16 sont vérifiés** contre une vraie base ; HFSQL est refusé (code 39).

> Cette commande **gère** les jetons ; ce sont les **routes générées** par `ebony make resource` qui les **vérifient** : sans `Authorization: Bearer eb_…` valide, elles répondent 401, et un jeton révoqué est refusé à la requête suivante.

## Comment ça marche

- Un jeton est **32 octets aléatoires** (`HasardSécuriséOctets`) en Base64 URL, précédés de `eb_` : 46 caractères, par exemple `eb_3q2-7wAAAAA…`. Le préfixe aide les outils qui cherchent des secrets oubliés.
- **Le secret n'est affiché qu'une fois, à la création.** La base ne garde que son **empreinte SHA-256** : même quelqu'un qui lit la base ne peut pas s'en servir, et ebony ne peut pas le retrouver. Un secret perdu se remplace : révoquez le jeton, créez-en un autre. Un hachage rapide suffit parce que le secret est aléatoire sur 256 bits (OWL n'a pas de hachage lent : c'est pourquoi il n'y a pas de mot de passe).
- **La table** s'appelle `eb_jetons` (comme `eb_migrations`) : `empreinte` (clé), `nom`, `cree_le`, `expire_le`, `revoque_le`, toutes en texte et jamais NULL (« » veut dire « n'expire pas » ou « pas révoqué »). Elle est créée par **la migration que le module `auth` fournit** (`database/migrations/M202611100000_CreeEbJetons.owl`, écrite par `ebony new` et `ebony init`, jouée par `ebony migrate`) : `token create` ne la crée plus, il refuse et dit de lancer `ebony migrate` si elle manque. **Si elle manque** (un projet dont les migrations ont été écrites avant les jetons), `ebony upgrade` ne l'écrit pas : copiez dans son `database/migrations/` les fichiers d'un projet neuf (`ebony new essai --auth --table <votre table>`), puis lancez `ebony migrate` (sans le fichier `CreeUtilisateurs` si votre table des utilisateurs existe déjà) ; `list` et `revoke` ne la créent pas non plus (comme AdonisJS, qui ne crée pas `auth_access_tokens` à la volée). Dates en UTC, `AAAA-MM-JJTHH:MM:SSZ`.
- **L'identifiant** montré par `list` est le début de l'empreinte (12 caractères hexadécimaux). Il désigne un jeton pour `revoke` et ne permet pas de retrouver le secret.
- **Le nom** est une étiquette libre (60 caractères au plus) ; plusieurs mots après `create` forment un seul nom (`ebony token create robot de nuit`). Deux jetons peuvent porter le même nom.
- **`--expire AAAA-MM-JJ`** : le jeton vaut jusqu'à la **fin de ce jour, en UTC** (`23:59:59Z`), puis il est refusé. Une date passée ou qui n'existe pas (`2027-02-30`) est refusée (code 2). Sans `--expire`, le jeton n'expire pas. Pas de durée relative (`--jours`) pour l'instant.
- **`revoke`** refuse le jeton aussitôt. Révoquer deux fois, ou un identifiant inconnu : code 1 (un script doit voir l'échec).
- **État** d'un jeton dans `list` : `actif`, `expiré` ou `révoqué` (révoqué l'emporte sur expiré).

## Codes de sortie

| Code | Cas |
|---|---|
| 0 | réussite |
| 1 | échec : base injoignable (45), table ou enregistrement refusés (51), aucun jeton actif à cet identifiant (52), configuration invalide (60) |
| 2 | usage incorrect (25) : sous-commande absente ou inconnue, nom ou identifiant manquant ou incorrect, option inconnue, `--expire` hors de `create` ou date incorrecte ou passée |

## Sortie `--json`

Une seule ligne, rien d'autre sur la sortie.

```
create : {"ok":true,"command":"token create","id":"46bdfff49098","name":"ci","token":"eb_…","expiresAt":"","notes":[…]}
list   : {"ok":true,"command":"token list","tokens":[{"id":"…","name":"ci","createdAt":"…","expiresAt":"","revokedAt":"","status":"active"}]}
revoke : {"ok":true,"command":"token revoke","id":"46bdfff49098","revoked":true}
```

`token` n'est donné que par `create`, une seule fois. En cas d'échec : `{"ok":false,"error":"…"}`. `status` vaut `active`, `expired` ou `revoked`.

## Ce qui est vérifié, ce qui ne l'est pas

- **Vérifié** : les fonctions et la classe (`modules/auth/execution/auth/`, 56 assertions sur une vraie base SQLite en mémoire), les arguments, l'affichage et l'orchestration (`tests/unitaires/commandes/token/`), et la commande réelle avec le lanceur sur la base d'un projet (`tests/integration/lanceur.ps1 -Groupe make`), y compris que **le fichier de la base ne contient pas le secret mais son empreinte**.
- **Vérifié aussi** (rejoué sur la version 0.1.0 publiée) : un jeton contre un vrai `owl serve` (401 sans jeton, 200 avec, 401 dès qu'il est révoqué), les codes de sortie et les formes `--json` ci-dessus ; sous Linux, la création, l'usage et la révocation d'un jeton (`tests/integration/linux.sh`).
- **Pas vérifié** : deux `token create` simultanés (aucun verrou, comme `migrate`).
- La recherche d'un jeton se fait par `WHERE empreinte = …`, sans comparaison en temps constant : acceptable pour une empreinte de 256 bits d'un secret aléatoire, à confirmer.
