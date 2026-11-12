# Supprime les versions d'ebony installees par "ebony install" : appele par bin\ebony.cmd pour "ebony uninstall" (OWL ne sait pas supprimer un dossier de facon recursive).
# C'est la SEULE exception a la regle "ebony ne supprime jamais rien" : une desinstallation qui laisse les fichiers ne desinstalle rien.
# Elle est strictement bornee :
#   - -Base doit s'appeler "ebony" (jamais une racine de disque, jamais un autre nom) et ne pas etre un lien ;
#   - seuls sont supprimes les sous-dossiers directs de -Base qui contiennent le fichier marqueur INSTALLE (ecrit EN DERNIER par "ebony install") ;
#   - tout autre dossier ou fichier de -Base (autre chose que nous y avons mis, lien symbolique ou jonction) est LAISSE, et dit ;
#   - -Base elle-meme n'est supprimee que si elle est vide ensuite.
# Ce fichier reste ASCII : les accents sont fabriques avec [char].
param(
    [Parameter(Mandatory = $true)][string]$Base,
    [string]$Marqueur = 'INSTALLE'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$eAigu = [string][char]0xE9
$eGrave = [string][char]0xE8
$aGrave = [string][char]0xE0

function EstLien([System.IO.FileSystemInfo]$Element) { return [bool]($Element.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }

$erreurs = 0
try {
    $baseComplete = [System.IO.Path]::GetFullPath($Base).TrimEnd('\')
    if ([System.IO.Path]::GetFileName($baseComplete) -ine 'ebony') {
        throw ("refus : le dossier $aGrave supprimer doit s'appeler ebony (re" + [char]0xE7 + "u : " + $baseComplete + "). Rien n'a " + $eAigu + "t" + $eAigu + " supprim" + $eAigu + ".")
    }
    if (-not (Test-Path -LiteralPath $baseComplete)) {
        Write-Host ("Rien " + $aGrave + " supprimer : " + $baseComplete + " n'existe pas.")
        exit 0
    }
    $dossierBase = Get-Item -LiteralPath $baseComplete -Force
    if ((EstLien $dossierBase) -or (-not $dossierBase.PSIsContainer)) {
        throw ("refus : " + $baseComplete + " est un lien ou un fichier, pas un dossier. Rien n'a " + $eAigu + "t" + $eAigu + " supprim" + $eAigu + ".")
    }

    foreach ($sousDossier in @(Get-ChildItem -LiteralPath $baseComplete -Directory -Force)) {
        if (EstLien $sousDossier) {
            Write-Host ("  laiss" + $eAigu + " (lien, jamais suivi) : " + $sousDossier.FullName)
        }
        elseif (Test-Path -LiteralPath (Join-Path $sousDossier.FullName $Marqueur) -PathType Leaf) {
            try {
                Remove-Item -LiteralPath $sousDossier.FullName -Recurse -Force -Confirm:$false -ErrorAction Stop
                Write-Host ("  supprim" + $eAigu + " : " + $sousDossier.FullName)
            }
            catch {
                $erreurs++
                Write-Host ("  ECHEC : " + $sousDossier.FullName + " : " + $_.Exception.Message)
            }
        }
        else {
            Write-Host ("  laiss" + $eAigu + " (pas une installation d'ebony : pas de fichier " + $Marqueur + ") : " + $sousDossier.FullName)
        }
    }

    $reste = @(Get-ChildItem -LiteralPath $baseComplete -Force)
    if ($reste.Count -eq 0) {
        Remove-Item -LiteralPath $baseComplete -Force -Confirm:$false -ErrorAction Stop
        Write-Host ("  supprim" + $eAigu + " (vide) : " + $baseComplete)
    }
    else {
        Write-Host ($baseComplete + " n'est pas supprim" + $eAigu + " : il contient encore " + $reste.Count + " " + $eAigu + "l" + $eAigu + "ment(s) qui ne sont pas des installations d'ebony.")
    }
}
catch {
    Write-Host ("ebony : suppression interrompue : " + $_.Exception.Message)
    exit 1
}
if ($erreurs -gt 0) {
    Write-Host ("ebony : " + $erreurs + " dossier(s) n'ont pas pu " + $eAigu + "tre supprim" + $eAigu + "s (fichier ouvert, ou terminal plac" + $eAigu + " dedans ?). Fermez-les puis relancez la d" + $eAigu + "sinstallation.")
    exit 1
}
exit 0
