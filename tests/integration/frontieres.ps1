# Test de scripts\controle-frontieres.ps1 : le controle VOIT les fuites. Sur des copies de modules\ et src\ faites dans le dossier temporaire du systeme (jamais sous le depot : les .owl copies
# y seraient charges avec les notres), on injecte une fuite par regle et l'on verifie que chacune est nommee, qu'un nom cite dans un commentaire ou une chaine de la bibliotheque ne declenche rien,
# et qu'une copie propre passe. Sans owl : quelques secondes. Usage : .\tests\integration\frontieres.ps1     (code de sortie 0 si tout passe, 1 sinon). Ce fichier reste ASCII.

$depot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$controle = Join-Path $depot 'scripts\controle-frontieres.ps1'
$utf8 = New-Object Text.UTF8Encoding($false)
$echecs = 0
$verifications = 0
# Le PowerShell qui execute ce script (powershell.exe sous Windows, pwsh sous Linux) : jamais « powershell » en dur.
$programmePowerShell = (Get-Process -Id $PID).Path
function Verifie([string]$Titre, [bool]$Condition, [string]$Detail) {
    $script:verifications++
    if ($Condition) { Write-Host ("  [OK]     " + $Titre) -ForegroundColor Green }
    else { Write-Host ("  [ECHEC]  " + $Titre) -ForegroundColor Red; if ($Detail -ne '') { Write-Host ("           " + $Detail) }; $script:echecs++ }
}

$zone = Join-Path ([IO.Path]::GetTempPath()) ('ebony_frontieres_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $zone | Out-Null

# Une copie neuve de modules\ et src\ ; on y ajoute AJOUT a la fin du fichier donne (chemin relatif au depot), puis on lance le controle dessus.
function Essai([string]$Nom, [string]$Fichier, [string]$Ajout) {
    $copie = Join-Path $zone $Nom
    New-Item -ItemType Directory -Force $copie | Out-Null
    Copy-Item -LiteralPath (Join-Path $depot 'modules') -Destination (Join-Path $copie 'modules') -Recurse
    Copy-Item -LiteralPath (Join-Path $depot 'src') -Destination (Join-Path $copie 'src') -Recurse
    if ($Fichier -ne '') {
        $chemin = Join-Path $copie $Fichier.Replace('/', '\')
        [IO.File]::AppendAllText($chemin, ("`r`n" + $Ajout + "`r`n"), $utf8)
    }
    $sortie = (& $programmePowerShell -NoProfile -File $controle -Racine $copie 2>&1 | ForEach-Object { "$_" }) -join "`n"
    return @{ Code = $LASTEXITCODE; Sortie = $sortie }
}

try {
    Write-Host "controle des frontieres : le controle voit les fuites"
    $r = Essai 'propre' '' ''
    Verifie "une copie propre passe (code 0)" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)

    $r = Essai 'texte' 'modules/core/execution/http/EbErreurHttp.owl' ('// cEbBaseApplication, EbAutorisation et EbJointChemin sont ici des mots de commentaire' + "`r`n" + 'sEssaiTexte est une chaine = "cEbJetons EbJointChemin cEbBaseApplication"')
    Verifie "un nom cite dans un commentaire ou une chaine de la bibliotheque ne declenche rien" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)

    $r = Essai 'r1' 'modules/core/execution/http/EbErreurHttp.owl' 'sEssaiR1 est une chaine = EbJointChemin("a", "b")'
    Verifie "R1 : la bibliotheque d'un module qui appelle un nom de src\ est refuse et nomme" (($r.Code -eq 1) -and ($r.Sortie -match 'R1 modules/core/execution/http/EbErreurHttp\.owl : reference EbJointChemin')) ("code=" + $r.Code + " " + $r.Sortie)

    $r = Essai 'r2' 'modules/core/execution/journal/cEbJournal.owl' 'oEssaiR2 est un cEbBaseApplication'
    Verifie "R2 : un fichier du coeur qui touche donnees est refuse et nomme" (($r.Code -eq 1) -and ($r.Sortie -match 'R2 modules/core/execution/journal/cEbJournal\.owl : reference cEbBaseApplication')) ("code=" + $r.Code + " " + $r.Sortie)

    $r = Essai 'r2app' 'modules/core/execution/cycle/cEbApplication.owl' 'oEssaiR2App est un cEbBaseApplication'
    Verifie "R2 : cEbApplication non plus ne connait pas la base (elle ne connait que le contrat iEbComposant)" (($r.Code -eq 1) -and ($r.Sortie -match 'R2 modules/core/execution/cycle/cEbApplication\.owl : reference cEbBaseApplication')) ("code=" + $r.Code + " " + $r.Sortie)

    $r = Essai 'r3' 'modules/core/execution/http/EbErreurHttp.owl' 'sEssaiR3 est une chaine = EbIdentiteDuJeton("x")'
    Verifie "R3 : un fichier du coeur qui appelle le module auth est refuse et nomme" (($r.Code -eq 1) -and ($r.Sortie -match 'R3 modules/core/execution/http/EbErreurHttp\.owl : reference EbIdentiteDuJeton')) ("code=" + $r.Code + " " + $r.Sortie)

    $r = Essai 'r4' 'modules/core/outils/commandes/EbCommandeVersion.owl' '// cEbJetons'
    Verifie "R4 : un fichier de src\ qui cite le module auth hors de modules\auth\outils\ est refuse et nomme" (($r.Code -eq 1) -and ($r.Sortie -match 'R4 modules/core/outils/commandes/EbCommandeVersion\.owl : cite cEbJetons')) ("code=" + $r.Code + " " + $r.Sortie)

    $r = Essai 'r5' 'modules/core/outils/commandes/EbCommandeVersion.owl' 'sEssaiR5 est une chaine = EbExecuteToken()'
    Verifie "R5 : un fichier d'outillage autre que le repartiteur qui appelle la commande du module est refuse et nomme" (($r.Code -eq 1) -and ($r.Sortie -match 'R5 modules/core/outils/commandes/EbCommandeVersion\.owl : reference EbExecuteToken')) ("code=" + $r.Code + " " + $r.Sortie)

    $r = Essai 'r5texte' 'modules/core/outils/commandes/EbCommandeVersion.owl' '// EbExecuteToken est cite en commentaire seulement'
    Verifie "R5 : un nom de la commande cite en commentaire ne declenche rien" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)

    $r = Essai 'r4permis' 'modules/auth/outils/commandes/token/EbCommandeToken.owl' '// cEbJetons EbAutorisation'
    Verifie "R4 : modules\auth\outils\ peut citer le module auth (c'est sa commande)" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)

    $r = Essai 'r2permis' 'modules/auth/execution/auth/EbAutorisation.owl' 'oEssaiPermis est un cEbBaseApplication'
    Verifie "R2 : le module auth peut dependre de donnees\ (dependance declaree)" ($r.Code -eq 0) ("code=" + $r.Code + " " + $r.Sortie)
}
finally {
    if (Test-Path -LiteralPath $zone) { Remove-Item -LiteralPath $zone -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($verifications -lt 10) { Write-Host ("`nFRONTIERES : seulement " + $verifications + " verification(s) executee(s) : le test n'a pas pu faire son travail") -ForegroundColor Red; exit 1 }
if ($echecs -gt 0) { Write-Host ("`nFRONTIERES : " + $echecs + " ECHEC(S)") -ForegroundColor Red; exit 1 }
Write-Host "`nFRONTIERES : TOUT PASSE" -ForegroundColor Green
exit 0
