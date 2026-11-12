# Performance et limites d'une application OWL

Ce que le serveur d'OWL (`owl serve`, ou le binaire produit par `owl-build`) permet et ne permet pas, pour écrire des handlers qui tiennent en production.
Origine : tests faits sous Linux (OWL 1.6.0, binaire statique, PostgreSQL 18). Seul le comportement de la section 1 a été refait sous Windows (OWL 1.7.0, voir plus bas) ; les autres mesures n'ont **pas** été refaites. EbonyCore ne promet rien de plus que ce qui est écrit ici. OWL évolue vite : ces limites sont à remesurer à chaque nouvelle version d'OWL.

## 1. Les requêtes sont servies une par une

Mesuré avec `owl serve` et avec le binaire `owl-build` :

| Situation | Résultat |
|---|---|
| 4 requêtes d'une seconde, envoyées ensemble | 4 s au total |
| `ping` envoyé pendant un calcul de 31 s | attend la fin du calcul (31 s observées) |
| un handler qui attend (`Temporise`) | bloque aussi les autres requêtes |
| client lent ou muet (connexion ouverte, rien envoyé) | ne bloque **pas** les autres |

**Remesuré sous Windows 11 avec OWL 1.7.0**, avec `owl serve` et un service minimal à deux routes (l'une attend `Temporise("1s")`, l'autre répond tout de suite) : le comportement est le même.

| Situation | Résultat |
|---|---|
| 1 requête d'une seconde, seule | 1,03 s |
| 4 requêtes d'une seconde, envoyées ensemble | 4,06 s au total (en concurrence : environ 1 s) |
| requête immédiate envoyée pendant une requête d'une seconde | 0,69 s (seule : 0,001 s) |

Limites de cette remesure : seule l'attente par `Temporise` a été essayée (pas un calcul long, pas un client lent ou muet) ; le binaire `owl-build` et un service généré par `ebony new` (base de données, bibliothèque `Eb*`) n'ont pas été mesurés.

**Aucune concurrence n'est promise.** Conséquences :

- Un handler doit répondre en quelques millisecondes. Pas de calcul long, pas d'attente (`Temporise`), pas d'appel réseau lent ou sans délai maximal dans une route.
- Un travail long ne se fait pas dans un handler : le découper, le confier à un autre processus, ou répondre tout de suite et le traiter ailleurs.
- La durée d'une requête retarde toutes les suivantes : une route à 200 ms plafonne le service à ~5 requêtes par seconde, quel que soit le nombre de clients.
- Un état partagé (la connexion à la base, des globales) n'a pas besoin de verrou : il n'y a jamais deux requêtes en même temps. Ne pas en déduire que c'est garanti pour toujours ; c'est un comportement mesuré, pas un contrat.

## 2. Taille des corps

Un corps de 20 Mo est refusé en `413` par défaut.

## 3. Base de données

- Ouvrir une connexion **à chaque requête** : ~40 requêtes/s (l'ouverture SCRAM de PostgreSQL coûte ~25 ms).
- Ouvrir **une fois** (`FinInitialisation`) et fermer dans `Fermeture` : 390 à 690 requêtes/s.
- Les erreurs d'E/S d'OWL sont « douces » : `Succès` faux, aucune exception. Une connexion partagée ne se rétablit jamais seule après un arrêt de la base.
  Utiliser `cEbBaseResiliente` (module `db` : `modules/db/execution/donnees/`) : elle sonde, rouvre, rejoue une fois, sinon rend « indisponible » (à traduire en `503`). Voir `modules/core/execution/donnees/README.md`.
- Une écriture dont la réponse s'est perdue peut être rejouée alors qu'elle avait abouti : écrire les requêtes d'écriture de façon idempotente quand c'est possible.

## 4. Erreurs

Une exception non gérée dans un handler donne un `500` et une trace sur la sortie standard ; le processus survit.

## Ce qui n'est pas fait

- `ebony doctor` n'avertit pas encore des appels bloquants dans un handler (prévu pour plus tard).
