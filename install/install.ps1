# Installateur d'ebony pour Windows. En une ligne, dans PowerShell (pas besoin d'etre administrateur) :
#
#   irm https://github.com/ebonyframework/ebony/releases/latest/download/install.ps1 | iex
#
# Ce que fait ce script, dans l'ordre :
#   1. verifie que "owl" est dans le PATH (ebony est ecrit en OWL : "ebony install" en a besoin). Il N'INSTALLE PAS OWL ;
#   2. telecharge ebony.zip et ebony.zip.sha256 (la derniere release) dans UN dossier temporaire qu'il cree, et verifie la somme SHA-256 ;
#   3. extrait l'archive dans ce dossier et lance "ebony install" : la copie va dans %LOCALAPPDATA%\Programs\ebony\<version>\ et le dossier bin de cette version
#      entre dans le PATH DE L'UTILISATEUR (jamais celui de la machine) ;
#   4. supprime le dossier temporaire (le seul dossier que ce script supprime ; jamais un clone ni un dossier de l'utilisateur).
# La somme SHA-256 protege d'un telechargement corrompu, pas d'une release compromise : lisez ce script avant de l'executer si vous voulez.
#
# Variables d'environnement facultatives (essais et miroirs) :
#   EBONY_URL_BASE   adresse (https://...) ou DOSSIER local qui contient ebony.zip et ebony.zip.sha256 (defaut : la derniere release de ebonyframework/ebony).
#
# Ce fichier reste ASCII (Windows PowerShell 5.1 ou plus) et ne contient aucun "exit" : lance par "iex", il fermerait le terminal.

function Install-Ebony {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $versionOwlReference = '1.8.1'
    $adresseParDefaut = 'https://github.com/ebonyframework/ebony/releases/latest/download'
    $base = $env:EBONY_URL_BASE
    if ([string]::IsNullOrEmpty($base)) { $base = $adresseParDefaut }

    function Dis([string]$Message) { Write-Host ("ebony : " + $Message) }
    function Avertit([string]$Message) { Write-Host ("ebony : ATTENTION : " + $Message) -ForegroundColor Yellow }
    function Echoue([string]$Message) { Write-Host ("ebony : ECHEC : " + $Message) -ForegroundColor Red }

    # 1. OWL : present dans le PATH, et la version de reference (une autre version n'empeche pas l'installation : "ebony doctor" la signalera).
    $owl = Get-Command owl -ErrorAction SilentlyContinue
    if ($null -eq $owl) {
        Echoue "la commande owl est introuvable dans le PATH. Installez d'abord OWL (https://github.com/followthewhiteowl/neowl), ouvrez un nouveau terminal, puis relancez. Rien n'a ete installe."
        return $false
    }
    $texteVersionOwl = (& owl --version 2>&1 | Select-Object -First 1)
    $trouveVersionOwl = [regex]::Match("$texteVersionOwl", '\d+\.\d+\.\d+')
    if (-not $trouveVersionOwl.Success) { Avertit ("la version d'OWL n'a pas pu etre lue (owl --version : " + $texteVersionOwl + ").") }
    elseif ($trouveVersionOwl.Value -ne $versionOwlReference) { Avertit ("OWL " + $trouveVersionOwl.Value + " est installe ; ebony est verifie avec OWL " + $versionOwlReference + ". L'installation continue.") }

    # 2. Le dossier temporaire : sans accent ni espace (owl n'ouvre pas un chemin absolu accentue en 1.8.1). On essaie le dossier temporaire de l'utilisateur, son nom court 8.3, puis ProgramData.
    function ProblematiqueChemin([string]$Chemin) { return ($Chemin -match '[^\x21-\x7E]') }
    function CheminSur([string]$Chemin) {
        if (-not (ProblematiqueChemin $Chemin)) { return $Chemin }
        try {
            $court = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($Chemin).ShortPath
            if (-not (ProblematiqueChemin $court)) { return $court }
        } catch { }
        return $null
    }
    $racineTravail = $null
    foreach ($candidat in @([IO.Path]::GetTempPath().TrimEnd('\'), $env:ProgramData)) {
        if ([string]::IsNullOrEmpty($candidat)) { continue }
        $sur = CheminSur $candidat
        if ($null -ne $sur) { $racineTravail = $sur; break }
    }
    if ($null -eq $racineTravail) {
        Echoue "aucun dossier temporaire sans accent ni espace n'a pu etre trouve. Telechargez ebony.zip a la main et suivez docs/guides/installation.md. Rien n'a ete installe."
        return $false
    }
    $travail = Join-Path $racineTravail ('ebony-install-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))

    $reussi = $false
    try {
        New-Item -ItemType Directory -Path $travail | Out-Null

        # 3. Le telechargement (ou la copie, si l'adresse de base est un dossier) et la somme SHA-256.
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
        $zip = Join-Path $travail 'ebony.zip'
        $fichierSomme = Join-Path $travail 'ebony.zip.sha256'
        foreach ($element in @(@('ebony.zip', $zip), @('ebony.zip.sha256', $fichierSomme))) {
            if ($base -match '^https?://') {
                Dis ("telechargement de " + $base.TrimEnd('/') + '/' + $element[0])
                Invoke-WebRequest -UseBasicParsing -Uri ($base.TrimEnd('/') + '/' + $element[0]) -OutFile $element[1]
            } else {
                $source = Join-Path $base $element[0]
                if (-not (Test-Path -LiteralPath $source)) { throw ("fichier introuvable : " + $source) }
                Copy-Item -LiteralPath $source -Destination $element[1]
            }
        }
        $sommeAttendue = ((Get-Content -LiteralPath $fichierSomme -TotalCount 1) -split '\s+')[0].ToLowerInvariant()
        if ($sommeAttendue -notmatch '^[0-9a-f]{64}$') { throw "le fichier ebony.zip.sha256 n'a pas la forme attendue (une somme SHA-256 de 64 caracteres)." }
        $sommeReelle = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sommeReelle -ne $sommeAttendue) { throw ("la somme SHA-256 de ebony.zip ne correspond pas (attendue " + $sommeAttendue + ", obtenue " + $sommeReelle + "). Rien n'a ete installe.") }
        Dis "somme SHA-256 verifiee."

        # 4. L'extraction, puis "ebony install" depuis l'archive extraite.
        $extraction = Join-Path $travail 'archive'
        Expand-Archive -LiteralPath $zip -DestinationPath $extraction
        $dossiers = @(Get-ChildItem -LiteralPath $extraction -Directory -Filter 'ebony-*')
        if ($dossiers.Count -ne 1) { throw ("l'archive ne contient pas un seul dossier ebony-<version> (trouve : " + $dossiers.Count + ").") }
        $racineEbony = $dossiers[0].FullName
        $lanceur = Join-Path $racineEbony 'bin\ebony.cmd'
        $fichierVersion = Join-Path $racineEbony 'modules\core\execution\VERSION'
        if (-not (Test-Path -LiteralPath $lanceur) -or -not (Test-Path -LiteralPath $fichierVersion)) { throw "l'archive est incomplete (bin\ebony.cmd ou VERSION absent)." }
        $version = (Get-Content -LiteralPath $fichierVersion -TotalCount 1).Trim()
        Dis ("installation d'ebony " + $version + " (ebony install)")
        # Out-Host : la sortie de la commande s'affiche, elle n'entre pas dans la valeur rendue par la fonction.
        & $lanceur install | Out-Host
        if ($LASTEXITCODE -ne 0) { throw ("ebony install a echoue (code " + $LASTEXITCODE + "). Son message est ci-dessus.") }
        $reussi = $true
    } catch {
        Echoue $_.Exception.Message
    } finally {
        # 5. Le nettoyage : uniquement le dossier que CE script a cree (nom verifie), jamais autre chose.
        if ((Test-Path -LiteralPath $travail) -and ((Split-Path $travail -Leaf) -match '^ebony-install-[0-9a-f]{8}$')) {
            try { Remove-Item -LiteralPath $travail -Recurse -Force -ErrorAction Stop }
            catch { Avertit ("le dossier temporaire " + $travail + " n'a pas pu etre supprime : " + $_.Exception.Message + ". Vous pouvez le supprimer a la main.") }
        }
    }

    if ($reussi) {
        Write-Host ""
        Dis ("ebony " + $version + " est installe. Ouvrez un NOUVEAU terminal (le PATH n'est lu qu'au demarrage d'un terminal), puis lancez : ebony doctor")
    }
    return $reussi
}

$ebonyInstalle = Install-Ebony
# Lance comme fichier (-File), le code de sortie dit le resultat ; lance par "irm | iex", on n'appelle pas exit (il fermerait le terminal).
if (-not $ebonyInstalle -and $PSCommandPath) { exit 1 }
