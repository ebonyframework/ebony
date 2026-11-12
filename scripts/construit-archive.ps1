# Fabrique l'archive de distribution d'ebony : un zip de ce que "ebony install" copie, et sa somme SHA-256.
#   .\scripts\construit-archive.ps1                       archive du commit HEAD, dans tmp\archives\
#   .\scripts\construit-archive.ps1 -Ref v0.2.0           archive d'un tag ou d'un commit
#   .\scripts\construit-archive.ps1 -Sortie D:\depot\out  autre dossier de sortie (cree s'il n'existe pas)
#
# L'archive est faite avec "git archive" A PARTIR D'UN COMMIT, pas du dossier de travail : elle ne contient jamais un fichier non suivi ni une modification non commitee,
# et refaite depuis le meme commit elle donne les memes octets (la date des fichiers est celle du commit). Le numero de version est celui de modules/core/execution/VERSION DANS CE COMMIT.
# Le contenu est celui du manifeste d'ebony (modules/core/outils/commandes/installation/EbManifeste.owl, lu dans le meme commit) : si le manifeste change, l'archive suit.
# Elle contient aussi .commandes (dossier FACULTATIF du manifeste) : un point d'entree reduit par commande, genere par scripts\construit-entrees.ps1 (doctor, new... en 1 a 7 s au lieu de 25).
# Sortie : ebony-<version>.zip et ebony-<version>.tar.gz (celui de Linux), chacun avec son .sha256 (une ligne "<somme>  <nom>", lisible par sha256sum). Code de sortie 0 si tout est bon, 1 sinon.
# -NomsFixes : ecrit aussi ebony.zip et ebony.tar.gz (memes octets, leur .sha256 porte le nom fixe) : les noms que lisent install.ps1 et install.sh sous releases/latest/download/.
# Le .zip est reproductible (memes octets depuis le meme commit) ; le .tar.gz ne l'est pas (gzip y met la date, tar.exe la date des fichiers extraits).
# Ce fichier reste ASCII (Windows PowerShell 5.1 ou plus).

param(
    [string]$Ref = 'HEAD',
    [string]$Sortie = '',
    [switch]$NomsFixes
)

$ErrorActionPreference = 'Stop'
$depot = Split-Path $PSScriptRoot -Parent
if ($Sortie -eq '') { $Sortie = Join-Path $depot 'tmp\archives' }

function Echec([string]$Message) { Write-Host ("ECHEC : " + $Message) -ForegroundColor Red; exit 1 }

# git ecrit ses messages d'information sur stderr : sous PowerShell 5.1 avec 'Stop', cela leverait. On passe par une fonction qui regarde le code de sortie.
# ATTENTION : PowerShell ne distingue pas la casse, une fonction nommee "Git" s'appellerait elle-meme a l'infini (mesure) : d'ou le nom ExecuteGit et "git.exe".
function ExecuteGit([string[]]$Arguments) {
    $ancien = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $sortie = & git.exe -C $depot @Arguments 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $ancien
    if ($code -ne 0) { Echec ("git " + ($Arguments -join ' ') + " : " + ($sortie -join ' ')) }
    return $sortie
}

$commit = (ExecuteGit @('rev-parse', '--verify', ($Ref + '^{commit}')) | Select-Object -First 1).Trim()
$version = ((ExecuteGit @('show', ($commit + ':modules/core/execution/VERSION'))) -join '').Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { Echec ("modules/core/execution/VERSION vaut '" + $version + "' dans " + $commit.Substring(0, 8) + " : attendu majeur.mineur.correctif") }

# Manifeste lu dans le MEME commit : une source de verite, celle d'ebony install.
$sourceManifeste = (ExecuteGit @('show', ($commit + ':modules/core/outils/commandes/installation/EbManifeste.owl'))) -join "`n"
function Lit-ListeManifeste([string]$NomProcedure) {
    $trouve = [regex]::Match($sourceManifeste, ('PROCEDURE ' + $NomProcedure + '\(\)[^\r\n]*\r?\n\s*RENVOYER [^\r\n(]+\("([^"]+)", ","\)'))
    if (-not $trouve.Success) { Echec ("le manifeste d'ebony (EbManifeste.owl) n'a pas la forme attendue : liste " + $NomProcedure + " introuvable") }
    return $trouve.Groups[1].Value.Split(',')
}
$dossiers = Lit-ListeManifeste 'EbDossiersAInstaller'
$fichiers = Lit-ListeManifeste 'EbFichiersAInstaller'
$facultatifs = Lit-ListeManifeste 'EbDossiersFacultatifs'
$chemins = @($dossiers) + @($fichiers)

$nom = 'ebony-' + $version
$prefixe = $nom + '/'
New-Item -ItemType Directory -Force $Sortie | Out-Null
$zip = Join-Path $Sortie ($nom + '.zip')
$fichierSomme = $zip + '.sha256'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
if (Test-Path -LiteralPath $fichierSomme) { Remove-Item -LiteralPath $fichierSomme -Force }

# Avertit si le dossier de travail differe du commit sur ce qui est archive : l'archive reflete le COMMIT.
$differences = @(ExecuteGit (@('status', '--porcelain', '--') + $chemins))
if ($differences.Count -gt 0) { Write-Host ("ATTENTION : " + $differences.Count + " fichier(s) archivables modifies ou non suivis dans le dossier de travail ; l'archive contient le commit " + $commit.Substring(0, 8) + ", pas ces changements :") -ForegroundColor Yellow; $differences | Select-Object -First 8 | ForEach-Object { Write-Host ("   " + $_) } }

$null = ExecuteGit (@('archive', '--format=zip', ('--prefix=' + $prefixe), '-o', $zip, $commit, '--') + $chemins)

# Points d'entree reduits par commande (dossier facultatif du manifeste, .commandes) : generes a partir de l'archive extraite, donc du COMMIT, puis ajoutes au zip.
# Chaque entree a la date du commit et les entrees sont triees : refaite depuis le meme commit, l'archive donne les memes octets. Le generateur utilise est celui du commit.
$horodatageCommit = [DateTimeOffset]::Parse(((ExecuteGit @('show', '-s', '--format=%cI', $commit)) | Select-Object -First 1).Trim())
$dossierExtraction = Join-Path ([IO.Path]::GetTempPath()) ('ebony_archive_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $dossierExtraction | Out-Null
try {
    Expand-Archive -LiteralPath $zip -DestinationPath $dossierExtraction
    $racineExtraite = Join-Path $dossierExtraction $nom
    # Le generateur du COMMIT (pas celui du dossier de travail) : l'archive d'un commit doit etre faite avec les scripts de ce commit (l'archive, elle, n'embarque pas scripts\).
    $dossierGenerateur = Join-Path $dossierExtraction '_generateur'
    New-Item -ItemType Directory -Path $dossierGenerateur | Out-Null
    foreach ($nomScript in @('construit-entrees.ps1', 'commandes-ebony.ps1')) {
        $texteScript = (ExecuteGit @('show', ($commit + ':scripts/' + $nomScript))) -join "`n"
        [IO.File]::WriteAllText((Join-Path $dossierGenerateur $nomScript), ($texteScript + "`n"), (New-Object Text.UTF8Encoding($false)))
    }
    $generateurDuCommit = Join-Path $dossierGenerateur 'construit-entrees.ps1'
    & powershell.exe -NoProfile -File $generateurDuCommit -Racine $racineExtraite | Out-Host
    if ($LASTEXITCODE -ne 0) { Echec "scripts\construit-entrees.ps1 a echoue" }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $dossierEntrees = Join-Path $racineExtraite '.commandes'
    $prefixeEntrees = $dossierEntrees + '\'
    $fichiersEntrees = @(Get-ChildItem -LiteralPath $dossierEntrees -Recurse -File | ForEach-Object { $_.FullName.Substring($prefixeEntrees.Length) })
    [Array]::Sort($fichiersEntrees, [StringComparer]::Ordinal)
    $archiveEnMiseAJour = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        foreach ($cheminRelatif in $fichiersEntrees) {
            $nomEntree = $prefixe + '.commandes/' + $cheminRelatif.Replace('\', '/')
            $entreeCreee = $archiveEnMiseAJour.CreateEntry($nomEntree, [System.IO.Compression.CompressionLevel]::Optimal)
            $entreeCreee.LastWriteTime = $horodatageCommit
            $fluxEcriture = $entreeCreee.Open()
            $octetsFichier = [IO.File]::ReadAllBytes((Join-Path $dossierEntrees $cheminRelatif))
            $fluxEcriture.Write($octetsFichier, 0, $octetsFichier.Length)
            $fluxEcriture.Dispose()
        }
    } finally { $archiveEnMiseAJour.Dispose() }

    # L'archive de Linux : le meme arbre, en .tar.gz (tar.exe est fourni avec Windows 10 et 11). Sans dependance a unzip cote Linux ; le bit d'execution n'y est pas fiable : install.sh refait chmod +x.
    $tgz = Join-Path $Sortie ($nom + '.tar.gz')
    if (Test-Path -LiteralPath $tgz) { Remove-Item -LiteralPath $tgz -Force }
    $ancienTar = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $sortieTar = & tar.exe -C $dossierExtraction -czf $tgz $nom 2>&1 | ForEach-Object { "$_" }
    $codeTar = $LASTEXITCODE
    $ErrorActionPreference = $ancienTar
    if ($codeTar -ne 0) { Echec ("tar.exe a echoue : " + ($sortieTar -join ' ')) }
    # Controle du .tar.gz : tout sous ebony-<version>/, la version, et bin/ebony en LF seul (un CR casserait le shebang sous Linux).
    $listeTar = @(& tar.exe -tzf $tgz 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -ne '' })
    $horsTar = @($listeTar | Where-Object { -not $_.StartsWith($prefixe) })
    if ($horsTar.Count -gt 0) { Echec ("entrees du .tar.gz hors de " + $prefixe + " : " + (($horsTar | Select-Object -First 3) -join ', ')) }
    foreach ($attenduTar in @(($prefixe + 'bin/ebony'), ($prefixe + 'modules/core/execution/VERSION'), ($prefixe + '.commandes/doctor/ebony.owl'))) { if ($listeTar -notcontains $attenduTar) { Echec ("le .tar.gz ne contient pas " + $attenduTar) } }
    $dossierControleTar = Join-Path $dossierExtraction '_controle_tar'
    New-Item -ItemType Directory -Path $dossierControleTar | Out-Null
    $null = & tar.exe -C $dossierControleTar -xzf $tgz ($prefixe + 'bin/ebony') ($prefixe + 'modules/core/execution/VERSION') 2>&1
    $octetsLanceurSh = [IO.File]::ReadAllBytes((Join-Path $dossierControleTar ($prefixe + 'bin/ebony')))
    if ([Array]::IndexOf($octetsLanceurSh, [byte]13) -ge 0) { Echec "bin/ebony du .tar.gz contient un retour chariot (CR) : le script sh exige du LF" }
    $versionDansTar = ([IO.File]::ReadAllText((Join-Path $dossierControleTar ($prefixe + 'modules/core/execution/VERSION')))).Trim()
    if ($versionDansTar -ne $version) { Echec ("VERSION du .tar.gz vaut " + $versionDansTar + " au lieu de " + $version) }
} finally { Remove-Item -LiteralPath $dossierExtraction -Recurse -Force -ErrorAction SilentlyContinue }

# Controle du contenu : uniquement le manifeste, sous le dossier ebony-<version>/, rien d'autre.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entrees = @($archive.Entries | Where-Object { $_.Name -ne '' } | ForEach-Object { $_.FullName })
    $hors = @($entrees | Where-Object { -not $_.StartsWith($prefixe) })
    if ($hors.Count -gt 0) { Echec ("entrees hors de " + $prefixe + " : " + ($hors | Select-Object -First 3) -join ', ') }
    $racines = @($entrees | ForEach-Object { $_.Substring($prefixe.Length).Split('/')[0] } | Sort-Object -Unique)
    $attendu = @((@($chemins) + @($facultatifs)) | Sort-Object -Unique)
    if (($racines -join ',') -ne ($attendu -join ',')) { Echec ("contenu different du manifeste. Obtenu : " + ($racines -join ', ') + " ; attendu : " + ($attendu -join ', ')) }
    $versionDansZip = $null
    $entreeVersion = $archive.GetEntry($prefixe + 'modules/core/execution/VERSION')
    if ($null -eq $entreeVersion) { Echec "modules/core/execution/VERSION absent de l'archive" }
    $lecteur = New-Object System.IO.StreamReader($entreeVersion.Open()); $versionDansZip = $lecteur.ReadToEnd().Trim(); $lecteur.Dispose()
    if ($versionDansZip -ne $version) { Echec ("modules/core/execution/VERSION de l'archive vaut " + $versionDansZip + " au lieu de " + $version) }
    # Le lanceur doit rester en CRLF (cmd.exe) : on le verifie dans l'archive elle-meme.
    $entreeLanceur = $archive.GetEntry($prefixe + 'bin/ebony.cmd')
    if ($null -eq $entreeLanceur) { Echec "bin/ebony.cmd absent de l'archive" }
    $flux = New-Object System.IO.MemoryStream; $source = $entreeLanceur.Open(); $source.CopyTo($flux); $source.Dispose()
    $octets = $flux.ToArray(); $flux.Dispose()
    $lfSeuls = 0; for ($i = 0; $i -lt $octets.Length; $i++) { if ($octets[$i] -eq 10 -and ($i -eq 0 -or $octets[$i - 1] -ne 13)) { $lfSeuls++ } }
    if ($lfSeuls -gt 0) { Echec ("bin/ebony.cmd contient " + $lfSeuls + " fin(s) de ligne LF seul : cmd.exe exige du CRLF (.gitattributes)") }
} finally { $archive.Dispose() }

$somme = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($fichierSomme, ($somme + '  ' + $nom + '.zip' + "`n"), (New-Object System.Text.UTF8Encoding($false)))
$taille = (Get-Item -LiteralPath $zip).Length

# La somme du .tar.gz, puis (avec -NomsFixes) les copies aux noms fixes : memes octets, et un .sha256 qui porte le nom fixe (c'est lui que verifient les installateurs).
$sommeTgz = (Get-FileHash -LiteralPath $tgz -Algorithm SHA256).Hash.ToLowerInvariant()
$fichierSommeTgz = $tgz + '.sha256'
[IO.File]::WriteAllText($fichierSommeTgz, ($sommeTgz + '  ' + $nom + '.tar.gz' + "`n"), (New-Object System.Text.UTF8Encoding($false)))
$fichiersFixes = @()
if ($NomsFixes) {
    $zipFixe = Join-Path $Sortie 'ebony.zip'; $tgzFixe = Join-Path $Sortie 'ebony.tar.gz'
    Copy-Item -LiteralPath $zip -Destination $zipFixe -Force
    Copy-Item -LiteralPath $tgz -Destination $tgzFixe -Force
    [IO.File]::WriteAllText(($zipFixe + '.sha256'), ($somme + '  ebony.zip' + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText(($tgzFixe + '.sha256'), ($sommeTgz + '  ebony.tar.gz' + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    $fichiersFixes = @($zipFixe, ($zipFixe + '.sha256'), $tgzFixe, ($tgzFixe + '.sha256'))
}

Write-Host ("Archive  : " + $zip)
Write-Host ("Version  : " + $version + "  (commit " + $commit.Substring(0, 12) + ")")
Write-Host ("Contenu  : " + $entrees.Count + " fichiers sous " + $prefixe + " (" + ($attendu -join ', ') + ")")
Write-Host ("Taille   : " + $taille + " octets")
Write-Host ("SHA-256  : " + $somme)
Write-Host ("Somme    : " + $fichierSomme)
Write-Host ("Linux    : " + $tgz + "  (SHA-256 " + $sommeTgz + ")")
foreach ($fichierFixe in $fichiersFixes) { Write-Host ("Nom fixe : " + $fichierFixe) }
exit 0
