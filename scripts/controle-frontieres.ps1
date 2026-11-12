# Controle : les frontieres entre le coeur et les modules d'ebony, sans lancer owl.
#
# Pourquoi : OWL n'a ni espaces de noms ni imports, donc rien ne l'empeche de laisser un fichier du coeur appeler un module. Une fuite passerait inapercue jusqu'au jour ou
# l'on retire le module (un projet genere qui ne compile plus). Ce controle fige les points de contact connus et echoue des qu'un nouveau apparait.
# Il lit les noms de haut niveau (classes, Collections, interfaces, structures, enumerations, procedures d'une Collection) et cherche leurs references dans le CODE des fichiers
# (commentaires et chaines de caracteres retires, ligne par ligne ; une chaine entre accents graves sur plusieurs lignes n'est pas retiree : approximation connue).
#
# Regles :
#   R1  la bibliotheque d'execution (modules\*\execution\) ne reference aucun nom declare dans l'outillage (src\ et modules\*\outils\) : elle est copiee seule dans les projets generes.
#   R2  hors de modules\db\execution\donnees\ (le module db), seuls deux fichiers referencent un de ses noms : modules\auth\execution\auth\cEbJetons.owl et EbAutorisation.owl
#       (le module auth depend de la base : dependance declaree, dans ce sens seulement). Le coeur, cEbApplication comprise, ne connait PAS la base : il ne connait que le contrat iEbComposant
#       (cycle\EbContratsApplication.owl), et c'est le service genere qui ajoute la base a l'application (cEbServiceBase).
#   R3  hors du module auth (modules\auth\), aucun fichier de la bibliotheque ne reference un nom d'auth.
#   R4  dans l'outillage, seul modules\auth\outils\ (la commande du module) cite un nom d'auth : le coeur ne sait plus ecrire un garde de routes, il insere celui que fournit le manifeste.
#   R5  hors du module auth, seul src\commandes\EbAiguillage.owl (le repartiteur de commandes) appelle un nom declare dans modules\auth\outils\ (la commande token).
#
# Usage : .\scripts\controle-frontieres.ps1 [-Racine <dossier>]       code de sortie 0 si les frontieres sont respectees, 1 sinon. Ce fichier reste ASCII.

param([string]$Racine = '')

if ($Racine -eq '') { $Racine = Split-Path $PSScriptRoot -Parent }
$Racine = (Resolve-Path -LiteralPath $Racine).Path.TrimEnd('\')
$utf8 = New-Object Text.UTF8Encoding($false)

function LitFichier([string]$Chemin) { return [IO.File]::ReadAllText($Chemin, $utf8) }
function CheminRelatif([string]$Chemin) { return $Chemin.Substring($Racine.Length + 1).Replace('\', '/') }

# Les noms de haut niveau declares dans ces fichiers. Un tableau associatif PowerShell ignore la casse, comme OWL.
function NomsDeclares([object[]]$Fichiers) {
    $noms = @{}
    foreach ($f in $Fichiers) {
        $texte = LitFichier $f.FullName
        foreach ($m in [regex]::Matches($texte, '(?m)^\s*(\w+)\s+est\s+une?\s+(Classe|CollectionDeProc\S*dures|Interface|Structure|Enum\S*ration)\b')) { $noms[$m.Groups[1].Value] = $true }
        if ($texte -match '(?m)^\w+\s+est\s+une\s+CollectionDeProc\S*dures') {
            foreach ($m in [regex]::Matches($texte, '(?m)^\s*PROCEDURE\s+(\w+)\s*\(')) { $noms[$m.Groups[1].Value] = $true }
        }
    }
    return $noms
}

# Le code d'un fichier : chaque ligne sans ses chaines ("..." et `...` sur une ligne) ni son commentaire (// jusqu'a la fin de la ligne).
function CodeSeul([string]$Texte) {
    $lignes = foreach ($ligne in ($Texte -split "`r?`n")) {
        $sansChaines = ($ligne -replace '"[^"]*"', '""') -replace '`[^`]*`', '""'
        $sansChaines -replace '//.*$', ''
    }
    return ($lignes -join "`n")
}

# Les noms de la liste qui apparaissent comme mots dans ce texte.
function NomsCites([string]$Texte, [hashtable]$Noms) {
    $trouves = @{}
    foreach ($m in [regex]::Matches($Texte, '\b[A-Za-z_]\w*')) {
        if ($Noms.ContainsKey($m.Value)) { $trouves[$m.Value] = $true }
    }
    return @($trouves.Keys | Sort-Object)
}

$fichiersExecution = @(Get-ChildItem (Join-Path $Racine 'modules') -Recurse -Filter '*.owl' | Where-Object { (CheminRelatif $_.FullName) -like 'modules/*/execution/*' })
$fichiersSrc = @(Get-ChildItem (Join-Path $Racine 'src') -Recurse -Filter '*.owl')
$fichiersOutilsModules = @(Get-ChildItem (Join-Path $Racine 'modules') -Recurse -Filter '*.owl' | Where-Object { (CheminRelatif $_.FullName) -like 'modules/*/outils/*' })
$fichiersOutils = @($fichiersSrc) + @($fichiersOutilsModules)
$fichiersAuthOutils = @($fichiersOutilsModules | Where-Object { (CheminRelatif $_.FullName) -like 'modules/auth/outils/*' })
$fichiersDonnees = @($fichiersExecution | Where-Object { (CheminRelatif $_.FullName) -like 'modules/db/execution/donnees/*' })
$fichiersAuth = @($fichiersExecution | Where-Object { (CheminRelatif $_.FullName) -like 'modules/auth/execution/*' })

$nomsOutils = NomsDeclares $fichiersOutils
$nomsAuthOutils = NomsDeclares $fichiersAuthOutils
$nomsDonnees = NomsDeclares $fichiersDonnees
$nomsAuth = NomsDeclares $fichiersAuth

$problemes = @()
if ($fichiersExecution.Count -eq 0 -or $fichiersSrc.Count -eq 0) { $problemes += "modules\*\execution\ ou src\ est introuvable ou vide dans $Racine : rien n'a ete controle" }
if ($fichiersDonnees.Count -eq 0 -or $nomsDonnees.Count -eq 0) { $problemes += "modules\db\execution\donnees\ est introuvable ou ne declare aucun nom : la regle R2 ne controlerait rien" }
if ($fichiersAuthOutils.Count -eq 0 -or $nomsAuthOutils.Count -eq 0) { $problemes += "modules\auth\outils\ est introuvable ou ne declare aucun nom : la regle R5 ne controlerait rien" }
if ($fichiersAuth.Count -eq 0 -or $nomsAuth.Count -eq 0) { $problemes += "modules\auth\execution\ est introuvable ou ne declare aucun nom : les regles R3 et R4 ne controleraient rien" }

$autorisesDonnees = @('modules/auth/execution/auth/cEbJetons.owl', 'modules/auth/execution/auth/EbAutorisation.owl')

foreach ($f in $fichiersExecution) {
    $rel = CheminRelatif $f.FullName
    $code = CodeSeul (LitFichier $f.FullName)
    foreach ($nom in (NomsCites $code $nomsOutils)) { $problemes += ("R1 " + $rel + " : reference " + $nom + ", declare dans l'outillage, src\ ou modules\*\outils\ (la bibliotheque ne doit rien devoir au generateur)") }
    if ($rel -notlike 'modules/db/execution/donnees/*' -and $autorisesDonnees -notcontains $rel) {
        foreach ($nom in (NomsCites $code $nomsDonnees)) { $problemes += ("R2 " + $rel + " : reference " + $nom + ", declare dans modules\db\execution\donnees\ (module db ; seuls cEbJetons et EbAutorisation, du module auth, le peuvent : le coeur ne connait pas la base)") }
    }
    if ($rel -notlike 'modules/auth/*') {
        foreach ($nom in (NomsCites $code $nomsAuth)) { $problemes += ("R3 " + $rel + " : reference " + $nom + ", declare dans modules\auth\ (le coeur ne connait pas le module)") }
    }
}

foreach ($f in $fichiersOutils) {
    $rel = CheminRelatif $f.FullName
    if ($rel -like 'modules/auth/*') { continue }
    # R5 : le code (hors commentaires et chaines) ne nomme pas la commande du module, sauf le repartiteur de commandes.
    if ($rel -ne 'src/commandes/EbAiguillage.owl') {
        foreach ($nom in (NomsCites (CodeSeul (LitFichier $f.FullName)) $nomsAuthOutils)) { $problemes += ("R5 " + $rel + " : reference " + $nom + ", declare dans modules\auth\outils\ (seul EbAiguillage appelle la commande du module)") }
    }
    # Texte brut, chaines et commentaires compris : le generateur ecrit des noms du module dans le texte qu'il produit, et un commentaire qui en parle est deja un couplage a nommer.
    foreach ($nom in (NomsCites (LitFichier $f.FullName) $nomsAuth)) { $problemes += ("R4 " + $rel + " : cite " + $nom + ", declare dans modules\auth\ (seul modules\auth\outils\ le peut)") }
}

if ($problemes.Count -gt 0) {
    $problemes | ForEach-Object { Write-Output $_ }
    exit 1
}
Write-Output ("Frontieres respectees : {0} fichiers de modules\*\execution\ et {1} d'outillage controles ({2} noms d'outillage, {3} dans donnees, {4} dans auth)." -f $fichiersExecution.Count, $fichiersOutils.Count, $nomsOutils.Count, $nomsDonnees.Count, $nomsAuth.Count)
exit 0
