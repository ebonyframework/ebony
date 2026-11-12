# Journalisation

OWL n'a qu'une sortie texte pour les journaux : la sortie standard (une exception non gérée dans un handler donne un `500` et une trace sur la sortie standard ; le processus survit).
`cEbJournal` (dans `ebony/journal/`) y écrit **une ligne JSON par événement**, dans un format stable que les hébergeurs savent collecter.

## Format

```
{"ts":"2026-11-02T12:09:37Z","niveau":"info","message":"requête","code":"200","route":"/api/clients"}
```

- `ts` : instant en UTC, précision d'**une seconde** (`DateHeureSys` d'OWL n'a pas de fraction : mesuré, les centièmes sont toujours à 00).
- `niveau` : `debug`, `info`, `warn` ou `error`.
- `message` : texte libre.
- Les champs que vous ajoutez viennent ensuite, **triés par nom** (l'ordre d'un tableau associatif d'OWL est celui des insertions : le trier rend la ligne reproductible). Leurs valeurs sont des chaînes.
- Un champ appelé `ts`, `niveau` ou `message` est renommé `_ts`, `_niveau`, `_message` : une clé n'apparaît jamais deux fois.
- Jamais de saut de ligne dans une ligne : un message sur plusieurs lignes est écrit avec `\n`. Les accents restent tels quels (UTF-8).

## Utilisation

```owl
oSortie est un cEbSortieJournalConsole
oHorloge est un cEbHorlogeSysteme
oJournal est un cEbJournal(oSortie, oHorloge, "info")

oJournal.Info("démarré")
oJournal.Erreur("base injoignable")

champs est un tableau associatif
champs["route"] = "/api/clients"
champs["code"] = "200"
oJournal.Ecrit("info", "requête", champs)
```

Le troisième paramètre du constructeur est le **niveau minimum** : en dessous, l'événement est ignoré (`"warn"` n'écrit que `warn` et `error`). Un niveau inconnu vaut `info`. Un niveau inconnu à l'écriture est écrit `info` : un journal ne lève jamais d'exception à cause de ce qu'on lui demande d'écrire.

## À savoir

- **Aucun secret** dans un message ni dans un champ : le journal écrit tel quel ce qu'on lui donne (voir `docs/guides/configuration.md`).
- Les tests utilisent `cEbSortieJournalFictive` (garde les lignes) et `cEbHorlogeFictive` (heure fixe), sans rien écrire sur la sortie.

## Ce qui n'est pas fait

- Le format `clé=valeur` (l'issue proposait JSON ou `clé=valeur` : seul JSON est fourni).
- Une fraction de seconde dans `ts`, et l'identifiant de corrélation par requête.
- Le branchement dans le code généré (`surErreur`, démarrage) : la procédure existe, aucun fichier généré ne l'appelle encore.
- Non testé : la collecte de la sortie par un hébergeur réel. Vérifié : la ligne écrite par `cEbSortieJournalConsole` sur la sortie standard sous `owl test`.
