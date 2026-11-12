# Controle : l'aiguillage (EbAiguillage.owl), le lanceur et les points d'entree reduits sont d'accord sur la liste des commandes.
#
# Pourquoi : une commande qui n'a pas de point d'entree reduit retombe sur ebony.owl a 20-25 s, sans erreur ni message. Ce controle l'empeche de passer inapercu.
# Il verifie, sans lancer owl :
#   1. bin\ebony.cmd (la seule liste ecrite a la main) contient exactement les commandes de l'aiguillage (hors aide et version) ;
#   2. si .commandes\ existe (genere par construit-entrees.ps1), chaque commande y a ses trois fichiers (ebony.owl, projet.owl, EbAiguillage.owl), et rien d'autre ne s'y trouve.
# La liste de reference est lue dans src\commandes\EbAiguillage.owl (voir commandes-ebony.ps1).
#
# Usage : .\scripts\controle-commandes.ps1 [-Racine <dossier>]       code de sortie 0 si tout est d'accord, 1 sinon. Ce fichier reste ASCII.

param([string]$Racine = '')

. (Join-Path $PSScriptRoot 'commandes-ebony.ps1')
if ($Racine -eq '') { $Racine = Split-Path $PSScriptRoot -Parent }
$Racine = (Resolve-Path -LiteralPath $Racine).Path.TrimEnd('\')

$problemes = @()
$commandesAiguillage = @(Get-CommandesAiguillage (Join-Path $Racine 'src\commandes\EbAiguillage.owl'))
# 0. L'aiguillage est a jour avec les commandes.json des modules (scripts\genere-aiguillage.ps1 -Verifie).
$scriptGeneration = Join-Path $PSScriptRoot 'genere-aiguillage.ps1'
& $scriptGeneration -Racine $Racine -Verifie *> $null
if ($LASTEXITCODE -ne 0) { $problemes += "src\commandes\EbAiguillage.owl n'est pas a jour avec les modules\*\outils\commandes.json (relancer scripts\genere-aiguillage.ps1)" }


# 1. La liste du lanceur : for %%C in (doctor new ...) do ...
$cheminLanceur = Join-Path $Racine 'bin\ebony.cmd'
$texteLanceur = [IO.File]::ReadAllText($cheminLanceur, [Text.Encoding]::ASCII)
$listeLanceur = [regex]::Match($texteLanceur, 'for %%C in \(([^)]*)\) do')
if (-not $listeLanceur.Success) { $problemes += "bin\ebony.cmd : la boucle 'for %%C in (...) do' des commandes est introuvable" }
else {
    $commandesLanceur = @($listeLanceur.Groups[1].Value -split '\s+' | Where-Object { $_ -ne '' } | Sort-Object -Unique)
    $manquantesLanceur = @($commandesAiguillage | Where-Object { $commandesLanceur -notcontains $_ })
    $enTropLanceur = @($commandesLanceur | Where-Object { $commandesAiguillage -notcontains $_ })
    if ($manquantesLanceur.Count -gt 0) { $problemes += ("bin\ebony.cmd : commande(s) de l'aiguillage absente(s) de la liste du lanceur (elles retomberaient sur le repli a 25 s) : " + ($manquantesLanceur -join ', ')) }
    if ($enTropLanceur.Count -gt 0) { $problemes += ("bin\ebony.cmd : commande(s) de la liste du lanceur inconnue(s) de l'aiguillage : " + ($enTropLanceur -join ', ')) }
}

# 1 bis. La liste du lanceur Linux (bin/ebony, un script sh) : for C in doctor new ...; do
$cheminLanceurLinux = Join-Path $Racine 'bin\ebony'
if (-not (Test-Path -LiteralPath $cheminLanceurLinux)) { $problemes += "bin\ebony (lanceur Linux) est introuvable" }
else {
    $texteLanceurLinux = [IO.File]::ReadAllText($cheminLanceurLinux, [Text.Encoding]::UTF8)
    $listeLanceurLinux = [regex]::Match($texteLanceurLinux, 'for C in ([^;]*); do')
    if (-not $listeLanceurLinux.Success) { $problemes += "bin\ebony : la boucle 'for C in ...; do' des commandes est introuvable" }
    else {
        $commandesLanceurLinux = @($listeLanceurLinux.Groups[1].Value -split '\s+' | Where-Object { $_ -ne '' } | Sort-Object -Unique)
        $manquantesLinux = @($commandesAiguillage | Where-Object { $commandesLanceurLinux -notcontains $_ })
        $enTropLinux = @($commandesLanceurLinux | Where-Object { $commandesAiguillage -notcontains $_ })
        if ($manquantesLinux.Count -gt 0) { $problemes += ("bin\ebony : commande(s) de l'aiguillage absente(s) de la liste du lanceur Linux : " + ($manquantesLinux -join ', ')) }
        if ($enTropLinux.Count -gt 0) { $problemes += ("bin\ebony : commande(s) de la liste du lanceur Linux inconnue(s) de l'aiguillage : " + ($enTropLinux -join ', ')) }
        if ($texteLanceurLinux.Contains("`r")) { $problemes += "bin\ebony contient des retours chariot (CR) : un script sh doit etre en LF" }
    }
}

# 2. Les points d'entree generes, s'ils existent.
$dossierEntrees = Join-Path $Racine '.commandes'
$entreesVerifiees = $false
if (Test-Path -LiteralPath $dossierEntrees) {
    $entreesVerifiees = $true
    foreach ($commande in $commandesAiguillage) {
        foreach ($fichier in @('ebony.owl', 'projet.owl', 'EbAiguillage.owl')) {
            if (-not (Test-Path -LiteralPath (Join-Path $dossierEntrees ($commande + '\' + $fichier)))) { $problemes += (".commandes\" + $commande + "\" + $fichier + " manque (relancer scripts\construit-entrees.ps1)") }
        }
    }
    $dossiersPresents = @(Get-ChildItem -LiteralPath $dossierEntrees -Directory | ForEach-Object { $_.Name })
    $dossiersEnTrop = @($dossiersPresents | Where-Object { $commandesAiguillage -notcontains $_ })
    if ($dossiersEnTrop.Count -gt 0) { $problemes += (".commandes : dossier(s) pour des commandes qui n'existent plus (relancer scripts\construit-entrees.ps1) : " + ($dossiersEnTrop -join ', ')) }
}

if ($problemes.Count -eq 0) {
    $suite = if ($entreesVerifiees) { ' ; .commandes complet' } else { ' ; .commandes absent (clone : repli a 25 s, lancer scripts\construit-entrees.ps1)' }
    Write-Host ("OK : {0} commande(s) d'accord entre l'aiguillage et le lanceur{1}" -f $commandesAiguillage.Count, $suite)
    exit 0
}
foreach ($probleme in $problemes) { Write-Host ("ECHEC : " + $probleme) -ForegroundColor Red }
exit 1
