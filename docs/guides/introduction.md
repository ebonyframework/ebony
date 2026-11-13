# Introduction


**Ebony** donne à OWL ce que les frameworks web donnent à leur langage : une façon **cohérente** de démarrer un projet, de décrire ses données, d'exposer une application et de la protéger. Le dépôt `ebonyframework/ebony` en est le **cœur** : la commande `ebony`, les générateurs et la petite bibliothèque d'exécution (`Eb*`) que chaque projet généré embarque.

Une commande crée un projet qui compile et démarre sous `owl serve`. Une autre écrit, pour une table, l'entité, les repositories, le service métier, le contrôleur REST et les tests, avec des routes protégées par jeton. Le code généré est lisible et reste le vôtre.

> **Préversion 0.1.1.** Un socle de démarrage pour une petite API OWL, pas encore un framework complet. Lisez le [statut et les limites](statut-et-limites.md) avant de l'adopter.

## L'écosystème Ebony


Le framework se construit en couches : le cœur d'abord, puis un type de projet à la fois.

| Projet | Ce que c'est | État |
|---|---|---|
| **Ebony** (le cœur) | Le cœur : commande `ebony`, générateurs, bibliothèque d'exécution, modules. | Disponible (préversion) |
| **API REST** | Un service HTTP : routes, contrôleurs, services métier, repositories, migrations, jetons. `ebony new` (kit `api`, par défaut) ; `ebony new <nom> --kit slim` pour le cœur seul, sans base de données (voir [les kits](modules.md#les-kits)). | Disponible (préversion), fourni par le cœur |
| **Web** | Des applications avec pages rendues côté serveur (moteur de gabarits). | Prévu |
| **Desktop** | Des applications de bureau. | Prévu |
| **Mobile** | Des applications mobiles. | À l'étude |

## Philosophie


Ebony fait des choix, et les assume.

- **Votre code vous appartient.** Ebony *génère* du code OWL lisible dans votre projet ; il ne le cache pas derrière une bibliothèque. `ebony make` ne remplace jamais un fichier existant, et Ebony ne supprime jamais rien (la seule exception est `ebony uninstall`, bornée et annoncée).
- **Explicite plutôt que magique.** OWL n'a ni espaces de noms ni paquets : chaque nom global de la bibliothèque porte le préfixe `Eb`. Rien n'est deviné : une route est protégée parce que le contrôleur le dit.
- **Sûr par défaut.** Les routes générées exigent un jeton. Un secret est affiché une seule fois, la base n'en garde que l'empreinte, et la configuration n'expose jamais la valeur d'un secret. Rendre une route publique est un choix (`AUTH_ROUTES=ouvertes`), pas un oubli.
- **Des couches nettes.** Un contrôleur parle HTTP et vérifie ce que le client envoie, un service porte les règles métier, un repository parle à la base. Chaque accès au système passe par un **port** avec un adaptateur réel et un adaptateur de test : on teste sans base ni disque.
- **Un cœur modulaire.** Le cœur ne connaît pas les modules ; un module déclare ce qu'il apporte dans un manifeste.
- **Honnête sur ses limites.** Ce qu'OWL ne permet pas (hachage lent, fils d'exécution, lancement de programmes…) est dit tel quel plutôt que contourné en silence.

