# Installer ebony

Prérequis : [OWL](https://github.com/followthewhiteowl/neowl) **1.8.1** (`owl` dans le PATH ; les installateurs ne l'installent pas) ; Windows ou Linux (Ubuntu sous WSL 2). Windows : PowerShell 5.1, fourni avec le système. Linux : `sh`, `tar`, `curl` ou `wget`.

## En une commande

**Windows** (PowerShell, pas besoin d'être administrateur) :

```powershell
irm https://github.com/ebonyframework/ebony/releases/latest/download/install.ps1 | iex
```

**Linux** :

```sh
curl -fsSL https://github.com/ebonyframework/ebony/releases/latest/download/install.sh | sh
```

Puis, dans un **nouveau terminal** (le PATH n'est lu qu'au démarrage d'un terminal) : `ebony doctor`.

Ce que fait l'installateur, dans l'ordre :

1. Il vérifie que `owl` est dans le PATH. Sinon il s'arrête, dit où l'installer, et n'a rien installé.
2. Il télécharge l'archive de la dernière release (`ebony.zip` ou `ebony.tar.gz`) **dans un dossier temporaire qu'il crée**, et vérifie sa somme SHA-256 (fichier `.sha256` voisin). Une somme fausse, un fichier absent ou illisible : il s'arrête, rien n'est installé.
3. Il installe : sous Windows, `ebony install` (copie dans `%LOCALAPPDATA%\Programs\ebony\<version>\`, dossier `bin` ajouté au PATH **de l'utilisateur**) ; sous Linux, une copie dans `~/.local/share/ebony/<version>/` et un lien `~/.local/bin/ebony`. Une version déjà installée n'est pas recopiée ; un fichier ou un lien existant qui n'est pas le sien n'est jamais remplacé (il est signalé).
4. Il supprime son dossier temporaire : **le seul dossier qu'il supprime**.

Sous Linux, le script ne modifie ni votre PATH ni vos fichiers de profil : si `~/.local/bin` n'y est pas, il vous donne la ligne à ajouter. Aucun droit root n'est utile.

**À savoir** : la somme SHA-256 protège d'un téléchargement corrompu, pas d'une release compromise. Lisez le script avant de l'exécuter si vous voulez (`install/install.ps1` et `install/install.sh` dans le dépôt : ils font une centaine de lignes) :

```powershell
irm https://github.com/ebonyframework/ebony/releases/latest/download/install.ps1 -OutFile install.ps1   # lisez-le, puis : powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Variables facultatives : `EBONY_URL_BASE` (une adresse `https://…` ou un dossier local qui contient `ebony.zip` ou `ebony.tar.gz` et leur `.sha256` : un miroir, ou un essai hors ligne) ; sous Linux aussi `EBONY_HOME` (défaut `~/.local/share/ebony`) et `EBONY_BIN` (défaut `~/.local/bin`). Pour retirer ebony sous Linux : `rm -rf ~/.local/share/ebony ~/.local/bin/ebony`.

**Profil Windows avec un accent** (`C:\Users\Hélène`) : `owl` 1.8.1 n'ouvre pas son propre fichier passé en chemin absolu accentué (corrigé côté OWL, pas encore dans la 1.8.1). L'installateur travaille dans un dossier temporaire sans accent ni espace (le nom court 8.3 du dossier temporaire, sinon `C:\ProgramData`), mais `ebony install` copie dans `%LOCALAPPDATA%`, donc sous le profil : il le dit si cela échoue.

## Windows, à la main

### Depuis l'archive (sans git)

Téléchargez `ebony.zip` et `ebony.zip.sha256` depuis les [releases](https://github.com/ebonyframework/ebony/releases), vérifiez la somme, extrayez, installez :

```powershell
(Get-FileHash .\ebony.zip -Algorithm SHA256).Hash.ToLower()      # doit être la somme du fichier .sha256
Expand-Archive .\ebony.zip C:\sources
C:\sources\ebony-0.1.0\bin\ebony.cmd install
```

### Depuis un clone (pour contribuer)

```powershell
git clone https://github.com/ebonyframework/ebony C:\sources\ebony
C:\sources\ebony\bin\ebony.cmd install
```

Ouvrez ensuite un **nouveau terminal** (le PATH n'est lu qu'au démarrage d'un terminal) et vérifiez :

```powershell
ebony doctor
```

### Ce que font `install` et `uninstall`

- `ebony install` copie le strict nécessaire dans `%LOCALAPPDATA%\Programs\ebony\<version>\` (un dossier par version) et ajoute le dossier `bin` de cette version au PATH **de l'utilisateur** (aucun droit d'administrateur, jamais le PATH de la machine). Les entrées des autres versions d'ebony sont retirées du PATH, leurs fichiers restent.
- Le relancer est sans danger : une version déjà installée n'est pas recopiée. Pour mettre à jour : `git pull` dans le clone, puis `ebony install` ; si la version a changé, la nouvelle s'installe à côté de l'ancienne.
- `ebony install` ne supprime jamais rien : pour retirer une ancienne version seule, supprimez son dossier à la main.
- **`ebony uninstall`** retire ebony de votre PATH **et supprime les versions installées** (c'est la seule commande d'ebony qui supprime des fichiers). Elle est bornée : elle ne supprime que les dossiers de version qui portent le fichier `INSTALLE` laissé par `ebony install`, sous un dossier nommé `ebony` ; un autre dossier, un fichier ou un lien qui s'y trouverait est laissé, et dit. Elle peut être lancée depuis la copie installée elle-même ; fermez les terminaux ouverts dans le dossier d'ebony avant. Vos projets ne sont jamais touchés.
- **N'ouvrez pas un terminal en administrateur** : `ebony install` n'en a pas besoin. Un clone ou une installation faits en administrateur appartiennent au groupe Administrateurs, et git refuse ensuite de les ouvrir depuis un terminal normal (« dubious ownership »).
- La copie installée est autonome : le clone ou l'archive extraite peuvent être supprimés. Si le nom de votre dossier utilisateur contient un accent, `owl` ne peut pas ouvrir un chemin absolu qui en contient : `ebony install` le dit.

## Linux

Le plus simple : [la commande unique](#en-une-commande) (`install.sh`). Le parcours des [premiers pas](premiers-pas.md) fonctionne avec le lanceur `bin/ebony`, sous Ubuntu (WSL 2) avec OWL 1.8.1 (archive `neowl-1.8.1-linux-x86_64.tar.gz`) et SQLite. À la main :

1. Installez OWL (l'archive Linux de la release d'OWL, `owl` dans le PATH) et `curl`.
2. Récupérez ebony : le dépôt cloné, ou `ebony.tar.gz` et `ebony.tar.gz.sha256` des [releases](https://github.com/ebonyframework/ebony/releases) (vérifiez la somme avec `sha256sum -c`, extrayez avec `tar -xzf`). Si le bit d'exécution manque : `chmod +x bin/ebony`.
3. Mettez-le dans le PATH : un lien suffit, `ln -s /chemin/vers/ebony/bin/ebony ~/.local/bin/ebony` (le lanceur suit les liens).
4. Vérifiez : `ebony --version`, puis `ebony doctor` dans un dossier de travail.

Ce qui diffère de Windows :

- **Pas d'`ebony install` ni d'`ebony uninstall`** : ils modifient le PATH par le registre de Windows. Sous Linux ils répondent par un refus net (code 2), sans rien faire.
- **Une commande est plus lente depuis un clone** : les mini-projets par commande (`.commandes/`) sont écrits par un script PowerShell et ne sont dans l'archive que si elle a été construite sous Windows.
- **Les chemins** : ebony écrit ses chemins avec `\` en interne mais garde le style `/` d'un chemin Linux. Deux chemins qui ne diffèrent que par la casse sont deux dossiers.

Non essayé : d'autres distributions, PostgreSQL sous Linux, `owl test` d'un projet généré sous Linux, un chemin de projet avec accents ou espaces.

## Dans un projet cloné avec git

Le dossier `ebony/` (la bibliothèque d'exécution) est ignoré par git, comme `node_modules` : après un `git clone` de votre projet, lancez `ebony restore` pour le restaurer d'après la version **minimale** notée dans `ebony.conf`. `ebony upgrade` aligne ensuite le projet sur l'ebony installé. Aucun des deux ne supprime ni ne rétrograde rien.
