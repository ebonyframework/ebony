# Du nom libre au projet qui compile, contre le VRAI owl.
# Pour chaque nom : les fonctions OWL d'ebony (EbDossierProjet, EbIdentifiantProjet) calculent le dossier et l'identifiant ; on cree ensuite ce
# dossier pour de vrai, on y ecrit un projet.owl dont le bloc est "<identifiant> est un Projet", et on verifie que owl le compile ET l'execute.
# Principe : le mot de l'utilisateur ne devient jamais tel quel un identifiant OWL (prefixe App), donc aucun nom n'est refuse (Liste, Si, Date, Client, EbConfig...).
#
#   .\noms-projet.ps1             rapide : une trentaine de noms delicats (mots reserves d'owl, accents, ligatures, noms de peripheriques Windows...)
#   .\noms-projet.ps1 -Complet    en plus : tout ce qu'owl fournit (owl list keywords / types / globalvars / natives), a reessayer apres chaque nouvelle version d'owl (2 a 3 minutes)
#
# Windows PowerShell 5.1 ou plus. Code de sortie 0 si tout est conforme, 1 sinon. Ce fichier reste ASCII (les accents sont fabriques avec [char]). Travaille dans tmp/ du depot.
#   .\noms-projet.ps1 -Source <fichier>   utilise une copie du module a la place du vrai (controles negatifs : on la casse, le script doit echouer)
param([switch]$Complet, [string]$Source = '')

$racine = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$source = if ($Source -ne '') { $Source } else { Join-Path $racine 'modules\core\outils\commandes\nouveau\EbNomProjet.owl' }
$cedille = [string][char]0xE7
$icirc = [string][char]0xEE
$utf8 = New-Object Text.UTF8Encoding($false)
$echecs = 0
function Echec([string]$Message) { $script:echecs++; Write-Host ("   [ECHEC]  " + $Message) -ForegroundColor Red }
function Ok([string]$Message) { Write-Host ("   [OK]     " + $Message) }

# ATTENTION : en PowerShell les noms de variables ne distinguent PAS les majuscules des minuscules ($e et $E sont la meme variable). Chaque lettre a donc un nom unique.
$eAigu = [string][char]0xE9; $eAiguMaj = [string][char]0xC9; $aGrave = [string][char]0xE0; $oeMaj = [string][char]0x152; $eszett = [string][char]0xDF; $nTilde = [string][char]0xF1; $uAigu = [string][char]0xFA
$cCedilleMaj = [string][char]0xC7; $lBarreMaj = [string][char]0x141; $oAigu = [string][char]0xF3; $zAigu = [string][char]0x17A; $zCaronMaj = [string][char]0x17D; $tCaron = [string][char]0x165; $cCaron = [string][char]0x10D; $iPointMaj = [string][char]0x130; $sVirgule = [string][char]0x219; $yAigu = [string][char]0xFD
# Noms delicats. Les deux derniers champs sont facultatifs : le dossier et l'identifiant ATTENDUS, quand on les connait d'avance.
$noms = @(
    @('liste'), @('Liste'), @('tous'), @('si'), @('or'), @('date'), @('a'), @('class'), @('json'), @('modulo'), @('compile'), @('chaine'), @('element'), @('herite'), @('prive'),
    @('client'), @('Client'), @('eb-config'), @('EbConfig'), @('ebony-demo'),
    @("Caf${eAigu} de la Gare", 'cafe-de-la-gare', 'AppCafeDeLaGare'),
    @("CAF${eAiguMaj} DE LA GARE", 'cafe-de-la-gare', 'AppCafeDeLaGare'),
    @("${eAiguMaj}t${eAigu} 2026", 'ete-2026', 'AppEte2026'),
    @("${cCedilleMaj}${aGrave} et l${aGrave}", 'ca-et-la', 'AppCaEtLa'),
    @("${lBarreMaj}${oAigu}d${zAigu}", 'lodz', 'AppLodz'),
    @("${zCaronMaj}lu${tCaron}ou${cCaron}k${yAigu}", 'zlutoucky', 'AppZlutoucky'),
    @("${iPointMaj}stanbul", 'istanbul', 'AppIstanbul'),
    @("Bra${sVirgule}ov", 'brasov', 'AppBrasov'),
    @("${oeMaj}uvre", 'oeuvre', 'AppOeuvre'),
    @("Stra${eszett}e", 'strasse', 'AppStrasse'),
    @("${nTilde}and${uAigu}", 'nandu', 'AppNandu'),
    @('2D Jeu', '2d-jeu', 'App2dJeu'), @('123', '123', 'App123'),
    @('con', 'con-app', 'AppConApp'), @('nul', 'nul-app', 'AppNulApp'), @('aux'), @('prn'), @('com1'), @('lpt9'),
    @('a/b\c', 'a-b-c', 'AppABC'), @('x.y.z', 'x-y-z', 'AppXYZ'), @('  Mon   App  ', 'mon-app', 'AppMonApp'), @('mon-app', 'mon-app', 'AppMonApp'), @('MonApp', 'monapp', 'AppMonapp')
)

if ($Complet) {
    $motifNom = "^\s{2}([^\s" + [char]0x2500 + "(\[|]+)"
    $vus = @{}; foreach ($n0 in $noms) { $vus[$n0[0]] = $true }
    foreach ($quoi in 'keywords', 'globalvars', 'types', 'natives') {
        owl list $quoi --plain 2>&1 | ForEach-Object { "$_" } | ForEach-Object { if ($_ -match $motifNom) { $Matches[1] } } | Sort-Object -Unique | ForEach-Object {
            if (-not $vus.ContainsKey($_)) { $vus[$_] = $true; $noms += , @($_) }
        }
    }
}

$base = Join-Path $racine ('tmp\noms_projet_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$harnais = Join-Path $base 'harnais'
New-Item -ItemType Directory -Force $harnais | Out-Null

try {
    Write-Host ("owl " + ((owl --version) -join ' ') + " ; " + $noms.Count + " noms")

    # 1. Le harnais OWL : une copie du module, et un projet qui affiche "<rang>|<dossier>|<identifiant>" pour chaque nom.
    Copy-Item $source (Join-Path $harnais 'EbNomProjet.owl')
    # Les noms sont lus dans un fichier (une ligne par nom) : un litteral de tableau OWL est limite a 255 elements.
    [IO.File]::WriteAllText((Join-Path $harnais 'noms.txt'), (($noms | ForEach-Object { $_[0] }) -join "`n"), $utf8)
    $prj = "AppHarnais est un Projet`n`tPROPRIETES`n`t`tLangues = [langueFran${cedille}ais]`n`tFIN`n`ttabNoms est un tableau de cha${icirc}nes = Cha${icirc}neD$([char]0xE9)coupe(fChargeTexte(`"noms.txt`"), Caract(10))`n`tnRang est un entier = 0`n`tPOUR TOUT sNom DE tabNoms`n`t`tnRang += 1`n`t`tsDossier est une cha${icirc}ne = EbDossierProjet(sNom)`n`t`tTrace(nRang + `"|`" + sDossier + `"|`" + EbIdentifiantProjet(sDossier))`n`tFIN`n`tPOUR n = 192 $([char]0xC0) 383`n`t`tTrace(`"A|`" + n + `"|`" + EbSansAccent(Caract(n)))`n`tFIN`nFIN`n"
    [IO.File]::WriteAllText((Join-Path $harnais 'projet.owl'), $prj, $utf8)
    $ErrorActionPreference = 'Continue'
    $sortie = @(owl (Join-Path $harnais 'projet.owl') 2>&1 | ForEach-Object { "$_" })
    $lignes = @($sortie | Where-Object { $_ -match '^\d+\|' })
    if ($lignes.Count -ne $noms.Count) { Echec ("le harnais OWL a rendu " + $lignes.Count + " lignes pour " + $noms.Count + " noms : " + (($sortie | Select-Object -First 3) -join ' / ')); throw 'harnais' }

    # 2. Pour chaque nom : dossier et identifiant attendus, vrai dossier, vrai projet compile et execute.
    $ecarts = New-Object Collections.ArrayList
    $nb = 0
    foreach ($l in $lignes) {
        $p = $l -split '\|', 3
        $nom = $noms[[int]$p[0] - 1]
        $dossier = $p[1]; $ident = $p[2]
        $nb++
        if ($nom.Count -ge 3 -and ($dossier -cne $nom[1] -or $ident -cne $nom[2])) { [void]$ecarts.Add("'" + $nom[0] + "' donne " + $dossier + " / " + $ident + " au lieu de " + $nom[1] + " / " + $nom[2]); continue }
        if ($dossier -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { [void]$ecarts.Add("'" + $nom[0] + "' : dossier non conforme : [$dossier]"); continue }
        if ($ident -notmatch '^App[A-Za-z0-9]+$') { [void]$ecarts.Add("'" + $nom[0] + "' : identifiant non conforme : [$ident]"); continue }
        $dir = Join-Path $base ('p' + $nb + '\' + $dossier)
        New-Item -ItemType Directory -Force $dir | Out-Null
        if (-not [IO.Directory]::Exists($dir)) { [void]$ecarts.Add("'" + $nom[0] + "' : le dossier $dossier n'a pas pu etre cree"); continue }
        $prjNom = "$ident est un Projet`n`tPROPRIETES`n`t`tLangues = [langueFran${cedille}ais]`n`tFIN`n`tTrace(`"ok`")`nFIN`n"
        [IO.File]::WriteAllText((Join-Path $dir 'projet.owl'), $prjNom, $utf8)
        $check = (owl --check (Join-Path $dir 'projet.owl')) -join ' '
        if ($check -notmatch '"errors":\[\]') { [void]$ecarts.Add("'" + $nom[0] + "' : owl --check refuse $ident : " + ([regex]::Match($check, '"message":"([^"]{0,90})').Groups[1].Value)); continue }
        $run = ((owl (Join-Path $dir 'projet.owl') 2>&1) | ForEach-Object { "$_" }) -join ' '
        if ($run -notmatch '^ok') { [void]$ecarts.Add("'" + $nom[0] + "' : l'execution de $ident echoue : " + $run.Substring(0, [Math]::Min(90, $run.Length))); continue }
    }
    if ($ecarts.Count -gt 0) { foreach ($x in $ecarts) { Echec $x } } else { Ok ("les " + $noms.Count + " noms donnent un dossier, un identifiant et un projet que owl compile et execute") }

    # 3. La table des accents contre la decomposition Unicode de .NET, sur les 192 lettres de U+00C0 a U+017F.
    # Seules les lettres que Unicode decompose en lettre ASCII + accent sont comparees ; les autres (ae, oe, d barre, l barre, eth, thorn...) sont verifiees par les tests unitaires.
    $accents = @($sortie | Where-Object { $_ -match '^A\|\d+\|' })
    if ($accents.Count -ne 192) { Echec ("la table des accents a rendu " + $accents.Count + " lignes au lieu de 192") }
    else {
        $diff = New-Object Collections.ArrayList
        $compares = 0
        foreach ($l in $accents) {
            $p = $l -split '\|', 3
            $lettre = [char][int]$p[1]
            $nfd = ([string]$lettre).Normalize([Text.NormalizationForm]::FormD)
            $lettreBase = $nfd.Substring(0, 1)
            if ($nfd.Length -gt 1 -and $lettreBase -cmatch '^[A-Za-z]$') {
                $compares++
                if ($p[2] -cne $lettreBase.ToLower()) { [void]$diff.Add(("U+{0:X4} donne [{1}] au lieu de [{2}]" -f [int]$lettre, $p[2], $lettreBase.ToLower())) }
            }
        }
        if ($diff.Count -gt 0) { foreach ($x in $diff) { Echec $x } }
        elseif ($compares -eq 0) { Write-Host "   [IGNORE] table des accents : la normalisation Unicode n'est pas disponible ici (mode invariant, libicu absent) : rien n'a ete compare" -ForegroundColor Yellow }
        else { Ok ("table des accents : $compares lettres comparees a la decomposition Unicode, aucun ecart") }
    }
}
catch { if ($_.Exception.Message -ne 'harnais') { Echec ("plantage du script : " + $_.Exception.Message) } }
finally {
    # Le nettoyage ne doit jamais echouer en silence : un dossier oublie dans tmp/ est un ecart a part entiere.
    try { Remove-Item -Recurse -Force $base -ErrorAction Stop }
    catch {
        Start-Sleep -Seconds 2
        try { Remove-Item -Recurse -Force $base -ErrorAction Stop } catch { Echec ("nettoyage impossible de $base : " + $_.Exception.Message) }
    }
}

Write-Host ""
if ($echecs -eq 0) { Write-Host "NOMS DE PROJET : CONFORMES" -ForegroundColor Green; exit 0 }
else { Write-Host ("NOMS DE PROJET : " + $echecs + " ECART(S)") -ForegroundColor Red; exit 1 }
