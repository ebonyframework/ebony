# Fabrique l'INSTANTANE PUBLIC d'ebony : l'arbre des fichiers publics, tel qu'il est au commit HEAD.
# Deux modes :
#   -Destination <dossier neuf ou vide>  : ecrit l'instantane avec un depot git a HISTORIQUE NEUF (un seul commit) ;
#   -Depot <clone existant du depot public> : remplace le contenu du clone par l'instantane et ajoute UN COMMIT de plus (l'historique existant est conserve).
# Sens unique et local : ce script ne pousse RIEN, ne cree aucun depot distant et ne touche pas au depot de developpement. Envoyer l'instantane vers un depot public est une operation a part (git push), faite a la main.
#
# Garde-fous, dans l'ordre (le premier qui echoue arrete tout, rien n'est ecrit) :
#   1. l'arbre de travail est propre (sinon l'instantane ne serait pas ce qui est commite) ;
#   2. scripts\controle-instantane.ps1 -Strict : plus aucune trace du processus dans les fichiers publics ;
#   3. la destination n'existe pas ou est vide (-Destination), ou le clone est un depot git propre, hors du depot de developpement (-Depot).
# Puis : copie des fichiers de HEAD (git archive), commit sobre, et, si -Gitleaks est donne, un audit de secrets de l'historique obtenu.
#
# Usage : .\scripts\publie-instantane.ps1 -Destination D:\Projets\ebonyframework\ebony -Version 0.1.0 [-Gitleaks <gitleaks.exe>] [-Auteur "Nom"] [-Courriel "adresse"]
#         .\scripts\publie-instantane.ps1 -Depot D:\Projets\ebonyframework\ebony -Version 0.1.0 [-Message "texte"] [-Gitleaks ...] [-Auteur ...] [-Courriel ...]
# Les fichiers publics sont ceux de scripts\instantane-liste.txt. Ce fichier reste ASCII.

param(
    [string]$Destination = '',
    [string]$Depot = '',
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Message = '',
    [string]$Gitleaks = '',
    [string]$Auteur = '',
    [string]$Courriel = ''
)

$ErrorActionPreference = 'Stop'
$racine = Split-Path $PSScriptRoot -Parent
Set-Location $racine

function Echec([string]$Texte) { Write-Host ("ECHEC : " + $Texte) -ForegroundColor Red; exit 1 }
function ExecuteGit([string[]]$Arguments) {
    $sortie = & git @Arguments 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { Echec ("git " + ($Arguments -join ' ') + " : " + ($sortie -join ' ')) }
    return $sortie
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') { Echec "la version doit etre de la forme X.Y.Z (recu : $Version)" }
if (($Destination -eq '') -eq ($Depot -eq '')) { Echec "donnez -Destination (historique neuf) OU -Depot (un commit de plus sur un clone existant), pas les deux ni aucun" }
$modeDepot = ($Depot -ne '')

# 1. Arbre propre.
$etat = @(ExecuteGit @('status', '--porcelain') | Where-Object { $_ -notmatch '^\?\? \.mcp\.json$' })
if ($etat.Count -gt 0) { Echec ("l'arbre de travail n'est pas propre (commiter ou ranger d'abord) : " + ($etat | Select-Object -First 3) -join ' | ') }

# 2. Plus aucune trace du processus.
& (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $PSScriptRoot 'controle-instantane.ps1') -Strict | Out-Host
if ($LASTEXITCODE -ne 0) { Echec "scripts\controle-instantane.ps1 -Strict : il reste des traces du processus dans les fichiers publics" }

# 3. Destination (ou clone) acceptable ; $destinationComplete est le dossier ou l'arbre est extrait (un dossier temporaire en mode -Depot).
if ($modeDepot) {
    if (-not (Test-Path -LiteralPath (Join-Path $Depot '.git'))) { Echec "-Depot n'est pas un clone git : $Depot" }
    $depotComplet = (Resolve-Path -LiteralPath $Depot).Path
    if ($depotComplet.StartsWith($racine, [StringComparison]::OrdinalIgnoreCase)) { Echec "le clone ne doit pas etre SOUS le depot de developpement (OWL chargerait les .owl en double)" }
    $etatClone = @(& git -C $depotComplet status --porcelain 2>&1)
    if ($etatClone.Count -gt 0) { Echec ("le clone n'est pas propre : " + ($etatClone | Select-Object -First 3) -join ' | ') }
    $destinationComplete = Join-Path ([IO.Path]::GetTempPath()) ('ebony-instantane-arbre-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $destinationComplete | Out-Null
}
else {
    if (Test-Path -LiteralPath $Destination) {
        if (@(Get-ChildItem -LiteralPath $Destination -Force).Count -gt 0) { Echec "le dossier destination existe et n'est pas vide : $Destination" }
    }
    else { New-Item -ItemType Directory -Path $Destination | Out-Null }
    $destinationComplete = (Resolve-Path -LiteralPath $Destination).Path
    if ($destinationComplete.StartsWith($racine, [StringComparison]::OrdinalIgnoreCase)) { Echec "la destination ne doit pas etre SOUS le depot de developpement (OWL chargerait les .owl en double)" }
}

# Les chemins publics (une ligne par entree ; un dossier se termine par /).
$entrees = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'instantane-liste.txt') -Encoding UTF8 | Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() })
if ($entrees.Count -eq 0) { Echec "scripts\instantane-liste.txt est vide" }

# Les fichiers de HEAD (pas ceux de l'arbre de travail) : git archive, extrait par tar.
$archive = Join-Path ([IO.Path]::GetTempPath()) ('ebony-instantane-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.tar')
try {
    $null = ExecuteGit (@('archive', '--format=tar', '--output', $archive, 'HEAD', '--') + $entrees)
    & tar -xf $archive -C $destinationComplete
    if ($LASTEXITCODE -ne 0) { Echec "tar n'a pas pu extraire l'archive" }
}
finally { Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue }

# Aucun .md dans l'instantane, sauf README.md a la racine et les guides d'usage de docs/guides/ (README de dossiers et notes de version restent dans le depot de developpement).
$racineInstantane = $destinationComplete.TrimEnd('\', '/')
$prefixeGuides = (Join-Path $racineInstantane 'docs\guides') + [IO.Path]::DirectorySeparatorChar
$estInterdit = { $_.FullName -ne (Join-Path $racineInstantane 'README.md') -and -not $_.FullName.StartsWith($prefixeGuides, [StringComparison]::OrdinalIgnoreCase) }
Get-ChildItem -LiteralPath $racineInstantane -Recurse -File -Filter '*.md' -Force | Where-Object $estInterdit | Remove-Item -Force
$mdRestants = @(Get-ChildItem -LiteralPath $racineInstantane -Recurse -File -Filter '*.md' -Force | Where-Object $estInterdit)
if ($mdRestants.Count -gt 0) { Echec ("il reste des .md dans l'instantane : " + ($mdRestants | Select-Object -First 3 | ForEach-Object Name) -join ', ') }
if (-not (Test-Path -LiteralPath (Join-Path $racineInstantane 'README.md'))) { Echec "l'instantane n'a pas de README.md a la racine" }
# Les dossiers vides ne sont pas suivis par git : rien d'autre a faire.

# Commit sobre.
$optionsIdentite = @()
if ($Auteur -ne '') { $optionsIdentite += @('-c', "user.name=$Auteur") }
if ($Courriel -ne '') { $optionsIdentite += @('-c', "user.email=$Courriel") }
$texteCommit = if ($Message -ne '') { $Message } else { "Ebony $Version" }
$dossierGit = if ($modeDepot) { $depotComplet } else { $destinationComplete }
Push-Location $dossierGit
try {
    if ($modeDepot) {
        # Le contenu du clone devient celui de l'instantane (un fichier retire du depot de developpement disparait), l'historique reste.
        Get-ChildItem -LiteralPath $dossierGit -Force | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force
        Get-ChildItem -LiteralPath $destinationComplete -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $dossierGit -Recurse -Force }
        Remove-Item -LiteralPath $destinationComplete -Recurse -Force -ErrorAction SilentlyContinue
        $null = ExecuteGit @('add', '--all')
        & git diff --cached --quiet
        if ($LASTEXITCODE -eq 0) { Write-Host "Rien a commiter : le clone est deja identique a l'instantane."; exit 0 }
        $null = ExecuteGit ($optionsIdentite + @('-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', $texteCommit))
        $nbFichiers = @(ExecuteGit @('ls-files')).Count
        $nbCommits = @(ExecuteGit @('rev-list', 'HEAD')).Count
        Write-Host ("Instantane ecrit dans {0} : {1} fichiers, {2} commits (dernier : {3}). Rien n'a ete envoye." -f $dossierGit, $nbFichiers, $nbCommits, $texteCommit)
    }
    else {
        $null = ExecuteGit @('init', '--quiet', '--initial-branch=main')
        $null = ExecuteGit @('add', '--all')
        $null = ExecuteGit ($optionsIdentite + @('-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', $texteCommit))
        $nbFichiers = @(ExecuteGit @('ls-files')).Count
        Write-Host ("Instantane ecrit dans {0} : {1} fichiers, un commit ({2}). Rien n'a ete envoye." -f $dossierGit, $nbFichiers, $texteCommit)
    }

    if ($Gitleaks -ne '') {
        $rapport = Join-Path ([IO.Path]::GetTempPath()) ('ebony-instantane-gitleaks-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        # gitleaks ecrit son journal sur stderr : sous 'Stop', PowerShell 5.1 en ferait une erreur ; seul le code de sortie compte.
        $ErrorActionPreference = 'Continue'
        & $Gitleaks git --no-banner --redact --report-format json --report-path $rapport $dossierGit 2>$null | Out-Null
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -eq 0) { Write-Host "Audit de secrets (gitleaks) : aucune fuite dans l'historique." }
        else { Write-Host ("Audit de secrets (gitleaks) : des fuites sont signalees, voir " + $rapport) -ForegroundColor Red; exit 1 }
        Remove-Item -LiteralPath $rapport -Force -ErrorAction SilentlyContinue
    }
}
finally { Pop-Location }
exit 0
