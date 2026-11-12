# Test d'integration de bin\ebony-supprime.ps1 : le script qui SUPPRIME les versions d'ebony installees (ebony uninstall). Il est destructeur : ce test verifie surtout ce qu'il ne doit PAS supprimer.
# Tout se passe dans un dossier temporaire cree par le test. Windows PowerShell 5.1 ou plus.   Usage :   .\tests\integration\suppression.ps1       (code de sortie 0 si tout passe, 1 sinon)
# Ce fichier reste ASCII. ATTENTION : les noms de variables PowerShell ne distinguent pas la casse.

$ErrorActionPreference = 'Stop'
$depot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script = Join-Path $depot 'bin\ebony-supprime.ps1'

$echecs = 0
function Verifie([string]$Titre, [bool]$Condition, [string]$Detail) {
    if ($Condition) { Write-Host ("  [OK]     " + $Titre) }
    else { Write-Host ("  [ECHEC]  " + $Titre) -ForegroundColor Red; if ($Detail) { Write-Host ("           " + $Detail) }; $script:echecs++ }
}
function Lance([string]$Base) {
    $sortie = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Base $Base 2>&1 | ForEach-Object { "$_" }
    return @{ Code = $LASTEXITCODE; Sortie = ($sortie -join "`n") }
}
function Ecrit([string]$Chemin, [string]$Texte) { New-Item -ItemType Directory -Force (Split-Path $Chemin -Parent) | Out-Null; Set-Content -LiteralPath $Chemin -Value $Texte }

$racineTmp = Join-Path $depot 'tmp'
New-Item -ItemType Directory -Force $racineTmp | Out-Null
$espace = Join-Path $racineTmp ('suppr_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    Write-Host "versions installees supprimees, tout le reste laisse"
    $base = Join-Path $espace 'Pro grams\ebony'
    Ecrit (Join-Path $base '0.1.0\INSTALLE') '0.1.0'
    Ecrit (Join-Path $base '0.1.0\bin\ebony.cmd') 'rem'
    Ecrit (Join-Path $base '0.1.0\src\commandes\EbPrincipal.owl') 'x'
    Ecrit (Join-Path $base '0.2.0\INSTALLE') '0.2.0'
    Ecrit (Join-Path $base '0.2.0\modules\core\execution\VERSION') '0.2.0'
    # un fichier en lecture seule dans une version : doit etre supprime quand meme
    Set-ItemProperty -LiteralPath (Join-Path $base '0.2.0\modules\core\execution\VERSION') -Name IsReadOnly -Value $true
    # un dossier qui n'est pas une installation d'ebony (pas de INSTALLE) : doit etre laisse
    Ecrit (Join-Path $base 'notes\important.txt') 'a garder'
    # une jonction vers des donnees a proteger : ne doit jamais etre suivie
    $donneesProtegees = Join-Path $espace 'donnees-protegees'
    Ecrit (Join-Path $donneesProtegees 'INSTALLE') 'piege : ce marqueur ne doit pas faire supprimer cette cible'
    Ecrit (Join-Path $donneesProtegees 'precieux.txt') 'a garder'
    New-Item -ItemType Junction -Path (Join-Path $base 'lien') -Target $donneesProtegees | Out-Null
    # un fichier a la racine de la base : laisse aussi
    Ecrit (Join-Path $base 'lisez-moi.txt') 'a garder'

    $r = Lance $base
    Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
    Verifie "0.1.0 supprime" (-not (Test-Path -LiteralPath (Join-Path $base '0.1.0'))) $r.Sortie
    Verifie "0.2.0 supprime (fichier en lecture seule compris)" (-not (Test-Path -LiteralPath (Join-Path $base '0.2.0'))) $r.Sortie
    Verifie "le dossier sans INSTALLE est laisse, avec son contenu" ((Get-Content -LiteralPath (Join-Path $base 'notes\important.txt')) -eq 'a garder') $r.Sortie
    Verifie "la jonction est laissee" (Test-Path -LiteralPath (Join-Path $base 'lien')) $r.Sortie
    Verifie "la cible de la jonction est INTACTE (jamais suivie)" (((Get-Content -LiteralPath (Join-Path $donneesProtegees 'precieux.txt')) -eq 'a garder') -and (Test-Path -LiteralPath (Join-Path $donneesProtegees 'INSTALLE'))) $r.Sortie
    Verifie "le fichier a la racine est laisse" (Test-Path -LiteralPath (Join-Path $base 'lisez-moi.txt')) $r.Sortie
    Verifie "la base n'est pas supprimee : elle contient encore autre chose" (Test-Path -LiteralPath $base) $r.Sortie
    Verifie "le rapport dit ce qui est supprime et ce qui est laisse" (($r.Sortie -match 'supprim. : .*0\.1\.0') -and ($r.Sortie -match 'supprim. : .*0\.2\.0') -and ($r.Sortie -match 'laiss. \(pas une installation') -and ($r.Sortie -match 'laiss. \(lien')) $r.Sortie

    Write-Host "deuxieme appel : idempotent"
    $r = Lance $base
    Verifie "code 0 et rien de plus n'est supprime" (($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $base 'notes\important.txt')) -and (Test-Path -LiteralPath (Join-Path $donneesProtegees 'precieux.txt'))) "code=$($r.Code) $($r.Sortie)"

    Write-Host "base devenue vide : supprimee aussi"
    cmd /c rmdir "$base\lien" | Out-Null
    Remove-Item -LiteralPath (Join-Path $base 'notes') -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $base 'lisez-moi.txt') -Force
    Ecrit (Join-Path $base '0.3.0\INSTALLE') '0.3.0'
    $r = Lance $base
    Verifie "code 0, 0.3.0 supprime et la base vide supprimee" (($r.Code -eq 0) -and (-not (Test-Path -LiteralPath $base))) "code=$($r.Code) $($r.Sortie)"
    Verifie "les donnees protegees sont toujours la" (Test-Path -LiteralPath (Join-Path $donneesProtegees 'precieux.txt')) ''

    Write-Host "base absente : rien a supprimer"
    $r = Lance $base
    Verifie "code 0 et le dit" (($r.Code -eq 0) -and ($r.Sortie -match 'Rien . supprimer')) "code=$($r.Code) $($r.Sortie)"

    Write-Host "un fichier ouvert empeche la suppression d'une version : echec signale (code 1), les autres versions sont quand meme supprimees"
    $baseVerrou = Join-Path $espace 'verrou\ebony'
    Ecrit (Join-Path $baseVerrou '0.1.0\INSTALLE') '0.1.0'
    Ecrit (Join-Path $baseVerrou '0.1.0\fichier-ouvert.txt') 'ouvert'
    Ecrit (Join-Path $baseVerrou '0.2.0\INSTALLE') '0.2.0'
    $fichierVerrouille = [System.IO.File]::Open((Join-Path $baseVerrou '0.1.0\fichier-ouvert.txt'), [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $r = Lance $baseVerrou
        Verifie "code 1 et dit quel dossier n'a pas pu etre supprime" (($r.Code -eq 1) -and ($r.Sortie -match 'ECHEC : .*0\.1\.0')) "code=$($r.Code) $($r.Sortie)"
        Verifie "l'autre version (0.2.0) est supprimee quand meme" (-not (Test-Path -LiteralPath (Join-Path $baseVerrou '0.2.0'))) $r.Sortie
        Verifie "la base n'est pas supprimee" (Test-Path -LiteralPath $baseVerrou) $r.Sortie
    }
    finally { $fichierVerrouille.Close() }
    $r = Lance $baseVerrou
    Verifie "fichier relache, nouvel essai : tout est supprime, code 0" (($r.Code -eq 0) -and (-not (Test-Path -LiteralPath $baseVerrou))) "code=$($r.Code) $($r.Sortie)"

    Write-Host "refus : la base ne s'appelle pas ebony (rien n'est supprime)"
    $autre = Join-Path $espace 'autre'
    Ecrit (Join-Path $autre '0.1.0\INSTALLE') 'x'
    $r = Lance $autre
    Verifie "code 1 et dit que le dossier doit s'appeler ebony" (($r.Code -eq 1) -and ($r.Sortie -match 's''appeler ebony')) "code=$($r.Code) $($r.Sortie)"
    Verifie "rien n'est supprime" (Test-Path -LiteralPath (Join-Path $autre '0.1.0\INSTALLE')) ''

    Write-Host "refus : une racine de disque et un dossier parent"
    $r = Lance ([IO.Path]::GetPathRoot($espace))
    Verifie "racine de disque : code 1" ($r.Code -eq 1) "code=$($r.Code) $($r.Sortie)"
    $r = Lance (Split-Path $base -Parent)
    Verifie "dossier parent (Pro grams) : code 1" ($r.Code -eq 1) "code=$($r.Code) $($r.Sortie)"

    Write-Host "refus : la base est elle-meme un lien nomme ebony"
    $vraiDossier = Join-Path $espace 'vrai'
    Ecrit (Join-Path $vraiDossier '0.1.0\INSTALLE') 'x'
    New-Item -ItemType Directory -Force (Join-Path $espace 'liens') | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $espace 'liens\ebony') -Target $vraiDossier | Out-Null
    $r = Lance (Join-Path $espace 'liens\ebony')
    Verifie "code 1 et rien n'est supprime dans la cible" (($r.Code -eq 1) -and (Test-Path -LiteralPath (Join-Path $vraiDossier '0.1.0\INSTALLE'))) "code=$($r.Code) $($r.Sortie)"
    cmd /c rmdir (Join-Path $espace 'liens\ebony') | Out-Null
}
finally {
    # Nettoyage visible. Les jonctions sont retirees d'abord (rmdir ne suit pas le lien) pour ne jamais suivre une cible.
    try {
        if (Test-Path -LiteralPath $espace) {
            Get-ChildItem -LiteralPath $espace -Recurse -Force -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | ForEach-Object { cmd /c rmdir $_.FullName | Out-Null }
            Get-ChildItem -LiteralPath $espace -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object { $_.IsReadOnly = $false }
            Remove-Item -Recurse -Force -LiteralPath $espace -ErrorAction Stop
        }
    }
    catch { Write-Host ("  [ECHEC]  nettoyage impossible de " + $espace + " : " + $_.Exception.Message) -ForegroundColor Red; $script:echecs++ }
}

Write-Host ""
if ($echecs -eq 0) { Write-Host "TOUT PASSE" -ForegroundColor Green; exit 0 }
else { Write-Host ("$echecs ECHEC(S)") -ForegroundColor Red; exit 1 }
