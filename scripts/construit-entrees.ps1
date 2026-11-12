# Genere un point d'entree REDUIT par commande ebony, dans <Racine>\.commandes\<commande>\ .
#
# Pourquoi : OWL charge et analyse TOUS les .owl du projet a chaque lancement (pas de chargement a la demande, pas de cache) : ebony met 20 a 25 s a demarrer,
# presque tout en compilation, parce que l'aiguillage (EbAiguillage.owl) reference toutes les commandes. Un mini-projet par commande ne contient que les fichiers dont
# CETTE commande depend : doctor 0,9 s, new 1,7 s, make resource 6,7 s au lieu de 26 a 28 s (memes fichiers produits octet pour octet).
#
# Comment : chaque commande est une procedure EbExecute<Nom>() dans son propre fichier. On part de EbPrincipalExecute, "version" et la commande, on ecrit un aiguillage reduit
# (le seul texte genere) et on copie les fichiers ENTIERS dont depend le tout (analyse STATIQUE des noms globaux : classes, interfaces, enumerations,
# structures, procedures de Collections ; commentaires, chaines et acces "x.Methode()" ignores). Un dossier a point est ignore par OWL quand on lance le projet
# complet (ebony.owl a la racine), donc ces copies ne creent pas de doublons ; un projet dont la racine est DANS un dossier a point charge ses propres fichiers (mesure).
#
# Le lanceur (bin\ebony.cmd) utilise ces dossiers s'ils existent et retombe sur ebony.owl sinon (par exemple dans un clone qui ne les a pas generes).
# Resultat jetable : .commandes est ignore par git et regenere par scripts\verifier.ps1 et scripts\construit-archive.ps1. Ne jamais le modifier a la main.
#
# Usage (Windows PowerShell 5.1 ou plus) :
#   .\scripts\construit-entrees.ps1                      depot courant
#   .\scripts\construit-entrees.ps1 -Racine D:\autre     un dossier qui contient src\, modules\ et ebony.owl (ex. une archive extraite)
# Code de sortie : 0 si tout est genere, 1 sinon. Ce fichier reste ASCII.

param(
    [string]$Racine = '',
    [string[]]$Commandes = @()
)

if ($Racine -eq '') { $Racine = Split-Path $PSScriptRoot -Parent }
$Racine = (Resolve-Path -LiteralPath $Racine).Path.TrimEnd('\')
$cheminAiguillage = Join-Path $Racine 'src\commandes\EbAiguillage.owl'
$encodageSansBom = New-Object Text.UTF8Encoding($false)
$cedille = [string][char]0xE7; $icirc = [string][char]0xEE; $eaigu = [string][char]0xE9; $guilGauche = [string][char]0xAB; $guilDroit = [string][char]0xBB
$contenuProjetIsole = "Ebony est un Projet`n`tPROPRIETES`n`t`tLangues = [langueFran" + $cedille + "ais]`n`tFIN`nFIN`n"

function Echec([string]$Message) { Write-Host ("ECHEC : " + $Message) -ForegroundColor Red; exit 1 }

# Sans -Commandes : toutes celles de l'aiguillage EbAiguillage.owl (source unique, voir commandes-ebony.ps1), moins l'aide et version.
. (Join-Path $PSScriptRoot 'commandes-ebony.ps1')
if ($Commandes.Count -eq 0) {
    try { $Commandes = @(Get-CommandesAiguillage $cheminAiguillage) } catch { Echec $_.Exception.Message }
}

# Ne garde que le code : retire les commentaires "//", les chaines "..." et les chaines multi-lignes entre accents graves.
function Get-CodeSansCommentaires([string[]]$LignesDuFichier) {
    $constructeurTexte = New-Object Text.StringBuilder
    $dansAccentGrave = $false
    foreach ($ligneCourante in $LignesDuFichier) {
        $dansGuillemets = $false
        $positionCourante = 0
        while ($positionCourante -lt $ligneCourante.Length) {
            $caractere = $ligneCourante[$positionCourante]
            if ($dansAccentGrave) { if ($caractere -eq '`') { $dansAccentGrave = $false } }
            elseif ($dansGuillemets) { if ($caractere -eq '"') { $dansGuillemets = $false } }
            elseif ($caractere -eq '`') { $dansAccentGrave = $true }
            elseif ($caractere -eq '"') { $dansGuillemets = $true }
            elseif ($caractere -eq '/' -and ($positionCourante + 1) -lt $ligneCourante.Length -and $ligneCourante[$positionCourante + 1] -eq '/') { break }
            else { [void]$constructeurTexte.Append($caractere) }
            $positionCourante++
        }
        [void]$constructeurTexte.Append("`n")
    }
    return $constructeurTexte.ToString()
}

$cheminPointEntree = Join-Path $Racine 'ebony.owl'
if (-not (Test-Path -LiteralPath $cheminAiguillage)) { Echec ("src\commandes\EbAiguillage.owl introuvable sous " + $Racine) }
if (-not (Test-Path -LiteralPath $cheminPointEntree)) { Echec ("ebony.owl introuvable sous " + $Racine) }
$racineAvecBarre = $Racine + '\'

# ---- Index des noms globaux (tout src\ et modules\ [la bibliotheque d'execution de chaque module], sauf EbAiguillage.owl, remplace par un aiguillage reduit) ----
$fichiersCandidats = @(Get-ChildItem (Join-Path $Racine 'src'), (Join-Path $Racine 'modules') -Recurse -Filter '*.owl' -File | Where-Object { $_.FullName -ne $cheminAiguillage } | Sort-Object { $_.FullName.Substring($racineAvecBarre.Length) } )
$cheminsParNom = @{}
$nomsUtilisesParFichier = @{}
foreach ($fichierCandidat in $fichiersCandidats) {
    $lignesLues = @(Get-Content -LiteralPath $fichierCandidat.FullName -Encoding UTF8)
    $fichierEstCollection = $false
    foreach ($ligneLue in $lignesLues) { if ($ligneLue -match '^\w+\s+est\s+une?\s+Collection') { $fichierEstCollection = $true; break } }
    foreach ($ligneLue in $lignesLues) {
        $nomDeclare = $null
        if ($ligneLue -match '^(\w+)\s+est\s+une?\s+\S') { $nomDeclare = $Matches[1] }
        elseif ($ligneLue -match '^\s+(\w+)\s+est\s+une?\s+(?:Interface|Classe|Structure|Enum\S*|\S+num\S*)\s*($|\s)') { $nomDeclare = $Matches[1] }
        elseif ($fichierEstCollection -and $ligneLue -match '^\t(?:PROC\S+)\s+(?:PUBLIQUE\s+)?(?:GLOBALE\s+)?(\w+)\s*\(') { $nomDeclare = $Matches[1] }
        if ($nomDeclare) {
            if (-not $cheminsParNom.ContainsKey($nomDeclare)) { $cheminsParNom[$nomDeclare] = @() }
            if ($cheminsParNom[$nomDeclare] -notcontains $fichierCandidat.FullName) { $cheminsParNom[$nomDeclare] += $fichierCandidat.FullName }
        }
    }
    $nomsDuFichier = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($occurrence in [regex]::Matches((Get-CodeSansCommentaires $lignesLues), '(?<![.:\w])[A-Za-z_]\w*')) { [void]$nomsDuFichier.Add($occurrence.Value) }
    $nomsUtilisesParFichier[$fichierCandidat.FullName] = $nomsDuFichier
}
function Get-FichiersDeclarant([System.Collections.Generic.HashSet[string]]$NomsUtilises) {
    $fichiersTrouves = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($nomUtilise in $NomsUtilises) {
        if ($cheminsParNom.ContainsKey($nomUtilise)) { foreach ($cheminDeclarant in $cheminsParNom[$nomUtilise]) { [void]$fichiersTrouves.Add($cheminDeclarant) } }
    }
    return ,$fichiersTrouves
}
$dependancesDirectes = @{}
foreach ($fichierCandidat in $fichiersCandidats) { $dependancesDirectes[$fichierCandidat.FullName] = Get-FichiersDeclarant $nomsUtilisesParFichier[$fichierCandidat.FullName] }
function Get-FermetureDependances([System.Collections.Generic.HashSet[string]]$FichiersDeDepart) {
    $fichiersVus = New-Object 'System.Collections.Generic.HashSet[string]'
    $pileATraiter = New-Object 'System.Collections.Generic.Stack[string]'
    foreach ($fichierDeDepart in $FichiersDeDepart) { if ($fichiersVus.Add($fichierDeDepart)) { $pileATraiter.Push($fichierDeDepart) } }
    while ($pileATraiter.Count -gt 0) {
        $fichierEnCours = $pileATraiter.Pop()
        if ($dependancesDirectes.ContainsKey($fichierEnCours)) { foreach ($fichierDependance in $dependancesDirectes[$fichierEnCours]) { if ($fichiersVus.Add($fichierDependance)) { $pileATraiter.Push($fichierDependance) } } }
    }
    return ,$fichiersVus
}

# ---- Un point d'entree par commande : fichiers entiers, aucun texte coupe ----
# Chaque commande est une procedure EbExecute<Nom>() dans son propre fichier (modules\core\outils\commandes\...\EbCommande<Nom>.owl) ; le generateur la retrouve par son nom dans l'index.
# Seul l'aiguillage (EbAiguillage.owl : une ligne CAS par commande) est ecrit ici, a partir d'un petit modele : il ne contient que "version" et la commande.
$dossierEntrees = Join-Path $Racine '.commandes'
if (Test-Path -LiteralPath $dossierEntrees) { Remove-Item -LiteralPath $dossierEntrees -Recurse -Force }
New-Item -ItemType Directory -Path $dossierEntrees | Out-Null

$modeleAiguillage = @(
    '// Aiguillage reduit (genere par scripts\construit-entrees.ps1) : cette commande et "version".',
    'EbAiguillage est une CollectionDeProc@E@dures',
    '',
    '@T@PROCEDURE EbExecuteCommande(sCommande est une cha@I@ne)',
    '@T@@T@SELON sCommande',
    '@T@@T@@T@CAS "version"',
    '@T@@T@@T@EbExecuteVersion()',
    '@T@@T@@T@CAS "@CMD@"',
    '@T@@T@@T@EbExecute@NOM@()',
    '@T@@T@@T@AUTRE CAS',
    '@T@@T@@T@ExceptionD@E@clenche(9, "Commande inconnue : @LG@ " + sCommande + " @RG@. Essayez @LG@ ebony aide @RG@.")',
    '@T@@T@FIN',
    '@T@FIN',
    'FIN'
)

foreach ($nomCommande in $Commandes) {
    $nomProcedureCommande = 'EbExecute' + $nomCommande.Substring(0, 1).ToUpperInvariant() + $nomCommande.Substring(1)
    if (-not $cheminsParNom.ContainsKey($nomProcedureCommande)) { Echec ("commande '" + $nomCommande + "' : procedure " + $nomProcedureCommande + " introuvable dans src\ ou modules\") }
    $nomsDeDepart = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($nomChoisi in @('EbPrincipalExecute', 'EbExecuteVersion', $nomProcedureCommande)) { [void]$nomsDeDepart.Add($nomChoisi) }
    $fermeture = [string[]](Get-FermetureDependances (Get-FichiersDeclarant $nomsDeDepart)) | Sort-Object { $_.Substring($racineAvecBarre.Length) }

    $texteAiguillage = New-Object Text.StringBuilder
    foreach ($ligneModele in $modeleAiguillage) {
        $ligneAiguillage = $ligneModele.Replace('@T@', "`t").Replace('@I@', $icirc).Replace('@E@', $eaigu).Replace('@LG@', $guilGauche).Replace('@RG@', $guilDroit).Replace('@CMD@', $nomCommande).Replace('@NOM@', $nomCommande.Substring(0, 1).ToUpperInvariant() + $nomCommande.Substring(1))
        [void]$texteAiguillage.Append($ligneAiguillage + "`n")
    }

    $dossierCommande = Join-Path $dossierEntrees $nomCommande
    New-Item -ItemType Directory -Path $dossierCommande | Out-Null
    [IO.File]::WriteAllText((Join-Path $dossierCommande 'projet.owl'), $contenuProjetIsole, $encodageSansBom)
    Copy-Item -LiteralPath $cheminPointEntree -Destination (Join-Path $dossierCommande 'ebony.owl')
    [IO.File]::WriteAllText((Join-Path $dossierCommande 'EbAiguillage.owl'), $texteAiguillage.ToString(), $encodageSansBom)
    $rangDependance = 0
    foreach ($cheminDependance in $fermeture) {
        $rangDependance++
        Copy-Item -LiteralPath $cheminDependance -Destination (Join-Path $dossierCommande ('d{0:D3}_{1}' -f $rangDependance, (Split-Path $cheminDependance -Leaf)))
    }
    Write-Host ("  {0,-10} {1,3} fichiers" -f $nomCommande, ($fermeture.Count + 3))
}
Write-Host ("Entrees generees dans " + $dossierEntrees)
exit 0
