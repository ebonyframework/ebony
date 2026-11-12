# Structure d'un projet


Tout projet Ebony part du **même socle** ; son **kit** (le type d'application, choisi par `ebony new <nom> --kit …`) ajoute des dossiers ou en retire. Le socle :

```text
mon-projet/
├── ebony.conf            nom, kit, modules, version minimale
├── projet.owl            le projet OWL (point d'entrée)
├── .env.exemple          modèle de .env (configuration)
├── .env.secrets.exemple  modèle de .env.secrets (secrets)
├── AGENTS.md             consignes pour un assistant de code
├── README.md
├── config/env.json       le schéma de la configuration
├── app/                  le code : dépend du kit (ci-dessous)
└── ebony/                la bibliothèque d'exécution
```

`ebony/` n'est pas à vous : c'est la bibliothèque, que `ebony upgrade` aligne sur la version installée. Tout le reste est à vous.

## Ce que chaque kit ajoute

| Kit | État | Dossiers propres à ce kit |
|---|---|---|
| **api** (par défaut) | Disponible | `app/http/` (service REST, contrôleurs), `app/services/`, `app/donnees/`, `app/domaine/`, `database/migrations/`, `tests/`, `storage/` (SQLite local) ; `config/Auth.owl` avec `--auth`. Détail ci-dessous. |
| **slim** | Disponible | `app/http/` seulement : le service REST, sans base de données ni migrations, ni variable `DB_*`. |
| **web** | Prévu | Ceux de l'API, plus `app/http/pages/` (routes de pages), `vues/` (gabarits HTML), `public/` (CSS, images, scripts) et `ebony/gabarits/`. |
| **desktop** (bureau) | Prévu | `app/ui/` (une fenêtre par fichier), `app/presentation/` (contrôleurs ou présentateurs), `ressources/` (icônes) ; plus de `app/http/`, sauf si l'application expose aussi une API. |
| **mobile** | À l'étude | Structure non définie. |

Seuls `api` et `slim` existent aujourd'hui. Les structures de `web` et de `desktop` sont des **intentions de conception, pas du code** : elles peuvent changer avant d'être livrées.

## Le kit api, en détail

Ce que crée `ebony new boutique`, puis `ebony make resource Produit …` :

```text
boutique/
├── ebony.conf            nom, kit, modules, version minimale
├── projet.owl            le projet OWL (point d'entrée)
├── .env.exemple          modèle de .env (configuration)
├── .env.secrets.exemple  modèle de .env.secrets (secrets)
├── AGENTS.md             consignes pour un assistant de code
├── config/
│   ├── env.json          le schéma de la configuration
│   └── Auth.owl          l'authentification (avec --auth)
├── app/
│   ├── http/             le service REST et les contrôleurs
│   ├── services/produit/ les règles métier
│   ├── donnees/produit/  les repositories : SQL et mémoire
│   └── domaine/produit/  l'entité et les contrats
├── database/migrations/  une migration par fichier
├── tests/                unitaires et d'intégration
├── storage/              la base SQLite locale (ignorée par git)
└── ebony/                la bibliothèque (ignorée par git)
```

