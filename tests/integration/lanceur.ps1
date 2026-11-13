# Test d'integration du lanceur : lance bin\ebony.cmd pour de vrai, depuis plusieurs dossiers, et verifie sortie et code de sortie.
# Les tests unitaires (owl test) ne passent pas par le lanceur : ils ne peuvent pas voir qu'ebony perd le dossier de lancement.
# Windows PowerShell 5.1 ou plus.   Usage :   .\tests\integration\lanceur.ps1       (code de sortie 0 si tout passe, 1 sinon)
# Ce fichier reste ASCII : les motifs recherches n'ont pas d'accent.
#
# -Groupe : le test se decoupe en quatre groupes INDEPENDANTS, que scripts\verifier.ps1 lance en parallele (chaque lancement d'ebony recompile tout le projet : 15 a 25 s ; trois
# compilations simultanees coutent ~1,6 fois une seule (mesure avec OWL 1.6.0), d'ou un gain proche de 2). Sans -Groupe (ou 'tous'), les quatre s'executent l'un apres l'autre.
#   base     : aide, versions, doctor depuis plusieurs dossiers (accent, espace, racine de disque) ;
#   projet   : new, env, restore, upgrade (projets generes, clones git) ;
#   make     : make resource et make migration dans un projet genere, compiles et testes avec le vrai owl ;
#   installe : install, copie installee (new, init, request avec un vrai owl serve), uninstall (variable de PATH de TEST).
# Un groupe lance seul travaille dans un dossier temporaire PRIVE : le controle "aucun fichier de code de sortie oublie" ne verrait sinon que les lancements des autres groupes.
param([ValidateSet('tous', 'base', 'projet', 'make', 'installe')][string]$Groupe = 'tous')

$ErrorActionPreference = 'Stop'
# Windows (bin\ebony.cmd) ou Linux (bin/ebony, PowerShell 7) : le lanceur, la facon de le lancer et les dossiers temporaires changent, les assertions sont les memes.
$estWindows = [IO.Path]::DirectorySeparatorChar -eq '\'
# Start-Process : -WindowStyle n'existe pas sous Linux ; ce hashtable, passe avec @fenetreCachee, le met sous Windows seulement.
$fenetreCachee = if ($estWindows) { @{ WindowStyle = 'Hidden' } } else { @{} }
# Le separateur du systeme, pour les chemins relatifs ecrits avec des barres obliques dans les sorties JSON d ebony.
$sepSysteme = [string][IO.Path]::DirectorySeparatorChar
# curl (curl.exe sous Windows : curl y est un alias de PowerShell 5.1) et le fichier nul.
$programmeCurl = if ($estWindows) { 'curl.exe' } else { 'curl' }
$fichierNul = if ($estWindows) { 'NUL' } else { '/dev/null' }
# La ligne de commande d'un processus, pour verifier qu'on n'arrete QUE notre service (Get-CimInstance sous Windows, /proc sous Linux). Vide si le processus n'existe plus.
function CommandeDuProcessus([int]$IdProcessus) {
    if ($estWindows) { return (Get-CimInstance Win32_Process -Filter ("ProcessId=" + $IdProcessus) -ErrorAction SilentlyContinue).CommandLine }
    $fichierCommande = "/proc/$IdProcessus/cmdline"
    if (-not (Test-Path -LiteralPath $fichierCommande)) { return $null }
    return ([IO.File]::ReadAllText($fichierCommande)).Replace([string][char]0, ' ').Trim()
}
$groupeTemp = $null
if ($Groupe -ne 'tous') {
    $groupeTemp = Join-Path ([IO.Path]::GetTempPath()) ('ebony_groupe_' + $Groupe + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $groupeTemp | Out-Null
    $env:TEMP = $groupeTemp; $env:TMP = $groupeTemp; $env:TMPDIR = $groupeTemp
}
$ebony = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) $(if ($estWindows) { 'bin\ebony.cmd' } else { 'bin/ebony' })
$depot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# $Environnement : variables d'environnement ajoutees pour CE processus seulement ; $Lanceur : un autre ebony.cmd que celui du depot (ex. une copie installee).
function Lance([string]$Dossier, [string[]]$Arguments, [hashtable]$Environnement = @{}, [string]$Lanceur = $ebony) {
    $p = New-Object Diagnostics.ProcessStartInfo
    if ($estWindows) {
        $p.FileName = $env:ComSpec
        $p.Arguments = '/c ""' + $Lanceur + '" ' + ($Arguments -join ' ') + '"'
    }
    else {
        # Sous Linux, pas de cmd : chaque argument est passe tel quel. Les guillemets que les appelants ajoutent pour cmd (un argument avec & ou %, un JSON) sont retires.
        $p.FileName = $Lanceur
        foreach ($argumentLance in $Arguments) {
            if ($argumentLance.Length -ge 2 -and $argumentLance.StartsWith('"') -and $argumentLance.EndsWith('"')) { $argumentLance = $argumentLance.Substring(1, $argumentLance.Length - 2) }
            $p.ArgumentList.Add($argumentLance)
        }
    }
    $p.WorkingDirectory = $Dossier
    $p.UseShellExecute = $false
    foreach ($ieCle in $Environnement.Keys) { $p.EnvironmentVariables[$ieCle] = [string]$Environnement[$ieCle] }
    $p.RedirectStandardOutput = $true; $p.RedirectStandardError = $true
    $p.StandardOutputEncoding = [Text.Encoding]::UTF8; $p.StandardErrorEncoding = [Text.Encoding]::UTF8
    $pr = [Diagnostics.Process]::Start($p)
    $sortie = $pr.StandardOutput.ReadToEnd() + $pr.StandardError.ReadToEnd()
    $pr.WaitForExit()
    return @{ Code = $pr.ExitCode; Sortie = $sortie }
}

$echecs = 0
function Verifie([string]$Titre, [bool]$Condition, [string]$Detail) {
    if ($Condition) { Write-Host ("  [OK]     " + $Titre) }
    else { Write-Host ("  [ECHEC]  " + $Titre) -ForegroundColor Red; if ($Detail) { Write-Host ("           " + $Detail) }; $script:echecs++ }
}

# Un dossier de test oublie derriere nous est un ecart a part entiere : le nettoyage ne doit jamais echouer en silence.
function Nettoie([string]$Chemin) {
    if (-not (Test-Path -LiteralPath $Chemin)) { return }
    try { Remove-Item -Recurse -Force -LiteralPath $Chemin -ErrorAction Stop }
    catch {
        Start-Sleep -Seconds 2
        try { Remove-Item -Recurse -Force -LiteralPath $Chemin -ErrorAction Stop } catch { Write-Host ("  [ECHEC]  nettoyage impossible de " + $Chemin + " : " + $_.Exception.Message) -ForegroundColor Red; $script:echecs++ }
    }
}

$espace = Join-Path ([IO.Path]::GetTempPath()) ('ebony test espace ' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $espace | Out-Null
$temp = [IO.Path]::GetTempPath().TrimEnd([IO.Path]::DirectorySeparatorChar)
$racines = if ($estWindows) { @('C:\', 'D:\') | Where-Object { Test-Path $_ } } else { @('/') }

try {
    if ($Groupe -in 'tous', 'base') {
    Write-Host "aide"
    $r = Lance $temp @('aide')
    Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code)"
    Verifie "affiche l'utilisation" ($r.Sortie -match 'Utilisation') $r.Sortie
    Verifie "l'aide liste make (resource, migration, --champs, --dry-run, les types) : c'est elle que lisent les outils" (($r.Sortie -match 'make resource') -and ($r.Sortie -match 'make migration') -and ($r.Sortie -match '--champs') -and ($r.Sortie -match '--dry-run') -and ($r.Sortie -match 'entier, texte, reel, booleen, date, dateheure')) $r.Sortie
    Verifie "l'aide dit que make ecrit le controleur et ne propose plus build" (($r.Sortie -match 'contr.leur .cinq routes REST.') -and ($r.Sortie -notmatch '(?m)^  build ')) $r.Sortie

    Write-Host "commande inconnue"
    $r = Lance $temp @('nimporte')
    Verifie "code 2 (usage incorrect)" ($r.Code -eq 2) "code=$($r.Code)"
    Verifie "message clair" ($r.Sortie -match 'Commande inconnue') $r.Sortie
    Verifie "une seule ligne courte, sans pile d'appels" (($r.Sortie -match '^ebony : ') -and ($r.Sortie -notmatch 'Pile') -and ($r.Sortie -notmatch 'Exception')) $r.Sortie

    Write-Host "sortie lisible par machine"
    $versionDepot = (Get-Content -LiteralPath (Join-Path $depot 'modules\core\execution\VERSION') -TotalCount 1).Trim()
    foreach ($optionVersion in @('--version', '-V', 'version')) {
        $r = Lance $temp @($optionVersion)
        Verifie ("ebony " + $optionVersion + " : code 0 et une ligne 'ebony " + $versionDepot + "'") (($r.Code -eq 0) -and ($r.Sortie.Trim() -ceq ('ebony ' + $versionDepot))) "code=$($r.Code) $($r.Sortie)"
    }
    $r = Lance $temp @('new')
    Verifie "ebony new sans nom : code 2, message court sans pile d'appels" (($r.Code -eq 2) -and ($r.Sortie -match 'Il manque le nom') -and ($r.Sortie -notmatch 'Pile') -and ($r.Sortie -notmatch 'Exception')) "code=$($r.Code) $($r.Sortie)"
    $r = Lance $temp @('nimporte', '--json')
    $json = $null; try { $json = $r.Sortie | ConvertFrom-Json } catch { }
    Verifie "echec avec --json : code 2 et un objet { ok: false, error }" (($r.Code -eq 2) -and ($null -ne $json) -and ($json.ok -eq $false) -and ($json.error -match 'Commande inconnue')) "code=$($r.Code) $($r.Sortie)"
    $r = Lance $temp @('doctor', '--json')
    $json = $null; try { $json = $r.Sortie | ConvertFrom-Json } catch { }
    Verifie "doctor --json : code 0 et un seul objet JSON, rien d'autre sur la sortie" (($r.Code -eq 0) -and ($null -ne $json) -and ($r.Sortie.Trim().StartsWith('{')) -and ($r.Sortie.Trim().EndsWith('}')) -and (($r.Sortie.Trim() -split "`n").Count -eq 1)) "code=$($r.Code) $($r.Sortie)"
    if ($null -ne $json) {
        Verifie "doctor --json : ok, versions d'ebony et d'OWL, zero erreur et zero avertissement" (($json.ok -eq $true) -and ($json.ebony -ceq $versionDepot) -and ($json.owl -match '^\d+\.\d+\.\d+$') -and ($json.errors -eq 0) -and ($json.warnings -eq 0)) $r.Sortie
        $ids = ($json.checks | ForEach-Object { $_.id }) -join ','
        Verifie "doctor --json : cinq verifications, aux identifiants stables et dans l'ordre" ($ids -ceq 'acces-dossier,installation,ecriture,version-owl,etat-projet') $ids
        Verifie "doctor --json : chaque verification a id, status (ok), label, message et correction" (@($json.checks | Where-Object { ($_.status -ceq 'ok') -and $_.label -and $_.message -and ($null -ne $_.correction) }).Count -eq 5) $r.Sortie
    }
    # Depuis une racine de disque, doctor rend un rapport complet (le code depend des droits d'ecriture de CE disque : C:\ est refuse a un utilisateur ordinaire, D:\ non).
    $r = Lance $racines[0] @('doctor', '--json')
    $json = $null; try { $json = $r.Sortie | ConvertFrom-Json } catch { }
    Verifie "doctor --json depuis une racine de disque : un objet JSON, cinq verifications, plus de 'dossier-courant'" (($null -ne $json) -and (@($json.checks).Count -eq 5) -and (@($json.checks | Where-Object { $_.id -ceq 'dossier-courant' }).Count -eq 0)) "code=$($r.Code) $($r.Sortie)"
    Verifie "aucun fichier de code de sortie oublie dans le dossier temporaire" (@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter 'ebony-sortie-*' -ErrorAction SilentlyContinue).Count -eq 0) ''

    foreach ($d in @($depot, $temp, $espace)) {
        Write-Host ("doctor depuis " + $d)
        $r = Lance $d @('doctor')
        Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        Verifie "rapporte le dossier de LANCEMENT (pas la racine du projet d'ebony)" ($r.Sortie.Contains($d)) $r.Sortie
        Verifie "cinq verifications, sans erreur ni avertissement" ($r.Sortie -match 'Bilan : 5 v.rification\(s\), 0 erreur\(s\), 0 avertissement\(s\)') $r.Sortie
        Verifie "l'etat du projet est sans objet hors d'un projet ebony" ($r.Sortie -match '.tat du projet : sans objet') $r.Sortie
        Verifie "la version d'OWL est lue depuis le lanceur" ($r.Sortie -match "Version d'OWL : OWL \d+\.\d+\.\d+") $r.Sortie
        Verifie "l'ecriture est verifiee, sans fichier laisse derriere" (($r.Sortie -match 'ebony peut .crire dans') -and -not (Test-Path -LiteralPath (Join-Path $d '.ebony-doctor-ecriture.tmp'))) $r.Sortie
        Verifie "l'installation d'ebony est retrouvee (bibliotheque des modules)" ($r.Sortie -match "Installation d'ebony" -and $r.Sortie -match 'la biblioth.que des modules est lisible') $r.Sortie
    }

    # Dossier dont le nom contient un accent (fabrique avec [char]0xE8 pour que ce fichier reste ASCII).
    $accent = Join-Path ([IO.Path]::GetTempPath()) ('Mod' + [char]0xE8 + 'les test ' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $accent | Out-Null
    try {
        Write-Host ("doctor depuis un dossier accentue " + $accent)
        # owl 1.7.0 se place dans un dossier accentue (en 1.5.0 et 1.6.0, doctor y signalait une erreur) : le lanceur transmet le dossier de lancement et owl s'y replace.
        $r = Lance $accent @('doctor')
        Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        Verifie "owl s'est place dans le dossier accentue" ($r.Sortie -match 'Acc.s au dossier : owl travaille bien dans ce dossier') $r.Sortie
        Verifie "cinq verifications, sans erreur ni avertissement" ($r.Sortie -match 'Bilan : 5 v.rification\(s\), 0 erreur\(s\), 0 avertissement\(s\)') $r.Sortie
        Verifie "rapporte le dossier accentue" ($r.Sortie.Contains($accent)) $r.Sortie
    }
    finally { Nettoie $accent }

    foreach ($rac in $racines) {
        Write-Host ("doctor depuis la racine " + $rac)
        $r = Lance $rac @('doctor')
        Verifie "rapport complet : cinq verifications, sans pile d'appels" (($r.Sortie -match 'Bilan : 5 v.rification\(s\)') -and ($r.Sortie -notmatch 'Pile') -and ($r.Sortie -notmatch 'Exception')) "code=$($r.Code) $($r.Sortie)"
        Verifie "la racine n'est plus refusee en tant que telle" ($r.Sortie -notmatch "racine d'un disque") $r.Sortie
        Verifie "l'ecriture est jugee sur le disque lui-meme (reussie, ou refusee avec la cause)" ($r.Sortie -match '.criture : ebony (peut|ne peut pas) .crire dans') $r.Sortie
        Verifie "le code suit l'ecriture : 0 si elle reussit, 1 si elle est refusee" (($r.Code -eq 0) -eq ($r.Sortie -match 'ebony peut .crire dans')) "code=$($r.Code)"
    }
    }   # fin du groupe 'base'

    # ---- ebony new : de bout en bout, avec le vrai lanceur, dans des dossiers neufs de tmp/ (ignore par git, meme disque que le depot) ----
    # Les accents sont fabriques avec [char] pour que ce fichier reste ASCII. ATTENTION : les noms de variables PowerShell ne distinguent pas la casse.
    $nwEAigu = [string][char]0xE9
    $nwNomCafe = 'Caf' + $nwEAigu + ' de la Gare'
    # tmp/.travail : un dossier dont le nom commence par un point est ignore par OWL. Les projets generes contiennent une copie de la bibliotheque (modules/*/execution/**/*.owl, dans ebony/ du projet) : sous un dossier visible de tmp/, le projet du depot
    # les chargerait et verrait chaque nom deux fois ("deja utilise par un autre element du projet"). Meme disque que le depot (fRepCree), ignore par git.
    $nwRacineTmp = Join-Path (Join-Path $depot 'tmp') '.travail'
    New-Item -ItemType Directory -Force $nwRacineTmp | Out-Null
    $nwBase = Join-Path $nwRacineTmp ('new_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $nwBase | Out-Null
    function NwDossierNeuf([string]$Nom) { $d1 = Join-Path $nwBase $Nom; New-Item -ItemType Directory -Force $d1 | Out-Null; return $d1 }
        function NiGit([string]$Dir, [string[]]$GitArgs) { $ErrorActionPreference = 'Continue'; & git -C $Dir -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false @GitArgs 2>$null }
        # Empreinte d'un dossier : chemin relatif + SHA-256 de chaque fichier (cachés compris), triés.
        function NiEmpreinte([string]$Dir) {
            $niBase = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd('\')
            @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($niBase.Length + 1) + ' ' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } | Sort-Object) -join "`n"
        }
        # L'empreinte de la bibliotheque d'execution du depot : celle de modules\core\execution et de modules\auth\execution FUSIONNEES, comme le dossier ebony/ d'un projet (les modules sont decouverts dans modules : rien a tenir a la main).
        function NiEmpreinteBibliothequeDepot() {
            $niFusion = Join-Path ([IO.Path]::GetTempPath()) ('ebony_fusion_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Force $niFusion | Out-Null
            try {
                # Les modules se decouvrent comme le fait ebony (cEbBibliothequeInstallee.Modules) : le coeur d'abord, puis chaque dossier de modules\ qui a un execution\, par ordre alphabetique. Aucune liste a tenir ici.
                $niModules = @('core') + @(Get-ChildItem -LiteralPath (Join-Path $depot 'modules') -Directory | Where-Object { ($_.Name -ne 'core') -and (Test-Path -LiteralPath (Join-Path $_.FullName 'execution')) } | Sort-Object Name | ForEach-Object { $_.Name })
                foreach ($niModule in $niModules) { Copy-Item -Path (Join-Path $depot ('modules\' + $niModule + '\execution\*')) -Destination $niFusion -Recurse -Force }
                return (NiEmpreinte $niFusion)
            } finally { Remove-Item -LiteralPath $niFusion -Recurse -Force -ErrorAction SilentlyContinue }
        }
    $nwVersionDepot = (Get-Content -Raw -Encoding UTF8 (Join-Path $depot 'modules\core\execution\VERSION')).Trim()
    try {
        if ($Groupe -in 'tous', 'projet') {
        $nwA = NwDossierNeuf 'a'
        Write-Host "new mon-app"
        $r = Lance $nwA @('new', 'mon-app')
        Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        Verifie "annonce le projet cree, son dossier et son identifiant" (($r.Sortie -match 'Projet cr') -and ($r.Sortie -match 'AppMonApp') -and $r.Sortie.Contains((Join-Path $nwA 'mon-app'))) $r.Sortie
        $nwP = Join-Path $nwA 'mon-app'
        foreach ($f in 'ebony.conf', 'projet.owl', '.gitignore', 'README.md', 'AGENTS.md', 'app\http\ServiceMonApp.owl', 'ebony\VERSION', 'ebony\cycle\cEbApplication.owl', 'ebony\donnees\cEbServiceBase.owl') {
            Verifie ("fichier cree : " + $f) (Test-Path -LiteralPath (Join-Path $nwP $f)) $r.Sortie
        }
        Verifie "ebony\VERSION est la version de la bibliotheque" ((Get-Content -Raw -Encoding UTF8 (Join-Path $nwP 'ebony\VERSION')).Trim() -eq $nwVersionDepot) ''
        $nwConf = Get-Content -Raw -Encoding UTF8 (Join-Path $nwP 'ebony.conf') | ConvertFrom-Json
        Verifie "ebony.conf : version, nom, dossier, identifiant, type, base" (($nwConf.ebony.version -eq $nwVersionDepot) -and ($nwConf.projet.nom -eq 'mon-app') -and ($nwConf.projet.dossier -eq 'mon-app') -and ($nwConf.projet.identifiant -eq 'AppMonApp') -and ($nwConf.projet.type -eq 'api') -and ($nwConf.base.fournisseur -eq 'sqlite')) ($nwConf | ConvertTo-Json -Compress)
        Verifie "aucun BOM ni CRLF dans les fichiers ecrits" (-not (@('ebony.conf', 'projet.owl', '.gitignore', '.env.exemple', '.env.secrets.exemple', 'config\env.json', 'app\http\ServiceMonApp.owl', 'README.md', 'AGENTS.md') | Where-Object { $b = [IO.File]::ReadAllBytes((Join-Path $nwP $_)); ($b.Length -ge 3 -and $b[0] -eq 0xEF) -or ([Text.Encoding]::UTF8.GetString($b).Contains("`r")) })) ''

        Write-Host "  le projet produit, vu par owl"
        Push-Location $nwP
        try {
            $nwCheck = (owl --check projet.owl) -join ' '
            Verifie "owl --check passe" ($nwCheck -match '"errors":\[\]') $nwCheck
            $ErrorActionPreference = 'Continue'
            $nwRun = ((owl projet.owl 2>&1) | ForEach-Object { "$_" }) -join ' '
            $nwRunCode = $LASTEXITCODE
            # Code 0 : owl projet.owl exécute aussi Fermeture() du service, sans FinInitialisation (défaut vu le 2026-11-03 : code 70 si Fermeture suppose l'application posée).
            Verifie "owl projet.owl s'execute, affiche le nom et rend 0" (($nwRun -match '^mon-app : projet cr') -and $nwRunCode -eq 0) ("code $nwRunCode : " + $nwRun)
            $nwTest = ((owl test 2>&1) | ForEach-Object { "$_" }) -join ' '
            Verifie "owl test (aucun test) : ALL CLEAR" ($nwTest -match 'ALL CLEAR') $nwTest
        } finally { $ErrorActionPreference = 'Stop'; Pop-Location }

        Write-Host "  le service produit, lance pour de vrai (owl serve) : GET /api/health"
        function NwPortLibre { $nwEcoute = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $nwEcoute.Start(); $nwNumero = $nwEcoute.LocalEndpoint.Port; $nwEcoute.Stop(); return $nwNumero }
        # Lance « owl serve » dans un projet, interroge un chemin jusqu'a une reponse, puis n'arrete QUE ce processus (PID, ligne de commande verifiee). Les traces vont hors du projet.
        function NwSert([string]$Dossier, [string]$Chemin, [string]$Traces) {
            $nwPort = NwPortLibre
            $nwSortie = Join-Path $Traces 'serve.out.txt'
            $nwErreur = Join-Path $Traces 'serve.err.txt'
            $nwCorps = Join-Path $Traces 'serve.body.txt'
            $nwProc = Start-Process -FilePath owl -ArgumentList @('serve', '--port', $nwPort) -WorkingDirectory $Dossier -PassThru @fenetreCachee -RedirectStandardOutput $nwSortie -RedirectStandardError $nwErreur
            $nwRes = @{ Pret = $false; Code = 0; Corps = ''; Port = $nwPort; Journal = '' }
            try {
                for ($nwEssai = 0; $nwEssai -lt 90 -and -not $nwRes.Pret; $nwEssai++) {
                    $nwCode = & $programmeCurl -s -m 5 -o $nwCorps -w '%{http_code}' ("http://127.0.0.1:" + $nwPort + $Chemin)
                    if ($nwCode -ne '000') { $nwRes.Pret = $true; $nwRes.Code = [int]$nwCode; $nwRes.Corps = [IO.File]::ReadAllText($nwCorps) } else { Start-Sleep -Milliseconds 700 }
                }
            } finally {
                $nwCommande = (CommandeDuProcessus $nwProc.Id)
                if ($nwCommande -and $nwCommande.Contains('serve') -and $nwCommande.Contains([string]$nwPort)) { Stop-Process -Id $nwProc.Id -ErrorAction SilentlyContinue }
                elseif ($nwCommande) { Write-Host ("  [ECHEC]  le processus " + $nwProc.Id + " n'est pas notre service, non arrete : " + $nwCommande) -ForegroundColor Red; $script:echecs++ }
            }
            Start-Sleep -Milliseconds 500
            if (Test-Path -LiteralPath $nwSortie) { $nwRes.Journal = (Get-Content -Raw -Encoding UTF8 -LiteralPath $nwSortie) }
            return $nwRes
        }
        $nwServi = NwSert $nwP '/api/health' $nwA
        Verifie "le service repond (owl serve)" $nwServi.Pret ("port " + $nwServi.Port + " " + $nwServi.Journal)
        Verifie "GET /api/health : 200 et la base (SQLite) repond" (($nwServi.Code -eq 200) -and ($nwServi.Corps -eq '{"statut":"ok","base":"ok"}')) ("code=" + $nwServi.Code + " corps=" + $nwServi.Corps)
        Verifie "le journal du demarrage est du JSON : base ouverte, application demarree" (($nwServi.Journal -match '"message":"Base ouverte"') -and ($nwServi.Journal -match '"message":"Application d.marr.e"')) $nwServi.Journal
        Verifie "la base SQLite a ete creee (storage/app.db)" (Test-Path -LiteralPath (Join-Path $nwP 'storage\app.db')) ''

        Write-Host "  idem avec PostgreSQL absent : le service demarre quand meme, /api/health repond 503"
        $r = Lance $nwA @('new', 'pg-app', '--base', 'postgresql')
        Verifie "new --base postgresql : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $nwPg = Join-Path $nwA 'pg-app'
        [IO.File]::WriteAllText((Join-Path $nwPg '.env'), ("DB_HOTE=127.0.0.1`nDB_PORT=1`n"), (New-Object Text.UTF8Encoding($false)))
        $nwServiPg = NwSert $nwPg '/api/health' $nwA
        Verifie "le service repond malgre la base absente" $nwServiPg.Pret ("port " + $nwServiPg.Port + " " + $nwServiPg.Journal)
        Verifie "GET /api/health : 503 et base indisponible" (($nwServiPg.Code -eq 503) -and ($nwServiPg.Corps -eq '{"statut":"degrade","base":"indisponible"}')) ("code=" + $nwServiPg.Code + " corps=" + $nwServiPg.Corps)
        Verifie "le journal avertit que la base est injoignable" ($nwServiPg.Journal -match '"niveau":"warn"') $nwServiPg.Journal

        Write-Host "  ebony doctor DANS le projet produit"
        $r = Lance $nwP @('doctor')
        Verifie "code 0, cinq verifications, sans erreur ni avertissement" (($r.Code -eq 0) -and ($r.Sortie -match 'Bilan : 5 v.rification\(s\), 0 erreur\(s\), 0 avertissement\(s\)')) "code=$($r.Code) $($r.Sortie)"
        Verifie "l'etat du projet donne la version de ebony/" ($r.Sortie -match ('.tat du projet : ebony/ est en version ' + [regex]::Escape($nwVersionDepot))) $r.Sortie
        Write-Host "  git : ebony/ est ignore"
        # git ecrit des avertissements sur stderr (ex. autocrlf) : sous 'Stop', PowerShell 5.1 les transformerait en exceptions.
        function NwGit([string[]]$GitArgs) { $ErrorActionPreference = 'Continue'; & git -C $nwP @GitArgs 2>$null }
        NwGit @('init', '-q') | Out-Null
        NwGit @('add', '-A') | Out-Null
        $nwIndex = @(NwGit @('diff', '--cached', '--name-only')) | Sort-Object
        $nwAttendu = @('.env.exemple', '.env.secrets.exemple', '.gitignore', 'README.md', 'AGENTS.md', 'app/Composants.owl', 'app/http/ServiceMonApp.owl', 'config/env.json', 'database/migrations/M202611100000_CreeEbJetons.owl', 'ebony.conf', 'projet.owl') | Sort-Object
        Verifie "seuls .env.exemple, .env.secrets.exemple, .gitignore, README.md, AGENTS.md, app/Composants.owl, app/http/ServiceMonApp.owl, config/env.json, database/migrations/M202611100000_CreeEbJetons.owl, ebony.conf et projet.owl seraient commites (ni ebony/ ni storage/)" (($nwIndex -join ',') -eq ($nwAttendu -join ',')) ($nwIndex -join ',')

        Write-Host "new mon-app une seconde fois (le dossier existe, n'est pas vide)"
        $nwHash = (Get-FileHash (Join-Path $nwP 'ebony.conf')).Hash
        $r = Lance $nwA @('new', 'mon-app')
        Verifie "code 1" ($r.Code -eq 1) "code=$($r.Code)"
        Verifie "dit que le dossier existe et n'est pas vide" (($r.Sortie -match 'existe d') -and ($r.Sortie -match "pas vide")) $r.Sortie
        Verifie "ebony.conf est intact" ((Get-FileHash (Join-Path $nwP 'ebony.conf')).Hash -eq $nwHash) ''

        # ebony env : d'abord le projet TEL QUE new le laisse (schema genere, aucun .env : tout doit etre valide), puis avec un schema de test, un .env invalide, un secret.
        # Le schema genere est sauvegarde puis remis en place, et les .env ajoutes sont retires a la fin du bloc : la suite du test commite et clone ce projet.
        Write-Host "env --json juste apres new : le schema genere et les valeurs par defaut"
        $r = Lance $nwP @('env', '--json')
        $nwEnvNeuf = $null
        try { $nwEnvNeuf = ($r.Sortie.Trim()) | ConvertFrom-Json } catch { }
        Verifie "code 0, ok=true, schema=true" (($r.Code -eq 0) -and ($null -ne $nwEnvNeuf) -and ($nwEnvNeuf.ok -eq $true) -and ($nwEnvNeuf.schema -eq $true)) "code=$($r.Code) $($r.Sortie)"
        if ($null -ne $nwEnvNeuf) {
            Verifie "deux variables : DB_FICHIER (SQLite, chemin, defaut storage/app.db), puis AUTH_ROUTES declaree par le manifeste du module auth (liste, defaut protegees)" ((@($nwEnvNeuf.variables).Count -eq 2) -and ($nwEnvNeuf.variables[0].cle -eq 'DB_FICHIER') -and ($nwEnvNeuf.variables[0].type -eq 'chemin') -and ($nwEnvNeuf.variables[0].source -eq 'defaut') -and ($nwEnvNeuf.variables[0].valeur -eq 'storage/app.db') -and ($nwEnvNeuf.variables[1].cle -eq 'AUTH_ROUTES') -and ($nwEnvNeuf.variables[1].type -eq 'liste') -and ($nwEnvNeuf.variables[1].source -eq 'defaut') -and ($nwEnvNeuf.variables[1].valeur -eq 'protegees')) $r.Sortie
        }
        Verifie "le manifeste du module auth est copie dans le projet : ebony\modules\auth.json" (Test-Path -LiteralPath (Join-Path $nwP 'ebony\modules\auth.json')) ''
        Verifie ".env.exemple documente AUTH_ROUTES=protegees" ([IO.File]::ReadAllText((Join-Path $nwP '.env.exemple'), [Text.Encoding]::UTF8).Contains('AUTH_ROUTES=protegees')) ''
        # AUTH_ROUTES est une liste : seules les deux valeurs exactes sont permises (une autre ecriture est refusee au lieu de proteger sans le dire).
        Write-Host "env --json : AUTH_ROUTES, valeur exacte acceptee, autre ecriture refusee"
        try {
            [IO.File]::WriteAllText((Join-Path $nwP '.env'), "AUTH_ROUTES=Ouvertes`n", (New-Object Text.UTF8Encoding $false))
            $r = Lance $nwP @('env', '--json')
            Verifie "AUTH_ROUTES=Ouvertes (autre casse) : code 1" ($r.Code -eq 1) "code=$($r.Code) $($r.Sortie)"
            [IO.File]::WriteAllText((Join-Path $nwP '.env'), "AUTH_ROUTES=ouvertes`n", (New-Object Text.UTF8Encoding $false))
            $r = Lance $nwP @('env', '--json')
            Verifie "AUTH_ROUTES=ouvertes : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        }
        finally {
            Remove-Item -LiteralPath (Join-Path $nwP '.env') -Force -ErrorAction SilentlyContinue
        }
        Write-Host "env --json : un schema, un .env invalide, un secret"
        $nwEnvConfig = Join-Path $nwP 'config'
        $nwEnvSchemaGenere = [IO.File]::ReadAllText((Join-Path $nwEnvConfig 'env.json'), [Text.Encoding]::UTF8)
        $nwEnvSchema = '{"variables":[{"cle":"DB_HOTE","type":"texte","obligatoire":true},{"cle":"DB_PORT","type":"port","defaut":"5432"},{"cle":"DB_MOT_DE_PASSE","type":"texte","secret":true,"obligatoire":true}]}'
        New-Item -ItemType Directory -Force $nwEnvConfig | Out-Null
        [IO.File]::WriteAllText((Join-Path $nwEnvConfig 'env.json'), $nwEnvSchema, (New-Object Text.UTF8Encoding $false))
        [IO.File]::WriteAllText((Join-Path $nwP '.env'), "DB_HOTE=db.exemple.fr`nDB_PORT=abc`n", (New-Object Text.UTF8Encoding $false))
        [IO.File]::WriteAllText((Join-Path $nwP '.env.secrets'), "DB_MOT_DE_PASSE=SecretDeTestAbc123`n", (New-Object Text.UTF8Encoding $false))
        try {
            $r = Lance $nwP @('env', '--json')
            Verifie "code 1 : la configuration est invalide" ($r.Code -eq 1) "code=$($r.Code)"
            $nwEnvLignes = @($r.Sortie -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
            Verifie "une seule ligne JSON, rien d'autre sur la sortie (pas de ligne d'echec en plus)" ($nwEnvLignes.Count -eq 1) $r.Sortie
            $nwEnvJson = $null
            try { $nwEnvJson = $nwEnvLignes[0] | ConvertFrom-Json } catch { }
            Verifie "la ligne est un objet JSON avec ok=false et schema=true" (($null -ne $nwEnvJson) -and ($nwEnvJson.ok -eq $false) -and ($nwEnvJson.schema -eq $true)) $r.Sortie
            if ($null -ne $nwEnvJson) {
                $nwEnvPort = @($nwEnvJson.variables | Where-Object { $_.cle -eq 'DB_PORT' })[0]
                Verifie "DB_PORT : type port, invalide, avec le type attendu dans l'erreur" (($nwEnvPort.type -eq 'port') -and ($nwEnvPort.valide -eq $false) -and ($nwEnvPort.erreur -match 'port')) $r.Sortie
                $nwEnvMdp = @($nwEnvJson.variables | Where-Object { $_.cle -eq 'DB_MOT_DE_PASSE' })[0]
                Verifie "le secret : source .env.secrets, valide, sans valeur" (($nwEnvMdp.source -eq '.env.secrets') -and ($nwEnvMdp.valide -eq $true) -and ($null -eq $nwEnvMdp.valeur)) $r.Sortie
            }
            Verifie "la valeur du secret n'est nulle part dans la sortie" (-not $r.Sortie.Contains('SecretDeTestAbc123')) ''

            Write-Host "env (texte) : meme verdict, jamais la valeur du secret"
            $r = Lance $nwP @('env')
            Verifie "code 1 et la ligne en erreur" (($r.Code -eq 1) -and ($r.Sortie -match 'ERREUR\s+DB_PORT')) "code=$($r.Code) $($r.Sortie)"
            Verifie "la valeur du secret n'est pas dans le texte" (-not $r.Sortie.Contains('SecretDeTestAbc123')) ''

            Write-Host "env --json : configuration corrigee"
            [IO.File]::WriteAllText((Join-Path $nwP '.env'), "DB_HOTE=db.exemple.fr`nDB_PORT=6543`n", (New-Object Text.UTF8Encoding $false))
            $r = Lance $nwP @('env', '--json')
            $nwEnvJson = $null
            try { $nwEnvJson = ($r.Sortie.Trim()) | ConvertFrom-Json } catch { }
            Verifie "code 0, ok=true, aucune erreur" (($r.Code -eq 0) -and ($null -ne $nwEnvJson) -and ($nwEnvJson.ok -eq $true) -and ($nwEnvJson.errors.Count -eq 0)) "code=$($r.Code) $($r.Sortie)"
            if ($null -ne $nwEnvJson) {
                $nwEnvPort = @($nwEnvJson.variables | Where-Object { $_.cle -eq 'DB_PORT' })[0]
                Verifie "DB_PORT : lu dans .env, valeur 6543" (($nwEnvPort.source -eq '.env') -and ($nwEnvPort.valeur -eq '6543')) $r.Sortie
            }
        }
        finally {
            Remove-Item -LiteralPath (Join-Path $nwP '.env'), (Join-Path $nwP '.env.secrets') -Force -ErrorAction SilentlyContinue
            [IO.File]::WriteAllText((Join-Path $nwEnvConfig 'env.json'), $nwEnvSchemaGenere, (New-Object Text.UTF8Encoding $false))
        }
        Verifie "le schema genere est remis en place et les fichiers d'essai sont retires" (([IO.File]::ReadAllText((Join-Path $nwEnvConfig 'env.json'), [Text.Encoding]::UTF8) -ceq $nwEnvSchemaGenere) -and -not (Test-Path -LiteralPath (Join-Path $nwP '.env'))) ''

        Write-Host "env hors d'un projet ebony"
        $nwEnvHors = NwDossierNeuf 'hors-projet'
        $r = Lance $nwEnvHors @('env', '--json')
        Verifie "code 1 et { ok: false, error } qui dit que ce n'est pas un projet ebony" (($r.Code -eq 1) -and ($r.Sortie -match '"ok":false') -and ($r.Sortie -match 'ebony\.conf')) "code=$($r.Code) $($r.Sortie)"

        Write-Host "new sans nom"
        $r = Lance $nwA @('new')
        Verifie "code 2 (usage incorrect)" ($r.Code -eq 2) "code=$($r.Code)"
        Verifie "dit qu'il manque le nom, avec un exemple" (($r.Sortie -match 'Il manque le nom') -and ($r.Sortie -match 'ebony new mon-app')) $r.Sortie

        $nwB = NwDossierNeuf 'b'
        Write-Host "new ??? (aucune lettre latine)"
        $r = Lance $nwB @('new', '???')
        Verifie "code 1" ($r.Code -eq 1) "code=$($r.Code)"
        Verifie "explique le refus" ($r.Sortie -match 'aucune lettre') $r.Sortie
        Verifie "aucun dossier cree" (@(Get-ChildItem -Force $nwB).Count -eq 0) ''

        $nwC = NwDossierNeuf 'c'
        Write-Host "new avec un nom accentue entre guillemets"
        $r = Lance $nwC @('new', ('"' + $nwNomCafe + '"'))
        Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $nwPc = Join-Path $nwC 'cafe-de-la-gare'
        Verifie "dossier cafe-de-la-gare" (Test-Path -LiteralPath $nwPc) $r.Sortie
        $nwOwlC = Get-Content -Raw -Encoding UTF8 (Join-Path $nwPc 'projet.owl')
        Verifie "projet.owl : identifiant AppCafeDeLaGare et nom accentue intact dans Description" (($nwOwlC -match 'AppCafeDeLaGare est un Projet') -and $nwOwlC.Contains('Description = "' + $nwNomCafe + '"')) $nwOwlC
        Verifie "ebony.conf garde le nom accentue" ((Get-Content -Raw -Encoding UTF8 (Join-Path $nwPc 'ebony.conf') | ConvertFrom-Json).projet.nom -eq $nwNomCafe) ''
        Push-Location $nwPc; try { Verifie "owl --check passe" (((owl --check projet.owl) -join ' ') -match '"errors":\[\]') '' } finally { Pop-Location }

        $nwD = NwDossierNeuf 'd'
        Write-Host "new avec le meme nom SANS guillemets (plusieurs arguments)"
        # Parentheses obligatoires : sans elles, PowerShell lit 'Caf' + ($nwEAigu, 'de', ...) et colle tout en une seule chaine.
        $r = Lance $nwD @('new', ('Caf' + $nwEAigu), 'de', 'la', 'Gare')
        Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        Verifie "meme dossier cafe-de-la-gare" (Test-Path -LiteralPath (Join-Path $nwD 'cafe-de-la-gare\projet.owl')) $r.Sortie

        $nwE = NwDossierNeuf 'e'
        Write-Host "new Liste (mot reserve d'OWL) et new con (nom reserve par Windows)"
        $r = Lance $nwE @('new', 'Liste')
        Verifie "Liste : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $nwPl = Join-Path $nwE 'liste'
        Verifie "Liste : identifiant AppListe" ((Test-Path -LiteralPath $nwPl) -and ((Get-Content -Raw -Encoding UTF8 (Join-Path $nwPl 'projet.owl')) -match 'AppListe est un Projet')) $r.Sortie
        Push-Location $nwPl; try { Verifie "Liste : owl --check passe (AppListe compile, Liste non)" (((owl --check projet.owl) -join ' ') -match '"errors":\[\]') '' } finally { Pop-Location }
        $r = Lance $nwE @('new', 'con')
        Verifie "con : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $nwPcon = Join-Path $nwE 'con-app'
        Verifie "con : le dossier con-app existe vraiment" ([IO.Directory]::Exists($nwPcon)) $r.Sortie
        Verifie "con : aucun dossier nomme con n'a ete cree" (-not (@(Get-ChildItem -Force $nwE | Where-Object { $_.Name -eq 'con' }).Count)) ''
        Push-Location $nwPcon; try { Verifie "con : owl --check passe" (((owl --check projet.owl) -join ' ') -match '"errors":\[\]') '' } finally { Pop-Location }

        $nwF = NwDossierNeuf 'f'
        New-Item -ItemType Directory -Force (Join-Path $nwF 'mon-app') | Out-Null
        Write-Host "new dans un dossier cible deja present mais VIDE"
        $r = Lance $nwF @('new', 'mon-app')
        Verifie "accepte : code 0 et projet.owl ecrit" (($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $nwF 'mon-app\projet.owl'))) "code=$($r.Code) $($r.Sortie)"

        Write-Host "new depuis un dossier dont le nom contient une espace"
        $r = Lance $espace @('new', 'mon-app')
        Verifie "code 0 et projet cree dans ce dossier" (($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $espace 'mon-app\projet.owl'))) "code=$($r.Code) $($r.Sortie)"

        # ---- ebony restore : apres un VRAI git clone (ebony/ est ignore par git, donc absent du clone) ----
        Write-Host "restore : projet clone avec git"
        NiGit $nwP @('add', '-A') | Out-Null
        NiGit $nwP @('commit', '-q', '-m', 'projet') | Out-Null
        $nwG = NwDossierNeuf 'g'
        $nwClone = Join-Path $nwG 'copie'
        NiGit $nwG @('clone', '-q', $nwP, 'copie') | Out-Null
        Verifie "le clone a projet.owl et ebony.conf" ((Test-Path -LiteralPath (Join-Path $nwClone 'projet.owl')) -and (Test-Path -LiteralPath (Join-Path $nwClone 'ebony.conf'))) ''
        Verifie "le clone n'a PAS de dossier ebony/ (ignore par git)" (-not (Test-Path -LiteralPath (Join-Path $nwClone 'ebony'))) ''

        Write-Host "doctor dans le clone AVANT restore (ebony/ absent)"
        $r = Lance $nwClone @('doctor')
        Verifie "code 0 (un avertissement ne bloque pas) et un seul avertissement" (($r.Code -eq 0) -and ($r.Sortie -match 'Bilan : 5 v.rification\(s\), 0 erreur\(s\), 1 avertissement\(s\)')) "code=$($r.Code) $($r.Sortie)"
        Verifie "l'etat du projet conseille ebony restore" (($r.Sortie -match '\[ATTENTION\] .tat du projet') -and ($r.Sortie -match 'ebony restore')) $r.Sortie

        Write-Host "restore dans le clone"
        $r = Lance $nwClone @('restore')
        Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        Verifie "annonce la restauration et la version" (($r.Sortie -match 'restaur') -and $r.Sortie.Contains($nwVersionDepot)) $r.Sortie
        Verifie "ebony/ est identique, fichier par fichier, a la bibliotheque des modules fusionnee (et la source est inchangee)" ((NiEmpreinte (Join-Path $nwClone 'ebony')) -eq (NiEmpreinteBibliothequeDepot)) ''
        Push-Location $nwClone
        try { Verifie "owl --check passe dans le clone restaure" (((owl --check projet.owl) -join ' ') -match '"errors":\[\]') '' } finally { Pop-Location }
        $r = Lance $nwClone @('doctor')
        Verifie "ebony doctor passe dans le clone restaure, sans avertissement" (($r.Code -eq 0) -and ($r.Sortie -match '0 erreur\(s\), 0 avertissement\(s\)')) "code=$($r.Code) $($r.Sortie)"

        Write-Host "restore une seconde fois (deja a jour)"
        $niAvant = NiEmpreinte (Join-Path $nwClone 'ebony')
        $r = Lance $nwClone @('restore')
        Verifie "code 0 et dit deja a jour" (($r.Code -eq 0) -and ($r.Sortie -match 'd.j. . jour')) "code=$($r.Code) $($r.Sortie)"
        Verifie "ebony/ est intact" ((NiEmpreinte (Join-Path $nwClone 'ebony')) -eq $niAvant) ''

        Write-Host "restore quand ebony/ est d'une autre version"
        [IO.File]::WriteAllText((Join-Path $nwClone 'ebony\VERSION'), '0.0.5', (New-Object Text.UTF8Encoding($false)))
        $niAvant = NiEmpreinte (Join-Path $nwClone 'ebony')
        $r = Lance $nwClone @('restore')
        Verifie "code 1" ($r.Code -eq 1) "code=$($r.Code)"
        Verifie "cite la version trouvee et dit qu'ebony ne supprime rien" (($r.Sortie -match '0\.0\.5') -and ($r.Sortie -match 'ne supprime rien')) $r.Sortie
        Verifie "ebony/ est intact" ((NiEmpreinte (Join-Path $nwClone 'ebony')) -eq $niAvant) ''

        Write-Host "restore quand ebony.conf demande une autre version"
        $nwH = NwDossierNeuf 'h'
        NiGit $nwH @('clone', '-q', $nwP, 'copie') | Out-Null
        $niConfH = Join-Path $nwH 'copie\ebony.conf'
        $niTexte = [IO.File]::ReadAllText($niConfH, [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($niConfH, $niTexte.Replace('"' + $nwVersionDepot + '"', '"0.0.9"'), (New-Object Text.UTF8Encoding($false)))
        $r = Lance (Join-Path $nwH 'copie') @('restore')
        Verifie "code 1" ($r.Code -eq 1) "code=$($r.Code)"
        Verifie "cite les deux versions" (($r.Sortie -match '0\.0\.9') -and $r.Sortie.Contains($nwVersionDepot)) $r.Sortie
        Verifie "ebony/ n'est pas cree" (-not (Test-Path -LiteralPath (Join-Path $nwH 'copie\ebony'))) ''
        Write-Host "doctor dans ce projet : ebony restore refuserait"
        $r = Lance (Join-Path $nwH 'copie') @('doctor')
        Verifie "code 0, un avertissement qui dit qu'ebony restore refuserait" (($r.Code -eq 0) -and ($r.Sortie -match '\[ATTENTION\] .tat du projet') -and ($r.Sortie -match 'refuserait')) "code=$($r.Code) $($r.Sortie)"
        Write-Host "doctor avec un ebony.conf inutilisable"
        [IO.File]::WriteAllText($niConfH, '{}', (New-Object Text.UTF8Encoding($false)))
        $r = Lance (Join-Path $nwH 'copie') @('doctor')
        Verifie "code 1 et erreur sur l'etat du projet" (($r.Code -eq 1) -and ($r.Sortie -match '\[ERREUR\] +.tat du projet')) "code=$($r.Code) $($r.Sortie)"

        Write-Host "restore quand ebony/ existe mais est vide"
        $nwI = NwDossierNeuf 'i'
        NiGit $nwI @('clone', '-q', $nwP, 'copie') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $nwI 'copie\ebony') | Out-Null
        $r = Lance (Join-Path $nwI 'copie') @('restore')
        Verifie "code 0 et bibliotheque restauree" (($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $nwI 'copie\ebony\VERSION'))) "code=$($r.Code) $($r.Sortie)"

        Write-Host "restore hors d'un projet (pas d'ebony.conf), meme si un dossier parent en a un"
        $r = Lance (Join-Path $nwP 'ebony') @('restore')
        Verifie "code 1" ($r.Code -eq 1) "code=$($r.Code)"
        Verifie "dit que ce n'est pas un projet ebony et propose ebony new" (($r.Sortie -match "pas un projet") -and ($r.Sortie -match 'ebony new')) $r.Sortie
        Verifie "rien n'est cree dans ebony/" (-not (Test-Path -LiteralPath (Join-Path $nwP 'ebony\ebony'))) ''

        # ---- ebony upgrade : un clone dont ebony.conf demande une generation plus ancienne (celle que restore refuse) ----
        Write-Host "upgrade : clone dont ebony.conf demande 0.0.9 (restore refuse)"
        $nwJ = NwDossierNeuf 'j'
        NiGit $nwJ @('clone', '-q', $nwP, 'copie') | Out-Null
        $niCloneJ = Join-Path $nwJ 'copie'
        $niConfJ = Join-Path $niCloneJ 'ebony.conf'
        $niConfOrigine = [IO.File]::ReadAllText((Join-Path $nwP 'ebony.conf'), [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($niConfJ, $niConfOrigine.Replace('"' + $nwVersionDepot + '"', '"0.0.9"'), (New-Object Text.UTF8Encoding($false)))
        $r = Lance $niCloneJ @('restore')
        Verifie "restore refuse (code 1)" ($r.Code -eq 1) "code=$($r.Code)"
        $r = Lance $niCloneJ @('upgrade')
        Verifie "upgrade : code 0, copie la bibliotheque et releve ebony.version" (($r.Code -eq 0) -and ($r.Sortie -match 'copi') -and ($r.Sortie -match 'ebony\.version')) "code=$($r.Code) $($r.Sortie)"
        Verifie "ebony/ est identique, fichier par fichier, a la bibliotheque des modules fusionnee" ((NiEmpreinte (Join-Path $niCloneJ 'ebony')) -eq (NiEmpreinteBibliothequeDepot)) ''
        Verifie "ebony.conf est redevenu EXACTEMENT celui d'ebony new (seule la version a change)" ([IO.File]::ReadAllText($niConfJ, [Text.Encoding]::UTF8) -ceq $niConfOrigine) ''
        $r = Lance $niCloneJ @('doctor')
        Verifie "doctor : plus aucun avertissement" (($r.Code -eq 0) -and ($r.Sortie -match '0 erreur\(s\), 0 avertissement\(s\)')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $niCloneJ @('restore')
        Verifie "restore : desormais deja a jour" (($r.Code -eq 0) -and ($r.Sortie -match 'd.j. . jour')) "code=$($r.Code) $($r.Sortie)"

        Write-Host "upgrade une seconde fois (deja aligne)"
        $niAvantJ = (NiEmpreinte (Join-Path $niCloneJ 'ebony')) + (Get-FileHash -LiteralPath $niConfJ).Hash
        $r = Lance $niCloneJ @('upgrade')
        Verifie "code 0 et dit deja aligne" (($r.Code -eq 0) -and ($r.Sortie -match 'd.j. align')) "code=$($r.Code) $($r.Sortie)"
        Verifie "rien n'a change" (((NiEmpreinte (Join-Path $niCloneJ 'ebony')) + (Get-FileHash -LiteralPath $niConfJ).Hash) -eq $niAvantJ) ''

        Write-Host "upgrade quand ebony/ est d'une autre version (refus, rien supprime ni modifie)"
        [IO.File]::WriteAllText((Join-Path $niCloneJ 'ebony\VERSION'), '0.0.5', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($niConfJ, $niConfOrigine.Replace('"' + $nwVersionDepot + '"', '"0.0.9"'), (New-Object Text.UTF8Encoding($false)))
        $niAvantJ = (NiEmpreinte (Join-Path $niCloneJ 'ebony')) + (Get-FileHash -LiteralPath $niConfJ).Hash
        $r = Lance $niCloneJ @('upgrade')
        Verifie "code 1, cite 0.0.5 et dit qu'ebony ne supprime rien" (($r.Code -eq 1) -and ($r.Sortie -match '0\.0\.5') -and ($r.Sortie -match 'ne supprime rien')) "code=$($r.Code) $($r.Sortie)"
        Verifie "ebony/ et ebony.conf sont intacts" (((NiEmpreinte (Join-Path $niCloneJ 'ebony')) + (Get-FileHash -LiteralPath $niConfJ).Hash) -eq $niAvantJ) ''

        Write-Host "upgrade ne retrograde jamais (ebony.conf demande 9.0.0)"
        $nwK = NwDossierNeuf 'k'
        NiGit $nwK @('clone', '-q', $nwP, 'copie') | Out-Null
        $niConfK = Join-Path $nwK 'copie\ebony.conf'
        [IO.File]::WriteAllText($niConfK, $niConfOrigine.Replace('"' + $nwVersionDepot + '"', '"9.0.0"'), (New-Object Text.UTF8Encoding($false)))
        $niHashK = (Get-FileHash -LiteralPath $niConfK).Hash
        $r = Lance (Join-Path $nwK 'copie') @('upgrade')
        Verifie "code 1, cite 9.0.0 et dit qu'upgrade ne retrograde pas" (($r.Code -eq 1) -and ($r.Sortie -match '9\.0\.0') -and ($r.Sortie -match 'r.trograde')) "code=$($r.Code) $($r.Sortie)"
        Verifie "rien n'est ecrit (ebony.conf intact, ebony/ non cree)" (((Get-FileHash -LiteralPath $niConfK).Hash -eq $niHashK) -and -not (Test-Path -LiteralPath (Join-Path $nwK 'copie\ebony'))) ''

        Write-Host "upgrade hors d'un projet"
        $r = Lance $nwB @('upgrade')
        Verifie "code 1, pas un projet ebony" (($r.Code -eq 1) -and ($r.Sortie -match 'pas un projet') -and ($r.Sortie -match 'ebony new')) "code=$($r.Code) $($r.Sortie)"

        }   # fin du groupe 'projet'
        if ($Groupe -in 'tous', 'make') {
        # ---- ebony make : une ressource et une migration dans un projet genere, COMPILEES et TESTEES contre le vrai owl (un faux disque ne montre pas que le code genere compile) ----
        # Le service genere reste EN PLACE pendant owl test : il ne declare plus de variable de bloc d'une classe du projet (l'application unique vit dans cEbServiceApplication, un membre GLOBAL), ce qui faisait planter
        # owl test avec owl 1.5.0 a 1.7.0 ("Variable inconnue 'cEbLectureEnvReelle'"). Verifie a la main avec OWL 1.7.0 : owl test ALL CLEAR avec le service present.
        Write-Host "make : une ressource et une migration dans un projet genere"
        $mkA = NwDossierNeuf 'make'
        $r = Lance $mkA @('new', 'boutique')
        Verifie "new boutique : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkP = Join-Path $mkA 'boutique'
        $mkChamps = 'id:entier*,nom:texte,email:texte?,actif:booleen,note:reel,naissance:date?'

        Write-Host "  make resource --dry-run --json : dit ce qui serait cree, n'ecrit rien"
        $r = Lance $mkP @('make', 'resource', 'Client', '--champs', $mkChamps, '--dry-run', '--json')
        Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkJson = $null; try { $mkJson = $r.Sortie.Trim() | ConvertFrom-Json } catch { }
        Verifie "une seule ligne JSON : ok, command, name, table, dryRun" (($r.Sortie.Trim() -notmatch "[\r\n]") -and $mkJson -and ($mkJson.ok -eq $true) -and ($mkJson.command -eq 'make resource') -and ($mkJson.name -eq 'Client') -and ($mkJson.table -eq 'clients') -and ($mkJson.dryRun -eq $true)) $r.Sortie
        Verifie "created : dix fichiers, kept vide" ($mkJson -and (@($mkJson.created).Count -eq 10) -and (@($mkJson.kept).Count -eq 0) -and (@($mkJson.created)[0] -eq 'app/domaine/client/cClient.owl')) $r.Sortie
        Verifie "rien n'est ecrit : ni app\domaine ni tests" (-not (Test-Path -LiteralPath (Join-Path $mkP 'app\domaine')) -and -not (Test-Path -LiteralPath (Join-Path $mkP 'tests'))) ''

        Write-Host "  make resource Client"
        $r = Lance $mkP @('make', 'resource', 'Client', '--champs', $mkChamps, '--json')
        Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkJson = $null; try { $mkJson = $r.Sortie.Trim() | ConvertFrom-Json } catch { }
        Verifie "dryRun faux, dix fichiers crees" ($mkJson -and ($mkJson.dryRun -eq $false) -and (@($mkJson.created).Count -eq 10)) $r.Sortie
        Verifie "les dix fichiers existent, chemins relatifs au projet" (-not (@($mkJson.created) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $mkP ($_ -replace '/', '\'))) })) $r.Sortie
        Verifie "aucun BOM ni CRLF dans les fichiers ecrits" (-not (@($mkJson.created) | Where-Object { $b = [IO.File]::ReadAllBytes((Join-Path $mkP ($_ -replace '/', '\'))); ($b.Length -ge 3 -and $b[0] -eq 0xEF) -or ([Text.Encoding]::UTF8.GetString($b).Contains("`r")) })) ''
        $mkEntite = Join-Path $mkP 'app\domaine\client\cClient.owl'
        $mkHashEntite = (Get-FileHash -LiteralPath $mkEntite).Hash

        Write-Host "  make resource Bon de commande : nom en plusieurs mots, cle texte, mots reserves d'owl, colonne avec espaces"
        $r = Lance $mkP @('make', 'resource', 'Bon', 'de', 'commande', '--champs', '"code:texte*,Date:date,order:entier@clients,etat:texte?,libelle:texte,Date de livraison:date?,table:texte"', '--json')
        Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkJson2 = $null; try { $mkJson2 = $r.Sortie.Trim() | ConvertFrom-Json } catch { }
        Verifie "name = Bon de commande, table bon_de_commandes, dossier bon-de-commande" ($mkJson2 -and ($mkJson2.name -eq 'Bon de commande') -and ($mkJson2.table -eq 'bon_de_commandes') -and (@($mkJson2.created)[0] -eq 'app/domaine/bon-de-commande/cBonDeCommande.owl')) $r.Sortie

        Write-Host "  make migration CreeClients"
        $r = Lance $mkP @('make', 'migration', 'CreeClients', '--champs', $mkChamps, '--json')
        Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkJson3 = $null; try { $mkJson3 = $r.Sortie.Trim() | ConvertFrom-Json } catch { }
        Verifie "migration datee et son test" ($mkJson3 -and ($mkJson3.command -eq 'make migration') -and ($mkJson3.table -eq 'clients') -and (@($mkJson3.created).Count -eq 2) -and (@($mkJson3.created)[0] -match '^database/migrations/M\d{12}_CreeClients\.owl$')) $r.Sortie
        Verifie "la note parle d'ebony migrate" ($mkJson3 -and ((@($mkJson3.notes) -join ' ') -match 'migrate')) $r.Sortie

        # Le formateur canonique d'owl ne trouve rien a redire aux fichiers generes (alignement, espaces) : ils ressemblent a ce qu'ecrirait l'utilisateur.
        Push-Location $mkP
        try {
            $mkNonConformes = @(@($mkJson.created) + @($mkJson2.created) + @($mkJson3.created) | ForEach-Object { $ErrorActionPreference = 'Continue'; $null = (owl fmt --check $_.Replace('/', $sepSysteme) 2>&1); $ErrorActionPreference = 'Stop'; if ($LASTEXITCODE -ne 0) { $_ } })
            Verifie 'owl fmt --check : aucun des fichiers generes n est a reformater' ($mkNonConformes.Count -eq 0) ($mkNonConformes -join ', ')
        } finally { Pop-Location }

        Write-Host "  le projet produit, vu par owl : compile, et ses tests passent"
        Push-Location $mkP
        try {
            $mkCheck = (owl --check projet.owl) -join ' '
            Verifie "owl --check passe" ($mkCheck -match '"errors":\[\]') $mkCheck
            Verifie "le service genere est en place pendant owl test" (Test-Path -LiteralPath (Join-Path $mkP 'app\http\ServiceBoutique.owl')) ''
            $ErrorActionPreference = 'Continue'
            $mkTest = ((owl test 2>&1) | ForEach-Object { "$_" }) -join ' '
            $ErrorActionPreference = 'Stop'
            Verifie "owl test : ALL CLEAR sur 9 suites (2 ressources x 4 fichiers + 1 migration)" (($mkTest -match 'ALL CLEAR \(9 suites') -and ($mkTest -notmatch 'FAIL|CRASH')) $mkTest
        } finally {
            $ErrorActionPreference = 'Stop'
            Pop-Location
        }

        Write-Host "  relancer la meme commande ne remplace rien : tout est conserve"
        $r = Lance $mkP @('make', 'resource', 'Client', '--champs', $mkChamps, '--json')
        Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkJson4 = $null; try { $mkJson4 = $r.Sortie.Trim() | ConvertFrom-Json } catch { }
        Verifie "created vide, dix fichiers dans kept, une note par fichier" ($mkJson4 -and (@($mkJson4.created).Count -eq 0) -and (@($mkJson4.kept).Count -eq 10) -and ((@($mkJson4.notes) | Where-Object { $_ -match 'existe d' }).Count -eq 10)) $r.Sortie
        Verifie "le fichier de l'utilisateur est intact (meme SHA-256)" ((Get-FileHash -LiteralPath $mkEntite).Hash -eq $mkHashEntite) ''

        Write-Host "  erreurs d'usage : une ligne, pas de pile d'appels, code 2"
        $r = Lance $mkP @('make', 'resource', 'Client', '--champs', 'id:entier*,nom:varchar', '--json')
        $mkErreur = $null; try { $mkErreur = $r.Sortie.Trim() | ConvertFrom-Json } catch { }
        Verifie "code 2 et { ok: false, error } qui cite le type et liste les types" (($r.Code -eq 2) -and $mkErreur -and ($mkErreur.ok -eq $false) -and ($mkErreur.error -match 'varchar') -and ($mkErreur.error -match 'entier, texte, reel, booleen, date, dateheure')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('make', 'entity', 'Client', '--champs', 'id:entier*,nom:texte')
        Verifie "sous-commande inconnue : code 2" (($r.Code -eq 2) -and ($r.Sortie -match 'resource, migration')) "code=$($r.Code) $($r.Sortie)"

        Write-Host "  hors d'un projet ebony"
        $r = Lance $mkA @('make', 'resource', 'Client', '--champs', 'id:entier*,nom:texte', '--json')
        $mkHors = $null; try { $mkHors = $r.Sortie.Trim() | ConvertFrom-Json } catch { }
        Verifie "code 1, { ok: false } qui dit que ce n'est pas un projet ebony" (($r.Code -eq 1) -and $mkHors -and ($mkHors.ok -eq $false) -and ($mkHors.error -match 'pas un projet ebony')) "code=$($r.Code) $($r.Sortie)"

        Write-Host "  depuis PowerShell, --champs non guillemete : PowerShell le decoupe en plusieurs arguments"
        Push-Location $mkP
        try {
            $ErrorActionPreference = 'Continue'
            $mkPs = ((& $ebony make resource Produit --champs id:entier*,nom:texte,prix:reel --dry-run --json 2>&1) | ForEach-Object { "$_" }) -join ' '
            $ErrorActionPreference = 'Stop'
            $mkJsonPs = $null; try { $mkJsonPs = $mkPs.Trim() | ConvertFrom-Json } catch { }
            Verifie "les trois champs sont lus : dix fichiers dans created" ($mkJsonPs -and ($mkJsonPs.ok -eq $true) -and (@($mkJsonPs.created).Count -eq 10)) $mkPs
        } finally { $ErrorActionPreference = 'Stop'; Pop-Location }
        Write-Host "  migrate : appliquer, lister, defaire, refuser, sur la vraie base SQLite du projet"
        # La table existe-t-elle vraiment dans le fichier de la base ? Un petit programme OWL, SEUL dans son dossier, la cherche. Ce dossier est dans le dossier temporaire du systeme : sous le depot (tmp\.travail compris),
        # owl remonte jusqu'au projet.owl d'ebony et refuse le fichier ("introuvable dans le projet", constate avec OWL 1.7.0).
        $mgVerif = Join-Path ([IO.Path]::GetTempPath()) ('ebony_verif_table_' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
        New-Item -ItemType Directory -Force $mgVerif | Out-Null
        function MgTableExiste([string]$Table) {
            $mgFichierBase = Join-Path $mkP 'storage\app.db'
            $mgQuote = [string][char]34
            $mgSource = "cnx est une sqlConnexion`ncnx..Provider = sqlSqlite`ncnx..Source = " + $mgQuote + $mgFichierBase + $mgQuote + "`nreq est une sqlRequ" + [char]0xEA + "te`nrep est une sqlR" + [char]0xE9 + "ponse`nSI PAS cnx.Ouvre() ALORS`n`tTrace(" + $mgQuote + "ERREUR" + $mgQuote + ")`nSINON`n`treq..Code = " + [string][char]96 + "SELECT 1 FROM " + $mgQuote + $Table + $mgQuote + [string][char]96 + "`n`trep = SQLEnvoie(cnx, req)`n`tSI rep..Succ" + [char]0xE8 + "s ALORS`n`t`tTrace(" + $mgQuote + "OUI" + $mgQuote + ")`n`tSINON`n`t`tTrace(" + $mgQuote + "NON" + $mgQuote + ")`n`tFIN`n`tcnx.Ferme()`nFIN`n"
            [IO.File]::WriteAllText((Join-Path $mgVerif 'verif.owl'), $mgSource, (New-Object Text.UTF8Encoding($false)))
            Push-Location $mgVerif
            try { $ErrorActionPreference = 'Continue'; $mgRes = ((owl verif.owl 2>&1) | ForEach-Object { "$_" }) -join ' '; $ErrorActionPreference = 'Stop' } finally { $ErrorActionPreference = 'Stop'; Pop-Location }
            return $mgRes.Trim()
        }
        function MgJson([object]$Resultat) { $mgJ = $null; try { $mgJ = $Resultat.Sortie.Trim() | ConvertFrom-Json } catch { }; return $mgJ }

        $r = Lance $mkP @('migrate', 'status', '--json')
        $mgJson = MgJson $r
        Verifie "status --json : code 0, une ligne, les deux migrations (celle des jetons, fournie par auth, puis la vôtre) sont en attente" (($r.Code -eq 0) -and ($r.Sortie.Trim() -notmatch "[\r\n]") -and $mgJson -and ($mgJson.command -eq 'migrate status') -and ($mgJson.base -eq 'sqlite') -and (@($mgJson.migrations).Count -eq 2) -and (@($mgJson.migrations | Where-Object { $_.status -eq 'pending' }).Count -eq 2) -and (@($mgJson.migrations)[0].name -eq 'M202611100000_CreeEbJetons') -and (@($mgJson.migrations)[1].name -match '^M\d{12}_CreeClients$')) "code=$($r.Code) $($r.Sortie)"
        $mgNom = @($mgJson.migrations)[1].name

        $r = Lance $mkP @('migrate', '--dry-run', '--json')
        $mgJson = MgJson $r
        Verifie "--dry-run : code 0, dryRun vrai, annonce la migration" (($r.Code -eq 0) -and $mgJson -and ($mgJson.dryRun -eq $true) -and (@($mgJson.done).Count -eq 2) -and (@($mgJson.done)[1] -eq $mgNom)) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('migrate', 'status', '--json')
        $mgJson = MgJson $r
        Verifie "apres --dry-run : toujours en attente, et la table n'existe pas" ($mgJson -and (@($mgJson.migrations | Where-Object { $_.status -eq 'pending' }).Count -eq 2) -and ((MgTableExiste 'clients') -eq 'NON')) "$($r.Sortie)"

        $r = Lance $mkP @('migrate', '--json')
        $mgJson = MgJson $r
        Verifie "migrate : code 0, les deux migrations appliquees, datees" (($r.Code -eq 0) -and $mgJson -and ($mgJson.dryRun -eq $false) -and (@($mgJson.done).Count -eq 2) -and (@($mgJson.migrations | Where-Object { $_.status -eq 'applied' }).Count -eq 2) -and ([regex]::Matches($r.Sortie, '"appliedAt":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"').Count -eq 2)) "code=$($r.Code) $($r.Sortie)"
        Verifie "la table clients existe dans le fichier de la base" ((MgTableExiste 'clients') -eq 'OUI') ''
        $r = Lance $mkP @('migrate', '--json')
        $mgJson = MgJson $r
        Verifie "migrate une seconde fois : code 0, rien a faire" (($r.Code -eq 0) -and $mgJson -and (@($mgJson.done).Count -eq 0) -and (@($mgJson.migrations)[0].status -eq 'applied')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('migrate', 'status')
        Verifie "status en texte : la migration est appliquee" (($r.Code -eq 0) -and ($r.Sortie -match 'appliqu') -and ($r.Sortie -match [regex]::Escape($mgNom))) "code=$($r.Code) $($r.Sortie)"

        Write-Host "  migrate rollback"
        $r = Lance $mkP @('migrate', 'rollback', '--dry-run', '--json')
        $mgJson = MgJson $r
        Verifie "rollback --dry-run : annonce la migration, ne defait rien" (($r.Code -eq 0) -and $mgJson -and ($mgJson.dryRun -eq $true) -and (@($mgJson.done)[0] -eq $mgNom) -and ((MgTableExiste 'clients') -eq 'OUI')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('migrate', 'rollback', '--json')
        $mgJson = MgJson $r
        Verifie "rollback : code 0, la migration est defaite, la table a disparu" (($r.Code -eq 0) -and $mgJson -and (@($mgJson.done)[0] -eq $mgNom) -and (@($mgJson.migrations)[1].status -eq 'pending') -and ((MgTableExiste 'clients') -eq 'NON')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('migrate', 'rollback', '--json')
        $mgJson = MgJson $r
        Verifie "rollback suivant : defait la migration des jetons (fournie par auth), la table eb_jetons disparait" (($r.Code -eq 0) -and $mgJson -and (@($mgJson.done).Count -eq 1) -and (@($mgJson.done)[0] -eq 'M202611100000_CreeEbJetons') -and ((MgTableExiste 'eb_jetons') -eq 'NON')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('migrate', 'rollback', '--json')
        $mgJson = MgJson $r
        Verifie "rollback sans rien d'applique : code 0, rien a defaire" (($r.Code -eq 0) -and $mgJson -and (@($mgJson.done).Count -eq 0)) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('migrate', '--json')
        Verifie "migrate la reapplique, la table revient" (($r.Code -eq 0) -and ((MgTableExiste 'clients') -eq 'OUI')) "code=$($r.Code) $($r.Sortie)"

        # ---- Le controleur genere par make resource, contre un VRAI owl serve (SQLite) : ce que fait l'utilisateur apres la commande. Un faux disque ne montre ni que le service monte, ni que le corps JSON est lu. ----
        # Un service lance a part (PID note) ; seul ce PID est arrete. Les traces vont hors du projet (dossier temporaire du systeme).
        $mkTraces = Join-Path ([IO.Path]::GetTempPath()) ('ebony_routes_' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
        New-Item -ItemType Directory -Force $mkTraces | Out-Null
        function MkDemarre([string]$Dossier) {
            $mkEcoute = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $mkEcoute.Start(); $mkNumero = $mkEcoute.LocalEndpoint.Port; $mkEcoute.Stop()
            $mkSortie = Join-Path $mkTraces ('serve' + $mkNumero + '.out.txt')
            $mkProc = Start-Process -FilePath owl -ArgumentList @('serve', '--port', $mkNumero) -WorkingDirectory $Dossier -PassThru @fenetreCachee -RedirectStandardOutput $mkSortie -RedirectStandardError (Join-Path $mkTraces ('serve' + $mkNumero + '.err.txt'))
            $mkServeur = @{ Port = $mkNumero; Proc = $mkProc; Pret = $false; Sortie = $mkSortie }
            for ($mkEssai = 0; $mkEssai -lt 90 -and -not $mkServeur.Pret; $mkEssai++) {
                $mkCode = & $programmeCurl -s -m 5 -o $fichierNul -w '%{http_code}' ('http://127.0.0.1:' + $mkNumero + '/api/health')
                if ($mkCode -ne '000') { $mkServeur.Pret = $true } else { Start-Sleep -Milliseconds 700 }
            }
            return $mkServeur
        }
        function MkArrete($Serveur) {
            $mkCommande = (CommandeDuProcessus $Serveur.Proc.Id)
            if ($mkCommande -and $mkCommande.Contains('serve') -and $mkCommande.Contains([string]$Serveur.Port)) { Stop-Process -Id $Serveur.Proc.Id -ErrorAction SilentlyContinue }
            elseif ($mkCommande) { Write-Host ("  [ECHEC]  le processus " + $Serveur.Proc.Id + " n'est pas notre service, non arrete : " + $mkCommande) -ForegroundColor Red; $script:echecs++ }
        }
        $script:mkJeton = ''
        function MkRequete($Serveur, [string]$Methode, [string]$Chemin, [string]$Json = '', [string]$Type = 'application/json') {
            $mkReponse = Join-Path $mkTraces 'reponse.txt'
            if (Test-Path -LiteralPath $mkReponse) { Remove-Item -LiteralPath $mkReponse -Force }
            $mkArguments = @('-s', '-m', '20', '-o', $mkReponse, '-w', '%{http_code}', '-X', $Methode)
            if ($script:mkJeton -ne '') { $mkArguments += @('-H', ('Authorization: Bearer ' + $script:mkJeton)) }
            if ($Json -ne '') {
                $mkEnvoi = Join-Path $mkTraces 'envoi.json'
                [IO.File]::WriteAllText($mkEnvoi, $Json, (New-Object Text.UTF8Encoding($false)))
                $mkArguments += @('-H', ('Content-Type: ' + $Type), '--data-binary', ('@' + $mkEnvoi))
            }
            $mkArguments += ('http://127.0.0.1:' + $Serveur.Port + $Chemin)
            $mkCode = & $programmeCurl @mkArguments
            $mkTexte = ''
            if (Test-Path -LiteralPath $mkReponse) { $mkTexte = [IO.File]::ReadAllText($mkReponse) }
            $mkObjet = $null; try { $mkObjet = $mkTexte | ConvertFrom-Json } catch { }
            return @{ Code = [int]$mkCode; Corps = $mkTexte; Json = $mkObjet }
        }
        # Les routes generees sont PROTEGEES par defaut : ce projet les ouvre par le reglage AUTH_ROUTES (le projet Pays plus bas les teste protegees, avec un vrai jeton).
        [IO.File]::WriteAllText((Join-Path $mkP '.env'), "AUTH_ROUTES=ouvertes`n", (New-Object Text.UTF8Encoding($false)))
        Write-Host "  le controleur genere, routes ouvertes (AUTH_ROUTES=ouvertes), avec un vrai owl serve (SQLite) : liste, lecture, creation, modification, suppression"
        $mkServeur = MkDemarre $mkP
        try {
            Verifie "le service monte avec le controleur genere (owl serve)" $mkServeur.Pret ("port " + $mkServeur.Port)
            $rq = MkRequete $mkServeur 'GET' '/api/clients'
            Verifie "GET /api/clients : 200 et une liste vide" (($rq.Code -eq 200) -and ($rq.Corps -eq '[]')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'POST' '/api/clients' '{"nom":"Ada","email":"a@x.fr","actif":true,"note":12.5,"naissance":"1990-01-02"}'
            Verifie "POST : 201, la cle est donnee par la base, les valeurs du corps sont relues" (($rq.Code -eq 201) -and $rq.Json -and ($rq.Json.id -eq 1) -and ($rq.Json.nom -eq 'Ada') -and ($rq.Json.email -eq 'a@x.fr') -and ($rq.Json.actif -eq $true) -and ($rq.Json.note -eq 12.5) -and ($rq.Json.naissance -eq '1990-01-02')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'POST' '/api/clients' '{"nom":"Bob"}'
            Verifie "POST avec des champs absents : 201, valeurs par defaut du type (texte vide, Faux, 0)" (($rq.Code -eq 201) -and $rq.Json -and ($rq.Json.id -eq 2) -and ($rq.Json.email -eq '') -and ($rq.Json.actif -eq $false) -and ($rq.Json.note -eq 0)) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'GET' '/api/clients'
            Verifie "GET /api/clients : 200 et deux clients dans l'ordre" (($rq.Code -eq 200) -and (@($rq.Json).Count -eq 2) -and (@($rq.Json)[0].nom -eq 'Ada') -and (@($rq.Json)[1].nom -eq 'Bob')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'GET' '/api/clients/1'
            Verifie "GET /api/clients/1 : 200 et Ada" (($rq.Code -eq 200) -and $rq.Json -and ($rq.Json.id -eq 1) -and ($rq.Json.nom -eq 'Ada')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'PUT' '/api/clients/1' '{"nom":"Ada L.","email":"ada@x.fr","actif":false,"note":20,"naissance":"1990-01-03"}'
            Verifie "PUT /api/clients/1 : 200, la cle est celle de l'adresse" (($rq.Code -eq 200) -and $rq.Json -and ($rq.Json.id -eq 1) -and ($rq.Json.nom -eq 'Ada L.') -and ($rq.Json.actif -eq $false) -and ($rq.Json.note -eq 20)) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'GET' '/api/clients/1'
            Verifie "la modification est dans la base" (($rq.Code -eq 200) -and $rq.Json -and ($rq.Json.nom -eq 'Ada L.') -and ($rq.Json.naissance -eq '1990-01-03')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'GET' '/api/clients/999'
            Verifie "GET d'une cle absente : 404 { code: introuvable, message }" (($rq.Code -eq 404) -and $rq.Json -and ($rq.Json.code -eq 'introuvable') -and ($rq.Json.message -match '999')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'PUT' '/api/clients/999' '{"nom":"Zed"}'
            Verifie "PUT d'une cle absente : 404 { code: introuvable }" (($rq.Code -eq 404) -and $rq.Json -and ($rq.Json.code -eq 'introuvable') -and ($rq.Json.message -match '999')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'POST' '/api/clients' '{"nom":"   ","note":1}'
            Verifie "POST d'un texte obligatoire vide : 400 { code: invalide } qui nomme le champ" (($rq.Code -eq 400) -and $rq.Json -and ($rq.Json.code -eq 'invalide') -and ($rq.Json.message -match 'nom')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'PUT' '/api/clients/1' '{"email":"x@y.fr"}'
            Verifie "PUT sans le champ obligatoire : 400, et la ligne n'a pas change" (($rq.Code -eq 400) -and $rq.Json -and ($rq.Json.code -eq 'invalide') -and ((MkRequete $mkServeur 'GET' '/api/clients/1').Json.nom -eq 'Ada L.')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'POST' '/api/clients' 'ceci n est pas du json'
            Verifie "POST d'un corps qui n'est pas du JSON : 400 (refuse par OWL avant la route)" ($rq.Code -eq 400) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'POST' '/api/clients' '{"nom":"X"}' 'text/plain'
            Verifie "POST avec un autre type de contenu : 415 (refuse par OWL avant la route)" ($rq.Code -eq 415) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'DELETE' '/api/clients/2'
            Verifie "DELETE /api/clients/2 : 204 sans corps" (($rq.Code -eq 204) -and ($rq.Corps -eq '')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'DELETE' '/api/clients/2'
            Verifie "DELETE une seconde fois : 404" (($rq.Code -eq 404) -and $rq.Json -and ($rq.Json.code -eq 'introuvable')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeur 'GET' '/api/clients'
            Verifie "GET /api/clients : il ne reste qu'Ada" (($rq.Code -eq 200) -and (@($rq.Json).Count -eq 1) -and (@($rq.Json)[0].nom -eq 'Ada L.')) ("code=" + $rq.Code + " " + $rq.Corps)
            $null = MkRequete $mkServeur 'DELETE' '/api/clients/1'
            $rq = MkRequete $mkServeur 'GET' '/api/health'
            Verifie "GET /api/health : le service de l'application tourne toujours a cote du controleur" (($rq.Code -eq 200) -and ($rq.Corps -eq '{"statut":"ok","base":"ok"}')) ("code=" + $rq.Code + " " + $rq.Corps)
        } finally { MkArrete $mkServeur }
        Start-Sleep -Milliseconds 500
        $mkJournal = ''; if (Test-Path -LiteralPath $mkServeur.Sortie) { $mkJournal = Get-Content -Raw -Encoding UTF8 -LiteralPath $mkServeur.Sortie }
        Verifie "le journal du service ne porte aucune erreur : 400, 404 et 415 sont des erreurs du client, pas du serveur" ($mkJournal -notmatch '"niveau":"error"') $mkJournal

        Write-Host "  migrate : une migration cassee est annulee en entier, les precedentes restent"
        $mgDossierMig = Join-Path $mkP 'database\migrations'
        $mgQ = [string][char]34
        $mgCassee = "cMx est une Classe implemente iEbMigration`n`tPROCEDURE PUBLIQUE Nom() : cha" + [char]0xEE + "ne`n`t`tRENVOYER " + $mgQ + "M299912312359_Cassee" + $mgQ + "`n`tFIN`n`tPROCEDURE PUBLIQUE Monte() : tableau de cha" + [char]0xEE + "nes`n`t`ttabSql est un tableau de cha" + [char]0xEE + "nes`n`t`tTableauAjoute(tabSql, " + $mgQ + "CREATE TABLE temoin (id INTEGER)" + $mgQ + ")`n`t`tTableauAjoute(tabSql, " + $mgQ + "CREATE TABLE casse (" + $mgQ + ")`n`t`tRENVOYER tabSql`n`tFIN`n`tPROCEDURE PUBLIQUE Descend() : tableau de cha" + [char]0xEE + "nes`n`t`ttabSql est un tableau de cha" + [char]0xEE + "nes`n`t`tTableauAjoute(tabSql, " + $mgQ + "DROP TABLE temoin" + $mgQ + ")`n`t`tRENVOYER tabSql`n`tFIN`nFIN`n"
        $mgFichierCasse = Join-Path $mgDossierMig 'M299912312359_Cassee.owl'
        [IO.File]::WriteAllText($mgFichierCasse, $mgCassee, (New-Object Text.UTF8Encoding($false)))
        $r = Lance $mkP @('migrate', '--json')
        $mgJson = MgJson $r
        Verifie "code 1, { ok: false } qui nomme la migration et l'instruction" (($r.Code -eq 1) -and $mgJson -and ($mgJson.ok -eq $false) -and ($mgJson.error -match 'M299912312359_Cassee') -and ($mgJson.error -match 'instruction 2 sur 2')) "code=$($r.Code) $($r.Sortie)"
        Verifie "la premiere instruction a ete annulee : pas de table temoin" ((MgTableExiste 'temoin') -eq 'NON') ''
        Verifie "la migration precedente reste appliquee" ((MgTableExiste 'clients') -eq 'OUI') ''
        $r = Lance $mkP @('migrate', 'status', '--json')
        $mgJson = MgJson $r
        Verifie "status : celle des jetons et CreeClients appliquees, la cassee en attente" ($mgJson -and (@($mgJson.migrations).Count -eq 3) -and (@($mgJson.migrations)[0].status -eq 'applied') -and (@($mgJson.migrations)[1].status -eq 'applied') -and (@($mgJson.migrations)[2].status -eq 'pending')) $r.Sortie
        # Une migration qui calcule son SQL n'est pas lue : refusee avant la moindre instruction.
        [IO.File]::WriteAllText($mgFichierCasse, $mgCassee.Replace($mgQ + "CREATE TABLE temoin (id INTEGER)" + $mgQ, $mgQ + "CREATE TABLE " + $mgQ + " + sNom"), (New-Object Text.UTF8Encoding($false)))
        $r = Lance $mkP @('migrate', '--json')
        $mgJson = MgJson $r
        Verifie "migration qui calcule son SQL : code 1, 'pas reconnue', rien n'est execute" (($r.Code -eq 1) -and $mgJson -and ($mgJson.error -match 'pas reconnue') -and ((MgTableExiste 'temoin') -eq 'NON')) "code=$($r.Code) $($r.Sortie)"
        Remove-Item -LiteralPath $mgFichierCasse -Force

        Write-Host "  migrate rollback : le fichier d'une migration appliquee a disparu"
        $mgFichierClients = Join-Path $mgDossierMig ($mgNom + '.owl')
        $mgContenuClients = [IO.File]::ReadAllBytes($mgFichierClients)
        Remove-Item -LiteralPath $mgFichierClients -Force
        $r = Lance $mkP @('migrate', 'rollback', '--json')
        $mgJson = MgJson $r
        Verifie "code 1, { ok: false } qui nomme la migration sans fichier, et la table reste" (($r.Code -eq 1) -and $mgJson -and ($mgJson.ok -eq $false) -and ($mgJson.error -match $mgNom) -and ((MgTableExiste 'clients') -eq 'OUI')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('migrate', 'status', '--json')
        $mgJson = MgJson $r
        Verifie "status : la migration est 'missing' avec sa date" ($mgJson -and (@($mgJson.migrations)[1].status -eq 'missing') -and (@($mgJson.migrations)[1].appliedAt -ne '')) $r.Sortie
        [IO.File]::WriteAllBytes($mgFichierClients, $mgContenuClients)

        Write-Host "  migrate : erreurs d'usage et hors d'un projet"
        $r = Lance $mkP @('migrate', '--force')
        Verifie "option inconnue : code 2" (($r.Code -eq 2) -and ($r.Sortie -match 'Option inconnue')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('migrate', 'rollback', '--pas', '0')
        Verifie "--pas 0 : code 2" (($r.Code -eq 2) -and ($r.Sortie -match 'pas')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkA @('migrate', 'status', '--json')
        $mgHors = MgJson $r
        Verifie "hors d'un projet : code 1, { ok: false } qui dit que ce n'est pas un projet ebony" (($r.Code -eq 1) -and $mgHors -and ($mgHors.ok -eq $false) -and ($mgHors.error -match 'pas un projet ebony')) "code=$($r.Code) $($r.Sortie)"
        Nettoie $mgVerif

        Write-Host "  token : creer, lister, revoquer, sur la vraie base SQLite du projet (le secret n'est jamais ecrit)"
        function TkJson([object]$Resultat) { $tkJ = $null; try { $tkJ = $Resultat.Sortie.Trim() | ConvertFrom-Json } catch { }; return $tkJ }
        # Sans la migration (ebony migrate pas encore lance), token ne cree plus la table en silence : il refuse et dit quoi faire (comme AdonisJS, qui ne cree pas auth_access_tokens a la volee).
        $r = Lance $mkA @('new', 'jetonsansmigration')
        Verifie "new jetonsansmigration : code 0, et la migration de la table des jetons est dans le projet" (($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $mkA 'jetonsansmigration\database\migrations\M202611100000_CreeEbJetons.owl'))) "code=$($r.Code) $($r.Sortie)"
        $r = Lance (Join-Path $mkA 'jetonsansmigration') @('token', 'create', 'ci')
        Verifie "token create avant ebony migrate : code 1, le message dit de lancer ebony migrate" (($r.Code -eq 1) -and ($r.Sortie -match 'ebony migrate')) "code=$($r.Code) $($r.Sortie)"
        # new --auth : la table des utilisateurs (celle de --table) est ECRITE dans le projet, puis creee par migrate sur une vraie base SQLite, apres celle des jetons.
        $r = Lance $mkA @('new', 'avecauth', '--auth', '--table', 'users')
        $mkAvecAuth = Join-Path $mkA 'avecauth'
        Verifie "new --auth --table users : code 0, la migration de la table des utilisateurs est dans le projet" (($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $mkAvecAuth 'database\migrations\M202611100001_CreeUtilisateurs.owl'))) "code=$($r.Code) $($r.Sortie)"
        Verifie "la migration ecrite cree bien la table users (pas {table_utilisateurs})" (([IO.File]::ReadAllText((Join-Path $mkAvecAuth 'database\migrations\M202611100001_CreeUtilisateurs.owl'), [Text.Encoding]::UTF8).Contains('CREATE TABLE users (')) -and (-not [IO.File]::ReadAllText((Join-Path $mkAvecAuth 'database\migrations\M202611100001_CreeUtilisateurs.owl'), [Text.Encoding]::UTF8).Contains('{table_utilisateurs}'))) ''
        $r = Lance $mkAvecAuth @('migrate', '--json')
        $mkJsonAuth = $null; try { $mkJsonAuth = $r.Sortie.Trim() | ConvertFrom-Json } catch { }
        Verifie "migrate sur SQLite : code 0, la table des jetons puis celle des utilisateurs sont appliquees" (($r.Code -eq 0) -and $mkJsonAuth -and (@($mkJsonAuth.done).Count -eq 2) -and (@($mkJsonAuth.done)[0] -eq 'M202611100000_CreeEbJetons') -and (@($mkJsonAuth.done)[1] -eq 'M202611100001_CreeUtilisateurs')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkA @('new', 'sansauthmigr')
        Verifie "new sans --auth : pas de migration de la table des utilisateurs" (($r.Code -eq 0) -and (-not (Test-Path -LiteralPath (Join-Path $mkA 'sansauthmigr\database\migrations\M202611100001_CreeUtilisateurs.owl')))) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'list', '--json')
        $tkJson = TkJson $r
        Verifie "list sans aucun jeton : code 0, une ligne, liste vide" (($r.Code -eq 0) -and ($r.Sortie.Trim() -notmatch "[\r\n]") -and $tkJson -and ($tkJson.command -eq 'token list') -and (@($tkJson.tokens).Count -eq 0)) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'create', 'ci', '--json')
        $tkJson = TkJson $r
        $tkSecret = ''; $tkId = ''
        if ($tkJson) { $tkSecret = [string]$tkJson.token; $tkId = [string]$tkJson.id }
        Verifie "create : code 0, secret eb_ de 46 caracteres, identifiant de 12 hexadecimaux" (($r.Code -eq 0) -and ($tkSecret -match '^eb_[A-Za-z0-9_-]{43}$') -and ($tkId -match '^[0-9a-f]{12}$') -and ($tkJson.name -eq 'ci') -and ($tkJson.expiresAt -eq '')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'list', '--json')
        $tkJson = TkJson $r
        Verifie "list : le jeton est actif, sans le secret" (($r.Code -eq 0) -and $tkJson -and (@($tkJson.tokens).Count -eq 1) -and (@($tkJson.tokens)[0].id -eq $tkId) -and (@($tkJson.tokens)[0].status -eq 'active') -and (@($tkJson.tokens)[0].name -eq 'ci') -and ($r.Sortie -notmatch [regex]::Escape($tkSecret))) "code=$($r.Code) $($r.Sortie)"
        # Le fichier de la base ne contient pas le secret, mais contient son empreinte SHA-256 : lecture des octets (latin1) et recherche de texte.
        $tkOctets = [IO.File]::ReadAllBytes((Join-Path $mkP 'storage\app.db'))
        $tkTexteBase = [Text.Encoding]::GetEncoding(28591).GetString($tkOctets)
        $tkSha = [Security.Cryptography.SHA256]::Create()
        $tkEmpreinte = ([BitConverter]::ToString($tkSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($tkSecret))) -replace '-', '').ToLowerInvariant()
        Verifie "la base ne contient pas le secret mais son empreinte SHA-256" (($tkSecret -ne '') -and (-not $tkTexteBase.Contains($tkSecret)) -and $tkTexteBase.Contains($tkEmpreinte) -and $tkEmpreinte.StartsWith($tkId)) "empreinte=$tkEmpreinte"
        $r = Lance $mkP @('token', 'create', 'robot nuit', '--expire', '2099-12-31', '--json')
        $tkJson = TkJson $r
        Verifie "create --expire : code 0, expiration a la fin du jour, nom avec espace garde" (($r.Code -eq 0) -and $tkJson -and ($tkJson.expiresAt -eq '2099-12-31T23:59:59Z') -and ($tkJson.name -eq 'robot nuit')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'create', 'trop-tard', '--expire', '2020-01-01')
        Verifie "create avec une expiration passee : code 2, rien d'ecrit" (($r.Code -eq 2) -and ($r.Sortie -match 'pass.e')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'list')
        Verifie "list en texte : deux jetons, aucun secret" (($r.Code -eq 0) -and ($r.Sortie -match '2 jeton') -and ($r.Sortie -match 'robot nuit') -and ($r.Sortie -notmatch [regex]::Escape($tkSecret))) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'revoke', $tkId, '--json')
        $tkJson = TkJson $r
        Verifie "revoke : code 0, revoked vrai" (($r.Code -eq 0) -and $tkJson -and ($tkJson.revoked -eq $true) -and ($tkJson.id -eq $tkId)) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'list', '--json')
        $tkJson = TkJson $r
        $tkRevoque = @($tkJson.tokens) | Where-Object { $_.id -eq $tkId }
        Verifie "list : le jeton revoque l'est, l'autre reste actif" (($r.Code -eq 0) -and $tkRevoque -and ($tkRevoque.status -eq 'revoked') -and ([regex]::IsMatch($r.Sortie, '"revokedAt":"\d{4}-\d{2}-\d{2}T[^"]*","status":"revoked"')) -and (@(@($tkJson.tokens) | Where-Object { $_.status -eq 'active' }).Count -eq 1)) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'revoke', $tkId, '--json')
        $tkJson = TkJson $r
        Verifie "revoke une seconde fois : code 1, { ok: false }" (($r.Code -eq 1) -and $tkJson -and ($tkJson.ok -eq $false) -and ($tkJson.error -match 'Aucun jeton actif')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'create', 'texte')
        Verifie "create en texte : le secret et l'avertissement sont affiches" (($r.Code -eq 0) -and ($r.Sortie -match 'eb_[A-Za-z0-9_-]{43}') -and ($r.Sortie -match "qu'une fois")) "code=$($r.Code) $($r.Sortie)"
        Write-Host "  token : erreurs d'usage et hors d'un projet"
        $r = Lance $mkP @('token')
        Verifie "sans sous-commande : code 2" (($r.Code -eq 2) -and ($r.Sortie -match 'sous-commande')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'create')
        Verifie "create sans nom : code 2" (($r.Code -eq 2) -and ($r.Sortie -match 'nom du jeton')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'revoke', 'ABC')
        Verifie "revoke avec un identifiant incorrect : code 2" (($r.Code -eq 2) -and ($r.Sortie -match 'identifiant')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkP @('token', 'create', 'x', '--expire', '2027-02-30')
        Verifie "create --expire avec une date impossible : code 2" (($r.Code -eq 2) -and ($r.Sortie -match 'AAAA-MM-JJ')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkA @('token', 'list', '--json')
        $tkHors = TkJson $r
        Verifie "hors d'un projet : code 1, { ok: false } qui dit que ce n'est pas un projet ebony" (($r.Code -eq 1) -and $tkHors -and ($tkHors.ok -eq $false) -and ($tkHors.error -match 'pas un projet ebony')) "code=$($r.Code) $($r.Sortie)"

        Write-Host "  controleur d'une ressource a cle texte (Pays) : la cle vient du corps a la creation, de l'adresse ensuite"
        $r = Lance $mkA @('new', 'pays')
        Verifie "new pays : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkPays = Join-Path $mkA 'pays'
        $mkChampsPays = 'code:texte*,nom:texte,creation:date?'
        $r = Lance $mkPays @('make', 'migration', 'CreePays', '--champs', $mkChampsPays, '--json')
        Verifie "make migration CreePays : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkPays @('make', 'resource', 'Pays', '--champs', $mkChampsPays, '--table', 'pays', '--json')
        Verifie "make resource Pays : code 0, dix fichiers dont le controleur" (($r.Code -eq 0) -and ($r.Sortie -match 'app/http/pays/ControleurPays\.owl')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkPays @('migrate', '--json')
        Verifie "migrate : la table pays est creee" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        # Ce projet est PROTEGE (aucun reglage AUTH_ROUTES) : on y cree un vrai jeton avec la commande, et on l'envoie dans l'en-tete Authorization.
        $r = Lance $mkPays @('token', 'create', 'test-pays', '--json')
        $mkJsonJeton = $null; try { $mkJsonJeton = $r.Sortie.Trim() | ConvertFrom-Json } catch { }
        $mkSecretPays = ''; $mkIdPays = ''
        if ($mkJsonJeton) { $mkSecretPays = [string]$mkJsonJeton.token; $mkIdPays = [string]$mkJsonJeton.id }
        Verifie "token create : un secret eb_ pour le projet Pays" (($r.Code -eq 0) -and ($mkSecretPays -match '^eb_')) "code=$($r.Code) $($r.Sortie)"
        $mkServeurPays = MkDemarre $mkPays
        try {
            Verifie "le service monte (owl serve)" $mkServeurPays.Pret ("port " + $mkServeurPays.Port)
            $script:mkJeton = ''
            $rq = MkRequete $mkServeurPays 'GET' '/api/pays'
            Verifie "sans jeton : 401, corps JSON { code: non_autorise }, avant toute route" (($rq.Code -eq 401) -and $rq.Json -and ($rq.Json.code -eq 'non_autorise')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurPays 'POST' '/api/pays' '{"code":"ZZ","nom":"Sans jeton"}'
            Verifie "POST sans jeton : 401, et rien n'est ecrit" (($rq.Code -eq 401) -and ($rq.Corps -notmatch 'ZZ')) ("code=" + $rq.Code + " " + $rq.Corps)
            $script:mkJeton = 'eb_ce-jeton-n-existe-pas'
            $rq = MkRequete $mkServeurPays 'GET' '/api/pays'
            Verifie "jeton inconnu : 401" ($rq.Code -eq 401) ("code=" + $rq.Code + " " + $rq.Corps)
            $script:mkJeton = $mkSecretPays.ToUpper()
            $rq = MkRequete $mkServeurPays 'GET' '/api/pays'
            Verifie "le vrai secret en majuscules : 401 (le secret est sensible a la casse)" ($rq.Code -eq 401) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurPays 'GET' '/api/health'
            Verifie "GET /api/health reste public, sans jeton" (($rq.Code -eq 200) -and ($rq.Corps -eq '{"statut":"ok","base":"ok"}')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurPays 'GET' '/api'
            Verifie "GET /api (l'accueil) reste public, sans jeton : 200 JSON qui designe /api/health" (($rq.Code -eq 200) -and $rq.Json -and ($rq.Json.statut -eq 'ok') -and ($rq.Json.sante -eq '/api/health')) ("code=" + $rq.Code + " " + $rq.Corps)
            $script:mkJeton = $mkSecretPays
            $rq = MkRequete $mkServeurPays 'POST' '/api/pays' '{"code":"FR","nom":"France","creation":"1789-07-14"}'
            Verifie "POST : 201, la cle est celle du corps" (($rq.Code -eq 201) -and $rq.Json -and ($rq.Json.code -eq 'FR') -and ($rq.Json.nom -eq 'France') -and ($rq.Json.creation -eq '1789-07-14')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurPays 'POST' '/api/pays' '{"code":"FR","nom":"Autre"}'
            Verifie "POST d'une cle deja prise : 409 { code: conflit }" (($rq.Code -eq 409) -and $rq.Json -and ($rq.Json.code -eq 'conflit') -and ($rq.Json.message -match 'FR')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurPays 'POST' '/api/pays' '{"code":"  ","nom":"Sans cle"}'
            Verifie "POST d'une cle vide : 400 qui nomme le champ" (($rq.Code -eq 400) -and $rq.Json -and ($rq.Json.code -eq 'invalide') -and ($rq.Json.message -match 'code')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurPays 'GET' '/api/pays/FR'
            Verifie "GET /api/pays/FR : 200, et la valeur du premier POST est intacte" (($rq.Code -eq 200) -and $rq.Json -and ($rq.Json.nom -eq 'France')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurPays 'PUT' '/api/pays/FR' '{"code":"XX","nom":"Republique francaise"}'
            Verifie "PUT /api/pays/FR : 200, la cle de l'adresse l'emporte sur celle du corps" (($rq.Code -eq 200) -and $rq.Json -and ($rq.Json.code -eq 'FR') -and ($rq.Json.nom -eq 'Republique francaise')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurPays 'GET' '/api/pays/XX'
            Verifie "GET /api/pays/XX : 404 (la cle du corps n'a pas ete creee)" ($rq.Code -eq 404) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurPays 'DELETE' '/api/pays/FR'
            Verifie "DELETE /api/pays/FR : 204" ($rq.Code -eq 204) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurPays 'GET' '/api/pays'
            Verifie "GET /api/pays : liste vide" (($rq.Code -eq 200) -and ($rq.Corps -eq '[]')) ("code=" + $rq.Code + " " + $rq.Corps)
            $r = Lance $mkPays @('token', 'revoke', $mkIdPays, '--json')
            Verifie "token revoke : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
            $rq = MkRequete $mkServeurPays 'GET' '/api/pays'
            Verifie "apres revoke, le meme jeton est refuse aussitot (401), sans redemarrer le service" ($rq.Code -eq 401) ("code=" + $rq.Code + " " + $rq.Corps)
            $script:mkJeton = ''
        } finally { MkArrete $mkServeurPays }

        # ---- Sans le module auth (son manifeste et sa bibliotheque retires) : le controleur genere ne peut pas l'appeler. Il est genere OUVERT, la commande le dit, le projet compile et le service repond sans jeton. ----
        Write-Host "  sans le module auth (manifeste et bibliotheque retires) : controleur genere OUVERT, projet compile, service sans jeton"
        $r = Lance $mkA @('new', 'sansauth')
        Verifie "new sansauth : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkSansAuth = Join-Path $mkA 'sansauth'
        Remove-Item -LiteralPath (Join-Path $mkSansAuth 'ebony\auth') -Recurse -Force
        Remove-Item -LiteralPath (Join-Path $mkSansAuth 'ebony\modules\auth.json') -Force
        Verifie "ebony/auth et ebony/modules/auth.json sont retires du projet" ((-not (Test-Path -LiteralPath (Join-Path $mkSansAuth 'ebony\auth'))) -and (-not (Test-Path -LiteralPath (Join-Path $mkSansAuth 'ebony\modules\auth.json')))) ''
        $mkChampsVille = 'id:entier*,nom:texte'
        $r = Lance $mkSansAuth @('make', 'migration', 'CreeVilles', '--champs', $mkChampsVille, '--table', 'villes', '--json')
        Verifie "make migration CreeVilles : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkSansAuth @('make', 'resource', 'Ville', '--champs', $mkChampsVille, '--table', 'villes', '--json')
        $mkJsonVille = TkJson $r
        Verifie "make resource Ville : code 0, et la note dit que les routes sont OUVERTES" (($r.Code -eq 0) -and $mkJsonVille -and ((@($mkJsonVille.notes) -join ' ') -match 'Les routes sont OUVERTES')) "code=$($r.Code) $($r.Sortie)"
        $mkControleurVille = [IO.File]::ReadAllText((Join-Path $mkSansAuth 'app\http\ville\ControleurVille.owl'), [Text.Encoding]::UTF8)
        Verifie "le controleur ne contient aucun appel au module auth et dit ROUTES OUVERTES" (($mkControleurVille -notmatch 'EbIdentiteDuJeton') -and ($mkControleurVille -match 'ROUTES OUVERTES')) ''
        Push-Location $mkSansAuth; try { $mkCheckSansAuth = (owl --check projet.owl) -join ' ' } finally { Pop-Location }
        Verifie "owl --check passe SANS ebony/auth (avant : le controleur ne compilait plus)" ($mkCheckSansAuth -match '"errors":\[\]') $mkCheckSansAuth
        $r = Lance $mkSansAuth @('migrate', '--json')
        Verifie "migrate : la table villes est creee" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkServeurSansAuth = MkDemarre $mkSansAuth
        try {
            Verifie "le service monte (owl serve) sans ebony/auth" $mkServeurSansAuth.Pret ("port " + $mkServeurSansAuth.Port)
            $script:mkJeton = ''
            $rq = MkRequete $mkServeurSansAuth 'POST' '/api/villes' '{"nom":"Abidjan"}'
            Verifie "POST sans jeton : 201 (routes ouvertes, aucun module auth)" (($rq.Code -eq 201) -and $rq.Json -and ($rq.Json.nom -eq 'Abidjan')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurSansAuth 'GET' '/api/villes'
            Verifie "GET sans jeton : 200 et la ville ecrite" (($rq.Code -eq 200) -and ($rq.Corps -match 'Abidjan')) ("code=" + $rq.Code + " " + $rq.Corps)
        } finally { MkArrete $mkServeurSansAuth }

        # ---- Sans le module db (ebony.conf : « modules » vide, le kit slim) : les commandes qui en dependent sont refusees (code 1) en nommant le module ; restore ne restaure que le coeur. ----
        Write-Host "  sans le module db (ebony.conf : modules vide) : migrate, make et token refuses, restore ne restaure que le coeur"
        $r = Lance $mkA @('new', 'sansdb')
        Verifie "new sansdb : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkSansDb = Join-Path $mkA 'sansdb'
        $mkConfAvant = [IO.File]::ReadAllText((Join-Path $mkSansDb 'ebony.conf'), [Text.Encoding]::UTF8)
        Verifie "ebony.conf de new note les modules du kit api (db et auth)" (($mkConfAvant -match '"modules":\s*\[\s*"db",\s*"auth"\s*\]')) $mkConfAvant
        $mkConfSansDb = [regex]::Replace($mkConfAvant, '(?s)"modules":\s*\[.*?\]', '"modules": []')
        [IO.File]::WriteAllText((Join-Path $mkSansDb 'ebony.conf'), $mkConfSansDb, (New-Object Text.UTF8Encoding($false)))
        Verifie "ebony.conf ne liste plus aucun module" ($mkConfSansDb -match '"modules": \[\]') $mkConfSansDb
        $r = Lance $mkSansDb @('migrate', '--json')
        Verifie "migrate : refuse (code 1) et nomme le module db" (($r.Code -eq 1) -and ($r.Sortie -match "n'a pas le module") -and ($r.Sortie -match 'db')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkSansDb @('make', 'migration', 'CreeX', '--champs', 'id:entier*,nom:texte', '--table', 'xs', '--json')
        Verifie "make migration : refuse (code 1) et nomme le module db" (($r.Code -eq 1) -and ($r.Sortie -match "n'a pas le module") -and ($r.Sortie -match 'db')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkSansDb @('make', 'resource', 'X', '--champs', 'id:entier*,nom:texte', '--table', 'xs', '--json')
        Verifie "make resource : refuse (code 1) et nomme le module db" (($r.Code -eq 1) -and ($r.Sortie -match "n'a pas le module") -and ($r.Sortie -match 'db')) "code=$($r.Code) $($r.Sortie)"
        Verifie "make n'a rien ecrit dans le projet (ni app\ ni database\migrations de X)" ((-not (Test-Path -LiteralPath (Join-Path $mkSansDb 'app\domaine\x'))) -and (@(Get-ChildItem -LiteralPath (Join-Path $mkSansDb 'database\migrations') -Filter '*CreeX*' -ErrorAction SilentlyContinue).Count -eq 0)) ''
        $r = Lance $mkSansDb @('token', 'list', '--json')
        Verifie "token : refuse (code 1) et nomme le module auth" (($r.Code -eq 1) -and ($r.Sortie -match "n'a pas le module") -and ($r.Sortie -match 'auth')) "code=$($r.Code) $($r.Sortie)"
        Remove-Item -LiteralPath (Join-Path $mkSansDb 'ebony') -Recurse -Force
        $r = Lance $mkSansDb @('restore', '--json')
        Verifie "restore d'un projet sans module db : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        Verifie "restore ne restaure que le coeur : ebony\cycle\cEbApplication.owl present, ebony\donnees et ebony\auth absents" ((Test-Path -LiteralPath (Join-Path $mkSansDb 'ebony\cycle\cEbApplication.owl')) -and (-not (Test-Path -LiteralPath (Join-Path $mkSansDb 'ebony\donnees'))) -and (-not (Test-Path -LiteralPath (Join-Path $mkSansDb 'ebony\auth')))) ''
        # ---- Le kit slim pour de vrai (« new --kit slim », pas un projet api dont on a vide la liste) : le projet compile, le service demarre SANS aucune variable DB_* ni fichier .env, et /api/health ne parle que de l'application. ----
        Write-Host "  le kit slim (new --kit slim) : sans base, le service demarre sans DB_*, /api/health repond {statut:ok}"
        $r = Lance $mkA @('new', 'slimreel', '--kit', 'slim', '--json')
        $mkJsonSlim = TkJson $r
        Verifie "new --kit slim : code 0, kit slim, type api, base vide" (($r.Code -eq 0) -and $mkJsonSlim -and ($mkJsonSlim.kit -eq 'slim') -and ($mkJsonSlim.type -eq 'api') -and ($mkJsonSlim.base -eq '') -and (-not $mkJsonSlim.auth.enabled)) "code=$($r.Code) $($r.Sortie)"
        $mkSlim = Join-Path $mkA 'slimreel'
        $mkConfSlim = [IO.File]::ReadAllText((Join-Path $mkSlim 'ebony.conf'), [Text.Encoding]::UTF8)
        Verifie "ebony.conf : kit slim, modules vide, aucune section base" (($mkConfSlim -match '"kit":\s*"slim"') -and ($mkConfSlim -match '"modules":\s*\[\s*\]') -and ($mkConfSlim -notmatch '"base"')) $mkConfSlim
        Verifie "ebony\ ne porte que le coeur : ni donnees ni auth, ni leurs manifestes" ((Test-Path -LiteralPath (Join-Path $mkSlim 'ebony\cycle\cEbApplication.owl')) -and (-not (Test-Path -LiteralPath (Join-Path $mkSlim 'ebony\donnees'))) -and (-not (Test-Path -LiteralPath (Join-Path $mkSlim 'ebony\auth'))) -and (-not (Test-Path -LiteralPath (Join-Path $mkSlim 'ebony\modules\db.json'))) -and (-not (Test-Path -LiteralPath (Join-Path $mkSlim 'ebony\modules\auth.json')))) ''
        $mkEnvSlim = [IO.File]::ReadAllText((Join-Path $mkSlim 'config\env.json'), [Text.Encoding]::UTF8) + [IO.File]::ReadAllText((Join-Path $mkSlim '.env.exemple'), [Text.Encoding]::UTF8)
        Verifie "aucune variable DB_* dans config\env.json ni .env.exemple" ($mkEnvSlim -notmatch 'DB_') ''
        Verifie "aucun fichier .env ni dossier database\ : rien a configurer" ((-not (Test-Path -LiteralPath (Join-Path $mkSlim '.env'))) -and (-not (Test-Path -LiteralPath (Join-Path $mkSlim 'database')))) ''
        Push-Location $mkSlim; try { $mkCheckSlim = (owl --check projet.owl) -join ' ' } finally { Pop-Location }
        Verifie "owl --check passe sur le projet slim" ($mkCheckSlim -match '"errors":\[\]') $mkCheckSlim
        $r = Lance $mkSlim @('doctor', '--json')
        Verifie "doctor : code 0 sur le projet slim" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkSlim @('env', '--json')
        Verifie "env : code 0 (aucune variable a controler)" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkServeurSlim = MkDemarre $mkSlim
        try {
            Verifie "le service slim monte (owl serve), sans DB_* ni .env" $mkServeurSlim.Pret ("port " + $mkServeurSlim.Port)
            $rq = MkRequete $mkServeurSlim 'GET' '/api/health'
            Verifie "GET /api/health : 200 et {statut:ok}, sans la moindre base" (($rq.Code -eq 200) -and ($rq.Corps -eq '{"statut":"ok"}')) ("code=" + $rq.Code + " " + $rq.Corps)
            $rq = MkRequete $mkServeurSlim 'GET' '/api'
            Verifie "GET /api : l'accueil repond 200" ($rq.Code -eq 200) ("code=" + $rq.Code + " " + $rq.Corps)
        } finally { MkArrete $mkServeurSlim }
        Start-Sleep -Milliseconds 500
        $mkJournalSlim = ''; if (Test-Path -LiteralPath $mkServeurSlim.Sortie) { $mkJournalSlim = (Get-Content -Raw -Encoding UTF8 -LiteralPath $mkServeurSlim.Sortie) }
        Verifie "le journal du service slim : application demarree, aucune base ouverte, aucun avertissement" (($mkJournalSlim -match '"message":"Application d.marr.e"') -and ($mkJournalSlim -notmatch 'Base ouverte') -and ($mkJournalSlim -notmatch '"niveau":"(warn|error)"')) $mkJournalSlim
        $r = Lance $mkSlim @('migrate', '--json')
        Verifie "migrate : refuse (code 1), nomme le module db" (($r.Code -eq 1) -and ($r.Sortie -match "n'a pas le module") -and ($r.Sortie -match 'db')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkSlim @('make', 'resource', 'X', '--champs', 'id:entier*,nom:texte', '--table', 'xs', '--json')
        Verifie "make resource : refuse (code 1), nomme le module db" (($r.Code -eq 1) -and ($r.Sortie -match "n'a pas le module") -and ($r.Sortie -match 'db')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkSlim @('token', 'list', '--json')
        Verifie "token : refuse (code 1), nomme le module auth" (($r.Code -eq 1) -and ($r.Sortie -match "n'a pas le module") -and ($r.Sortie -match 'auth')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkA @('new', 'slim-base', '--kit', 'slim', '--base', 'postgresql')
        Verifie "new --kit slim --base : refuse (code 2), dit comment obtenir une base" (($r.Code -eq 2) -and ($r.Sortie -match '--kit api')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkA @('new', 'slim-auth', '--kit', 'slim', '--auth')
        Verifie "new --kit slim --auth : refuse (code 2)" ($r.Code -eq 2) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkA @('new', 'kit-inconnu', '--kit', 'web')
        Verifie "new --kit web : refuse (code 2), liste les kits" (($r.Code -eq 2) -and ($r.Sortie -match 'api, slim')) "code=$($r.Code) $($r.Sortie)"
        Verifie "aucun des trois projets refuses n'a ete cree" ((-not (Test-Path -LiteralPath (Join-Path $mkA 'slim-base'))) -and (-not (Test-Path -LiteralPath (Join-Path $mkA 'slim-auth'))) -and (-not (Test-Path -LiteralPath (Join-Path $mkA 'kit-inconnu')))) ''
        # ---- ebony add : un module de plus dans un projet existant. Critere de reussite : slim, puis add db, puis add auth redonne un projet api neuf (aux fichiers kit pres : ebony.conf, README.md, AGENTS.md). ----
        Write-Host "  ebony add : slim + add db + add auth redonne un projet api neuf (octet pour octet, hors kit)"
        $r = Lance $mkA @('new', 'addreel', '--kit', 'slim', '--json')
        Verifie "add : le projet slim de depart est cree" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkAdd = Join-Path $mkA 'addreel'
        $r = Lance $mkAdd @('add', 'auth', '--json')
        Verifie "add auth avant db : refuse (code 1), dit d'ajouter db d'abord" (($r.Code -eq 1) -and ($r.Sortie -match 'ebony add db')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkAdd @('add', 'validation', '--json')
        Verifie "add d'un module inconnu : refuse (code 1), liste les modules possibles" (($r.Code -eq 1) -and ($r.Sortie -match "n'existe pas") -and ($r.Sortie -match 'auth, db')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkAdd @('add', '--json')
        Verifie "add sans nom de module : usage incorrect (code 2)" ($r.Code -eq 2) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkAdd @('add', 'db', '--base', 'oracle')
        Verifie "add db --base oracle : usage incorrect (code 2)" ($r.Code -eq 2) "code=$($r.Code) $($r.Sortie)"
        $mkConfAvant = [IO.File]::ReadAllText((Join-Path $mkAdd 'ebony.conf'), [Text.Encoding]::UTF8)
        Verifie "les refus n'ont rien ecrit : ebony.conf et ebony\ inchanges" (($mkConfAvant -match '"modules":\s*\[\s*\]') -and (-not (Test-Path -LiteralPath (Join-Path $mkAdd 'ebony\donnees')))) $mkConfAvant
        $r = Lance $mkAdd @('add', 'db', '--json')
        $mkJsonAdd = TkJson $r
        Verifie "add db : code 0, base sqlite, ebony.conf et le registre reecrits" (($r.Code -eq 0) -and $mkJsonAdd -and ($mkJsonAdd.module -eq 'db') -and ($mkJsonAdd.base -eq 'sqlite') -and (@($mkJsonAdd.updated) -contains 'ebony.conf') -and (@($mkJsonAdd.updated) -contains 'app/Composants.owl')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkAdd @('add', 'db')
        Verifie "add db une seconde fois : refuse (code 1), module deja present" (($r.Code -eq 1) -and ($r.Sortie -match 'd.j. dans ce projet')) "code=$($r.Code) $($r.Sortie)"
        $r = Lance $mkAdd @('add', 'auth', '--json')
        $mkJsonAdd = TkJson $r
        Verifie "add auth : code 0, la migration des jetons est ecrite, ebony migrate est la suite" (($r.Code -eq 0) -and $mkJsonAdd -and (@($mkJsonAdd.modules) -join ',') -eq 'db,auth' -and (@($mkJsonAdd.files) -contains 'database/migrations/M202611100000_CreeEbJetons.owl') -and (@($mkJsonAdd.next) -contains 'ebony migrate')) "code=$($r.Code) $($r.Sortie)"
        # La reference : le meme projet cree d'un coup en kit api, dans un autre dossier parent (meme nom : meme identifiant).
        $mkRefParent = Join-Path $mkA 'refadd'
        New-Item -ItemType Directory -Force $mkRefParent | Out-Null
        $r = Lance $mkRefParent @('new', 'addreel', '--json')
        Verifie "add : le projet api de reference est cree" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
        $mkRefAdd = Join-Path $mkRefParent 'addreel'
        $mkListeAdd = { param($Racine) Get-ChildItem -LiteralPath $Racine -Recurse -File -Force | Where-Object { $_.FullName.Substring($Racine.Length + 1) -notin @('ebony.conf', 'README.md', 'AGENTS.md') } | ForEach-Object { $_.FullName.Substring($Racine.Length + 1) + ' ' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } }
        $mkDiffAdd = Compare-Object @(& $mkListeAdd $mkAdd) @(& $mkListeAdd $mkRefAdd)
        $mkNbAdd = @(& $mkListeAdd $mkRefAdd).Count
        Verifie "slim + add db + add auth : memes fichiers et memes octets qu'un projet api neuf (hors ebony.conf, README.md, AGENTS.md)" (($mkNbAdd -ge 30) -and (@($mkDiffAdd).Count -eq 0)) "fichiers de reference : $mkNbAdd ; differences : $(@($mkDiffAdd | ForEach-Object { $_.InputObject }) -join ' | ')"
        $mkConfAdd = [IO.File]::ReadAllText((Join-Path $mkAdd 'ebony.conf'), [Text.Encoding]::UTF8)
        $mkConfRefAdd = [IO.File]::ReadAllText((Join-Path $mkRefAdd 'ebony.conf'), [Text.Encoding]::UTF8)
        Verifie "ebony.conf : seul le kit note differe (slim contre api)" (($mkConfAdd -replace '"kit": "slim"', '"kit": "api"') -ceq $mkConfRefAdd) $mkConfAdd
        Push-Location $mkAdd; try { $mkCheckAdd = (owl --check projet.owl) -join ' ' } finally { Pop-Location }
        Verifie "owl --check passe sur le projet obtenu par add" ($mkCheckAdd -match '"errors":\[\]') $mkCheckAdd
        $r = Lance $mkAdd @('migrate', '--json')
        Verifie "migrate applique la migration ecrite par add auth" (($r.Code -eq 0) -and ($r.Sortie -match 'CreeEbJetons')) "code=$($r.Code) $($r.Sortie)"
        Write-Host "  une colonne dont le nom est ignore par OWL comme membre (liste) : pas de controleur, et la note le dit"
        $r = Lance $mkP @('make', 'resource', 'Etiquette', '--champs', 'id:entier*,liste:texte', '--dry-run', '--json')
        $mkJsonSans = $null; try { $mkJsonSans = $r.Sortie.Trim() | ConvertFrom-Json } catch { }
        Verifie "code 0, neuf fichiers (pas de controleur), la note nomme la colonne" (($r.Code -eq 0) -and $mkJsonSans -and (@($mkJsonSans.created).Count -eq 9) -and (-not (@($mkJsonSans.created) | Where-Object { $_ -match 'Controleur' })) -and ((@($mkJsonSans.notes) -join ' ') -match 'Le contr.leur n.est pas .crit') -and ((@($mkJsonSans.notes) -join ' ') -match 'liste')) "code=$($r.Code) $($r.Sortie)"
        Nettoie $mkTraces
        }   # fin du groupe 'make'
        if ($Groupe -in 'tous', 'installe') {
        # ---- ebony install : installe ebony lui-meme (dossier des programmes + PATH). Le dossier des programmes est redirige vers un dossier de test (EBONY_PROGRAMMES)
        # et le PATH vers une variable de TEST (EBONY_PATH_VAR) : le vrai PATH de l'utilisateur n'est JAMAIS modifie (verifie a la fin). ----
        Write-Host "install : ebony s'installe dans le dossier des programmes et s'ajoute au PATH (variable de test)"
        $ieNomVariable = 'EBONY_TEST_PATH'
        $ieCleUtilisateur = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
        $ieLitPath = { param($Nom) $ieCleUtilisateur.GetValue($Nom, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
        if ($null -ne (& $ieLitPath $ieNomVariable)) { throw "La variable de test $ieNomVariable existe deja dans le registre de l'utilisateur : arret." }
        $ieVraiPathAvant = & $ieLitPath 'Path'
        $ieRacineTemp = Join-Path ([IO.Path]::GetTempPath()) ('ebony_install_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Force $ieRacineTemp | Out-Null
        try {
            # Tout ce que cette section installe ou copie est HORS du depot (dossier temporaire du systeme, ici sur C:) : tous les .owl d'un projet sont charges ensemble, donc une copie d'ebony
            # laissee sous le depot ferait voir les memes noms deux fois a l'ebony du depot. Le dossier de depart (D:) et celui des programmes (C:) sont sur deux disques differents si la machine
            # en a deux : c'est le cas reel qui faisait echouer fRepCree avec owl 1.5.0 et 1.6.0 (corrige en 1.7.0, le lanceur n'a plus de contournement).
            $ieProgrammes = Join-Path $ieRacineTemp 'programmes'
            New-Item -ItemType Directory -Force $ieProgrammes | Out-Null
            $ieEnv = @{ EBONY_PROGRAMMES = $ieProgrammes; EBONY_PATH_VAR = $ieNomVariable }
            $ieDossierVersion = Join-Path $ieProgrammes ('ebony\' + $nwVersionDepot)
            $ieBin = Join-Path $ieDossierVersion 'bin'
            $ieDepart = NwDossierNeuf 'depart'

            $r = Lance $ieDepart @('install') $ieEnv
            Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
            if ((Split-Path -Qualifier $ieProgrammes) -eq (Split-Path -Qualifier $ieDepart)) { Write-Host "  (note : un seul disque ici, le cas ""depart et programmes sur deux disques"" n'est pas couvert)" } else { Write-Host ("  (couvert : depart sur " + (Split-Path -Qualifier $ieDepart) + ", programmes sur " + (Split-Path -Qualifier $ieProgrammes) + ")") }
            Verifie "annonce l'installation et le dossier" (($r.Sortie -match 'install.') -and $r.Sortie.Contains('ebony\' + $nwVersionDepot)) $r.Sortie
            Verifie "annonce la mise a jour du PATH" ($r.Sortie -match 'PATH utilisateur mis . jour') $r.Sortie
            foreach ($ieDossier in 'bin', 'src', 'modules') {
                Verifie ("dossier " + $ieDossier + " identique, fichier par fichier, a celui du depot") ((NiEmpreinte (Join-Path $ieDossierVersion $ieDossier)) -eq (NiEmpreinte (Join-Path $depot $ieDossier))) ''
            }
            foreach ($ieFichier in 'ebony.owl', 'projet.owl', 'LICENSE', 'README.md') {
                Verifie ("fichier " + $ieFichier + " identique") ((Test-Path -LiteralPath (Join-Path $ieDossierVersion $ieFichier)) -and ((Get-FileHash -LiteralPath (Join-Path $ieDossierVersion $ieFichier)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $depot $ieFichier)).Hash)) ''
            }
            Verifie "tests, docs, scripts, assets et .git ne sont pas copies" (-not (@('tests', 'docs', 'scripts', 'assets', '.git', 'tmp') | Where-Object { Test-Path -LiteralPath (Join-Path $ieDossierVersion $_) })) ''
            Verifie "le fichier INSTALLE contient la version" ((Get-Content -Raw -Encoding UTF8 (Join-Path $ieDossierVersion 'INSTALLE')).Trim() -eq $nwVersionDepot) ''
            Verifie "la variable de PATH de test contient le dossier bin installe" ((& $ieLitPath $ieNomVariable) -eq $ieBin) (& $ieLitPath $ieNomVariable)

            Write-Host "la copie installee fonctionne seule (lanceur installe, depuis un autre dossier)"
            $ieLanceurInstalle = Join-Path $ieBin 'ebony.cmd'
            $r = Lance $ieDepart @('doctor') @{} $ieLanceurInstalle
            Verifie "doctor : code 0, cinq verifications, sans erreur ni avertissement" (($r.Code -eq 0) -and ($r.Sortie -match 'Bilan : 5 v.rification\(s\), 0 erreur\(s\), 0 avertissement\(s\)')) "code=$($r.Code) $($r.Sortie)"
            Verifie "doctor cite le dossier d'installation sous son nom LONG et non sous son nom court 8.3 (~)" ($r.Sortie.Contains($ieDossierVersion) -and -not ($r.Sortie -match "Installation d.ebony : [^\r\n]*~")) $r.Sortie
            $r = Lance $ieDepart @('new', 'depuis-installe') @{} $ieLanceurInstalle
            Verifie "new : code 0, projet cree par la copie installee" (($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $ieDepart 'depuis-installe\projet.owl'))) "code=$($r.Code) $($r.Sortie)"
            Push-Location (Join-Path $ieDepart 'depuis-installe')
            try { Verifie "le projet produit compile (owl --check)" (((owl --check projet.owl) -join ' ') -match '"errors":\[\]') '' } finally { Pop-Location }
            Verifie "sa bibliotheque ebony/ est celle de la copie installee" ((NiEmpreinte (Join-Path $ieDepart 'depuis-installe\ebony')) -eq (NiEmpreinteBibliothequeDepot)) ''

            Write-Host "new --json et options (copie installee : hors du depot, la sortie ne porte que le JSON)"
            $r = Lance $ieDepart @('new', 'Ma', 'Boutique', '--base', 'postgresql', '--auth', '--table', 'users', '--json') @{} $ieLanceurInstalle
            $ieLignes = @(($r.Sortie -split "`r?`n") | Where-Object { $_ -ne '' })
            Verifie "code 0 et une seule ligne sur la sortie" (($r.Code -eq 0) -and ($ieLignes.Count -eq 1)) "code=$($r.Code) $($r.Sortie)"
            $ieJson = $null
            try { $ieJson = $ieLignes[0] | ConvertFrom-Json } catch { }
            Verifie "la ligne est un objet JSON valide avec ok=true" (($null -ne $ieJson) -and ($ieJson.ok -eq $true)) $r.Sortie
            if ($null -ne $ieJson) {
                Verifie "dir est le dossier cree" (($ieJson.dir -eq (Join-Path $ieDepart 'ma-boutique')) -and (Test-Path -LiteralPath $ieJson.dir)) $ieLignes[0]
                Verifie "files : chaque fichier annonce existe" (-not ($ieJson.files | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ieJson.dir $_.TrimEnd('/'))) })) $ieLignes[0]
                Verifie "files contient .env.exemple, next donne trois consignes" (($ieJson.files -contains '.env.exemple') -and ($ieJson.next.Count -eq 3)) $ieLignes[0]
                Verifie "base, type, authentification et table rendus" (($ieJson.base -eq 'postgresql') -and ($ieJson.type -eq 'api') -and ($ieJson.auth.enabled -eq $true) -and ($ieJson.auth.table -eq 'users') -and ($ieJson.auth.mode -eq 'opaque')) $ieLignes[0]
            }
            $ieConf = Get-Content -Raw -Encoding UTF8 (Join-Path $ieDepart 'ma-boutique\ebony.conf') | ConvertFrom-Json
            Verifie "ebony.conf : base postgresql, jetons, table users" (($ieConf.base.fournisseur -eq 'postgresql') -and ($ieConf.auth.jetons -eq $true) -and ($ieConf.auth.table -eq 'users') -and ($ieConf.auth.mode -eq 'opaque')) ($ieConf | ConvertTo-Json -Compress)
            $ieEnvExemple = [IO.File]::ReadAllText((Join-Path $ieDepart 'ma-boutique\.env.exemple'), [Text.Encoding]::UTF8)
            Verifie ".env.exemple : variables PostgreSQL, nom de la base = dossier" ($ieEnvExemple.Contains('DB_PORT=5432') -and $ieEnvExemple.Contains('DB_NOM=ma-boutique') -and -not $ieEnvExemple.Contains('DB_FICHIER')) $ieEnvExemple
            $ieSecretsExemple = [IO.File]::ReadAllText((Join-Path $ieDepart 'ma-boutique\.env.secrets.exemple'), [Text.Encoding]::UTF8)
            Verifie ".env.secrets.exemple : le mot de passe (vide) y est, et seulement la-bas" ($ieSecretsExemple.Contains("DB_MOT_DE_PASSE=`n") -and -not $ieEnvExemple.Contains('MOT_DE_PASSE')) $ieSecretsExemple
            Verifie "config/Auth.owl existe (--auth), annonce dans files" (Test-Path -LiteralPath (Join-Path $ieDepart 'ma-boutique\config\Auth.owl')) ''
            # Le contenu vient du manifeste d'auth : la table du projet, et les colonnes que la migration des utilisateurs cree (une seule source).
            $ieAuthOwl = [IO.File]::ReadAllText((Join-Path $ieDepart 'ma-boutique\config\Auth.owl'), [Text.Encoding]::UTF8)
            $ieMigrationUtilisateurs = [IO.File]::ReadAllText((Join-Path $ieDepart 'ma-boutique\database\migrations\M202611100001_CreeUtilisateurs.owl'), [Text.Encoding]::UTF8)
            Verifie "config/Auth.owl (manifeste d'auth) : table users" ($ieAuthOwl.Contains('"users"')) $ieAuthOwl
            Verifie "config/Auth.owl : les colonnes sont celles de la migration des utilisateurs" ((@('identifiant', 'mot_de_passe', 'role') | Where-Object { -not ($ieAuthOwl.Contains("`"$_`"") -and $ieMigrationUtilisateurs.Contains($_)) }).Count -eq 0) $ieAuthOwl
            Verifie "config/Auth.owl : pas de jeton {table_utilisateurs} restant, LF seul" ((-not $ieAuthOwl.Contains('{table_utilisateurs}')) -and (-not $ieAuthOwl.Contains("`r"))) $ieAuthOwl
            owl fmt --check (Join-Path $ieDepart 'ma-boutique\config\Auth.owl') | Out-Null
            Verifie "config/Auth.owl passe owl fmt --check" ($LASTEXITCODE -eq 0) "code=$LASTEXITCODE"
            Push-Location (Join-Path $ieDepart 'ma-boutique')
            try {
                $ieCheckAuth = (owl --check projet.owl) -join ' '
                Verifie "le projet produit avec --auth compile (owl --check, config/Auth.owl compris)" ($ieCheckAuth -match '"errors":\[\]') $ieCheckAuth
                $ieRunAuth = ((owl projet.owl 2>&1) | ForEach-Object { "$_" }) -join ' '
                Verifie "le projet produit avec --auth s'execute" ($ieRunAuth -match '^Ma Boutique : projet cr') $ieRunAuth
            } finally { Pop-Location }
            $ieRefus = Lance $ieDepart @('new', 'refuse', '--base', 'mysql', '--json') @{} $ieLanceurInstalle
            Verifie "valeur refusee : code 2, { ok:false, error } sur une ligne, rien cree" (($ieRefus.Code -eq 2) -and ($ieRefus.Sortie -match '^\{"ok":false,"error":".*mysql.*"\}\s*$') -and -not (Test-Path -LiteralPath (Join-Path $ieDepart 'refuse'))) "code=$($ieRefus.Code) $($ieRefus.Sortie)"
            $ieRefus = Lance $ieDepart @('new', 'refuse', '--table', 'users') @{} $ieLanceurInstalle
            Verifie "--table sans --auth : code 2, message court sans pile d'appels" (($ieRefus.Code -eq 2) -and ($ieRefus.Sortie -match '--auth') -and ($ieRefus.Sortie -notmatch 'Pile')) "code=$($ieRefus.Code) $($ieRefus.Sortie)"
            $ieRefus = Lance $ieDepart @('new', 'ma-boutique', '--json') @{} $ieLanceurInstalle
            Verifie "dossier deja occupe avec --json : code 1, { ok:false, error }" (($ieRefus.Code -eq 1) -and ($ieRefus.Sortie -match '^\{"ok":false,"error":"')) "code=$($ieRefus.Code) $($ieRefus.Sortie)"

            Write-Host "init : ajouter ebony a un projet OWL existant (copie installee, hors du depot)"
            function IiDossierNeuf([string]$Nom) { $ii1 = Join-Path (Join-Path $ieRacineTemp 'init') $Nom; New-Item -ItemType Directory -Force $ii1 | Out-Null; return $ii1 }
            $iiProjet = IiDossierNeuf 'projet-existant'
            $iiSansBom = New-Object Text.UTF8Encoding($false)
            $iiTexteProjet = "MonAppli est un Projet`n`tPROPRIETES`n`t`tDescription = ""Mon appli""`n`t`tLangues = [langueFran" + [char]0xE7 + "ais]`n`tFIN`n`n`tTrace(""mon appli demarre"")`nFIN`n"
            [IO.File]::WriteAllText((Join-Path $iiProjet 'projet.owl'), $iiTexteProjet, $iiSansBom)
            [IO.File]::WriteAllText((Join-Path $iiProjet '.gitignore'), "*.log`n", $iiSansBom)
            $iiHashProjet = (Get-FileHash -LiteralPath (Join-Path $iiProjet 'projet.owl')).Hash
            $iiHashGitignore = (Get-FileHash -LiteralPath (Join-Path $iiProjet '.gitignore')).Hash
            $r = Lance $iiProjet @('init', '--base', 'postgresql', '--auth', '--json') @{} $ieLanceurInstalle
            $iiLignes = @(($r.Sortie -split "`r?`n") | Where-Object { $_ -ne '' })
            Verifie "init --json : code 0 et une seule ligne" (($r.Code -eq 0) -and ($iiLignes.Count -eq 1)) "code=$($r.Code) $($r.Sortie)"
            $iiJson = $null
            try { $iiJson = $iiLignes[0] | ConvertFrom-Json } catch { }
            Verifie "la ligne est un objet JSON avec ok=true" (($null -ne $iiJson) -and ($iiJson.ok -eq $true)) $r.Sortie
            if ($null -ne $iiJson) {
                Verifie "files : ebony/, ebony.conf, .env.exemple, .env.secrets.exemple, config/env.json, README.md, AGENTS.md, app/Composants.owl, config/Auth.owl, la migration des jetons (pas projet.owl ni .gitignore)" ((($iiJson.files | Sort-Object) -join ',') -eq ((@('ebony/', 'ebony.conf', '.env.exemple', '.env.secrets.exemple', 'config/env.json', 'README.md', 'AGENTS.md', 'app/Composants.owl', 'config/Auth.owl', 'database/migrations/M202611100000_CreeEbJetons.owl') | Sort-Object) -join ',')) $iiLignes[0]
                Verifie "kept : projet.owl et .gitignore" ((($iiJson.kept | Sort-Object) -join ',') -eq ((@('projet.owl', '.gitignore') | Sort-Object) -join ',')) $iiLignes[0]
                Verifie "notes : le .gitignore n'a pas ebony/, storage/, .env ni .env.secrets, puis le registre a appeler depuis le service" (($iiJson.notes.Count -eq 2) -and ($iiJson.notes[0] -match 'ebony/, storage/, \.env, \.env\.secrets') -and ($iiJson.notes[1] -match 'POUR TOUT oFabrique DE')) $iiLignes[0]
                Verifie "identifiant lu dans projet.owl, base, authentification" (($iiJson.identifier -eq 'MonAppli') -and ($iiJson.base -eq 'postgresql') -and ($iiJson.auth.enabled -eq $true) -and ($iiJson.auth.mode -eq 'opaque')) $iiLignes[0]
            }
            Verifie "projet.owl et .gitignore sont octet pour octet ceux d'avant" (((Get-FileHash -LiteralPath (Join-Path $iiProjet 'projet.owl')).Hash -eq $iiHashProjet) -and ((Get-FileHash -LiteralPath (Join-Path $iiProjet '.gitignore')).Hash -eq $iiHashGitignore)) ''
            foreach ($iiFichier in 'ebony.conf', '.env.exemple', '.env.secrets.exemple', 'config\env.json', 'README.md', 'AGENTS.md', 'config\Auth.owl', 'ebony\VERSION') {
                Verifie ("fichier cree : " + $iiFichier) (Test-Path -LiteralPath (Join-Path $iiProjet $iiFichier)) ''
            }
            $iiConf = Get-Content -Raw -Encoding UTF8 (Join-Path $iiProjet 'ebony.conf') | ConvertFrom-Json
            Verifie "ebony.conf : identifiant du projet existant, nom du dossier, version, base, jetons" (($iiConf.projet.identifiant -eq 'MonAppli') -and ($iiConf.projet.nom -eq 'projet-existant') -and ($iiConf.ebony.version -eq $nwVersionDepot) -and ($iiConf.base.fournisseur -eq 'postgresql') -and ($iiConf.auth.jetons -eq $true)) ($iiConf | ConvertTo-Json -Compress)
            Push-Location $iiProjet
            try {
                $iiCheck = (owl --check projet.owl) -join ' '
                Verifie "le projet avec ebony ajoute compile (owl --check)" ($iiCheck -match '"errors":\[\]') $iiCheck
                $iiRun = ((owl projet.owl 2>&1) | ForEach-Object { "$_" }) -join ' '
                Verifie "le projet s'execute comme avant" ($iiRun -match '^mon appli demarre') $iiRun
            } finally { Pop-Location }
            $r = Lance $iiProjet @('doctor') @{} $ieLanceurInstalle
            Verifie "doctor dans le projet : code 0, cinq verifications, sans erreur" (($r.Code -eq 0) -and ($r.Sortie -match 'Bilan : 5 v.rification\(s\), 0 erreur\(s\)')) "code=$($r.Code) $($r.Sortie)"

            Write-Host "init une seconde fois, sur un dossier sans projet.owl, et avec un conflit"
            $r = Lance $iiProjet @('init', '--json') @{} $ieLanceurInstalle
            Verifie "deja ebony : code 1, { ok:false, error } qui renvoie vers ebony upgrade" (($r.Code -eq 1) -and ($r.Sortie -match '^\{"ok":false,"error":".*ebony upgrade')) "code=$($r.Code) $($r.Sortie)"
            $iiVide = IiDossierNeuf 'sans-projet'
            $r = Lance $iiVide @('init') @{} $ieLanceurInstalle
            Verifie "pas de projet.owl : code 1, message sans pile d'appels, rien cree" (($r.Code -eq 1) -and ($r.Sortie -match 'projet\.owl est absent') -and ($r.Sortie -notmatch 'Pile') -and -not (Test-Path -LiteralPath (Join-Path $iiVide 'ebony'))) "code=$($r.Code) $($r.Sortie)"
            $iiConflit = IiDossierNeuf 'conflit'
            [IO.File]::WriteAllText((Join-Path $iiConflit 'projet.owl'), "ConflitAppli est un Projet`nFIN`n", $iiSansBom)
            New-Item -ItemType Directory (Join-Path $iiConflit 'ebony') | Out-Null
            [IO.File]::WriteAllText((Join-Path $iiConflit 'ebony\mien.txt'), "a moi", $iiSansBom)
            $r = Lance $iiConflit @('init') @{} $ieLanceurInstalle
            Verifie "ebony/ deja la : code 1, liste le conflit, rien ecrit" (($r.Code -eq 1) -and ($r.Sortie -match 'Rien n.a .t. .crit') -and ($r.Sortie -match 'ebony/') -and -not (Test-Path -LiteralPath (Join-Path $iiConflit 'ebony.conf')) -and ([IO.File]::ReadAllText((Join-Path $iiConflit 'ebony\mien.txt')) -ceq 'a moi')) "code=$($r.Code) $($r.Sortie)"
            $r = Lance $iiVide @('init', 'mon-nom') @{} $ieLanceurInstalle
            Verifie "init avec un nom : code 2 (usage), il n'en prend pas" (($r.Code -eq 2) -and ($r.Sortie -match 'ne prend pas de nom')) "code=$($r.Code) $($r.Sortie)"

            Write-Host "request : envoyer des requetes a un vrai service (owl serve), via la copie installee"
            $rqService = Join-Path $ieRacineTemp 'service-request'
            New-Item -ItemType Directory -Force $rqService | Out-Null
            [IO.File]::WriteAllText((Join-Path $rqService 'projet.owl'), ("AppMesure est un Projet`n`tPROPRIETES`n`t`tDescription = ""mesure""`n`t`tLangues = [langueFran" + [char]0xE7 + "ais]`n`tFIN`nFIN`n"), $iiSansBom)
            $rqTexteService = "ServiceMesure est un ServiceREST`n`tPROPRIETES`n`t`tUrlBase = [""api""]`n`tFIN`n`n`tLitClient est une Op{e}rationHTTP`n`t`tPROPRIETES`n`t`t`tM{e}thode  = httpGet`n`t`t`tChemin   = [""clients"", id]`n`t`t`tR{e}ponses = [httpOK]`n`t`t`tCode{E}tat = httpOK`n`t`tFIN`n`t`tPROCEDURE surRequ{ec}te(id est un entier) : entier`n`t`t`tRENVOYER id`n`t`tFIN`n`tFIN`nFIN`n"
            $rqTexteService = $rqTexteService.Replace('{e}', [string][char]0xE9).Replace('{E}', [string][char]0xC9).Replace('{ec}', [string][char]0xEA)
            [IO.File]::WriteAllText((Join-Path $rqService 'ServiceMesure.owl'), $rqTexteService, $iiSansBom)
            function RqPortLibre { $rq1 = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $rq1.Start(); $rq2 = $rq1.LocalEndpoint.Port; $rq1.Stop(); return $rq2 }
            $rqPort = RqPortLibre
            $rqProcessus = Start-Process -FilePath owl -ArgumentList @('serve', '--port', $rqPort) -WorkingDirectory $rqService -PassThru @fenetreCachee
            try {
                $rqPret = $false
                for ($rqEssai = 0; $rqEssai -lt 40 -and -not $rqPret; $rqEssai++) {
                    try { $null = Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:" + $rqPort + "/api/clients/42") -TimeoutSec 2; $rqPret = $true } catch { Start-Sleep -Milliseconds 500 }
                }
                Verifie "le service de test repond (owl serve)" $rqPret ("port " + $rqPort)
                if ($rqPret) {
                    $r = Lance $iiVide @('request', 'GET', '/api/clients/42', '--port', $rqPort, '--header', '"Accept: application/json"', '--json') @{} $ieLanceurInstalle
                    $rqLignes = @(($r.Sortie -split "`r?`n") | Where-Object { $_ -ne '' })
                    Verifie "request --json : code 0 et une seule ligne" (($r.Code -eq 0) -and ($rqLignes.Count -eq 1)) "code=$($r.Code) $($r.Sortie)"
                    $rqJson = $null
                    try { $rqJson = $rqLignes[0] | ConvertFrom-Json } catch { }
                    Verifie "ok, statut 200, corps 42, en-tete Content-Type JSON, duree" (($null -ne $rqJson) -and ($rqJson.ok -eq $true) -and ($rqJson.status -eq 200) -and ($rqJson.body -eq '42') -and ($rqJson.headers.'Content-Type' -eq 'application/json') -and ($rqJson.ms -ge 0)) $r.Sortie
                    $r = Lance $iiVide @('request', 'GET', '/api/inconnu', '--url', ('http://127.0.0.1:' + $rqPort)) @{} $ieLanceurInstalle
                    Verifie "un 404 est une reponse : code 0, texte 'HTTP 404'" (($r.Code -eq 0) -and ($r.Sortie -match 'HTTP 404 Not Found')) "code=$($r.Code) $($r.Sortie)"
                    $r = Lance $iiVide @('request', 'POST', '/api/clients/42', '--port', $rqPort, '--body', '"{\"a\":1}"', '--json') @{} $ieLanceurInstalle
                    Verifie "POST avec un corps JSON atteint le service (la route n'accepte que GET : 404, mais une reponse)" (($r.Code -eq 0) -and ($r.Sortie -match '"ok":true')) "code=$($r.Code) $($r.Sortie)"
                }
            } finally {
                $rqCommande = (CommandeDuProcessus $rqProcessus.Id)
                if ($rqCommande -and $rqCommande.Contains('serve') -and $rqCommande.Contains([string]$rqPort)) { Stop-Process -Id $rqProcessus.Id -ErrorAction SilentlyContinue }
                elseif ($rqCommande) { Write-Host ("  [ECHEC]  le processus " + $rqProcessus.Id + " n'est pas notre service, non arrete : " + $rqCommande) -ForegroundColor Red; $script:echecs++ }
            }
            $rqPortFerme = RqPortLibre
            $r = Lance $iiVide @('request', 'GET', '/x', '--port', $rqPortFerme, '--json') @{} $ieLanceurInstalle
            Verifie "aucune reponse : code 1, { ok:false, error } qui dit de verifier owl serve et --port" (($r.Code -eq 1) -and ($r.Sortie -match '^\{"ok":false,"error":"Aucune r.ponse') -and ($r.Sortie -match 'owl serve')) "code=$($r.Code) $($r.Sortie)"
            $r = Lance $iiVide @('request', 'GET', 'api') @{} $ieLanceurInstalle
            Verifie "chemin sans barre initiale : code 2 (usage), sans pile d'appels" (($r.Code -eq 2) -and ($r.Sortie -match 'doit commencer par') -and ($r.Sortie -notmatch 'Pile')) "code=$($r.Code) $($r.Sortie)"
            $r = Lance $iiVide @('request', 'FETCH', '/x') @{} $ieLanceurInstalle
            Verifie "methode inconnue : code 2 et liste des methodes" (($r.Code -eq 2) -and ($r.Sortie -match 'GET, POST, PUT, DELETE, PATCH, HEAD')) "code=$($r.Code) $($r.Sortie)"

            Write-Host "install une seconde fois (deja installe, deja dans le PATH)"
            $r = Lance $ieDepart @('install') $ieEnv
            Verifie "code 0, dit deja installe et deja dans le PATH" (($r.Code -eq 0) -and ($r.Sortie -match 'd.j. install.') -and ($r.Sortie -match 'd.j. dans le PATH')) "code=$($r.Code) $($r.Sortie)"
            Verifie "la variable de PATH de test est inchangee" ((& $ieLitPath $ieNomVariable) -eq $ieBin) (& $ieLitPath $ieNomVariable)

            Write-Host "install depuis la copie installee elle-meme"
            $r = Lance $ieDepart @('install') $ieEnv $ieLanceurInstalle
            Verifie "code 0 et deja installe" (($r.Code -eq 0) -and ($r.Sortie -match 'd.j. install.')) "code=$($r.Code) $($r.Sortie)"

            Write-Host "install d'une NOUVELLE version : a cote de l'ancienne, PATH deplace vers la nouvelle"
            $ieNouvelle = Join-Path $ieRacineTemp 'nouvelle-source'

            foreach ($ieDossier in 'bin', 'src', 'modules') { Copy-Item -Recurse -LiteralPath (Join-Path $depot $ieDossier) -Destination (Join-Path $ieNouvelle $ieDossier) }
            foreach ($ieFichier in 'ebony.owl', 'projet.owl', 'LICENSE', 'README.md') { Copy-Item -LiteralPath (Join-Path $depot $ieFichier) -Destination (Join-Path $ieNouvelle $ieFichier) }
            [IO.File]::WriteAllText((Join-Path $ieNouvelle 'modules\core\execution\VERSION'), '9.9.9', (New-Object Text.UTF8Encoding($false)))
            $ieAvantAncienne = NiEmpreinte $ieDossierVersion
            $r = Lance $ieDepart @('install') $ieEnv (Join-Path $ieNouvelle 'bin\ebony.cmd')
            Verifie "code 0 et installe en 9.9.9" (($r.Code -eq 0) -and $r.Sortie.Contains('ebony\9.9.9')) "code=$($r.Code) $($r.Sortie)"
            Verifie "l'ancienne version est intacte (rien d'ecrase ni supprime)" ((NiEmpreinte $ieDossierVersion) -eq $ieAvantAncienne) ''
            Verifie "la nouvelle version a son dossier et son marqueur" ((Get-Content -Raw -Encoding UTF8 (Join-Path $ieProgrammes 'ebony\9.9.9\INSTALLE')).Trim() -eq '9.9.9') ''
            Verifie "le PATH de test ne contient plus que la nouvelle version" ((& $ieLitPath $ieNomVariable) -eq (Join-Path $ieProgrammes 'ebony\9.9.9\bin')) (& $ieLitPath $ieNomVariable)
            Verifie "annonce le retrait de l'ancienne entree" ($r.Sortie -match 'retir.') $r.Sortie

            Write-Host "install quand le dossier des programmes n'existe pas (refus, PATH non modifie)"
            $ieAvantRefus = & $ieLitPath $ieNomVariable
            $r = Lance $ieDepart @('install') @{ EBONY_PROGRAMMES = (Join-Path $ieProgrammes 'absent'); EBONY_PATH_VAR = $ieNomVariable }
            Verifie "code 1 et dit que le dossier des programmes est introuvable ou inconnu" (($r.Code -eq 1) -and ($r.Sortie -match 'programmes')) "code=$($r.Code) $($r.Sortie)"
            Verifie "le PATH de test n'a pas ete touche" ((& $ieLitPath $ieNomVariable) -eq $ieAvantRefus) ''
            Verifie "aucun dossier ebony cree la-bas" (-not (Test-Path -LiteralPath (Join-Path $ieProgrammes 'absent'))) ''

            Write-Host "install quand le dossier de la version est occupe par autre chose (refus, PATH non modifie)"
            $ieOccupe = Join-Path $ieRacineTemp 'programmes-occupe'

            New-Item -ItemType Directory -Force (Join-Path $ieOccupe ('ebony\' + $nwVersionDepot)) | Out-Null
            Set-Content -LiteralPath (Join-Path $ieOccupe ('ebony\' + $nwVersionDepot + '\x.txt')) -Value 'x'
            $r = Lance $ieDepart @('install') @{ EBONY_PROGRAMMES = $ieOccupe; EBONY_PATH_VAR = $ieNomVariable }
            Verifie "code 1 et dit qu'ebony ne supprime rien" (($r.Code -eq 1) -and ($r.Sortie -match 'ne supprime rien')) "code=$($r.Code) $($r.Sortie)"
            Verifie "le PATH de test n'a pas ete touche" ((& $ieLitPath $ieNomVariable) -eq $ieAvantRefus) ''

            # ---- ebony uninstall : retire ebony du PATH ET supprime les versions installees. Le cas le plus dur : le lancer DEPUIS la copie installee, qui se supprime elle-meme pendant qu'elle s'execute. ----
            Write-Host "uninstall depuis la copie installee elle-meme (la version du depot et 9.9.9 sont installees, 9.9.9 est dans le PATH)"
            $ieBaseInstallee = Join-Path $ieProgrammes 'ebony'
            $ieLanceur999 = Join-Path $ieBaseInstallee '9.9.9\bin\ebony.cmd'
            $ieDossierProtege = Join-Path $ieProgrammes 'ebony-autre\bin'
            New-Item -ItemType Directory -Force $ieDossierProtege | Out-Null
            Set-Content -LiteralPath (Join-Path $ieDossierProtege 'precieux.txt') -Value 'a garder'
            $r = Lance $ieDepart @('uninstall') $ieEnv $ieLanceur999
            Verifie "code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
            Verifie "annonce la desinstallation" ($r.Sortie -match 'D.sinstallation d.ebony') $r.Sortie
            Verifie "aucune erreur parasite de cmd ou de PowerShell (le lanceur s'est supprime sans accroc)" (-not ($r.Sortie -match "introuvable|ECHEC|Erreur d.execution|n.a pas . . modifi")) $r.Sortie
            Verifie "les deux versions installees sont supprimees, ainsi que la base devenue vide" (-not (Test-Path -LiteralPath $ieBaseInstallee)) $r.Sortie
            Verifie "le rapport dit ce qui est supprime" (($r.Sortie -match ('supprim. : .*' + [regex]::Escape($nwVersionDepot))) -and ($r.Sortie -match 'supprim. : .*9\.9\.9')) $r.Sortie
            Verifie "le PATH de test ne contient plus ebony" (-not ((& $ieLitPath $ieNomVariable) -match 'ebony')) (& $ieLitPath $ieNomVariable)
            Verifie "un dossier voisin au nom proche (ebony-autre) est intact" ((Get-Content -LiteralPath (Join-Path $ieDossierProtege 'precieux.txt')) -eq 'a garder') ''
            Verifie "le dossier des programmes lui-meme est intact" (Test-Path -LiteralPath $ieProgrammes) ''

            Write-Host "uninstall quand ebony n'est plus installe (rien a supprimer, rien a retirer)"
            $r = Lance $ieDepart @('uninstall') $ieEnv
            Verifie "code 0, dit qu'ebony n'est pas installe et qu'il n'y a rien a retirer" (($r.Code -eq 0) -and ($r.Sortie -match "n.est pas install.") -and ($r.Sortie -match 'Rien . supprimer') -and ($r.Sortie -match 'Aucune entr.e d.ebony')) "code=$($r.Code) $($r.Sortie)"

            Write-Host "uninstall avec une entree de PATH orpheline (dossier supprime a la main), le reste du PATH conserve"
            $ieOrpheline = Join-Path $ieBaseInstallee '0.5.0\bin'
            $ieCleUtilisateur.SetValue($ieNomVariable, ('C:\A;' + $ieOrpheline + ';C:\Z'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
            $r = Lance $ieDepart @('uninstall') $ieEnv
            Verifie "code 0 et l'entree orpheline est retiree, C:\A et C:\Z conserves" (($r.Code -eq 0) -and ((& $ieLitPath $ieNomVariable) -eq 'C:\A;C:\Z')) ("code=$($r.Code) " + (& $ieLitPath $ieNomVariable) + " " + $r.Sortie)

            Write-Host "uninstall quand un dossier etranger se trouve dans le dossier d'ebony (il est laisse)"
            $ieEtranger = Join-Path $ieBaseInstallee 'mes-notes'
            New-Item -ItemType Directory -Force $ieEtranger | Out-Null
            Set-Content -LiteralPath (Join-Path $ieEtranger 'a-garder.txt') -Value 'a garder'
            $ieVersionFictive = Join-Path $ieBaseInstallee '0.7.0'
            New-Item -ItemType Directory -Force $ieVersionFictive | Out-Null
            Set-Content -LiteralPath (Join-Path $ieVersionFictive 'INSTALLE') -Value '0.7.0'
            $r = Lance $ieDepart @('uninstall') $ieEnv
            Verifie "code 0, la version portant INSTALLE est supprimee" (($r.Code -eq 0) -and (-not (Test-Path -LiteralPath $ieVersionFictive))) "code=$($r.Code) $($r.Sortie)"
            Verifie "le dossier etranger et son contenu sont laisses, ainsi que la base" (((Get-Content -LiteralPath (Join-Path $ieEtranger 'a-garder.txt')) -eq 'a garder') -and (Test-Path -LiteralPath $ieBaseInstallee)) $r.Sortie
            Verifie "le rapport dit qu'il l'a laisse" ($r.Sortie -match 'laiss. \(pas une installation') $r.Sortie

            Write-Host "uninstall quand le dossier des programmes est inconnu (refus : rien n'est supprime ni retire)"
            $ieAvantInconnu = & $ieLitPath $ieNomVariable
            $r = Lance $ieDepart @('uninstall') @{ EBONY_PROGRAMMES = (Join-Path $ieProgrammes 'absent'); EBONY_PATH_VAR = $ieNomVariable }
            Verifie "code 1 et dit que le dossier des programmes est inconnu" (($r.Code -eq 1) -and ($r.Sortie -match 'programmes')) "code=$($r.Code) $($r.Sortie)"
            Verifie "rien n'a ete supprime et le PATH de test est intact" ((Test-Path -LiteralPath $ieEtranger) -and ((& $ieLitPath $ieNomVariable) -eq $ieAvantInconnu)) ''
        }
        finally {
            # Nettoyage visible : la variable de test ne doit jamais rester dans le registre de l'utilisateur.
            try { if ($null -ne (& $ieLitPath $ieNomVariable)) { $ieCleUtilisateur.DeleteValue($ieNomVariable) } } catch { Write-Host ("  [ECHEC]  nettoyage de la variable de test impossible : " + $_.Exception.Message) -ForegroundColor Red; $script:echecs++ }
            if ($null -ne (& $ieLitPath $ieNomVariable)) { Write-Host "  [ECHEC]  la variable de test existe encore" -ForegroundColor Red; $script:echecs++ }
            Nettoie $ieRacineTemp
        }
        Verifie "le VRAI PATH de l'utilisateur est identique avant et apres tout ce test" ((& $ieLitPath 'Path') -eq $ieVraiPathAvant) ''
        $ieCleUtilisateur.Close()
        }   # fin du groupe 'installe'
    }
    finally { Nettoie $nwBase }
}
finally {
    Nettoie $espace
    if ($groupeTemp) { Nettoie $groupeTemp }
}

Write-Host ""
if ($Groupe -ne 'tous') { Write-Host ("groupe " + $Groupe) }
if ($echecs -eq 0) { Write-Host "TOUT PASSE" -ForegroundColor Green; exit 0 }
else { Write-Host ("$echecs ECHEC(S)") -ForegroundColor Red; exit 1 }
