# Test d'integration de l'installateur Windows (install\install.ps1), contre une archive construite a partir du commit HEAD.
#   .\tests\integration\installateur.ps1                       fabrique l'archive (noms fixes) dans un dossier temporaire, puis teste
#   .\tests\integration\installateur.ps1 -Archives C:\x         utilise un dossier qui contient deja ebony.zip, ebony.zip.sha256, ebony.tar.gz et ebony.tar.gz.sha256
# Ce qui est verifie : l'installation depuis un dossier local ; la reinstallation ; un telechargement HTTP reel avec une redirection (comme GitHub) ; une somme fausse ; un fichier absent ;
# un PATH sans owl ; le lancement par "irm | iex" (le terminal ne se ferme pas) ; un dossier temporaire accentue (repli) ; aucun dossier temporaire residuel.
# Si WSL et un owl Linux sont disponibles, installateur.sh est rejoue sur le .tar.gz (sinon : IGNORE, dit).
# Le dossier des programmes est redirige (EBONY_PROGRAMMES) et le PATH vise une variable de TEST (EBONY_PATH_VAR) : le VRAI PATH n'est jamais modifie (verifie a la fin).
# Code de sortie 0 si tout passe, 1 sinon. Ce fichier reste ASCII. ATTENTION : les noms de variables PowerShell ne distinguent pas la casse.

param([string]$Archives = '')

$ErrorActionPreference = 'Stop'
$depot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$installateur = Join-Path $depot 'install\install.ps1'
$nomVariableTest = 'EBONY_TEST_PATH_INSTALLATEUR'
$programmePowerShell = (Get-Process -Id $PID).Path

$echecs = 0
function Verifie([string]$Titre, [bool]$Condition, [string]$Detail) {
    if ($Condition) { Write-Host ("  [OK]     " + $Titre) }
    else { Write-Host ("  [ECHEC]  " + $Titre) -ForegroundColor Red; if ($Detail) { Write-Host ("           " + $Detail) }; $script:echecs++ }
}
function Nettoie([string]$Chemin) {
    if (-not (Test-Path -LiteralPath $Chemin)) { return }
    try { Remove-Item -Recurse -Force -LiteralPath $Chemin -ErrorAction Stop }
    catch { Start-Sleep -Seconds 2; try { Remove-Item -Recurse -Force -LiteralPath $Chemin -ErrorAction Stop } catch { Write-Host ("  [ECHEC]  nettoyage impossible de " + $Chemin) -ForegroundColor Red; $script:echecs++ } }
}
function EmpreinteDossier([string]$Dossier) {
    $racine = (Resolve-Path -LiteralPath $Dossier).Path.TrimEnd('\')
    $lignes = Get-ChildItem -LiteralPath $racine -Recurse -File -Force | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($racine.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes(($lignes -join "`n")))) -replace '-', '')
}

# Lance install.ps1 dans un PowerShell a part, avec des variables d'environnement ajoutees pour CE processus seulement. $Commande : le texte a executer (par defaut : -File install.ps1).
function LanceInstallateur([hashtable]$Environnement, [string[]]$Arguments) {
    $infos = New-Object Diagnostics.ProcessStartInfo
    $infos.FileName = $programmePowerShell
    $infos.Arguments = ($Arguments -join ' ')
    $infos.WorkingDirectory = $espace
    $infos.UseShellExecute = $false
    foreach ($cle in $Environnement.Keys) { $infos.EnvironmentVariables[$cle] = [string]$Environnement[$cle] }
    $infos.RedirectStandardOutput = $true; $infos.RedirectStandardError = $true
    $infos.StandardOutputEncoding = [Text.Encoding]::UTF8; $infos.StandardErrorEncoding = [Text.Encoding]::UTF8
    $processus = [Diagnostics.Process]::Start($infos)
    $tacheSortie = $processus.StandardOutput.ReadToEndAsync(); $tacheErreur = $processus.StandardError.ReadToEndAsync()
    if (-not $processus.WaitForExit(240000)) { try { $processus.Kill() } catch { }; return @{ Code = -1; Sortie = 'delai depasse (240 s)' } }
    $processus.WaitForExit()
    return @{ Code = $processus.ExitCode; Sortie = ($tacheSortie.Result + $tacheErreur.Result) }
}
function ArgumentsFichier { return @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $installateur + '"')) }

$espace = Join-Path ([IO.Path]::GetTempPath()) ('ebony_installateur_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $espace | Out-Null
$cleUtilisateur = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
function LitPath([string]$Nom) { return $cleUtilisateur.GetValue($Nom, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
if ($null -ne (LitPath $nomVariableTest)) { Write-Host "La variable de test $nomVariableTest existe deja : arret, rien n'est modifie."; Nettoie $espace; exit 1 }
$vraiPathAvant = LitPath 'Path'
$ecouteur = $null

try {
    Verifie "install\install.ps1 existe" (Test-Path -LiteralPath $installateur) $installateur
    $octetsInstallateur = [IO.File]::ReadAllBytes($installateur)
    Verifie "install.ps1 est ASCII (Windows PowerShell 5.1 lit un fichier sans BOM selon la page de codes)" (@($octetsInstallateur | Where-Object { $_ -gt 127 }).Count -eq 0) ''
    Verifie "install.ps1 ne contient aucun « exit » hors de la garde finale (il fermerait le terminal sous iex)" (@(Select-String -LiteralPath $installateur -Pattern '^\s*[^#\s].*\bexit\b' | Where-Object { $_.Line -notmatch 'PSCommandPath' }).Count -eq 0) ''

    if ($Archives -eq '') {
        Write-Host "fabrication de l'archive du commit HEAD (noms fixes)"
        $Archives = Join-Path $espace 'archives'
        $null = & $programmePowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $depot 'scripts\construit-archive.ps1') -Ref HEAD -Sortie $Archives -NomsFixes 2>&1
        Verifie "construit-archive.ps1 -NomsFixes : code 0" ($LASTEXITCODE -eq 0) ''
    }
    foreach ($nomFichier in @('ebony.zip', 'ebony.zip.sha256', 'ebony.tar.gz', 'ebony.tar.gz.sha256')) { Verifie ("l'archive a " + $nomFichier) (Test-Path -LiteralPath (Join-Path $Archives $nomFichier)) $Archives }
    $version = [regex]::Match((Get-Content -LiteralPath (Join-Path $depot 'modules\core\execution\VERSION') -TotalCount 1), '\d+\.\d+\.\d+').Value
    Verifie "le .sha256 de ebony.zip porte le nom fixe" ((Get-Content -LiteralPath (Join-Path $Archives 'ebony.zip.sha256') -TotalCount 1) -match '^[0-9a-f]{64}  ebony\.zip$') ''

    # Un dossier TEMP propre a chaque essai : on y verifie qu'aucun dossier temporaire de l'installateur ne reste.
    function NouveauTemp([string]$Nom) { $d = Join-Path $espace $Nom; New-Item -ItemType Directory -Path $d | Out-Null; return $d }
    function Residus([string]$DossierTemp) { return @(Get-ChildItem -LiteralPath $DossierTemp -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'ebony-install-*' }) }
    function EnvironnementEssai([string]$DossierTemp, [string]$Programmes, [string]$Base) { return @{ TEMP = $DossierTemp; TMP = $DossierTemp; EBONY_URL_BASE = $Base; EBONY_PROGRAMMES = $Programmes; EBONY_PATH_VAR = $nomVariableTest } }

    Write-Host "installation depuis un dossier local (-File)"
    $temp1 = NouveauTemp 'temp1'; $programmes1 = NouveauTemp 'programmes1'
    $r = LanceInstallateur (EnvironnementEssai $temp1 $programmes1 $Archives) (ArgumentsFichier)
    Verifie "code 0" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)
    Verifie "somme verifiee, et il dit d'ouvrir un NOUVEAU terminal puis ebony doctor" (($r.Sortie -match 'somme SHA-256 verifiee') -and ($r.Sortie -match 'NOUVEAU terminal') -and ($r.Sortie -match 'ebony doctor')) $r.Sortie
    $dossierInstalle = Join-Path $programmes1 ('ebony\' + $version)
    Verifie "la version est installee, avec INSTALLE et les points d'entree reduits" ((Test-Path -LiteralPath (Join-Path $dossierInstalle 'INSTALLE')) -and (Test-Path -LiteralPath (Join-Path $dossierInstalle '.commandes\doctor\ebony.owl'))) $r.Sortie
    Verifie "le PATH de test contient le dossier bin installe" ((LitPath $nomVariableTest) -like ('*' + $dossierInstalle + '\bin*')) ((LitPath $nomVariableTest))
    Verifie "aucun dossier temporaire ne reste" ((Residus $temp1).Count -eq 0) ((Residus $temp1 | ForEach-Object { $_.Name }) -join ', ')
    $empreinte = EmpreinteDossier $dossierInstalle

    Write-Host "reinstallation : sans degat"
    $r = LanceInstallateur (EnvironnementEssai $temp1 $programmes1 $Archives) (ArgumentsFichier)
    Verifie "code 0" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)
    Verifie "aucun fichier de la version installee n'a change" ((EmpreinteDossier $dossierInstalle) -eq $empreinte) ''
    Verifie "pas de doublon dans le PATH de test" ((@((LitPath $nomVariableTest) -split ';' | Where-Object { $_ -like ('*ebony\' + $version + '\bin*') })).Count -eq 1) ((LitPath $nomVariableTest))

    Write-Host "l'ebony installe repond (doctor depuis la copie installee)"
    $lanceurInstalle = Join-Path $dossierInstalle 'bin\ebony.cmd'
    $infosDoctor = New-Object Diagnostics.ProcessStartInfo
    $infosDoctor.FileName = $env:ComSpec; $infosDoctor.Arguments = '/c ""' + $lanceurInstalle + '" doctor --json"'; $infosDoctor.WorkingDirectory = $espace
    $infosDoctor.UseShellExecute = $false; $infosDoctor.RedirectStandardOutput = $true; $infosDoctor.RedirectStandardError = $true
    $infosDoctor.StandardOutputEncoding = [Text.Encoding]::UTF8
    $processusDoctor = [Diagnostics.Process]::Start($infosDoctor); $sortieDoctor = $processusDoctor.StandardOutput.ReadToEnd(); $null = $processusDoctor.StandardError.ReadToEnd(); $processusDoctor.WaitForExit()
    $jsonDoctor = $null; try { $jsonDoctor = $sortieDoctor | ConvertFrom-Json } catch { }
    Verifie "doctor --json : code 0, version de l'archive, aucune erreur" (($processusDoctor.ExitCode -eq 0) -and $jsonDoctor -and ($jsonDoctor.ebony -ceq $version) -and ($jsonDoctor.errors -eq 0)) $sortieDoctor

    Write-Host "telechargement HTTP reel, avec une redirection (comme releases/latest/download sur GitHub)"
    $portHttp = $null
    try {
        $verifPort = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $verifPort.Start(); $portHttp = $verifPort.LocalEndpoint.Port; $verifPort.Stop()
        $ecouteur = New-Object Net.HttpListener
        $ecouteur.Prefixes.Add('http://127.0.0.1:' + $portHttp + '/')
        $ecouteur.Start()
    } catch { $ecouteur = $null }
    if ($null -eq $ecouteur) {
        Write-Host "  [IGNORE] un HttpListener n'a pas pu demarrer sans droits d'administrateur : le telechargement HTTP n'est pas rejoue ici"
    } else {
        $dossierServi = $Archives
        $espaceServeur = [RunspaceFactory]::CreateRunspace(); $espaceServeur.Open()
        $serveur = [PowerShell]::Create(); $serveur.Runspace = $espaceServeur
        $null = $serveur.AddScript({
            param($ecoute, $dossier)
            while ($ecoute.IsListening) {
                try { $contexte = $ecoute.GetContext() } catch { break }
                $chemin = $contexte.Request.Url.AbsolutePath
                if ($chemin.StartsWith('/release/')) { $contexte.Response.StatusCode = 302; $contexte.Response.RedirectLocation = '/fichiers/' + $chemin.Substring(9) }
                elseif ($chemin.StartsWith('/fichiers/') -and (Test-Path -LiteralPath (Join-Path $dossier $chemin.Substring(10)))) {
                    $octets = [IO.File]::ReadAllBytes((Join-Path $dossier $chemin.Substring(10)))
                    $contexte.Response.ContentLength64 = $octets.Length
                    $contexte.Response.OutputStream.Write($octets, 0, $octets.Length)
                } else { $contexte.Response.StatusCode = 404 }
                $contexte.Response.Close()
            }
        }).AddArgument($ecouteur).AddArgument($dossierServi)
        $attente = $serveur.BeginInvoke()
        try {
            $temp2 = NouveauTemp 'temp2'; $programmes2 = NouveauTemp 'programmes2'
            $r = LanceInstallateur (EnvironnementEssai $temp2 $programmes2 ('http://127.0.0.1:' + $portHttp + '/release')) (ArgumentsFichier)
            Verifie "code 0 : telechargement suivi a travers la redirection" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)
            Verifie "ebony installe depuis HTTP, somme verifiee" ((Test-Path -LiteralPath (Join-Path $programmes2 ('ebony\' + $version + '\INSTALLE'))) -and ($r.Sortie -match 'somme SHA-256 verifiee')) $r.Sortie
            Verifie "aucun dossier temporaire ne reste" ((Residus $temp2).Count -eq 0) ''
            $temp3 = NouveauTemp 'temp3'; $programmes3 = NouveauTemp 'programmes3'
            $r = LanceInstallateur (EnvironnementEssai $temp3 $programmes3 ('http://127.0.0.1:' + $portHttp + '/inconnu')) (ArgumentsFichier)
            Verifie "adresse inconnue (404) : code 1, rien d'installe, rien ne reste" (($r.Code -eq 1) -and ($r.Sortie -match 'ECHEC') -and (-not (Test-Path -LiteralPath (Join-Path $programmes3 'ebony'))) -and ((Residus $temp3).Count -eq 0)) ("code=" + $r.Code + " " + $r.Sortie)
        } finally {
            $ecouteur.Stop(); $ecouteur.Close()
            try { $null = $serveur.EndInvoke($attente) } catch { }
            $serveur.Dispose(); $espaceServeur.Dispose()
        }
    }

    Write-Host "somme fausse, fichier absent"
    $fausse = NouveauTemp 'archive-fausse'
    Copy-Item -LiteralPath (Join-Path $Archives 'ebony.zip') -Destination $fausse
    [IO.File]::WriteAllText((Join-Path $fausse 'ebony.zip.sha256'), ('0' * 64 + '  ebony.zip' + "`n"), (New-Object Text.UTF8Encoding($false)))
    $temp4 = NouveauTemp 'temp4'; $programmes4 = NouveauTemp 'programmes4'
    $r = LanceInstallateur (EnvironnementEssai $temp4 $programmes4 $fausse) (ArgumentsFichier)
    Verifie "somme fausse : code 1, 'ne correspond pas', rien d'installe, rien ne reste" (($r.Code -eq 1) -and ($r.Sortie -match 'ne correspond pas') -and (-not (Test-Path -LiteralPath (Join-Path $programmes4 'ebony'))) -and ((Residus $temp4).Count -eq 0)) ("code=" + $r.Code + " " + $r.Sortie)
    $r = LanceInstallateur (EnvironnementEssai $temp4 $programmes4 (Join-Path $espace 'nulle-part')) (ArgumentsFichier)
    Verifie "dossier absent : code 1, fichier introuvable, rien ne reste" (($r.Code -eq 1) -and ($r.Sortie -match 'introuvable') -and ((Residus $temp4).Count -eq 0)) ("code=" + $r.Code + " " + $r.Sortie)
    [IO.File]::WriteAllText((Join-Path $fausse 'ebony.zip.sha256'), "pas une somme`n", (New-Object Text.UTF8Encoding($false)))
    $r = LanceInstallateur (EnvironnementEssai $temp4 $programmes4 $fausse) (ArgumentsFichier)
    Verifie "somme illisible : code 1, 'pas la forme attendue'" (($r.Code -eq 1) -and ($r.Sortie -match 'pas la forme attendue')) ("code=" + $r.Code + " " + $r.Sortie)

    Write-Host "sans owl dans le PATH : refus net, rien d'installe"
    $temp5 = NouveauTemp 'temp5'; $programmes5 = NouveauTemp 'programmes5'
    $environnementSansOwl = EnvironnementEssai $temp5 $programmes5 $Archives
    $environnementSansOwl['PATH'] = (Join-Path $env:SystemRoot 'System32') + ';' + $env:SystemRoot + ';' + (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0')
    if (Get-Command owl -ErrorAction SilentlyContinue | Where-Object { $_.Source -like ((Join-Path $env:SystemRoot '*')) }) {
        Write-Host "  [IGNORE] owl est dans le dossier de Windows : le cas « sans owl » ne peut pas etre rejoue ici"
    } else {
        $r = LanceInstallateur $environnementSansOwl (ArgumentsFichier)
        Verifie "code 1, le message nomme owl et dit que rien n'est installe" (($r.Code -eq 1) -and ($r.Sortie -match 'owl') -and ($r.Sortie -match "Rien n'a ete installe") -and (-not (Test-Path -LiteralPath (Join-Path $programmes5 'ebony')))) ("code=" + $r.Code + " " + $r.Sortie)
    }

    Write-Host "lance par « irm | iex » : le terminal ne se ferme pas, meme en cas d'echec"
    $temp6 = NouveauTemp 'temp6'; $programmes6 = NouveauTemp 'programmes6'
    $commandeIex = '"Get-Content -Raw -LiteralPath ''' + $installateur + ''' | Invoke-Expression; Write-Output ''APRES_IEX''"'
    $r = LanceInstallateur (EnvironnementEssai $temp6 $programmes6 $Archives) @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $commandeIex)
    Verifie "installation par iex : code 0 et la suite du terminal s'execute" (($r.Code -eq 0) -and ($r.Sortie -match 'APRES_IEX') -and (Test-Path -LiteralPath (Join-Path $programmes6 ('ebony\' + $version + '\INSTALLE')))) ("code=" + $r.Code + " " + $r.Sortie)
    $r = LanceInstallateur (EnvironnementEssai $temp6 $programmes6 $fausse) @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $commandeIex)
    Verifie "echec par iex (somme illisible) : le terminal continue (APRES_IEX affiche)" (($r.Sortie -match 'ECHEC') -and ($r.Sortie -match 'APRES_IEX')) ("code=" + $r.Code + " " + $r.Sortie)

    Write-Host "dossier temporaire accentue : repli sur un chemin sans accent"
    $accent = Join-Path $espace ('Mod' + [char]232 + 'les tmp')
    New-Item -ItemType Directory -Path $accent | Out-Null
    $programmes7 = NouveauTemp 'programmes7'
    $r = LanceInstallateur (EnvironnementEssai $accent $programmes7 $Archives) (ArgumentsFichier)
    Verifie "TEMP accentue et avec espace : code 0, ebony installe" (($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $programmes7 ('ebony\' + $version + '\INSTALLE')))) ("code=" + $r.Code + " " + $r.Sortie)
    Verifie "rien ne reste dans le dossier accentue ni dans ProgramData" (((Residus $accent).Count -eq 0) -and ((Residus $env:ProgramData).Count -eq 0)) ''

    Write-Host "l'installateur Linux, sur le .tar.gz de la meme archive (WSL)"
    $wslDisponible = $null -ne (Get-Command wsl -ErrorAction SilentlyContinue)
    if (-not $wslDisponible) {
        Write-Host "  [IGNORE] WSL est absent : installateur.sh n'est pas rejoue ici"
    } else {
        $dossierOwlWsl = ''; if ($env:EBONY_WSL_OWL_BIN) { $dossierOwlWsl = $env:EBONY_WSL_OWL_BIN }
        $versLinux = { param([string]$Chemin) $lecteur = $Chemin.Substring(0, 1).ToLowerInvariant(); return '/mnt/' + $lecteur + $Chemin.Substring(2).Replace('\', '/') }
        $commandeWsl = 'EBONY_WSL_OWL_BIN=' + $dossierOwlWsl + ' sh ' + (& $versLinux (Join-Path $depot 'tests\integration\installateur.sh')) + ' ' + (& $versLinux $Archives)
        $ancienne = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $sortieWsl = (& wsl bash -c $commandeWsl 2>&1 | ForEach-Object { "$_" }) -join "`n"
        $codeWsl = $LASTEXITCODE
        $ErrorActionPreference = $ancienne
        if ($sortieWsl -match 'IGNORE : owl') { Write-Host "  [IGNORE] owl n'est pas dans le PATH de WSL (EBONY_WSL_OWL_BIN) : installateur.sh n'est pas rejoue ici" }
        else { Verifie "installateur.sh sous WSL : tout passe" (($codeWsl -eq 0) -and ($sortieWsl -match 'INSTALLATEUR LINUX : TOUT PASSE')) $sortieWsl }
    }
}
finally {
    if ($null -ne $ecouteur) { try { $ecouteur.Close() } catch { } }
    try { if ($null -ne (LitPath $nomVariableTest)) { $cleUtilisateur.DeleteValue($nomVariableTest) } } catch { Write-Host ("  [ECHEC]  nettoyage de la variable de test impossible : " + $_.Exception.Message) -ForegroundColor Red; $script:echecs++ }
    if ($null -ne (LitPath $nomVariableTest)) { Write-Host "  [ECHEC]  la variable de test existe encore" -ForegroundColor Red; $script:echecs++ }
    Nettoie $espace
}
Verifie "le VRAI PATH de l'utilisateur est identique avant et apres ce test" ((LitPath 'Path') -eq $vraiPathAvant) ''
$cleUtilisateur.Close()

Write-Host ""
if ($echecs -eq 0) { Write-Host "INSTALLATEUR WINDOWS : TOUT PASSE" -ForegroundColor Green; exit 0 }
Write-Host ("INSTALLATEUR WINDOWS : " + $echecs + " ECHEC(S)") -ForegroundColor Red
exit 1
