# Verifie tout le depot : compilation, tests unitaires, tests d'integration du lanceur et de l'ajout au PATH.
# Les tests unitaires sont ceux de scripts\test-rapide.ps1 (chaque suite isolee avec ses seules dependances, plus un controle statique des globales de fichiers de test) :
# memes totaux qu'"owl test" (50 suites, 1937 assertions, 474 scenarios, au moment de la mesure) en 1 minute au lieu de 23 a 42 (owl test recompile tout pour chaque suite).
# Les trois premiers sont necessaires : owl --check et les tests unitaires acceptent des erreurs que le lancement reel refuse
# (ex. une methode qui implemente une interface avec PROCEDURE PUBLIC). Seul le test d'integration les voit.
# Windows PowerShell 5.1 ou plus, ou PowerShell 7 sous Linux.   Usage :   .\scripts\verifier.ps1      (code de sortie 0 si tout passe, 1 sinon)
# Sous Linux (PowerShell 7, owl, bash et curl dans le PATH ; mettre DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 s'il manque libicu) les etapes propres a Windows sont ignorees EXPLICITEMENT (groupe installe, registre, archive, PostgreSQL)
# et le parcours de tests\integration\linux.sh les remplace : voir la section Linux du README.
# Ce fichier reste ASCII.

$racine = Split-Path $PSScriptRoot -Parent
Set-Location $racine
$echecs = 0
$estWindows = [IO.Path]::DirectorySeparatorChar -eq '\'
# Le PowerShell qui execute ce script (powershell.exe sous Windows, pwsh sous Linux) : jamais le mot powershell en dur.
$programmePowerShell = (Get-Process -Id $PID).Path

# Une etape propre a Windows, sautee sous Linux : dite a l'ecran, jamais passee sous silence.
function EtapeIgnoree([string]$Nom, [string]$Raison) {
    Write-Host ("== " + $Nom)
    Write-Host ("   IGNORE : " + $Raison) -ForegroundColor Yellow
}

function Etape([string]$Nom, [scriptblock]$Commande) {
    Write-Host ("== " + $Nom)
    $sortie = & $Commande 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) {
        $script:echecs++
        Write-Host "   ECHEC" -ForegroundColor Red
        $sortie | Select-Object -First 12 | ForEach-Object { Write-Host ("   " + $_) }
    }
    else { Write-Host "   OK" -ForegroundColor Green }
}

# Encapsulation. Le controle de visibilite d'owl ne voit pas tous les acces (variable de boucle POUR TOUT, resultat d'un appel,
# code des Collections et du bloc de projet.owl). On le complete
# par la convention de nommage : un champ a un prefixe de type (nStatut, sMessage, oSysteme, tabItems), une methode est en PascalCase
# (Statut()). Donc "quelquechose.nStatut" sans parenthese est un acces direct a un champ. Les valeurs d'enumeration (eEbStatut.erreur)
# sont en minuscules apres le point et ne sont pas concernees. ATTENTION : -match est insensible a la casse en PowerShell,
# il faut -cmatch, sinon [A-Z] accepte aussi les minuscules.
$motifChamp = '(?:(?<![.\w"])[A-Za-z_]\w*|[\)\]])\.(?:tab|[snbroe])[A-Z]\w*\b(?!\()'
Etape "encapsulation : aucun acces direct a un champ" {
    $fichiers = @(Get-ChildItem (Join-Path $racine 'src'), (Join-Path $racine 'tests') -Recurse -Filter '*.owl')
    $fichiers += @(Get-ChildItem (Join-Path $racine 'modules') -Recurse -Filter '*.owl' | Where-Object { $_.FullName.Replace('\', '/') -like '*/outils/*' })
    $fichiers += Get-Item (Join-Path $racine 'ebony.owl'), (Join-Path $racine 'projet.owl')
    $trouves = foreach ($f in $fichiers) {
        $n = 0
        foreach ($ligne in (Get-Content $f.FullName -Encoding UTF8)) {
            $n++
            $code = ($ligne -replace '//.*$', '') -replace '"[^"]*"', '""'
            if ($code -cmatch $motifChamp) { "{0}:{1}  {2}" -f $f.FullName.Replace($racine + '\', ''), $n, $ligne.Trim() }
        }
    }
    if ($trouves) { $trouves | ForEach-Object { Write-Output $_ }; $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
}

Etape "owl --check projet.owl" { owl --check projet.owl }
# Points d'entree reduits par commande (.commandes, ignore par git) : le lanceur les utilise s'ils existent, donc les tests d'integration appellent ebony en 1 a 7 s au lieu de 25.
# Regeneres A CHAQUE verification : un dossier perime fausserait le test. Regenere aussi par scripts\construit-archive.ps1 pour l'archive.
Etape "points d'entree reduits par commande (scripts\construit-entrees.ps1)" { & $programmePowerShell -NoProfile -File (Join-Path $racine 'scripts\construit-entrees.ps1') }
# La liste des commandes vient de l'aiguillage (EbAiguillage.owl) ; celle de bin\ebony.cmd est la seule ecrite a la main : elle doit etre d'accord (sinon une commande retomberait sans bruit sur le repli a 25 s).
Etape "commandes : aiguillage, lanceur et points d'entree d'accord (scripts\controle-commandes.ps1)" { & $programmePowerShell -NoProfile -File (Join-Path $racine 'scripts\controle-commandes.ps1') }
# Frontieres du coeur et des modules : le coeur n'appelle ni le SQL (hors cEbApplication) ni auth, la bibliotheque ne depend pas de src\. Sans owl ; le test injecte de vraies fuites dans une copie et verifie qu'elles sont vues.
Etape "frontieres du coeur et des modules (scripts\controle-frontieres.ps1 et tests\integration\frontieres.ps1)" {
    & $programmePowerShell -NoProfile -File (Join-Path $racine 'scripts\controle-frontieres.ps1')
    if ($LASTEXITCODE -eq 0) { & $programmePowerShell -NoProfile -File (Join-Path $racine 'tests\integration\frontieres.ps1') }
}
# Les etapes longues (tests unitaires rapides, tests d'integration du lanceur) sont faites de lancements d'owl (les integrations recompilent tout le projet, 20 a 25 s chacun) et ne dependent pas l'une de l'autre :
# on les lance EN PARALLELE (tests unitaires + les quatre groupes du lanceur + l'archive). Mesure avec OWL 1.6.0 : trois compilations simultanees coutent ~1,6 fois une seule, pas trois fois (PC a 2 coeurs, 4 threads).
# Chaque tache ecrit dans un fichier ; on affiche les resultats a la fin, dans l'ordre. Les etapes qui touchent le registre (chemin-path) ou sont breves restent sequentielles APRES :
# chemin-path et le groupe 'installe' utilisent la meme variable de PATH de test et ne doivent jamais tourner ensemble.
function EtapesEnParallele([object[]]$Taches) {
    $dossierSortie = Join-Path ([IO.Path]::GetTempPath()) ('ebony_verifier_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dossierSortie | Out-Null
    $lancees = @()
    foreach ($tache in $Taches) {
        $sortieFichier = Join-Path $dossierSortie ($lancees.Count.ToString() + '.out')
        $erreurFichier = Join-Path $dossierSortie ($lancees.Count.ToString() + '.err')
        $debut = Get-Date
        $parametresProcessus = @{ FilePath = $tache.Programme; ArgumentList = $tache.Arguments; WorkingDirectory = $racine; PassThru = $true; RedirectStandardOutput = $sortieFichier; RedirectStandardError = $erreurFichier }
        if ($estWindows) { $parametresProcessus.WindowStyle = 'Hidden' }
        $processus = Start-Process @parametresProcessus
        $null = $processus.Handle   # garde le handle : sans cela, ExitCode peut rester vide apres la fin du processus
        $lancees += [pscustomobject]@{ Nom = $tache.Nom; Processus = $processus; Sortie = $sortieFichier; Erreur = $erreurFichier; Debut = $debut }
    }
    foreach ($tache in $lancees) { $tache.Processus.WaitForExit() }
    foreach ($tache in $lancees) {
        Write-Host ("== " + $tache.Nom)
        $texte = @(Get-Content -LiteralPath $tache.Sortie -Encoding UTF8 -ErrorAction SilentlyContinue) + @(Get-Content -LiteralPath $tache.Erreur -Encoding UTF8 -ErrorAction SilentlyContinue)
        if ($tache.Processus.ExitCode -ne 0) {
            $script:echecs++
            Write-Host "   ECHEC" -ForegroundColor Red
            # Les lignes en echec d'abord (avec leur detail), sinon le debut de la sortie.
            $lignesEchec = @()
            for ($i = 0; $i -lt $texte.Count; $i++) {
                if ("$($texte[$i])" -match 'ECHEC|FAIL|Erreur') { $lignesEchec += "$($texte[$i])"; if ($i + 1 -lt $texte.Count) { $lignesEchec += "$($texte[$i + 1])" } }
            }
            if ($lignesEchec.Count -eq 0) { $lignesEchec = @($texte | ForEach-Object { "$_" }) }
            $lignesEchec | Select-Object -First 24 | ForEach-Object { Write-Host ("   " + $_) }
        }
        else { Write-Host "   OK" -ForegroundColor Green }
    }
    Remove-Item -LiteralPath $dossierSortie -Recurse -Force -ErrorAction SilentlyContinue
}
$lanceurScript = Join-Path $racine 'tests\integration\lanceur.ps1'
$tachesParalleles = @(
    @{ Nom = 'tests unitaires (scripts\test-rapide.ps1 : suites isolees + controle des globales de test)'; Programme = $programmePowerShell; Arguments = @('-NoProfile', '-File', (Join-Path $racine 'scripts\test-rapide.ps1')) }
)
if ($estWindows) {
    $tachesParalleles += @(
        @{ Nom = "test d'integration du lanceur : groupe base"; Programme = $programmePowerShell; Arguments = @('-NoProfile', '-File', $lanceurScript, '-Groupe', 'base') },
        @{ Nom = "test d'integration du lanceur : groupe projet"; Programme = $programmePowerShell; Arguments = @('-NoProfile', '-File', $lanceurScript, '-Groupe', 'projet') },
        @{ Nom = "test d'integration du lanceur : groupe make"; Programme = $programmePowerShell; Arguments = @('-NoProfile', '-File', $lanceurScript, '-Groupe', 'make') },
        @{ Nom = "test d'integration du lanceur : groupe installe"; Programme = $programmePowerShell; Arguments = @('-NoProfile', '-File', $lanceurScript, '-Groupe', 'installe') },
        # PostgreSQL REEL (Docker) : migrate, depot SQL genere, service, niveaux TLS. Deux conteneurs jetables, ports libres ; IGNORE (code 0) si Docker ne repond pas ou si l'image postgres:16 n'est pas deja telechargee.
        @{ Nom = "PostgreSQL reel (Docker, tests\integration\postgresql.ps1) : migrate, depot SQL, service, TLS"; Programme = $programmePowerShell; Arguments = @('-NoProfile', '-File', (Join-Path $racine 'tests\integration\postgresql.ps1')) },
        # L'archive de distribution est faite a partir du commit HEAD (git archive), PAS du dossier de travail : commiter avant de lancer cette etape pour qu'elle voie ce qu'on veut livrer.
        # Elle utilise sa propre variable de PATH de test (EBONY_TEST_PATH_ARCHIVE), donc elle peut tourner en meme temps que le groupe 'installe'.
        @{ Nom = "archive de distribution : somme, installation sans git, reinstallation, ebony new, desinstallation"; Programme = $programmePowerShell; Arguments = @('-NoProfile', '-File', (Join-Path $racine 'tests\integration\archive.ps1')) },
        # Les installateurs (install\install.ps1 sous Windows ; install\install.sh rejoue sous WSL quand WSL et un owl Linux sont la, sinon IGNORE dit dans la sortie) contre l'archive du commit HEAD (noms fixes). PATH de test propre : EBONY_TEST_PATH_INSTALLATEUR.
        @{ Nom = "installateurs (install.ps1, install.sh) : une ligne, somme, reinstallation, HTTP, refus"; Programme = $programmePowerShell; Arguments = @('-NoProfile', '-File', (Join-Path $racine 'tests\integration\installateur.ps1')) }
    )
}
else {
    # Sous Linux : les groupes base, projet et make du lanceur (bin/ebony, un vrai owl, un vrai owl serve), puis le parcours de linux.sh, en parallele des tests unitaires.
    # Le groupe installe (install, uninstall, PATH) est propre a Windows.
    $tachesParalleles += @(
        @{ Nom = "test d'integration du lanceur : groupe base"; Programme = $programmePowerShell; Arguments = @('-NoProfile', '-File', $lanceurScript, '-Groupe', 'base') },
        @{ Nom = "test d'integration du lanceur : groupe projet"; Programme = $programmePowerShell; Arguments = @('-NoProfile', '-File', $lanceurScript, '-Groupe', 'projet') },
        @{ Nom = "test d'integration du lanceur : groupe make"; Programme = $programmePowerShell; Arguments = @('-NoProfile', '-File', $lanceurScript, '-Groupe', 'make') },
        @{ Nom = "parcours sous Linux avec bin/ebony (tests/integration/linux.sh)"; Programme = 'bash'; Arguments = @((Join-Path $racine 'tests/integration/linux.sh')) }
    )
}
EtapesEnParallele $tachesParalleles
if ($estWindows) {
    # L'ajout d'ebony au PATH, contre le vrai registre mais sur une variable de TEST (EBONY_TEST_PATH) : le vrai PATH n'est jamais modifie, le test le verifie.
    Etape "ajout au PATH (bin\ebony-path.ps1), sur une variable de test" { & $programmePowerShell -NoProfile -File (Join-Path $racine 'tests\integration\chemin-path.ps1') }
    # La suppression des versions installees (ebony uninstall) est destructrice : ce test verifie surtout ce qu'elle ne doit PAS supprimer (dossier etranger, jonction, mauvais nom, racine de disque).
    Etape "suppression (bin\ebony-supprime.ps1), bornee aux dossiers d'ebony" { & $programmePowerShell -NoProfile -File (Join-Path $racine 'tests\integration\suppression.ps1') }
}
else {
    $raisonWindows = "propre a Windows (lanceur .cmd, registre, PowerShell 5.1) ; couvert sous Linux par tests/integration/linux.sh"
    EtapeIgnoree "test d'integration du lanceur : groupe installe (install, uninstall, PATH)" $raisonWindows
    EtapeIgnoree "PostgreSQL reel (Docker, tests\integration\postgresql.ps1)" "pas encore portable sous Linux (voir la section Linux du README)"
    EtapeIgnoree "archive de distribution (tests\integration\archive.ps1)" $raisonWindows
    EtapeIgnoree "installateurs (tests\integration\installateur.ps1)" "l'archive est construite sous Windows (construit-archive.ps1) ; install.sh se rejoue avec : sh tests/integration/installateur.sh <dossier de l'archive>"
    EtapeIgnoree "ajout au PATH et suppression (bin\ebony-path.ps1, bin\ebony-supprime.ps1)" $raisonWindows
}
# Du nom libre au projet qui compile (dossier et identifiant calcules par nos fonctions OWL, puis vrai dossier et vrai projet compiles par owl) : 6 s.
# Le mode -Complet (2 minutes, ~1 000 noms) est a lancer apres chaque mise a jour d'owl : .\tests\integration\noms-projet.ps1 -Complet
Etape "noms de projet : du nom libre au projet compile, contre le vrai owl" { & $programmePowerShell -NoProfile -File (Join-Path $racine 'tests\integration\noms-projet.ps1') }

Write-Host ""
if ($echecs -eq 0) { Write-Host "TOUT PASSE" -ForegroundColor Green; exit 0 }
else { Write-Host ("$echecs ETAPE(S) EN ECHEC") -ForegroundColor Red; exit 1 }
