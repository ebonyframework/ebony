# Controle de l'instantane public (feuille de route B3 et B4) : liste, dans les fichiers qui iraient dans un depot public, les traces du PROCESSUS de developpement
# (numeros d'issues, "le mainteneur", mesures datees, noms de l'ancien projet, outil d'assistance) qu'ADR-0006 demande de retirer ("depot humanise").
# Lecture seule : ne modifie rien, n'envoie rien. Par defaut il est INFORMATIF (code 0) ; avec -Strict, il echoue (code 1) s'il reste une trace.
#
# L'ensemble public est la liste ci-dessous : ce qui sert a installer, utiliser et verifier ebony (de docs\releases, seules les notes de la 0.1.0 : les anciennes ne sont pas publiees). N'en font pas partie CLAUDE.md, docs\decisions (ADR),
# docs\architecture (cadrage, audit, feuille de route : documents de travail) et docs\rapports-neowl (retours pour l'equipe OWL, a part). Cette liste est une PROPOSITION : voir docs\architecture\publication-0.3.0.md.
#
# Usage : .\scripts\controle-instantane.ps1 [-Strict] [-Detail]        (-Detail : chaque ligne trouvee, avec fichier et numero)
# Ce fichier reste ASCII.

param([switch]$Strict, [switch]$Detail)

$racine = Split-Path $PSScriptRoot -Parent
Set-Location $racine

# La liste des chemins publics est celle de publie-instantane.ps1 : une seule source.
$inclus = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'instantane-liste.txt') -Encoding UTF8 | Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() })
$fichiers = @(& git ls-files | Where-Object { $chemin = $_; @($inclus | Where-Object { $chemin -eq $_ -or ($_.EndsWith('/') -and $chemin.StartsWith($_)) }).Count -gt 0 } | Where-Object { $_ -eq 'README.md' -or $_.StartsWith('docs/guides/') -or -not $_.EndsWith('.md') })   # aucun .md public sauf le README racine et docs/guides/

# Chaque motif : un nom, une expression (insensible a la casse), et ce qu'on y fait. Ce fichier-ci est exclu de l'analyse (il cite les motifs).
$motifs = @(
    @{ Nom = "numero d'issue (#12, issue #12)";        Expression = '(?<![\w&/#])#\d{1,3}(?![\w])' },
    @{ Nom = "le mainteneur";                          Expression = 'mainteneur' },
    @{ Nom = "mesure datee dans un commentaire ou un texte"; Expression = 'mesur[^|]{0,60}20\d\d-\d\d-\d\d|20\d\d-\d\d-\d\d[^|]{0,30}mesur' },
    @{ Nom = "renvoi a un document non public";        Expression = 'docs[/\\](architecture|decisions|rapports-neowl|releases)|capability-audit|feuille-de-route|modules[/\\]README' },
    @{ Nom = "ancien projet (pcsoft, WinDev)";         Expression = 'pcsoft|windev' },
    @{ Nom = "outil d'assistance (Claude, Anthropic)"; Expression = 'claude|anthropic' },
    @{ Nom = "renvoi a un ADR";                        Expression = '\bADR-\d{4}' },
    @{ Nom = "renvoi a un depot prive (ElmiraLabs)";   Expression = 'ElmiraLabs/(ebonycore|sankofa)|ebonycore-dev' },
    @{ Nom = "decision deleguee, l'assistant";         Expression = "l'assistant|choix de l'assistant" },
    @{ Nom = "Sankofa (aucune mention publique)";     Expression = 'sankofa' },
    @{ Nom = "numero de version du developpement prive (0.2.x, 0.3.x : le public commence a 0.1.0)"; Expression = '\b0\.[23]\.(x|\d+)\b[^|]{0,40}(passer|mise a niveau|mise à niveau|garde sa|nouveau|depuis|since|upgrade)|(nouveau|depuis la|passer d.une|mise [àa] niveau d.une|since|new since)[^|]{0,30}\b0\.[23]\.(x|\d+)\b' }
)

$trouvailles = New-Object 'System.Collections.Generic.List[object]'
foreach ($fichier in $fichiers) {
    if ($fichier -eq 'scripts/controle-instantane.ps1') { continue }
    $ligneDonnee = '^\s*dbgV'
    $chemin = Join-Path $racine $fichier
    $texte = [IO.File]::ReadAllText($chemin, [Text.Encoding]::UTF8)
    if ($texte.IndexOf([char]0) -ge 0) { continue }   # binaire
    $lignes = $texte -split "`n"
    for ($numero = 0; $numero -lt $lignes.Count; $numero++) {
        if ($lignes[$numero] -match $ligneDonnee) { continue }   # donnee de test (une date dans une assertion), pas un commentaire
        foreach ($motif in $motifs) {
            if ([regex]::IsMatch($lignes[$numero], $motif.Expression, 'IgnoreCase')) {
                $trouvailles.Add([pscustomobject]@{ Motif = $motif.Nom; Fichier = $fichier; Ligne = $numero + 1; Texte = $lignes[$numero].Trim() })
            }
        }
    }
}

Write-Host ("Instantane propose : {0} fichiers suivis sur {1}." -f $fichiers.Count, @(& git ls-files).Count)
foreach ($motif in $motifs) {
    $parMotif = @($trouvailles | Where-Object { $_.Motif -eq $motif.Nom })
    $nbFichiers = @($parMotif | Select-Object -ExpandProperty Fichier -Unique).Count
    Write-Host ("  {0,4} ligne(s) dans {1,3} fichier(s) : {2}" -f $parMotif.Count, $nbFichiers, $motif.Nom)
    if ($Detail) { foreach ($t in $parMotif) { Write-Host ("        {0}:{1}  {2}" -f $t.Fichier, $t.Ligne, $t.Texte.Substring(0, [Math]::Min(110, $t.Texte.Length))) } }
}
$total = $trouvailles.Count
if ($total -eq 0) { Write-Host "Aucune trace du processus dans l'instantane propose."; exit 0 }
Write-Host ("Total : {0} ligne(s) a reecrire ou retirer avant l'ouverture." -f $total)
if ($Strict) { exit 1 }
exit 0
