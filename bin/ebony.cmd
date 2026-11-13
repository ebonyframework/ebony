@echo off
rem Lanceur de la commande ebony (Windows).
rem OWL ne donne pas le dossier d'un script : ce lanceur calcule le sien et le passe a ebony.owl (-racine=).
setlocal

rem %~dps0 = dossier du lanceur en nom COURT 8.3 (sans accent : owl n'ouvre pas les chemins accentues), avec barre finale.
set "BIN=%~dps0"
rem On retire "\bin\" (5 caracteres) : une barre finale suivie du guillemet avalerait l'argument suivant.
set "RACINE=%BIN:~0,-5%"
rem Le meme dossier sous son nom LONG, pour les messages seulement (le nom court 8.3 ci-dessus est illisible : 0170E4~1.0 pour 0.1.0). owl ouvre les fichiers avec RACINE, jamais avec celui-ci.
set "RACINE_AFFICHEE=%~dp0"
set "RACINE_AFFICHEE=%RACINE_AFFICHEE:~0,-5%"

rem "ebony --version" (ou -V) : une ligne "ebony X.Y.Z" lue dans modules\core\execution\VERSION, sans lancer owl.
if /i "%~1"=="--version" goto :version
if /i "%~1"=="-V" goto :version

set "VERSION_OWL="
for /f "tokens=2" %%v in ('owl --version') do set "VERSION_OWL=%%v"

rem owl se place dans la racine du projet quand le script est dans un projet : on transmet donc le dossier de lancement (-cwd=).
rem Une racine de disque (D:\) se termine par une barre qui avalerait le guillemet : on la transmet avec "/" (D:/).
set "LANCEMENT=%CD%"
if "%LANCEMENT:~-1%"=="\" set "LANCEMENT=%LANCEMENT:~0,-1%/"

rem Dossier des programmes de l'utilisateur, ou "ebony install" installe ebony. EBONY_PROGRAMMES le redirige (utilise par les tests).
rem OWL n'ouvre pas un chemin accentue : on transmet sa forme courte 8.3 (vide si le dossier n'existe pas).
if not defined EBONY_PROGRAMMES set "EBONY_PROGRAMMES=%LOCALAPPDATA%\Programs"
set "PROGRAMMES_COURT="
if exist "%EBONY_PROGRAMMES%\" for %%I in ("%EBONY_PROGRAMMES%") do set "PROGRAMMES_COURT=%%~sI"

rem OWL ne sait pas donner de code de sortie : toute erreur serait le code 70 avec une pile d'appels. ebony.owl ecrit donc le code voulu (1 = echec, 2 = usage incorrect) dans ce fichier
rem (-sortie=) et on le relit apres owl. Le dossier temporaire est transmis en nom COURT 8.3 : owl n'ouvre pas un chemin accentue.
for %%I in ("%TEMP%") do set "TEMP_COURT=%%~sI"
set "SORTIE_FICHIER=%TEMP_COURT%\ebony-sortie-%RANDOM%%RANDOM%.txt"
if exist "%SORTIE_FICHIER%" del "%SORTIE_FICHIER%" 2>nul

rem Un mini-projet par commande (scripts\construit-entrees.ps1) : OWL analyse tout le projet a chaque lancement (20 a 25 s pour ebony entier, 1 a 7 s pour une commande seule).
rem Il est utilise s'il existe (archive, ou depot apres scripts\verifier.ps1). Sinon, ou pour une commande qui n'en a pas (aide, commande inconnue), le point d'entree complet.
rem Le nom du dossier vient de CETTE liste, jamais du texte tape : pas de chemin forge.
set "ENTREE=%RACINE%\ebony.owl"
for %%C in (doctor new init add make migrate token env request restore upgrade install uninstall) do if /i "%~1"=="%%C" if exist "%RACINE%\.commandes\%%C\ebony.owl" set "ENTREE=%RACINE%\.commandes\%%C\ebony.owl"
owl "%ENTREE%" "-racine=%RACINE%" "-affiche=%RACINE_AFFICHEE%" "-owl=%VERSION_OWL%" "-cwd=%LANCEMENT%" "-programmes=%PROGRAMMES_COURT%" "-sortie=%SORTIE_FICHIER%" %*
set "CODE_OWL=%ERRORLEVEL%"
if exist "%SORTIE_FICHIER%" call :lit_code_sortie
if not "%CODE_OWL%"=="0" exit /b %CODE_OWL%

rem Apres une installation reussie, OWL ne pouvant pas modifier l'environnement, le lanceur ajoute le dossier bin de cette version au PATH de l'utilisateur.
if /i "%~1"=="install" call :ajoute_au_path
if /i "%~1"=="uninstall" goto :desinstalle
exit /b %ERRORLEVEL%

:version
set "VERSION_EBONY="
set /p VERSION_EBONY=<"%RACINE%\modules\core\execution\VERSION"
if not defined VERSION_EBONY (
    echo ebony : version introuvable dans "%RACINE%\modules\core\execution\VERSION".
    exit /b 1
)
echo ebony %VERSION_EBONY%
exit /b 0

:lit_code_sortie
rem Le code ecrit par ebony.owl l'emporte sur celui d'owl ; le fichier est supprime dans tous les cas.
set "CODE_FICHIER="
set /p CODE_FICHIER=<"%SORTIE_FICHIER%"
del "%SORTIE_FICHIER%" 2>nul
if defined CODE_FICHIER set "CODE_OWL=%CODE_FICHIER%"
exit /b 0

:ajoute_au_path
set "VERSION_EBONY="
set /p VERSION_EBONY=<"%RACINE%\modules\core\execution\VERSION"
if not defined VERSION_EBONY (
    echo ebony : version introuvable dans "%RACINE%\modules\core\execution\VERSION", le PATH n'a pas ete modifie.
    exit /b 1
)
rem EBONY_PATH_VAR : variable modifiee (Path par defaut). Les tests la redirigent pour ne jamais toucher au vrai PATH.
if not defined EBONY_PATH_VAR set "EBONY_PATH_VAR=Path"
powershell -NoProfile -ExecutionPolicy Bypass -File "%BIN%ebony-path.ps1" -Dossier "%EBONY_PROGRAMMES%\ebony\%VERSION_EBONY%\bin" -Base "%EBONY_PROGRAMMES%\ebony" -NomVariable "%EBONY_PATH_VAR%"
exit /b %ERRORLEVEL%

:desinstalle
rem "ebony uninstall" : owl a verifie et annonce ; le lanceur retire ebony du PATH, puis supprime les versions installees (ebony-supprime.ps1, bornee aux dossiers qui contiennent le marqueur INSTALLE).
if not defined EBONY_PATH_VAR set "EBONY_PATH_VAR=Path"
powershell -NoProfile -ExecutionPolicy Bypass -File "%BIN%ebony-path.ps1" -Retire -Base "%EBONY_PROGRAMMES%\ebony" -NomVariable "%EBONY_PATH_VAR%"
if errorlevel 1 exit /b %ERRORLEVEL%
rem DERNIERE ligne : ce lanceur est dans le dossier qui va etre supprime, cmd ne doit plus rien lire apres. "(goto) 2>nul &" termine le contexte du fichier avant de lancer la suppression
rem (sinon cmd affiche "chemin introuvable" et renvoie un mauvais code : mesure). Le code de retour est celui de la suppression.
(goto) 2>nul & powershell -NoProfile -ExecutionPolicy Bypass -File "%BIN%ebony-supprime.ps1" -Base "%EBONY_PROGRAMMES%\ebony"
