# Test d'integration contre un VRAI PostgreSQL (Docker) : ebony migrate, le repository SQL genere par make resource, le service genere, et les niveaux TLS (DB_TLS).
# Ce que SQLite ne montre pas : le SQL de make migration / make resource accepte par PostgreSQL, le DDL annule avec la transaction, la connexion chiffree et verifiee.
#
# Il lance deux conteneurs JETABLES (postgres:16, ports libres sur 127.0.0.1) et ne touche a AUCUN autre serveur : pas au PostgreSQL de la machine, pas aux conteneurs des autres projets.
# Ignore (code 0, message) si Docker ne repond pas ou si l'image postgres:16 n'est pas deja telechargee : jamais de telechargement ici, et jamais d'echec parce que Docker manque.
# Les projets de test sont dans tmp\.travail du depot (dossier a point : ignore par OWL), le certificat de test est fabrique dans le conteneur.
# Usage : .\tests\integration\postgresql.ps1      (code de sortie 0 si tout passe ou si le test est ignore, 1 sinon)
# Ce fichier reste ASCII.

$ErrorActionPreference = 'Stop'
$depot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ebony = Join-Path $depot 'bin\ebony.cmd'
$image = 'postgres:16'
$echecs = 0

function Verifie([string]$Titre, [bool]$Condition, [string]$Detail) {
    if ($Condition) { Write-Host ("  [OK]     " + $Titre) }
    else { Write-Host ("  [ECHEC]  " + $Titre) -ForegroundColor Red; if ($Detail) { Write-Host ("           " + $Detail) }; $script:echecs++ }
}

# Docker : une commande, sortie et code. (Le code d'un programme natif ne leve pas ; stderr ne doit pas non plus lever.)
function Dk([string[]]$Arguments) {
    $ancien = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $sortie = (& docker @Arguments 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $code = $LASTEXITCODE
    $ErrorActionPreference = $ancien
    return @{ Code = $code; Sortie = $sortie.Trim() }
}

$dockerPret = $false
try { $dockerPret = ((Dk @('version', '--format', '{{.Server.Version}}')).Code -eq 0) } catch { }
if (-not $dockerPret) { Write-Host "IGNORE : Docker ne repond pas (le test PostgreSQL a besoin d'un serveur PostgreSQL jetable)."; exit 0 }
if ((Dk @('image', 'inspect', $image)).Code -ne 0) { Write-Host ("IGNORE : l'image " + $image + " n'est pas telechargee ici (docker pull " + $image + ") ; ce test ne telecharge rien."); exit 0 }

function PortLibre { $pl = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $pl.Start(); $pn = $pl.LocalEndpoint.Port; $pl.Stop(); return $pn }
function Lance([string]$Dossier, [string[]]$Arguments) {
    $p = New-Object Diagnostics.ProcessStartInfo
    $p.FileName = $env:ComSpec
    $p.Arguments = '/c ""' + $ebony + '" ' + ($Arguments -join ' ') + '"'
    $p.WorkingDirectory = $Dossier
    $p.UseShellExecute = $false
    $p.RedirectStandardOutput = $true; $p.RedirectStandardError = $true
    $p.StandardOutputEncoding = [Text.Encoding]::UTF8; $p.StandardErrorEncoding = [Text.Encoding]::UTF8
    $pr = [Diagnostics.Process]::Start($p)
    $sortie = $pr.StandardOutput.ReadToEnd() + $pr.StandardError.ReadToEnd()
    $pr.WaitForExit()
    return @{ Code = $pr.ExitCode; Sortie = $sortie }
}
function Json([object]$Resultat) { $pj = $null; try { $pj = $Resultat.Sortie.Trim() | ConvertFrom-Json } catch { }; return $pj }
$sansBom = New-Object Text.UTF8Encoding($false)
# Une requete HTTP au service lance (curl.exe, corps JSON lu dans un fichier : PowerShell 5.1 retire les guillemets d'un JSON passe en argument).
# Les routes generees sont PROTEGEES par defaut : le secret d'un vrai jeton (ebony token create) est envoye dans l'en-tete Authorization tant que $script:pgJeton n'est pas vide.
$script:pgJeton = ''
function PgRequete([int]$Port, [string]$Methode, [string]$Chemin, [string]$CorpsJson = '') {
    $prReponse = Join-Path $zone 'reponse.txt'
    if (Test-Path -LiteralPath $prReponse) { Remove-Item -LiteralPath $prReponse -Force }
    $prArguments = @('-s', '-m', '20', '-o', $prReponse, '-w', '%{http_code}', '-X', $Methode)
    if ($script:pgJeton -ne '') { $prArguments += @('-H', ('Authorization: Bearer ' + $script:pgJeton)) }
    if ($CorpsJson -ne '') {
        $prEnvoi = Join-Path $zone 'envoi.json'
        [IO.File]::WriteAllText($prEnvoi, $CorpsJson, $sansBom)
        $prArguments += @('-H', 'Content-Type: application/json', '--data-binary', ('@' + $prEnvoi))
    }
    $prArguments += ('http://127.0.0.1:' + $Port + $Chemin)
    $prCode = & curl.exe @prArguments
    $prTexte = ''
    if (Test-Path -LiteralPath $prReponse) { $prTexte = [IO.File]::ReadAllText($prReponse) }
    $prObjet = $null; try { $prObjet = $prTexte | ConvertFrom-Json } catch { }
    return @{ Code = [int]$prCode; Corps = $prTexte; Json = $prObjet }
}

$suffixe = [Guid]::NewGuid().ToString('N').Substring(0, 6)
$nomSansTls = 'ebony-test-pg-' + $suffixe
$nomAvecTls = 'ebony-test-pgtls-' + $suffixe
$portSansTls = PortLibre
$portAvecTls = PortLibre
$zone = Join-Path (Join-Path (Join-Path $depot 'tmp') '.travail') ('pg_' + $suffixe)
New-Item -ItemType Directory -Force $zone | Out-Null

# Attend que le VRAI serveur reponde en TCP (le serveur temporaire de l'initialisation n'ecoute que sur une socket) puis cree la base.
function AttendServeur([string]$Nom) {
    for ($k = 0; $k -lt 90; $k++) {
        if ((Dk @('exec', $Nom, 'psql', '-h', '127.0.0.1', '-U', 'postgres', '-tAc', 'SELECT 1')).Code -eq 0) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}
function Sql([string]$Nom, [string]$Requete) { return (Dk @('exec', $Nom, 'psql', '-U', 'postgres', '-d', 'pgapp', '-tAc', $Requete)).Sortie }

try {
    Write-Host ("PostgreSQL jetable sans TLS : " + $nomSansTls + " (127.0.0.1:" + $portSansTls + ")")
    $r = Dk @('run', '-d', '--rm', '--name', $nomSansTls, '-e', 'POSTGRES_PASSWORD=ebonytest', '-p', ('127.0.0.1:' + $portSansTls + ':5432'), $image)
    Verifie "le conteneur demarre" ($r.Code -eq 0) $r.Sortie
    Verifie "le serveur repond en TCP" (AttendServeur $nomSansTls) ''
    $null = Dk @('exec', $nomSansTls, 'psql', '-U', 'postgres', '-c', 'CREATE DATABASE pgapp')

    # ---- ebony new --base postgresql, configuration ecrite avec des chemins ABSOLUS (un chemin relatif serait lu depuis le dossier du processus, pas celui de PowerShell) ----
    $r = Lance $zone @('new', 'pgapp', '--base', 'postgresql')
    Verifie "ebony new pgapp --base postgresql : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
    $pgProjet = Join-Path $zone 'pgapp'
    [IO.File]::WriteAllText((Join-Path $pgProjet '.env'), ("DB_HOTE=127.0.0.1`nDB_PORT=" + $portSansTls + "`nDB_NOM=pgapp`nDB_UTILISATEUR=postgres`n"), $sansBom)
    [IO.File]::WriteAllText((Join-Path $pgProjet '.env.secrets'), "DB_MOT_DE_PASSE=ebonytest`n", $sansBom)
    $pgChamps = 'id:entier*,nom:texte,email:texte?,actif:booleen,solde:reel,naissance:date?'

    Write-Host "  TLS : OWL exige un TLS verifie par defaut"
    $r = Lance $pgProjet @('migrate', 'status')
    Verifie "serveur sans TLS, DB_TLS absent : code 1, et le message nomme DB_TLS=desactive" (($r.Code -eq 1) -and ($r.Sortie -match 'DB_TLS=desactive')) "code=$($r.Code) $($r.Sortie)"
    [IO.File]::AppendAllText((Join-Path $pgProjet '.env'), "DB_TLS=desactive`n", $sansBom)
    $r = Lance $pgProjet @('env', '--json')
    $pgEnv = Json $r
    Verifie "ebony env : DB_TLS vaut desactive, lu depuis .env" (($r.Code -eq 0) -and $pgEnv -and (@($pgEnv.variables | Where-Object { $_.cle -eq 'DB_TLS' -and $_.valeur -eq 'desactive' -and $_.source -eq '.env' }).Count -eq 1)) $r.Sortie

    Write-Host "  migrate sur PostgreSQL"
    $r = Lance $pgProjet @('make', 'migration', 'CreeClients', '--champs', ('"' + $pgChamps + '"'))
    Verifie "make migration CreeClients : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
    $r = Lance $pgProjet @('migrate', '--json')
    $pgJson = Json $r
    Verifie "migrate : code 0, deux migrations appliquees (celle des jetons, fournie par auth, puis CreeClients)" (($r.Code -eq 0) -and $pgJson -and ($pgJson.base -eq 'postgresql') -and (@($pgJson.done).Count -eq 2)) "code=$($r.Code) $($r.Sortie)"
    Verifie "les tables clients, eb_jetons (migration d'auth) et eb_migrations existent dans PostgreSQL" ((Sql $nomSansTls "SELECT string_agg(tablename, ',' ORDER BY tablename) FROM pg_tables WHERE schemaname='public'") -eq 'clients,eb_jetons,eb_migrations') ''
    $pgColonnes = Sql $nomSansTls "SELECT string_agg(column_name || ':' || data_type || ':' || is_nullable, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_name='clients'"
    Verifie "types : identite entiere, text, boolean, double precision, colonnes NULL" ($pgColonnes -eq 'id:integer:NO,nom:text:NO,email:text:YES,actif:boolean:NO,solde:double precision:NO,naissance:text:YES') $pgColonnes
    $r = Lance $pgProjet @('migrate', 'rollback', '--json')
    Verifie "rollback : la table clients a disparu, celle des jetons reste, le suivi n'a plus que la migration des jetons" (($r.Code -eq 0) -and ((Sql $nomSansTls "SELECT string_agg(tablename, ',' ORDER BY tablename) FROM pg_tables WHERE schemaname='public'") -eq 'eb_jetons,eb_migrations') -and ((Sql $nomSansTls 'SELECT count(*) FROM eb_migrations') -eq '1')) "code=$($r.Code) $($r.Sortie)"
    $r = Lance $pgProjet @('migrate', '--json')
    Verifie "migrate la reapplique" (($r.Code -eq 0) -and ((Sql $nomSansTls 'SELECT count(*) FROM clients') -eq '0')) "code=$($r.Code) $($r.Sortie)"

    # ---- ebony new --auth --table users : la migration de la table des utilisateurs (ecrite par le manifeste d'auth), jouee sur un vrai PostgreSQL. Une autre base du meme serveur. ----
    Write-Host "  ebony new --auth --table users : la migration des utilisateurs sur PostgreSQL"
    $null = Dk @('exec', $nomSansTls, 'psql', '-U', 'postgres', '-c', 'CREATE DATABASE pgauth')
    $r = Lance $zone @('new', 'pgauth', '--base', 'postgresql', '--auth', '--table', 'users')
    Verifie "ebony new pgauth --base postgresql --auth --table users : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
    $pgAuthProjet = Join-Path $zone 'pgauth'
    [IO.File]::WriteAllText((Join-Path $pgAuthProjet '.env'), ("DB_HOTE=127.0.0.1`nDB_PORT=" + $portSansTls + "`nDB_NOM=pgauth`nDB_UTILISATEUR=postgres`nDB_TLS=desactive`n"), $sansBom)
    [IO.File]::WriteAllText((Join-Path $pgAuthProjet '.env.secrets'), "DB_MOT_DE_PASSE=ebonytest`n", $sansBom)
    $r = Lance $pgAuthProjet @('migrate', '--json')
    $pgAuthJson = Json $r
    Verifie "migrate : code 0, deux migrations (jetons puis utilisateurs)" (($r.Code -eq 0) -and $pgAuthJson -and (@($pgAuthJson.done).Count -eq 2) -and ($r.Sortie -match 'CreeUtilisateurs')) "code=$($r.Code) $($r.Sortie)"
    function SqlAuth([string]$Requete) { return (Dk @('exec', $nomSansTls, 'psql', '-U', 'postgres', '-d', 'pgauth', '-tAc', $Requete)).Sortie }
    Verifie "la table users existe : colonnes identifiant, mot_de_passe, role (text, NOT NULL)" ((SqlAuth "SELECT string_agg(column_name || ':' || data_type || ':' || is_nullable, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_name='users'") -eq 'identifiant:text:NO,mot_de_passe:text:NO,role:text:NO') ''
    Verifie "identifiant est la cle primaire" ((SqlAuth "SELECT count(*) FROM information_schema.key_column_usage k JOIN information_schema.table_constraints c USING (constraint_name, table_name) WHERE k.table_name='users' AND c.constraint_type='PRIMARY KEY' AND k.column_name='identifiant'") -eq '1') ''
    $null = SqlAuth "INSERT INTO users (identifiant) VALUES ('ada')"
    Verifie "les valeurs par defaut : mot de passe vide, role utilisateur" ((SqlAuth "SELECT mot_de_passe || '|' || role FROM users WHERE identifiant='ada'") -eq '|utilisateur') ''
    $pgAuthDoublon = Dk @('exec', $nomSansTls, 'psql', '-U', 'postgres', '-d', 'pgauth', '-c', "INSERT INTO users (identifiant) VALUES ('ada')")
    Verifie "un identifiant en double est refuse par la base" ($pgAuthDoublon.Sortie -match 'duplicate key|unique') $pgAuthDoublon.Sortie
    $r = Lance $pgAuthProjet @('migrate', 'rollback', '--json')
    Verifie "rollback : la table users a disparu, celle des jetons reste" (($r.Code -eq 0) -and ((SqlAuth "SELECT string_agg(tablename, ',' ORDER BY tablename) FROM pg_tables WHERE schemaname='public' AND tablename IN ('users','eb_jetons')") -eq 'eb_jetons')) "code=$($r.Code) $($r.Sortie)"

    Write-Host "  une migration cassee : le DDL est annule avec la transaction (PostgreSQL le permet)"
    $pgGuillemet = [string][char]34
    $pgI = [string][char]0xEE
    $pgCassee = "cMx est une Classe implemente iEbMigration`n`tPROCEDURE PUBLIQUE Nom() : cha" + $pgI + "ne`n`t`tRENVOYER " + $pgGuillemet + "M299912312359_Cassee" + $pgGuillemet + "`n`tFIN`n`tPROCEDURE PUBLIQUE Monte() : tableau de cha" + $pgI + "nes`n`t`ttabSql est un tableau de cha" + $pgI + "nes`n`t`tTableauAjoute(tabSql, " + $pgGuillemet + "CREATE TABLE temoin (id INTEGER)" + $pgGuillemet + ")`n`t`tTableauAjoute(tabSql, " + $pgGuillemet + "CREATE TABLE casse (" + $pgGuillemet + ")`n`t`tRENVOYER tabSql`n`tFIN`n`tPROCEDURE PUBLIQUE Descend() : tableau de cha" + $pgI + "nes`n`t`ttabSql est un tableau de cha" + $pgI + "nes`n`t`tTableauAjoute(tabSql, " + $pgGuillemet + "DROP TABLE temoin" + $pgGuillemet + ")`n`t`tRENVOYER tabSql`n`tFIN`nFIN`n"
    $pgFichierCasse = Join-Path $pgProjet 'database\migrations\M299912312359_Cassee.owl'
    [IO.File]::WriteAllText($pgFichierCasse, $pgCassee, $sansBom)
    $r = Lance $pgProjet @('migrate', '--json')
    $pgJson = Json $r
    Verifie "code 1, { ok: false } qui nomme la migration et l'instruction" (($r.Code -eq 1) -and $pgJson -and ($pgJson.ok -eq $false) -and ($pgJson.error -match 'M299912312359_Cassee') -and ($pgJson.error -match 'instruction 2 sur 2')) "code=$($r.Code) $($r.Sortie)"
    Verifie "la premiere instruction est annulee : pas de table temoin ; clients reste ; suivi intact" (((Sql $nomSansTls "SELECT count(*) FROM pg_tables WHERE tablename='temoin'") -eq '0') -and ((Sql $nomSansTls 'SELECT count(*) FROM eb_migrations') -eq '2')) ''
    Remove-Item -LiteralPath $pgFichierCasse -Force

    Write-Host "  make resource : le repository SQL genere, rejoue sur PostgreSQL (memes scenarios que sur SQLite)"
    $r = Lance $pgProjet @('make', 'resource', 'Client', '--champs', ('"' + $pgChamps + '"'), '--json')
    Verifie "make resource Client : code 0" ($r.Code -eq 0) "code=$($r.Code) $($r.Sortie)"
    $pgTest = Join-Path $pgProjet 'tests\integration\client\test_cRepoClientSql.owl'
    $pgTexte = [IO.File]::ReadAllText($pgTest, [Text.Encoding]::UTF8)
    $pgE = [string][char]0xE9
    $pgBackquote = [string][char]96
    $pgFabrique = "// Une base PostgreSQL de test, ouverte, table videe (elle vient de ebony migrate).`nPROCEDURE BaseDeTestClient() : cEbBaseResiliente`n`tcnx est une sqlConnexion`n`tcnx..Provider = sqlPostgres`n`tcnx..Serveur = " + $pgGuillemet + "127.0.0.1:" + $portSansTls + $pgGuillemet + "`n`tcnx..BaseDeDonn" + $pgE + "es = " + $pgGuillemet + "pgapp" + $pgGuillemet + "`n`tcnx..Utilisateur = " + $pgGuillemet + "postgres" + $pgGuillemet + "`n`tcnx..MotDePasse = " + $pgGuillemet + "ebonytest" + $pgGuillemet + "`n`tcnx..ModeTLS = tlsDesactive`n`toConnexion est un cEbConnexionSqlReelle(cnx, " + $pgGuillemet + "SELECT 1" + $pgGuillemet + ")`n`toBase      est un cEbBaseResiliente(oConnexion)`n`toBase.Ouvre()`n`ttabAucun est un tableau associatif`n`toBase.Execute(" + $pgBackquote + "TRUNCATE TABLE " + $pgGuillemet + "clients" + $pgGuillemet + " RESTART IDENTITY" + $pgBackquote + ", tabAucun)`n`tRENVOYER oBase`nFIN`n`n"
    $pgModifie = [regex]::Replace($pgTexte, '(?s)// Une base SQLite en m.moire.*?(?=// La base du sc.nario en cours)', $pgFabrique.Replace('$', '$$'))
    Verifie "le test genere a bien ete adapte a PostgreSQL" ($pgModifie -ne $pgTexte) ''
    [IO.File]::WriteAllText($pgTest, $pgModifie, $sansBom)
    Push-Location $pgProjet
    try {
        $ErrorActionPreference = 'Continue'
        $pgSortieTest = ((owl test -vv --filter test_cRepoClientSql 2>&1) | ForEach-Object { "$_" }) -join ' '
        $ErrorActionPreference = 'Stop'
    } finally { $ErrorActionPreference = 'Stop'; Pop-Location }
    Verifie "owl test : le repository SQL passe ses 8 scenarios sur PostgreSQL (ajout avec RETURNING, lecture, modification, suppression, 404, NULL)" (($pgSortieTest -match 'ALL CLEAR \(1 suites') -and ($pgSortieTest -match '8 scenarios') -and ($pgSortieTest -notmatch 'FAIL|CRASH')) $pgSortieTest

    Write-Host "  un jeton d'acces sur PostgreSQL (les routes generees sont protegees par defaut)"
    $r = Lance $pgProjet @('token', 'create', 'test-pg', '--json')
    $pgJsonJeton = Json $r
    $pgSecret = ''
    if ($pgJsonJeton) { $pgSecret = [string]$pgJsonJeton.token }
    Verifie "token create sur PostgreSQL : code 0 et un secret eb_" (($r.Code -eq 0) -and ($pgSecret -match '^eb_')) "code=$($r.Code) $($r.Sortie)"
    Verifie "la table eb_jetons existe dans PostgreSQL, avec un jeton" ((Sql $nomSansTls 'SELECT count(*) FROM eb_jetons') -eq '1') ''

    Write-Host "  le service genere sur PostgreSQL"
    $pgPortService = PortLibre
    $pgServiceFichier = @(Get-ChildItem (Join-Path $pgProjet 'app\http') -Filter 'Service*.owl')[0].Name
    $pgJournal = Join-Path $zone 'service.log'
    $pgService = Start-Process -FilePath 'owl' -ArgumentList @('serve', ('app/http/' + $pgServiceFichier), '--port', $pgPortService) -WorkingDirectory $pgProjet -PassThru -WindowStyle Hidden -RedirectStandardOutput $pgJournal -RedirectStandardError (Join-Path $zone 'service.err')
    $pgSante = ''
    try {
        for ($k = 0; $k -lt 60; $k++) {
            Start-Sleep -Seconds 3
            $pgRep = & curl.exe -s --max-time 4 ('http://127.0.0.1:' + $pgPortService + '/api/health') 2>$null
            if ($LASTEXITCODE -eq 0 -and $pgRep) { $pgSante = "$pgRep"; break }
        }
        # Le controleur genere par make resource (ControleurClient.owl), sur le meme service : le CRUD complet contre PostgreSQL. La table vient de ebony migrate.
        if ($pgSante) {
            $script:pgJeton = ''
            $pgSansJeton = PgRequete $pgPortService 'GET' '/api/clients'
            $script:pgJeton = $pgSecret
            $pgListeVide = PgRequete $pgPortService 'GET' '/api/clients'
            $pgCree = PgRequete $pgPortService 'POST' '/api/clients' '{"nom":"Ada","email":"a@x.fr","actif":true,"solde":12.5,"naissance":"1990-01-02"}'
            $pgLu = PgRequete $pgPortService 'GET' '/api/clients/1'
            $pgModifieReponse = PgRequete $pgPortService 'PUT' '/api/clients/1' '{"nom":"Ada L.","email":"ada@x.fr","actif":false,"solde":20,"naissance":"1990-01-03"}'
            $pgRelu = PgRequete $pgPortService 'GET' '/api/clients/1'
            $pgAbsent = PgRequete $pgPortService 'GET' '/api/clients/999'
            $pgInvalide = PgRequete $pgPortService 'POST' '/api/clients' '{"nom":"  "}'
            $pgSupprime = PgRequete $pgPortService 'DELETE' '/api/clients/1'
            $pgSupprimeEncore = PgRequete $pgPortService 'DELETE' '/api/clients/1'
            $pgListeFinale = PgRequete $pgPortService 'GET' '/api/clients'
        }
    } finally { Stop-Process -Id $pgService.Id -Force -ErrorAction SilentlyContinue }
    Verifie "GET /api/health : statut ok et base ok" (($pgSante -match '"statut":"ok"') -and ($pgSante -match '"base":"ok"')) $pgSante
    if ($pgSante) {
        Write-Host "  le controleur genere (make resource) sur PostgreSQL : liste, creation, lecture, modification, suppression"
        Verifie "sans jeton : 401 { code: non_autorise }, avant la route" (($pgSansJeton.Code -eq 401) -and $pgSansJeton.Json -and ($pgSansJeton.Json.code -eq 'non_autorise')) ("code=" + $pgSansJeton.Code + " " + $pgSansJeton.Corps)
        Verifie "GET /api/clients : 200 et liste vide" (($pgListeVide.Code -eq 200) -and ($pgListeVide.Corps -eq '[]')) ("code=" + $pgListeVide.Code + " " + $pgListeVide.Corps)
        Verifie "POST : 201, la cle vient de INSERT ... RETURNING, les valeurs sont relues" (($pgCree.Code -eq 201) -and $pgCree.Json -and ($pgCree.Json.id -eq 1) -and ($pgCree.Json.nom -eq 'Ada') -and ($pgCree.Json.actif -eq $true) -and ($pgCree.Json.solde -eq 12.5) -and ($pgCree.Json.naissance -eq '1990-01-02')) ("code=" + $pgCree.Code + " " + $pgCree.Corps)
        Verifie "GET /api/clients/1 : 200 et Ada, relue depuis PostgreSQL" (($pgLu.Code -eq 200) -and $pgLu.Json -and ($pgLu.Json.nom -eq 'Ada') -and ($pgLu.Json.email -eq 'a@x.fr')) ("code=" + $pgLu.Code + " " + $pgLu.Corps)
        Verifie "PUT /api/clients/1 : 200 et la modification est dans la base" (($pgModifieReponse.Code -eq 200) -and ($pgRelu.Code -eq 200) -and $pgRelu.Json -and ($pgRelu.Json.nom -eq 'Ada L.') -and ($pgRelu.Json.actif -eq $false) -and ($pgRelu.Json.solde -eq 20)) ("code=" + $pgModifieReponse.Code + " " + $pgRelu.Corps)
        Verifie "GET d'une cle absente : 404 { code: introuvable }" (($pgAbsent.Code -eq 404) -and $pgAbsent.Json -and ($pgAbsent.Json.code -eq 'introuvable')) ("code=" + $pgAbsent.Code + " " + $pgAbsent.Corps)
        Verifie "POST d'un texte obligatoire vide : 400 { code: invalide }" (($pgInvalide.Code -eq 400) -and $pgInvalide.Json -and ($pgInvalide.Json.code -eq 'invalide')) ("code=" + $pgInvalide.Code + " " + $pgInvalide.Corps)
        Verifie "DELETE : 204, puis 404 la seconde fois" (($pgSupprime.Code -eq 204) -and ($pgSupprimeEncore.Code -eq 404)) ("codes=" + $pgSupprime.Code + "," + $pgSupprimeEncore.Code)
        Verifie "GET /api/clients : liste vide de nouveau" (($pgListeFinale.Code -eq 200) -and ($pgListeFinale.Corps -eq '[]')) ("code=" + $pgListeFinale.Code + " " + $pgListeFinale.Corps)
    }

    # ---- TLS : un serveur avec un certificat signe par une autorite de test ----
    Write-Host ("PostgreSQL jetable avec TLS : " + $nomAvecTls + " (127.0.0.1:" + $portAvecTls + ")")
    $r = Dk @('run', '-d', '--rm', '--name', $nomAvecTls, '-e', 'POSTGRES_PASSWORD=ebonytest', '-p', ('127.0.0.1:' + $portAvecTls + ':5432'), $image)
    Verifie "le conteneur demarre" ($r.Code -eq 0) $r.Sortie
    Verifie "le serveur repond en TCP" (AttendServeur $nomAvecTls) ''
    $null = Dk @('exec', $nomAvecTls, 'psql', '-U', 'postgres', '-c', 'CREATE DATABASE pgapp')
    $pgCertificats = "set -e`nmkdir -p /var/lib/postgresql/certs && cd /var/lib/postgresql/certs`nopenssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 2 -subj /CN=ebony-test-ca 2>/dev/null`nopenssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj /CN=localhost 2>/dev/null`nprintf 'subjectAltName=DNS:localhost,IP:127.0.0.1' > ext.cnf`nopenssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 2 -extfile ext.cnf 2>/dev/null`nchown postgres:postgres *; chmod 600 server.key`n"
    $r = Dk @('exec', $nomAvecTls, 'bash', '-c', $pgCertificats)
    Verifie "certificat de test fabrique dans le conteneur" ($r.Code -eq 0) $r.Sortie
    # Un -c par commande : ALTER SYSTEM refuse de tourner dans un bloc de plusieurs instructions (un seul -c les enveloppe dans une transaction).
    $r = Dk @('exec', $nomAvecTls, 'psql', '-U', 'postgres', '-c', "ALTER SYSTEM SET ssl_cert_file='/var/lib/postgresql/certs/server.crt'", '-c', "ALTER SYSTEM SET ssl_key_file='/var/lib/postgresql/certs/server.key'", '-c', "ALTER SYSTEM SET ssl='on'", '-c', 'SELECT pg_reload_conf()')
    Verifie "ALTER SYSTEM : ssl, certificat et cle" ($r.Code -eq 0) $r.Sortie
    Start-Sleep -Seconds 2
    Verifie "ssl est actif sur le serveur" ((Dk @('exec', $nomAvecTls, 'psql', '-U', 'postgres', '-tAc', 'SHOW ssl')).Sortie -eq 'on') ''
    # Le serveur REFUSE ensuite toute connexion non chiffree : une connexion qui passe est donc vraiment chiffree.
    $r = Dk @('exec', $nomAvecTls, 'bash', '-c', "sed -i '1i hostnossl all all all reject' /var/lib/postgresql/data/pg_hba.conf")
    $null = Dk @('exec', $nomAvecTls, 'psql', '-U', 'postgres', '-tAc', 'SELECT pg_reload_conf()')
    Start-Sleep -Seconds 2
    $pgCa = Join-Path $zone 'ca.crt'
    $r = Dk @('cp', ($nomAvecTls + ':/var/lib/postgresql/certs/ca.crt'), $pgCa)
    Verifie "l'autorite de test est copiee" (($r.Code -eq 0) -and (Test-Path -LiteralPath $pgCa)) $r.Sortie

    function EssaiTls([string]$Titre, [string]$Tls, [string]$Certificat, [bool]$Attendu) {
        $pgEnvTls = "DB_HOTE=127.0.0.1`nDB_PORT=" + $portAvecTls + "`nDB_NOM=pgapp`nDB_UTILISATEUR=postgres`nDB_TLS=" + $Tls + "`n"
        if ($Certificat -ne '') { $pgEnvTls += "DB_CERTIFICAT_CA=" + $Certificat + "`n" }
        [IO.File]::WriteAllText((Join-Path $pgProjet '.env'), $pgEnvTls, $sansBom)
        $pgRes = Lance $pgProjet @('migrate', 'status')
        Verifie $Titre ((($pgRes.Code -eq 0) -eq $Attendu)) "code=$($pgRes.Code) $($pgRes.Sortie)"
    }
    Write-Host "  DB_TLS : chaque niveau, contre un serveur qui refuse le non chiffre"
    EssaiTls "verifie, autorite inconnue : refuse" 'verifie' '' $false
    EssaiTls "verifie + DB_CERTIFICAT_CA : accepte (certificat et nom du serveur verifies)" 'verifie' $pgCa $true
    EssaiTls "ca + DB_CERTIFICAT_CA : accepte (chaine verifiee)" 'ca' $pgCa $true
    EssaiTls "accepte : accepte (chiffre, certificat non verifie)" 'accepte' '' $true
    EssaiTls "desactive : refuse par le serveur (pas de chiffrement)" 'desactive' '' $false
}
finally {
    foreach ($pgNom in $nomSansTls, $nomAvecTls) { $null = Dk @('rm', '-f', $pgNom) }
    if (Test-Path -LiteralPath $zone) {
        try { Remove-Item -Recurse -Force -LiteralPath $zone -ErrorAction Stop }
        catch { Start-Sleep -Seconds 2; try { Remove-Item -Recurse -Force -LiteralPath $zone -ErrorAction Stop } catch { Write-Host ("  [ECHEC]  nettoyage impossible de " + $zone) -ForegroundColor Red; $echecs++ } }
    }
}

Write-Host ""
if ($echecs -eq 0) { Write-Host "POSTGRESQL : TOUT PASSE" -ForegroundColor Green; exit 0 }
else { Write-Host ("POSTGRESQL : " + $echecs + " ECHEC(S)") -ForegroundColor Red; exit 1 }
