<div align="center">

<img src="assets/logo-ebony.png" width="200" alt="Logo Ebony : une tête d'éléphant souriant, oreilles orange">

# Ebony

**Le cœur du framework Ebony : des applications OWL structurées, générées par une commande.**

Inspiré d'AdonisJS, pour le langage [OWL](https://github.com/followthewhiteowl/neowl).

[![Documentation](https://img.shields.io/badge/Documentation-ebonyframework.github.io-blue?style=for-the-badge)](https://ebonyframework.github.io/ebony/)
[![Version](https://img.shields.io/github/v/release/ebonyframework/ebony?style=for-the-badge&label=Version)](https://github.com/ebonyframework/ebony/releases)
[![Licence MIT](https://img.shields.io/github/license/ebonyframework/ebony?style=for-the-badge&label=Licence)](LICENSE)
[![OWL 1.8.1](https://img.shields.io/badge/OWL-1.8.1-blue?style=for-the-badge)](https://github.com/followthewhiteowl/neowl)
[![Plateformes : Windows et Linux](https://img.shields.io/badge/Plateformes-Windows%20%7C%20Linux-lightgrey?style=for-the-badge)](https://ebonyframework.github.io/ebony/guides/installation)
[![Statut : préversion](https://img.shields.io/badge/Statut-Pr%C3%A9version-yellow?style=for-the-badge)](https://ebonyframework.github.io/ebony/guides/statut-et-limites)

[Installation](#installation) ·
[Démarrage rapide](#démarrage-rapide) ·
[Documentation](https://ebonyframework.github.io/ebony/) ·
[Contribuer](#contribuer)

</div>

---

## Présentation

**Ebony** donne à OWL ce que les frameworks web donnent à leur langage : une façon **cohérente** de démarrer un projet, de décrire ses données, d'exposer une application et de la protéger.

Une commande crée un projet qui compile et démarre sous `owl serve`. Une autre écrit, pour une table, l'entité, les repositories, le service métier, le contrôleur REST et les tests, avec des routes protégées par jeton. Le code généré est lisible et reste le vôtre.

> **Préversion 0.1.0.** Un socle de démarrage pour une petite API OWL, pas encore un framework complet. Lisez le [statut et les limites](https://ebonyframework.github.io/ebony/guides/statut-et-limites) avant de l'adopter.

## Installation

Prérequis : [OWL](https://github.com/followthewhiteowl/neowl) **1.8.1** (`owl` dans le PATH, la version prise en charge ; une autre version donne un avertissement de `ebony doctor`), Windows ou Linux. Installez Ebony **en une commande** (elle vérifie que `owl` est là, télécharge la dernière release, contrôle sa somme SHA-256 et installe ; elle n'installe pas OWL) :

```powershell
irm https://github.com/ebonyframework/ebony/releases/latest/download/install.ps1 | iex      # Windows (PowerShell)
```
```sh
curl -fsSL https://github.com/ebonyframework/ebony/releases/latest/download/install.sh | sh   # Linux
```

Ouvrez ensuite un nouveau terminal et lancez `ebony doctor`. Autres voies (archive, clone) et détail de ce que fait l'installateur : le [guide d'installation](https://ebonyframework.github.io/ebony/guides/installation).

## Démarrage rapide

Ebony installé (voir [Installation](#installation)), créez une API, migrez-la, protégez-la par un jeton et lancez-la :

```powershell
ebony new boutique ; cd boutique
Copy-Item .env.exemple .env ; Copy-Item .env.secrets.exemple .env.secrets
ebony make migration CreeProduits --champs 'id:entier*,nom:texte,prix:reel,actif:booleen'
ebony make resource Produit --champs 'id:entier*,nom:texte,prix:reel,actif:booleen' --table produits
ebony migrate
ebony token create essai          # le secret (eb_…) n'est affiché qu'une fois : copiez-le
owl serve --port 8080
```

Puis, dans un second terminal (le secret du jeton à la place de `eb_…`) :

```powershell
curl.exe -s -H "Authorization: Bearer eb_…" http://127.0.0.1:8080/api/produits       # []
```

Sans jeton, la même requête répond **401**. Sous Linux : `cp` à la place de `Copy-Item` (la commande `ebony` est le lien posé par `install.sh`). Le [parcours détaillé](https://ebonyframework.github.io/ebony/guides/premiers-pas) explique chaque étape.

## Documentation

**Toute la documentation est sur [ebonyframework.github.io/ebony](https://ebonyframework.github.io/ebony/).** Pour commencer :

- [Introduction](https://ebonyframework.github.io/ebony/guides/introduction) : ce qu'est Ebony, ses kits et sa philosophie.
- [Premiers pas](https://ebonyframework.github.io/ebony/guides/premiers-pas) et le [tutoriel d'une petite boutique](https://ebonyframework.github.io/ebony/guides/tutoriel).
- [Structure d'un projet](https://ebonyframework.github.io/ebony/guides/structure) : où est quoi, pour chaque kit.
- [Référence des commandes](https://ebonyframework.github.io/ebony/guides/commandes) et [les modules](https://ebonyframework.github.io/ebony/guides/modules).
- [Adopter Ebony dans un projet existant](https://ebonyframework.github.io/ebony/guides/adopter-un-projet).

## Contribuer

Les contributions sont les bienvenues, même petites : un rapport de bug clair aide autant qu'une correction. Avant de commencer, lisez le [guide de contribution](https://github.com/ebonyframework/.github/blob/main/CONTRIBUTING.md) et le [code de conduite](https://github.com/ebonyframework/.github/blob/main/CODE_OF_CONDUCT.md). Pour signaler une faille de sécurité, suivez la [politique de sécurité](https://github.com/ebonyframework/.github/blob/main/SECURITY.md) : pas de ticket public.

Ebony est un projet indépendant, **non affilié** à l'équipe du langage OWL (NeOwl) : il s'appuie sur la commande `owl` publiée par ce projet, sans la modifier ni l'embarquer.

## Licence

[MIT](LICENSE), au nom d'ElmiraLabs.
