# ebony sous Linux

Le parcours du guide [premiers pas](premiers-pas.md) (`new`, `make`, `migrate`, `token`, `owl serve`, `curl`) marche sous Linux avec le lanceur `bin/ebony`. Vérifié avec Ubuntu sous WSL 2, OWL 1.8.1 (archive `neowl-1.8.1-linux-x86_64.tar.gz`), SQLite. `tests/integration/linux.sh` le rejoue.

## Installer

1. OWL : l'archive Linux de la [release d'OWL](https://github.com/followthewhiteowl/neowl/releases) (`owl` dans le PATH) et `curl`.
2. ebony, en une commande : `curl -fsSL https://github.com/ebonyframework/ebony/releases/latest/download/install.sh | sh` (voir le [guide d'installation](installation.md#en-une-commande) : somme SHA-256 vérifiée, copie dans `~/.local/share/ebony/<version>/`, lien `~/.local/bin/ebony`). Vérifié avec Ubuntu sous WSL 2 contre l'archive construite par `scripts/construit-archive.ps1`, et rejoué le 12 novembre 2026 contre la **release 0.1.0 publiée** (somme vérifiée, ebony --version, puis 
ew, make, migrate, 	oken, owl test et owl serve sur un projet neuf). À la main : le dépôt cloné, ou `ebony.tar.gz` extraite ; `chmod +x bin/ebony` si le bit d'exécution manque.
3. Le PATH, si vous n'avez pas utilisé `install.sh` : un lien suffit, `ln -s /chemin/vers/ebony/bin/ebony ~/.local/bin/ebony` (le lanceur suit les liens pour retrouver son dossier).

`ebony --version`, puis `ebony doctor` dans un dossier de travail.

## Vérifier (pour contribuer)

`pwsh scripts/verifier.ps1` (PowerShell 7, `owl`, `bash` et `curl` dans le PATH) tourne sous Linux : compilation, contrôles statiques, 76 suites unitaires, les groupes `base`, `projet` et `make` du lanceur (`tests/integration/lanceur.ps1`, avec le vrai `bin/ebony` et un vrai `owl serve`), le parcours de `tests/integration/linux.sh` et les noms de projet. Vérifié avec Ubuntu sous WSL 2, PowerShell 7.7.0 et OWL 1.8.1. **Quatre étapes sont ignorées, et le disent** : le groupe `installe` (install, uninstall, PATH par le registre), l'archive, le PATH et la suppression, PostgreSQL (script non porté, voir ci-dessous). Sans `libicu`, PowerShell demande `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` ; la comparaison de la table des accents est alors ignorée (« IGNORE » dans `noms-projet.ps1`) plutôt que comptée comme réussie.

Pièges rencontrés en portant `lanceur.ps1` (PowerShell 7) : `ConvertFrom-Json` transforme une date ISO (`"appliedAt":"2026-…Z"`) en objet `DateTime`, donc un test qui la compare à un motif doit lire le texte brut ; `Start-Process` n'a pas `-WindowStyle` ; `Get-CimInstance` n'existe pas (on lit `/proc/<pid>/cmdline`) ; `curl.exe` est `curl` ; un chemin relatif écrit avec `\` n'est pas un chemin sous Linux.

## Ce qui diffère de Windows

- **Pas d'`ebony install` ni d'`ebony uninstall`** : ils modifient le PATH par le registre de Windows (`bin/ebony-path.ps1`). Sous Linux ils répondent par un refus net (code 2), sans rien faire.
- **Une commande est plus lente depuis un clone** : les mini-projets par commande (`.commandes/`) sont écrits par `scripts/construit-entrees.ps1` (PowerShell) et ne sont dans l'archive de distribution que si elle a été construite sous Windows. Sans eux, chaque commande recompile ebony entier (`owl --check projet.owl` : 40 s sur la machine de mesure ; une commande n'a pas été chronométrée).
- **Les chemins** : ebony écrit ses chemins avec `\` en interne (la forme de Windows). Un chemin Linux (`/root/essai`) garde son style `/` dans tous les messages ; les appels au système passent par `EbCheminDuSysteme` (`fSep()`). Sous Linux, deux chemins qui ne diffèrent que par la casse sont deux dossiers.
- **Affichage** : quelques noms relatifs écrits en dur avec `\` (« modules\core\execution » dans le message du `doctor`, par exemple) s'affichent tels quels sous Linux ; les chemins absolus sont en `/`. C'est cosmétique : tout appel au système est converti (`fSep()`). `fSep()` n'est utilisé qu'à cette frontière : les fonctions de `EbChemin` restent pures (même résultat sur tout système), ce que les tests à faux disque, écrits avec `D:\...`, supposent.
- **Le lanceur** `bin/ebony` est un script `sh` : mêmes options passées à `ebony.owl` que `bin/ebony.cmd` (`-racine=`, `-cwd=`, `-owl=`, `-sortie=`…), même code de sortie. `-programmes=` reste vide (il ne sert qu'à `install`).

## Ce qui n'est pas vérifié

- D'autres distributions, d'autres versions d'OWL.
- PostgreSQL sous Linux (le test PostgreSQL est un script PowerShell qui lance Docker) ; le niveau TLS `verifie` avec une autorité publique.
- PostgreSQL sous Linux : `tests/integration/postgresql.ps1` est écrit pour Windows (`Start-Process -WindowStyle`, `curl.exe`) et l'Ubuntu de mesure n'a pas Docker ; le porter sans pouvoir l'exécuter ne prouverait rien, il reste donc ignoré, et dit.
- Un chemin de projet avec des accents ou des espaces sous Linux.
