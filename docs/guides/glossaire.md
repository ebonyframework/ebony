# Glossaire

Les mots d'ebony, dans l'ordre où une requête les traverse. Certains (service, route) n'ont pas le même sens en OWL et dans une application : la dernière section les sépare.

| Mot | Sens dans ebony |
|---|---|
| **Route** | Une adresse et une méthode HTTP (`GET /api/clients/12`). C'est une ligne de `start/routes.eb` (`ebony build`) ou une `OpérationHTTP` d'un contrôleur. |
| **Contrôleur** | La porte d'entrée HTTP d'une ressource : il déclare ses routes, **vérifie ce que le client envoie** (corps, clé) et répond en JSON. Fichier généré : `app/http/<dossier>/Controleur<Nom>.owl`. Il ne contient pas de règle métier. |
| **Service** (métier) | Les règles de l'application (« un client inactif ne peut pas commander »). Ne sait rien du HTTP. Il appelle le repository ; le contrôleur appelle le service, jamais le repository. Fichier généré : `app/services/<dossier>/cService<Nom>.owl`, mince au départ (il passe les appels au repository) : c'est là que vous ajoutez vos règles. |
| **Repository** | Le seul endroit qui parle à la base pour une entité : lire, ajouter, modifier, supprimer. Contrat `iRepo<Nom>`, adaptateurs `cRepo<Nom>Sql` et `cRepo<Nom>Memoire`. |
| **Entité** | Un objet de l'application (`cClient`) : champs privés, accesseurs `Lit…`, immuable. Ne sait rien de la base ni du HTTP. |
| **Validation** | Le nettoyage de ce qu'envoie le client, fait par le contrôleur (première couche). Une règle métier relève du service. |

## Service OWL et service métier : deux choses

- Un **`ServiceREST`** est un type d'OWL : un fichier qui déclare des routes et que `owl serve` monte. Un **contrôleur** d'ebony *est* un `ServiceREST`, d'où le `ControleurClient est un ServiceREST` des fichiers générés.
- Un **service métier** est une classe ordinaire (`cServiceClient`) : ce n'est pas un `ServiceREST`.

Quand ce guide dit « le service » seul, c'est le service métier ; le `ServiceREST` est « le service OWL ».

## Route et contrôleur

`ebony build` garde le mot **routes** : `start/routes.eb` est la liste des routes, `build/Routes.owl` le service OWL qu'on en tire. `make resource` écrit un **contrôleur**, qui regroupe les routes d'une ressource avec le code qui les traite (comme un contrôleur Symfony avec ses attributs de route).
