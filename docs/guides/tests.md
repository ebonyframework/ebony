# Tester une application Ebony

Les tests d'un projet Ebony sont des tests OWL ordinaires, lancés par `owl test` : Ebony n'a pas de lanceur de test à lui. Ce guide dit **ce qu'Ebony écrit pour vous**, comment le lancer et le lire, et ce qui n'est pas couvert. Il ne remplace pas la charte de test d'OWL (`owl learn test`). Tout ce qui suit a été rejoué sur un projet créé avec Ebony 0.1.0 (Windows 11, OWL 1.8.1).

## Ce que le projet contient

Un projet neuf n'a **aucun test** : `owl test` répond `ALL CLEAR (0 suites, 0 assertions)`. Les tests viennent des commandes `make`.

Pour `ebony make migration CreeProduits …` puis `ebony make resource Produit …` :

| Fichier | Ce qu'il vérifie | Base |
|---|---|---|
| `tests/integration/migrations/test_M…_CreeProduits.owl` | le nom de la migration, que `Monte()` crée la table et que `Descend()` la supprime | SQLite en mémoire |
| `tests/unitaires/produit/test_cProduit.owl` | l'entité : accesseurs, `EnJson()` | aucune |
| `tests/unitaires/produit/test_cRepoProduitMemoire.owl` | le repository en mémoire : ajout, lecture, modification, suppression, clés absentes | aucune |
| `tests/integration/produit/test_cRepoProduitSql.owl` | le même contrat sur le repository SQL (et, si une colonne accepte `NULL`, sa lecture comme valeur par défaut) | SQLite en mémoire |
| `tests/unitaires/produit/test_cServiceProduit.owl` | le service métier sur le repository en mémoire | aucune |

Soit, pour la table `produits` de cet exemple (quatre colonnes, aucune ne tolérant `NULL`), **5 suites, 59 assertions, 24 scénarios**, qui s'exécutent en 13 à 14 secondes sur la machine d'essai. Ces fichiers sont à vous : ajoutez-y vos règles, ou supprimez ce dont vous n'avez pas besoin. Si vous supprimez une migration, supprimez aussi son test, sans quoi `owl test` plante (voir [Dépanner](depanner.md)).

Les tests de base de données ouvrent une base SQLite **en mémoire** : ils ne touchent ni `storage/app.db` ni votre configuration. Les deux tests de base déclarent `avantChaqueTest` et `apresChaqueTest` (ouvrir puis fermer la connexion), les autres n'ont pas besoin de fixtures.

## Lancer

```sh
owl test                          # tous les tests du projet
owl test -vv                      # une ligne par assertion, avec la valeur obtenue et attendue
owl test --filter cProduit        # les fichiers dont le nom contient « cProduit »
```

Une exécution réussie :

```text
✓ test_cProduit.owl (8 assertions)
…
   BILAN: 5 suites
     ✓   5 OK         (59 assertions PASS)
     ✓  24 SCENARIOS  (charte de test §4)
   STATUS: ALL CLEAR (5 suites, 59 assertions, 24 scenarios)
```

Le code de sortie est 0 si tout passe, 1 sinon.

**Le filtre porte sur le nom du fichier, et la casse compte.** `--filter cProduit` ne retient que `test_cProduit.owl` (1 suite : il ne contient pas `cRepoProduitSql`) ; `--filter cproduit` et un nom qui ne correspond à rien répondent `ALL CLEAR (0 suites, 0 assertions)` avec le code **0**. Ce n'est pas une réussite : **vérifiez toujours le nombre de suites**, surtout dans un script ou une intégration continue.

## Lire un échec

Avec l'attendu de `LitId()` changé de 5 en 6 dans `test_cProduit.owl`, `owl test` répond (code 1) :

```text
✗ test_cProduit.owl (7/8 passed)
…
Assertions failed :
  ✗ test_cProduit.owl (7/8)
   STATUS: 1 FAILURES
```

Il dit **quel fichier** échoue, pas quelle assertion. Relancez cette suite avec `-vv` :

```text
  FAIL: id -- got 5 expected 6
  ✗ scenario scenario_les_accesseurs_rendent_les_valeurs_du_constructeur (3 pass, 1 fail)
```

Le libellé (`id`) est le dernier argument de l'assertion : écrivez-en un qui dise ce qui est vérifié. Un fichier qui ne **compile** pas est compté en `CRASH`, pas en échec : l'erreur de compilation est affichée avec le fichier et la ligne.

## Écrire un test

Un fichier `test_*.owl`, n'importe où dans le projet : `owl test` parcourt tous les dossiers. Chaque procédure dont le nom commence par `scenario_` est un scénario ; le commentaire qui la précède la décrit en une phrase ; `dbgVérifieEgalité(obtenu, attendu, "libellé")` et `dbgVérifieVrai(condition, "libellé")` sont les assertions. Exemple, rejoué :

```owl
// Le prix total est le prix unitaire multiplié par la quantité.
PROCEDURE scenario_prix_total()
	dbgVérifieEgalité(2 * 3, 6, "deux fois trois")
FIN
```

Posé dans `tests/unitaires/perso/test_prix.owl`, il est trouvé et exécuté : `✓ test_prix.owl (1 assertions)`.

Deux pièges propres à Ebony, d'après les mesures faites sur son propre dépôt :

- Une variable déclarée **au niveau d'un fichier de test** est une globale de tout le projet : si une variable locale d'un autre fichier porte le même nom, `owl test` plante avec une erreur de compilation dans un fichier voisin. Donnez à ces variables un préfixe `g` (`gBase`).
- Un `ServiceREST` dont le bloc déclare une variable d'une classe du projet fait planter `owl test` (« Variable inconnue »). Le service généré ne le fait pas ; voir [Générer : make](make.md) pour la façon de construire repository et service **dans** la route.

Pour les fixtures (`avantChaqueTest`, `apresChaqueTest`…), les scénarios privés et le reste de la charte : `owl learn test`.

## Ce que les tests générés ne couvrent pas

- **Les routes HTTP.** Aucun test généré n'envoie de requête : le contrôleur n'est vérifié par aucune des 5 suites. Pour le vérifier, lancez le service et appelez-le (voir les [premiers pas](premiers-pas.md)). Un test de route automatisé n'a pas été essayé.
- **Les règles que vous ajoutez** : le service généré passe les appels au repository ; vos règles ont besoin de vos tests.
- **PostgreSQL** : le test du repository SQL tourne sur SQLite en mémoire. Le SQL de PostgreSQL est vérifié par les tests d'Ebony lui-même, pas par ceux de votre projet.

## Ce qui n'est pas vérifié

- Le temps d'`owl test` sur un gros projet : OWL recompile le projet pour **chaque suite** (mesuré sur le dépôt d'Ebony, où le coût devient vite sensible). Les 13 secondes ci-dessus valent pour 5 suites d'un petit projet.
- Les mêmes essais sous Linux (le parcours `owl test` d'un projet généré y passe : 5 suites, 59 assertions, mais le filtre, `-vv` et les échecs n'y ont pas été rejoués).
