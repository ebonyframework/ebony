# Test d'integration de bin\ebony-path.ps1 : l'ajout d'ebony au PATH de l'utilisateur, contre le VRAI registre, mais sur une variable de TEST (EBONY_TEST_PATH).
# Le vrai PATH n'est jamais modifie : le test compare sa valeur brute avant et apres, et echoue si elle a change.
# Windows PowerShell 5.1 ou plus.   Usage :   .\tests\integration\chemin-path.ps1       (code de sortie 0 si tout passe, 1 sinon)
# Ce fichier reste ASCII. ATTENTION : les noms de variables PowerShell ne distinguent pas la casse.

$ErrorActionPreference = 'Stop'
$depot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script = Join-Path $depot 'bin\ebony-path.ps1'
$nomVariableTest = 'EBONY_TEST_PATH'

$echecs = 0
function Verifie([string]$Titre, [bool]$Condition, [string]$Detail) {
    if ($Condition) { Write-Host ("  [OK]     " + $Titre) }
    else { Write-Host ("  [ECHEC]  " + $Titre) -ForegroundColor Red; if ($Detail) { Write-Host ("           " + $Detail) }; $script:echecs++ }
}

$cleUtilisateur = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
function LitBrut([string]$Nom) { return $cleUtilisateur.GetValue($Nom, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
function LitGenre([string]$Nom) { return $cleUtilisateur.GetValueKind($Nom).ToString() }
function PoseTest([string]$Valeur) { $cleUtilisateur.SetValue($nomVariableTest, $Valeur, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
function Lance([string]$Dossier, [string]$Base) {
    $sortie = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Dossier $Dossier -Base $Base -NomVariable $nomVariableTest 2>&1 | ForEach-Object { "$_" }
    return @{ Code = $LASTEXITCODE; Sortie = ($sortie -join "`n") }
}
# Mode -Retire : retire ebony du PATH (ebony uninstall), sans dossier a ajouter.
function LanceRetire([string]$Base) {
    $sortie = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Retire -Base $Base -NomVariable $nomVariableTest 2>&1 | ForEach-Object { "$_" }
    return @{ Code = $LASTEXITCODE; Sortie = ($sortie -join "`n") }
}

if ($null -ne (LitBrut $nomVariableTest)) { Write-Host "La variable de test $nomVariableTest existe deja : arret, rien n'est modifie."; exit 1 }
$vraiPathAvant = LitBrut 'Path'
$racineTmp = Join-Path $depot 'tmp'
New-Item -ItemType Directory -Force $racineTmp | Out-Null
$espaceTest = Join-Path $racineTmp ('path_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$base = Join-Path $espaceTest 'Pro grams\ebony'
$bin1 = Join-Path $base '0.1.0\bin'
$bin2 = Join-Path $base '0.2.0\bin'
$autre = Join-Path $espaceTest 'Pro grams\ebony-autre\bin'
try {
    foreach ($d in $bin1, $bin2, $autre) { New-Item -ItemType Directory -Force $d | Out-Null; Set-Content -LiteralPath (Join-Path $d 'ebony.cmd') -Value 'rem test' }

    Write-Host "variable absente : creee avec la seule entree"
    $r = Lance $bin1 $base
    Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
    Verifie "la variable contient exactement le dossier" ((LitBrut $nomVariableTest) -eq $bin1) (LitBrut $nomVariableTest)
    Verifie "type REG_EXPAND_SZ (celui du vrai PATH)" ((LitGenre $nomVariableTest) -eq 'ExpandString') (LitGenre $nomVariableTest)

    Write-Host "deuxieme appel identique : idempotent"
    $r = Lance $bin1 $base
    Verifie "code 0 et dit deja present" (($r.Code -eq 0) -and ($r.Sortie -match 'd.j. dans le PATH')) "code=$($r.Code) $($r.Sortie)"
    Verifie "valeur inchangee" ((LitBrut $nomVariableTest) -eq $bin1) (LitBrut $nomVariableTest)

    Write-Host "autres entrees conservees (dont %VAR% non expanse), ancienne version retiree, nouvelle ajoutee a la fin"
    # L'ancienne version est ecrite EN MAJUSCULES : -eq de PowerShell ignore la casse, mais StartsWith/EndsWith la respectent, donc seule la normalisation en minuscules la fait reconnaitre.
    # $horsBin est sous la base mais n'est pas un dossier bin : il ne doit pas etre retire.
    $horsBin = Join-Path $base '0.3.0\outils'
    PoseTest ('C:\A;%USERPROFILE%\bin;' + $bin1.ToUpperInvariant() + ';' + $autre + ';' + $horsBin + ';C:\Z')
    $r = Lance $bin2 $base
    Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
    $attendu = 'C:\A;%USERPROFILE%\bin;' + $autre + ';' + $horsBin + ';C:\Z;' + $bin2
    Verifie "valeur exacte : 0.1.0 (en majuscules) retiree, ebony-autre et un dossier de la base qui n'est pas un bin conserves, %USERPROFILE% intact, 0.2.0 en dernier" ((LitBrut $nomVariableTest) -eq $attendu) ("attendu : " + $attendu + "`n           obtenu  : " + (LitBrut $nomVariableTest))
    Verifie "annonce le retrait de l'ancienne version" ($r.Sortie -match 'retir.') $r.Sortie
    Verifie "dit d'ouvrir un nouveau terminal" ($r.Sortie -match 'nouveau terminal') $r.Sortie
    Verifie "type conserve" ((LitGenre $nomVariableTest) -eq 'ExpandString') (LitGenre $nomVariableTest)

    Write-Host "entree deja presente mais ecrite autrement (majuscules, barre finale, doublon) : reconnue et dedoublonnee"
    PoseTest ('C:\A;' + $bin2.ToUpperInvariant() + '\;C:\Z;' + $bin2)
    $r = Lance $bin2 $base
    Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
    Verifie "une seule entree 0.2.0 reste, a sa place d'origine (la premiere)" ((LitBrut $nomVariableTest) -eq ('C:\A;' + $bin2.ToUpperInvariant() + '\;C:\Z')) (LitBrut $nomVariableTest)

    Write-Host "type REG_SZ conserve"
    $cleUtilisateur.SetValue($nomVariableTest, 'C:\A', [Microsoft.Win32.RegistryValueKind]::String)
    $r = Lance $bin2 $base
    Verifie "code 0, valeur et type" (($r.Code -eq 0) -and ((LitBrut $nomVariableTest) -eq ('C:\A;' + $bin2)) -and ((LitGenre $nomVariableTest) -eq 'String')) ("code=$($r.Code) " + (LitBrut $nomVariableTest) + ' / ' + (LitGenre $nomVariableTest))

    Write-Host "-Retire : ebony retire du PATH (toutes les versions, meme orphelines), le reste conserve"
    # 0.9.9 n'existe pas sur le disque (entree orpheline) ; $horsBin est sous la base mais n'est pas un bin ; $autre a le meme prefixe de nom ; l'une est en MAJUSCULES.
    PoseTest ('C:\A;%USERPROFILE%\bin;' + $bin1 + ';' + $autre + ';' + (Join-Path $base '0.9.9\bin').ToUpperInvariant() + ';' + $horsBin + ';' + $bin2 + ';C:\Z')
    $r = LanceRetire $base
    Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
    $attendu = 'C:\A;%USERPROFILE%\bin;' + $autre + ';' + $horsBin + ';C:\Z'
    Verifie "valeur exacte : les 3 entrees d'ebony retirees (dont l'orpheline et celle en majuscules), ebony-autre, un dossier non bin et %USERPROFILE% conserves" ((LitBrut $nomVariableTest) -eq $attendu) ("attendu : " + $attendu + "`n           obtenu  : " + (LitBrut $nomVariableTest))
    Verifie "annonce le retrait et dit d'ouvrir un nouveau terminal" (($r.Sortie -match 'ebony retir.') -and ($r.Sortie -match 'nouveau terminal')) $r.Sortie
    Verifie "type conserve" ((LitGenre $nomVariableTest) -eq 'ExpandString') (LitGenre $nomVariableTest)
    Verifie "les dossiers sur le disque ne sont pas touches par ce script" ((Test-Path -LiteralPath $bin1) -and (Test-Path -LiteralPath $bin2)) ''

    Write-Host "-Retire deux fois : idempotent, rien a retirer"
    $r = LanceRetire $base
    Verifie "code 0 et dit qu'il n'y a rien a retirer" (($r.Code -eq 0) -and ($r.Sortie -match 'Aucune entr.e d.ebony')) "code=$($r.Code) $($r.Sortie)"
    Verifie "valeur inchangee" ((LitBrut $nomVariableTest) -eq $attendu) (LitBrut $nomVariableTest)

    Write-Host "-Retire sur une variable absente : rien n'est cree"
    $cleUtilisateur.DeleteValue($nomVariableTest, $false)
    $r = LanceRetire $base
    Verifie "code 0 et la variable n'a pas ete creee" (($r.Code -eq 0) -and ($null -eq (LitBrut $nomVariableTest))) "code=$($r.Code) $($r.Sortie)"

    Write-Host "sans -Retire et sans dossier : refus"
    PoseTest 'C:\A'
    $sortieSansDossier = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Base $base -NomVariable $nomVariableTest 2>&1 | ForEach-Object { "$_" }
    $r = @{ Code = $LASTEXITCODE; Sortie = ($sortieSansDossier -join "`n") }
    Verifie "code 1, dit que le dossier a ajouter n'est pas indique, valeur inchangee" (($r.Code -eq 1) -and ($r.Sortie -match 'pas indiqu') -and ((LitBrut $nomVariableTest) -eq 'C:\A')) "code=$($r.Code) $($r.Sortie)"
    Write-Host "dossier sans ebony.cmd : refus, rien n'est modifie"
    PoseTest 'C:\A'
    $vide = Join-Path $espaceTest 'vide'
    New-Item -ItemType Directory -Force $vide | Out-Null
    $r = Lance $vide $base
    Verifie "code 1 et dit que le PATH n'a pas ete modifie" (($r.Code -eq 1) -and ($r.Sortie -match "n'a pas .t. modifi")) "code=$($r.Code) $($r.Sortie)"
    Verifie "valeur inchangee" ((LitBrut $nomVariableTest) -eq 'C:\A') (LitBrut $nomVariableTest)
}
finally {
    # Nettoyage visible : la variable de test ne doit jamais rester dans le registre de l'utilisateur.
    try { if ($null -ne (LitBrut $nomVariableTest)) { $cleUtilisateur.DeleteValue($nomVariableTest) } } catch { Write-Host ("  [ECHEC]  nettoyage de la variable de test impossible : " + $_.Exception.Message) -ForegroundColor Red; $script:echecs++ }
    if ($null -ne (LitBrut $nomVariableTest)) { Write-Host "  [ECHEC]  la variable de test existe encore" -ForegroundColor Red; $script:echecs++ }
    try { if (Test-Path -LiteralPath $espaceTest) { Remove-Item -Recurse -Force -LiteralPath $espaceTest -ErrorAction Stop } } catch { Write-Host ("  [ECHEC]  nettoyage impossible de " + $espaceTest + " : " + $_.Exception.Message) -ForegroundColor Red; $script:echecs++ }
}

Write-Host ""
Write-Host "le vrai PATH n'a pas ete touche"
Verifie "valeur brute du PATH utilisateur identique avant et apres" ((LitBrut 'Path') -eq $vraiPathAvant) ''
$cleUtilisateur.Close()

Write-Host ""
if ($echecs -eq 0) { Write-Host "TOUT PASSE" -ForegroundColor Green; exit 0 }
else { Write-Host ("$echecs ECHEC(S)") -ForegroundColor Red; exit 1 }
