# Test d'integration de l'archive de distribution : on l'installe SANS git ni clone, comme le ferait un testeur.
#   .\tests\integration\archive.ps1                      fabrique l'archive du commit HEAD dans un dossier temporaire, puis la verifie
#   .\tests\integration\archive.ps1 -Archive C:\x\ebony-0.2.0.zip     verifie une archive donnee (sa somme .sha256 doit etre a cote)
# Ce qui est verifie : la somme SHA-256 ; le contenu extrait dans un dossier SANS accent ; "ebony --version" et "doctor" depuis l'archive extraite ;
# "ebony install" (deux fois de suite, sans degat) ; "ebony new" depuis la copie installee, et le projet cree compile ; "ebony uninstall" qui la retire.
# Le dossier des programmes est redirige (EBONY_PROGRAMMES) et le PATH vise une variable de TEST (EBONY_PATH_VAR) : le VRAI PATH de l'utilisateur n'est jamais modifie (verifie a la fin).
# Code de sortie 0 si tout passe, 1 sinon. Ce fichier reste ASCII. ATTENTION : les noms de variables PowerShell ne distinguent pas la casse.

param([string]$Archive = '')

$ErrorActionPreference = 'Stop'
$depot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$nomVariableTest = 'EBONY_TEST_PATH_ARCHIVE'

$echecs = 0
function Verifie([string]$Titre, [bool]$Condition, [string]$Detail) {
    if ($Condition) { Write-Host ("  [OK]     " + $Titre) }
    else { Write-Host ("  [ECHEC]  " + $Titre) -ForegroundColor Red; if ($Detail) { Write-Host ("           " + $Detail) }; $script:echecs++ }
}

# $Environnement : variables d'environnement ajoutees pour CE processus seulement ; $Lanceur : l'ebony.cmd a lancer.
function LanceEbony([string]$Lanceur, [string]$Dossier, [string[]]$Arguments, [hashtable]$Environnement = @{}) {
    $infos = New-Object Diagnostics.ProcessStartInfo
    $infos.FileName = $env:ComSpec
    $infos.Arguments = '/c ""' + $Lanceur + '" ' + ($Arguments -join ' ') + '"'
    $infos.WorkingDirectory = $Dossier
    $infos.UseShellExecute = $false
    foreach ($cle in $Environnement.Keys) { $infos.EnvironmentVariables[$cle] = [string]$Environnement[$cle] }
    $infos.RedirectStandardOutput = $true; $infos.RedirectStandardError = $true
    $infos.StandardOutputEncoding = [Text.Encoding]::UTF8; $infos.StandardErrorEncoding = [Text.Encoding]::UTF8
    $processus = [Diagnostics.Process]::Start($infos)
    $sortie = $processus.StandardOutput.ReadToEnd() + $processus.StandardError.ReadToEnd()
    $processus.WaitForExit()
    return @{ Code = $processus.ExitCode; Sortie = $sortie }
}

# Empreinte d'un dossier : chemin relatif + SHA-256 de chaque fichier, tries.
function EmpreinteDossier([string]$Dossier) {
    $racine = (Resolve-Path -LiteralPath $Dossier).Path.TrimEnd('\')
    $lignes = Get-ChildItem -LiteralPath $racine -Recurse -File -Force | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($racine.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    $octets = [Text.Encoding]::UTF8.GetBytes(($lignes -join "`n"))
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($octets)) -replace '-', '')
}

function Nettoie([string]$Chemin) {
    if (-not (Test-Path -LiteralPath $Chemin)) { return }
    try { Remove-Item -Recurse -Force -LiteralPath $Chemin -ErrorAction Stop }
    catch {
        Start-Sleep -Seconds 2
        try { Remove-Item -Recurse -Force -LiteralPath $Chemin -ErrorAction Stop } catch { Write-Host ("  [ECHEC]  nettoyage impossible de " + $Chemin + " : " + $_.Exception.Message) -ForegroundColor Red; $script:echecs++ }
    }
}

# Espace de travail SANS accent ni espace : c'est le cas a couvrir pour une archive.
$espace = Join-Path ([IO.Path]::GetTempPath()) ('ebony_archive_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $espace | Out-Null

$cleUtilisateur = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
function LitPath([string]$Nom) { return $cleUtilisateur.GetValue($Nom, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
if ($null -ne (LitPath $nomVariableTest)) { Write-Host "La variable de test $nomVariableTest existe deja : arret, rien n'est modifie."; Nettoie $espace; exit 1 }
$vraiPathAvant = LitPath 'Path'

try {
    if ($Archive -eq '') {
        Write-Host "fabrication de l'archive du commit HEAD"
        $sortieArchive = Join-Path $espace 'archive'
        $null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $depot 'scripts\construit-archive.ps1') -Ref HEAD -Sortie $sortieArchive 2>&1
        Verifie "construit-archive.ps1 : code 0" ($LASTEXITCODE -eq 0) ''
        $Archive = (Get-ChildItem -LiteralPath $sortieArchive -Filter '*.zip' | Select-Object -First 1).FullName
    }
    if (-not (Test-Path -LiteralPath $Archive)) { throw "archive introuvable : $Archive" }
    $nomArchive = Split-Path $Archive -Leaf
    $version = [regex]::Match($nomArchive, '^ebony-(\d+\.\d+\.\d+)\.zip$').Groups[1].Value
    Verifie "le nom de l'archive est ebony-<version>.zip" ($version -ne '') $nomArchive

    Write-Host "somme SHA-256"
    $fichierSomme = $Archive + '.sha256'
    Verifie "le fichier .sha256 est a cote de l'archive" (Test-Path -LiteralPath $fichierSomme) $fichierSomme
    $sommeAttendue = ((Get-Content -LiteralPath $fichierSomme -TotalCount 1) -split '\s+')[0].ToLowerInvariant()
    $sommeReelle = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
    Verifie "la somme de l'archive est celle du fichier .sha256" ($sommeReelle -eq $sommeAttendue) ("attendue " + $sommeAttendue + " obtenue " + $sommeReelle)

    Write-Host "extraction dans un dossier sans accent (pas de git, pas de clone)"
    $extraction = Join-Path $espace 'extrait'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Archive, $extraction)
    $dossierArchive = Join-Path $extraction ('ebony-' + $version)
    Verifie "un seul dossier ebony-<version> a la racine de l'archive" ((Test-Path -LiteralPath $dossierArchive) -and (@(Get-ChildItem -LiteralPath $extraction).Count -eq 1)) ''
    Verifie "aucun dossier .git ni tests ni docs dans l'archive" (-not (Test-Path -LiteralPath (Join-Path $dossierArchive '.git')) -and -not (Test-Path -LiteralPath (Join-Path $dossierArchive 'tests')) -and -not (Test-Path -LiteralPath (Join-Path $dossierArchive 'docs'))) ''
    $lanceurExtrait = Join-Path $dossierArchive 'bin\ebony.cmd'
    Verifie "bin\ebony.cmd est present" (Test-Path -LiteralPath $lanceurExtrait) ''
    # Points d'entree reduits par commande (.commandes) : dans l'archive, un mini-projet complet par commande.
    . (Join-Path $depot 'scripts\commandes-ebony.ps1')
    $commandesAttendues = @(Get-CommandesAiguillage (Join-Path $depot 'src\commandes\EbAiguillage.owl'))
    $commandesManquantes = @($commandesAttendues | Where-Object { -not ((Test-Path -LiteralPath (Join-Path $dossierArchive ('.commandes\' + $_ + '\ebony.owl'))) -and (Test-Path -LiteralPath (Join-Path $dossierArchive ('.commandes\' + $_ + '\projet.owl'))) -and (Test-Path -LiteralPath (Join-Path $dossierArchive ('.commandes\' + $_ + '\EbAiguillage.owl')))) })
    Verifie "l'archive contient un point d'entree reduit par commande (.commandes)" ($commandesManquantes.Count -eq 0) ("manquants : " + ($commandesManquantes -join ', '))

    $travail = Join-Path $espace 'travail'
    New-Item -ItemType Directory -Path $travail | Out-Null

    Write-Host "depuis l'archive extraite : --version et doctor"
    $r = LanceEbony $lanceurExtrait $travail @('--version')
    Verifie "ebony --version : code 0 et 'ebony <version>'" (($r.Code -eq 0) -and ($r.Sortie.Trim() -ceq ('ebony ' + $version))) ("code=" + $r.Code + " " + $r.Sortie)
    $r = LanceEbony $lanceurExtrait $travail @('doctor', '--json')
    $json = $null; try { $json = $r.Sortie | ConvertFrom-Json } catch { }
    Verifie "ebony doctor --json : code 0, ok, version d'ebony de l'archive, aucune erreur" (($r.Code -eq 0) -and ($null -ne $json) -and ($json.ok -eq $true) -and ($json.ebony -ceq $version) -and ($json.errors -eq 0)) ("code=" + $r.Code + " " + $r.Sortie)
    if ($null -ne $json) { Verifie "doctor : l'installation est lisible depuis l'archive extraite" (@($json.checks | Where-Object { ($_.id -ceq 'installation') -and ($_.status -ceq 'ok') }).Count -eq 1) $r.Sortie }

    Write-Host "ebony install, depuis l'archive extraite, deux fois de suite"
    $programmes = Join-Path $espace 'programmes'
    New-Item -ItemType Directory -Path $programmes | Out-Null
    $environnement = @{ EBONY_PROGRAMMES = $programmes; EBONY_PATH_VAR = $nomVariableTest }
    $r = LanceEbony $lanceurExtrait $travail @('install') $environnement
    Verifie "install : code 0" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)
    $dossierInstalle = Join-Path $programmes ('ebony\' + $version)
    Verifie "le dossier de la version est cree" (Test-Path -LiteralPath $dossierInstalle) $r.Sortie
    $marqueur = Join-Path $dossierInstalle 'INSTALLE'
    Verifie "le marqueur INSTALLE contient la version" ((Test-Path -LiteralPath $marqueur) -and ((Get-Content -LiteralPath $marqueur -TotalCount 1).Trim() -ceq $version)) ''
    Verifie "l'installation a copie les points d'entree reduits (.commandes\doctor et .commandes\new)" ((Test-Path -LiteralPath (Join-Path $dossierInstalle '.commandes\doctor\ebony.owl')) -and (Test-Path -LiteralPath (Join-Path $dossierInstalle '.commandes\new\ebony.owl'))) ''
    Verifie "le PATH de test contient le dossier bin installe" ((LitPath $nomVariableTest) -like ('*' + $dossierInstalle + '\bin*')) ''
    $empreinteAvant = EmpreinteDossier $dossierInstalle
    $r = LanceEbony $lanceurExtrait $travail @('install') $environnement
    Verifie "install une seconde fois : code 0" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)
    Verifie "la seconde installation ne change aucun fichier" ((EmpreinteDossier $dossierInstalle) -eq $empreinteAvant) ''
    $valeurPathApres = LitPath $nomVariableTest
    Verifie "le PATH de test n'a pas de doublon apres la seconde installation" ((@($valeurPathApres -split ';' | Where-Object { $_ -like ('*ebony\' + $version + '\bin*') })).Count -eq 1) $valeurPathApres

    Write-Host "depuis la copie INSTALLEE : ebony new, et le projet cree compile"
    $lanceurInstalle = Join-Path $dossierInstalle 'bin\ebony.cmd'
    $r = LanceEbony $lanceurInstalle $travail @('new', 'boutique') $environnement
    Verifie "ebony new boutique : code 0" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)
    $projetCree = Join-Path $travail 'boutique'
    Verifie "le projet contient ebony.conf, projet.owl et le service" ((Test-Path -LiteralPath (Join-Path $projetCree 'ebony.conf')) -and (Test-Path -LiteralPath (Join-Path $projetCree 'projet.owl')) -and (Test-Path -LiteralPath (Join-Path $projetCree 'app\http\ServiceBoutique.owl'))) ''
    Verifie "ebony.conf note la version de l'archive comme minimum" ((Get-Content -LiteralPath (Join-Path $projetCree 'ebony.conf') -Raw) -match ('"version":\s*"' + [regex]::Escape($version) + '"')) ''
    Push-Location $projetCree
    try {
        $ErrorActionPreference = 'Continue'
        $verification = ((owl --check projet.owl 2>&1) | ForEach-Object { "$_" }) -join ' '
        $ErrorActionPreference = 'Stop'
        Verifie "owl --check du projet cree : aucune erreur" ($verification -match '"errors":\s*\[\]') $verification
    } finally { $ErrorActionPreference = 'Stop'; Pop-Location }

    Write-Host "ebony uninstall, depuis la copie installee"
    $r = LanceEbony $lanceurInstalle $travail @('uninstall') $environnement
    Verifie "uninstall : code 0" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)
    Verifie "le dossier de la version est supprime" (-not (Test-Path -LiteralPath $dossierInstalle)) $r.Sortie
    Verifie "le PATH de test ne contient plus ebony" (-not ((LitPath $nomVariableTest) -like '*ebony*')) ((LitPath $nomVariableTest))
}
finally {
    # Nettoyage visible : la variable de test ne doit jamais rester dans le registre de l'utilisateur.
    try { if ($null -ne (LitPath $nomVariableTest)) { $cleUtilisateur.DeleteValue($nomVariableTest) } } catch { Write-Host ("  [ECHEC]  nettoyage de la variable de test impossible : " + $_.Exception.Message) -ForegroundColor Red; $script:echecs++ }
    if ($null -ne (LitPath $nomVariableTest)) { Write-Host "  [ECHEC]  la variable de test existe encore" -ForegroundColor Red; $script:echecs++ }
    Nettoie $espace
}
Verifie "le VRAI PATH de l'utilisateur est identique avant et apres ce test" ((LitPath 'Path') -eq $vraiPathAvant) ''
$cleUtilisateur.Close()

Write-Host ""
if ($echecs -eq 0) { Write-Host "ARCHIVE : TOUT PASSE" -ForegroundColor Green; exit 0 }
Write-Host ("ARCHIVE : " + $echecs + " ECHEC(S)") -ForegroundColor Red
exit 1
