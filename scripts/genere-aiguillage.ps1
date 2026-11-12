# Genere src\commandes\EbAiguillage.owl d'apres les declarations des modules : modules\<nom>\outils\commandes.json.
#
# OWL n'a pas de reflexion : appeler la commande d'un module demande du code qui la nomme. Cet aiguillage est donc ECRIT par ce script (le modele est scripts\aiguillage.tpl)
# et versionne ; -Verifie (utilise par scripts\controle-commandes.ps1) echoue s'il n'est pas a jour. Un commandes.json :
#   { "commandes": [ { "noms": ["token"], "procedure": "EbExecuteToken" } ] }
# "noms" : un ou plusieurs noms de commande (minuscules ASCII ; "" est le nom vide, sans commande) ; "procedure" : une procedure sans argument.
# Ordre : le coeur d'abord (module core), puis les autres modules par ordre alphabetique ; dans un module, l'ordre du fichier. Un nom en double entre deux modules est refuse.
#
# Usage : .\scripts\genere-aiguillage.ps1 [-Racine <dossier>] [-Verifie]     code 0 si ecrit (ou a jour avec -Verifie), 1 sinon. Ce fichier reste ASCII.

param([string]$Racine = '', [switch]$Verifie)

$ErrorActionPreference = 'Stop'
if ($Racine -eq '') { $Racine = Split-Path $PSScriptRoot -Parent }
$Racine = (Resolve-Path -LiteralPath $Racine).Path.TrimEnd('\')
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-CommandesDesModules([string]$RacineDepot) {
    $dossiers = @(Get-ChildItem -LiteralPath (Join-Path $RacineDepot 'modules') -Directory | Sort-Object { if ($_.Name -ceq 'core') { '' } else { $_.Name } })
    $entrees = New-Object 'System.Collections.Generic.List[object]'
    $vus = @{}
    foreach ($dossier in $dossiers) {
        $fichier = Join-Path $dossier.FullName 'outils\commandes.json'
        if (-not (Test-Path -LiteralPath $fichier)) { continue }
        $json = [IO.File]::ReadAllText($fichier, $utf8) | ConvertFrom-Json
        if ($null -eq $json.commandes -or @($json.commandes).Count -eq 0) { throw ("modules/" + $dossier.Name + "/outils/commandes.json : aucune commande declaree") }
        foreach ($commande in @($json.commandes)) {
            $noms = @($commande.noms)
            if ($noms.Count -eq 0) { throw ("modules/" + $dossier.Name + "/outils/commandes.json : une commande sans nom") }
            if ($commande.procedure -notmatch '^Eb[A-Za-z0-9]+$') { throw ("modules/" + $dossier.Name + "/outils/commandes.json : procedure invalide : " + $commande.procedure) }
            foreach ($nom in $noms) {
                if ($nom -cnotmatch '^[a-z]*$') { throw ("modules/" + $dossier.Name + "/outils/commandes.json : nom de commande invalide (minuscules ASCII) : " + $nom) }
                if ($vus.ContainsKey($nom)) { throw ("la commande '" + $nom + "' est declaree deux fois (" + $vus[$nom] + " et " + $dossier.Name + ")") }
                $vus[$nom] = $dossier.Name
            }
            $entrees.Add([pscustomobject]@{ Noms = $noms; Procedure = $commande.procedure })
        }
    }
    return $entrees.ToArray()
}

function New-TexteAiguillage([string]$RacineDepot) {
    $modele = [IO.File]::ReadAllText((Join-Path $RacineDepot 'scripts\aiguillage.tpl'), $utf8)
    $lignes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entree in (Get-CommandesDesModules $RacineDepot)) {
        $liste = (@($entree.Noms | ForEach-Object { '"' + $_ + '"' }) -join ', ')
        $lignes.Add("`t`t`tCAS " + $liste)
        $lignes.Add("`t`t`t" + $entree.Procedure + "()")
    }
    return $modele.Replace('{{CAS}}', ($lignes -join "`n"))
}

$texte = New-TexteAiguillage $Racine
$cible = Join-Path $Racine 'src\commandes\EbAiguillage.owl'
if ($Verifie) {
    $actuel = if (Test-Path -LiteralPath $cible) { [IO.File]::ReadAllText($cible, $utf8) } else { '' }
    if ($actuel -ceq $texte) { Write-Host "OK : src\commandes\EbAiguillage.owl est a jour avec les commandes.json des modules"; exit 0 }
    Write-Host "ECHEC : src\commandes\EbAiguillage.owl n'est pas a jour avec les commandes.json des modules (relancer scripts\genere-aiguillage.ps1)" -ForegroundColor Red
    exit 1
}
[IO.File]::WriteAllText($cible, $texte, $utf8)
Write-Host ("Ecrit : src\commandes\EbAiguillage.owl (" + (@(Get-CommandesDesModules $Racine) | ForEach-Object { $_.Noms.Count } | Measure-Object -Sum).Sum + " nom(s) de commande)")
exit 0
