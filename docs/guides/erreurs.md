# Les erreurs d'une API Ebony

Toutes les erreurs d'une route générée ont **la même forme**, une ligne JSON :

```json
{"code":"introuvable","message":"Produit introuvable : 999"}
```

`code` est un identifiant stable, lisible par un programme ; `message` est un texte pour un humain. Le statut HTTP est celui de la réponse.

## Les codes

| Statut | `code` | Quand | Le `message` |
|---|---|---|---|
| **400** | `invalide` | le client envoie un corps invalide : un champ obligatoire vide, un texte qui n'est pas du JSON | le nom du champ concerné, par exemple « Le champ « nom » est obligatoire. » |
| **401** | `non_autorise` | pas de jeton, ou jeton inconnu, révoqué ou expiré | fixe : « Un jeton d'accès valable est exigé (Authorization: Bearer ...). » |
| **404** | `introuvable` | la ressource demandée n'existe pas (aussi une clé qui n'est pas un entier : lue comme 0) | « Produit introuvable : 999 » |
| **409** | `conflit` | une clé texte déjà prise, ou une règle métier qui lève 409 | celui de l'exception |
| **503** | `base_indisponible` | la base ne répond pas, même après une reconnexion | fixe : « La base de données est indisponible. » |
| **500** | `erreur_interne` | tout le reste : une requête refusée par la base, une exception imprévue | fixe : « Une erreur interne est survenue. » |

Un corps JSON avec un `Content-Type` qui n'est pas JSON est refusé par OWL avec le statut 415, avant la route.

**Le détail d'une erreur serveur (500, 503) va au journal, jamais au client.** Les erreurs du client (400, 401, 404, 409) ne sont pas journalisées. Une réponse d'erreur ne contient donc jamais de texte SQL ni de chemin interne.

## Lever une erreur depuis votre code

Dans un service ou dans une route, une règle violée se signale par une exception dont le **code** est le statut voulu :

```owl
ExceptionDéclenche(409, "Ce produit existe déjà")
ExceptionDéclenche(400, "Le prix ne peut pas être négatif")
ExceptionDéclenche(404, "Client introuvable : " + nId)
```

La route qui a appelé le service attrape l'exception (`QUAND EXCEPTION`), traduit son code par `EbStatutHttpDeCode`, et répond avec `EbCorpsErreurHttp`. Les codes **reconnus** sont 400, 401, 404, 409 et 503 ; **tout autre code devient 500** et son message est caché. Pour répondre avec un autre statut (403, 422…), écrivez la réponse vous-même dans la route : les fichiers générés sont à vous.

## Ce qu'on voit côté client

```text
GET  /api/produits                       (sans jeton)         →  401  {"code":"non_autorise",…}
POST /api/produits   {"prix":3}                                →  400  {"code":"invalide","message":"Le champ « nom » est obligatoire."}
GET  /api/produits/999                                         →  404  {"code":"introuvable","message":"Produit introuvable : 999"}
```

## Les erreurs de la ligne de commande

`ebony` a sa propre convention, distincte de celle de l'API : un code de sortie (0 réussite, 1 échec, 2 usage incorrect, 70 erreur interne) et, pour un échec, une seule ligne `ebony : <cause>` (avec `--json` : `{"ok":false,"error":"…"}`). Jamais de pile d'appels.
