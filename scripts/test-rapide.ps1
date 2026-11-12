# Tests unitaires RAPIDES : chaque suite test_*.owl est lancee dans un dossier isole qui ne contient que les fichiers dont elle depend.
#
# Pourquoi : "owl test" recompile tout le depot pour chaque suite (mesure : 26 a 33 s par suite, quelle que soit sa taille ; 50 suites = 23 a 42 minutes).
# Une suite qui teste une fonction pure n'a besoin que de 2 fichiers (0,2 s) ; la plus lourde en a 30 (11 s). Memes assertions, memes scenarios.
#
# Comment : analyse STATIQUE, sans lancer owl. On releve les noms globaux declares par chaque fichier (classes, interfaces, enumerations, structures, et les
# procedures des Collections), puis les noms utilises par chaque fichier en ignorant commentaires, chaines et acces "x.Methode()". La fermeture des dependances
# d'une suite donne les fichiers a copier. Une dependance manquee donne un plantage visible (jamais un faux vert) : le script le dit et rend le code 1.
#
# Ce qu'une suite isolee ne voit pas, et comment c'est couvert : (1) une variable globale d'un fichier de test qui heurte un autre nom du projet : verifiee ICI par un controle statique
# du projet entier (voir plus bas) ; (2) un nom de classe ou de Collection en double entre fichiers hors tests ("Symbole ambigu") : vu par "owl --check projet.owl", que verifier.ps1 lance.
# Ce script ne lance PAS les tests d'integration du lanceur (scripts\verifier.ps1 les lance).
#
# Usage (Windows PowerShell 5.1 ou plus) :
#   .\scripts\test-rapide.ps1                        toutes les suites
#   .\scripts\test-rapide.ps1 -Filtre EbChemin       les suites dont le NOM DE FICHIER contient ce texte (respecte la casse, comme owl test --filter)
#   .\scripts\test-rapide.ps1 -Detail                une ligne par suite (fichiers, duree, assertions)
#   .\scripts\test-rapide.ps1 -Garde                 conserve les dossiers isoles (diagnostic) et dit ou ils sont
# Code de sortie : 0 si toutes les suites trouvees passent, 1 sinon (y compris si aucune suite ne correspond : "owl test" rend alors un faux vert).
# Ce fichier reste ASCII.

param(
    [string]$Filtre = '',
    [switch]$Detail,
    [switch]$Garde
)

$racineDepot = Split-Path $PSScriptRoot -Parent
$encodageSansBom = New-Object Text.UTF8Encoding($false)
# Un projet minimal : OWL exige "Langues". La cedille est ecrite par son code pour que ce fichier reste ASCII.
$contenuProjetIsole = "Essai est un Projet`n`tPROPRIETES`n`t`tLangues = [langueFran" + [char]0xE7 + "ais]`n`tFIN`nFIN`n"

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

# Les fichiers qui peuvent etre des dependances : tout .owl du depot sauf les suites test_*.owl (et sauf ebony.owl / projet.owl, qui ne declarent rien d'utile).
$fichiersCandidats = @(Get-ChildItem (Join-Path $racineDepot 'src'), (Join-Path $racineDepot 'modules'), (Join-Path $racineDepot 'tests') -Recurse -Filter '*.owl' -File | Where-Object { $_.Name -notlike 'test_*' })
$fichiersDesSuites = @(Get-ChildItem (Join-Path $racineDepot 'tests') -Recurse -Filter 'test_*.owl' -File | Where-Object { $Filtre -eq '' -or $_.Name.Contains($Filtre) } | Sort-Object FullName)

if ($fichiersDesSuites.Count -eq 0) {
    Write-Host ("ECHEC : aucune suite ne correspond au filtre '" + $Filtre + "' (owl test rendrait ALL CLEAR sur 0 suites).") -ForegroundColor Red
    exit 1
}

$cheminsParNom = @{}      # nom global declare -> chemins des fichiers qui le declarent
$nomsUtilisesParFichier = @{}
$tailleParFichier = @{}
foreach ($fichierCandidat in $fichiersCandidats) {
    $lignesLues = @(Get-Content -LiteralPath $fichierCandidat.FullName -Encoding UTF8)
    $tailleParFichier[$fichierCandidat.FullName] = $fichierCandidat.Length
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

# Fichiers (hors celui qui les utilise) qui declarent au moins un des noms donnes.
function Get-FichiersDeclarant([System.Collections.Generic.HashSet[string]]$NomsUtilises, [string]$FichierExclu) {
    $fichiersTrouves = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($nomUtilise in $NomsUtilises) {
        if ($cheminsParNom.ContainsKey($nomUtilise)) {
            foreach ($cheminDeclarant in $cheminsParNom[$nomUtilise]) { if ($cheminDeclarant -ne $FichierExclu) { [void]$fichiersTrouves.Add($cheminDeclarant) } }
        }
    }
    return ,$fichiersTrouves
}

$dependancesDirectes = @{}
foreach ($fichierCandidat in $fichiersCandidats) {
    $dependancesDirectes[$fichierCandidat.FullName] = Get-FichiersDeclarant $nomsUtilisesParFichier[$fichierCandidat.FullName] $fichierCandidat.FullName
}

# Tous les fichiers dont dependent, directement ou non, les fichiers de depart.
function Get-FermetureDependances([System.Collections.Generic.HashSet[string]]$FichiersDeDepart) {
    $fichiersVus = New-Object 'System.Collections.Generic.HashSet[string]'
    $pileATraiter = New-Object 'System.Collections.Generic.Stack[string]'
    foreach ($fichierDeDepart in $FichiersDeDepart) { if ($fichiersVus.Add($fichierDeDepart)) { $pileATraiter.Push($fichierDeDepart) } }
    while ($pileATraiter.Count -gt 0) {
        $fichierEnCours = $pileATraiter.Pop()
        if ($dependancesDirectes.ContainsKey($fichierEnCours)) {
            foreach ($fichierDependance in $dependancesDirectes[$fichierEnCours]) { if ($fichiersVus.Add($fichierDependance)) { $pileATraiter.Push($fichierDependance) } }
        }
    }
    return ,$fichiersVus
}

# Controle du PROJET ENTIER, sans owl (ce qu'une suite isolee ne voit pas) : une variable declaree au niveau d'un fichier de test est une GLOBALE du projet, partagee avec tous les autres fichiers.
# Elle doit (1) commencer par "g", (2) n'etre declaree que dans un seul fichier de test, (3) ne porter le nom d'aucune variable, parametre ou champ declare dans un autre fichier
# (OWL ne distingue ni la casse ni les accents : on compare en minuscules). Sinon le test plante "compile error dans le fichier voisin" (constate avec OWL 1.6.0 et une variable oEnv).
# Les noms en double entre fichiers hors tests (classes, Collections) sont, eux, deja vus par "owl --check projet.owl", que verifier.ps1 lance.
$tousLesFichiersDeTest = @(Get-ChildItem (Join-Path $racineDepot 'tests') -Recurse -Filter 'test_*.owl' -File | Sort-Object FullName)
$fichiersParNomDeclare = @{}     # nom en minuscules -> chemins des fichiers qui le declarent (variable, parametre, champ, classe...)
$globalesParFichierDeTest = @{}  # chemin -> noms des variables de niveau fichier
foreach ($fichierAControler in (@($fichiersCandidats) + $tousLesFichiersDeTest)) {
    $codeAControler = Get-CodeSansCommentaires @(Get-Content -LiteralPath $fichierAControler.FullName -Encoding UTF8)
    foreach ($declarationTrouvee in [regex]::Matches($codeAControler, '(?<![.:\w])([A-Za-z_]\w*)\s+est\s+une?\s')) {
        $nomEnMinuscules = $declarationTrouvee.Groups[1].Value.ToLowerInvariant()
        if (-not $fichiersParNomDeclare.ContainsKey($nomEnMinuscules)) { $fichiersParNomDeclare[$nomEnMinuscules] = @() }
        if ($fichiersParNomDeclare[$nomEnMinuscules] -notcontains $fichierAControler.FullName) { $fichiersParNomDeclare[$nomEnMinuscules] += $fichierAControler.FullName }
    }
    if ($fichierAControler.Name -like 'test_*') {
        $globalesDuFichier = @()
        foreach ($ligneDeCode in ($codeAControler -split "`n")) {
            if ($ligneDeCode -match '^([A-Za-z_]\w*)\s+est\s+une?\s') { $globalesDuFichier += $Matches[1] }
        }
        $globalesParFichierDeTest[$fichierAControler.FullName] = $globalesDuFichier
    }
}
$problemesGlobales = @()
$nombreDeGlobales = 0
foreach ($fichierDeTest in $tousLesFichiersDeTest) {
    foreach ($nomGlobale in $globalesParFichierDeTest[$fichierDeTest.FullName]) {
        $nombreDeGlobales++
        $nomGlobaleEnMinuscules = $nomGlobale.ToLowerInvariant()
        if (-not $nomGlobale.StartsWith('g')) { $problemesGlobales += ("{0} : la globale '{1}' ne commence pas par g" -f $fichierDeTest.Name, $nomGlobale) }
        $autresFichiers = @($fichiersParNomDeclare[$nomGlobaleEnMinuscules] | Where-Object { $_ -ne $fichierDeTest.FullName })
        if ($autresFichiers.Count -gt 0) {
            $nomsDesAutres = ($autresFichiers | ForEach-Object { Split-Path $_ -Leaf }) -join ', '
            $problemesGlobales += ("{0} : la globale '{1}' est aussi declaree dans {2}" -f $fichierDeTest.Name, $nomGlobale, $nomsDesAutres)
        }
    }
}
$controleGlobalesEchoue = ($problemesGlobales.Count -gt 0)
Write-Host ("Controle des globales de fichiers de test (projet entier, sans owl) : {0} globale(s) dans {1} fichier(s) de test" -f $nombreDeGlobales, $tousLesFichiersDeTest.Count)
if ($controleGlobalesEchoue) {
    foreach ($problemeGlobale in $problemesGlobales) { Write-Host ("  ECHEC " + $problemeGlobale) -ForegroundColor Red }
}

$dossierTravail = Join-Path ([IO.Path]::GetTempPath()) ('ebony_test_rapide_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $dossierTravail | Out-Null

$suitesEchouees = @()
$totalAssertions = 0
$totalScenarios = 0
$totalSuitesPassees = 0
$numeroSuite = 0
$debutGeneral = Get-Date
Write-Host ("Tests rapides : {0} suite(s), dossiers isoles dans {1}" -f $fichiersDesSuites.Count, $dossierTravail)

foreach ($fichierSuite in $fichiersDesSuites) {
    $numeroSuite++
    $nomsDeLaSuite = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($occurrence in [regex]::Matches((Get-CodeSansCommentaires @(Get-Content -LiteralPath $fichierSuite.FullName -Encoding UTF8)), '(?<![.:\w])[A-Za-z_]\w*')) { [void]$nomsDeLaSuite.Add($occurrence.Value) }
    $fichiersDeDepart = Get-FichiersDeclarant $nomsDeLaSuite ''
    $fermeture = [string[]](Get-FermetureDependances $fichiersDeDepart) | Sort-Object

    $dossierIsole = Join-Path $dossierTravail ('s{0:D3}' -f $numeroSuite)
    New-Item -ItemType Directory -Path $dossierIsole | Out-Null
    [IO.File]::WriteAllText((Join-Path $dossierIsole 'projet.owl'), $contenuProjetIsole, $encodageSansBom)
    Copy-Item -LiteralPath $fichierSuite.FullName -Destination (Join-Path $dossierIsole $fichierSuite.Name)
    $rangDependance = 0
    foreach ($cheminDependance in $fermeture) {
        $rangDependance++
        Copy-Item -LiteralPath $cheminDependance -Destination (Join-Path $dossierIsole ('d{0:D3}_{1}' -f $rangDependance, (Split-Path $cheminDependance -Leaf)))
    }

    $texteSortie = ''
    Push-Location $dossierIsole
    $dureeSuite = (Measure-Command { $texteSortie = (& owl test -vv 2>&1 | ForEach-Object { "$_" }) -join "`n" }).TotalSeconds
    Pop-Location

    $resultatSuite = [regex]::Match($texteSortie, 'ALL CLEAR \((\d+) suites?, (\d+) assertions?, (\d+) scenarios?\)')
    if ($resultatSuite.Success -and [int]$resultatSuite.Groups[1].Value -eq 1) {
        $totalSuitesPassees++
        $totalAssertions += [int]$resultatSuite.Groups[2].Value
        $totalScenarios += [int]$resultatSuite.Groups[3].Value
        if ($Detail) { Write-Host ("  OK   {0,-38} {1,3} fichiers  {2,5:N1} s  {3,4} assertions" -f $fichierSuite.BaseName, ($fermeture.Count + 1), $dureeSuite, $resultatSuite.Groups[2].Value) }
    }
    else {
        $suitesEchouees += $fichierSuite.BaseName
        Write-Host ("  ECHEC {0} ({1} fichiers, {2:N1} s)" -f $fichierSuite.BaseName, ($fermeture.Count + 1), $dureeSuite) -ForegroundColor Red
        $lignesUtiles = @($texteSortie -split "`n" | Where-Object { $_ -match 'FAIL|Error at|CRASH|STATUS' } | Select-Object -First 8)
        foreach ($ligneUtile in $lignesUtiles) { Write-Host ("       " + $ligneUtile.Trim()) }
        if ($texteSortie -match 'inconnue|inconnu') { Write-Host "       (nom inconnu : dependance manquee par l'analyse statique ? voir -Garde)" }
    }
    if (-not $Garde) { Remove-Item -LiteralPath $dossierIsole -Recurse -Force -ErrorAction SilentlyContinue }
}

$dureeTotale = ((Get-Date) - $debutGeneral).TotalSeconds
if (-not $Garde) { Remove-Item -LiteralPath $dossierTravail -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host ""
Write-Host ("Suites : {0} sur {1} passent ; {2} assertions, {3} scenarios ; {4:N0} s ({5:N1} min)." -f $totalSuitesPassees, $fichiersDesSuites.Count, $totalAssertions, $totalScenarios, $dureeTotale, ($dureeTotale / 60))
if ($Garde) { Write-Host ("Dossiers conserves : " + $dossierTravail) }
if ($suitesEchouees.Count -eq 0 -and -not $controleGlobalesEchoue) { Write-Host "TOUT PASSE" -ForegroundColor Green; exit 0 }
else {
    if ($suitesEchouees.Count -gt 0) { Write-Host ("SUITES EN ECHEC : " + ($suitesEchouees -join ', ')) -ForegroundColor Red }
    if ($controleGlobalesEchoue) { Write-Host ("CONTROLE DES GLOBALES EN ECHEC : {0} probleme(s), voir plus haut" -f $problemesGlobales.Count) -ForegroundColor Red }
    exit 1
}
