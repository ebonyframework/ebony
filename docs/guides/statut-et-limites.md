# Statut et limites connues


Ebony 0.1.0 est une **préversion**. À savoir avant de l'adopter :

- **Une requête à la fois.** Un service OWL traite les requêtes une par une (quatre requêtes d'une seconde envoyées ensemble prennent environ quatre secondes) : ne l'exposez pas à une charge imprévisible. OWL n'a ni thread ni asynchrone.
- **Bases** : SQLite et PostgreSQL 16 pour `ebony migrate` (essayés contre un vrai serveur) ; HFSQL est refusé pour les migrations.
- **Authentification** : des jetons d'accès pour des clients ; pas de connexion d'utilisateur (mot de passe, session, rôles).
- **Un `PUT` remplace toute la ressource** : un champ absent du corps est remis à la valeur par défaut de son type, et il n'y a pas de mise à jour partielle générée (voir [le chemin d'une requête](architecture.md#le-corps-dune-requête--une-lecture-tolérante)).
- **Validation minimale** : seuls les champs texte obligatoires sont vérifiés ; un module de validation est prévu.
- **SQLite et clés étrangères** : une clé étrangère déclarée dans une migration n'est pas vérifiée par la connexion SQLite (un produit d'une catégorie inexistante est accepté) ; vérifiez-le dans le service.
- **Pas encore** : fabriques et `seed`, routes déclarées dans un fichier à la AdonisJS, pages web, bureau, mobile. Ce qui est utilisable aujourd'hui est le projet API décrit plus haut.
- **Plateformes** : Windows ; Linux (`install.sh` à la place d'`ebony install`).
- **Lenteur au lancement** : une commande `ebony` prend 1 à 7 secondes depuis l'archive ou une copie installée, mais 20 à 25 secondes depuis un clone tant que les points d'entrée réduits n'ont pas été générés : OWL analyse tout le projet à chaque lancement.

