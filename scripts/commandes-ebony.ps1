# Bibliotheque partagee des scripts (a charger avec ". .\commandes-ebony.ps1") : la liste des commandes d'ebony, lue dans l'aiguillage (EbAiguillage.owl).
#
# Source UNIQUE : la procedure EbExecuteCommande (SELON sCommande ... CAS "doctor" ...) de src\commandes\EbAiguillage.owl.
# Avant, la liste etait recopiee dans construit-entrees.ps1, bin\ebony.cmd, tests\integration\archive.ps1 : ajouter une commande sans tout mettre a jour la laissait
# retomber sans bruit sur le repli a 25 s. Seule la liste de bin\ebony.cmd reste ecrite a la main (un .cmd ne sait pas lire de l'OWL) : scripts\controle-commandes.ps1 la verifie.
# Ce fichier reste ASCII.

# Commandes sans point d'entree reduit : le menu d'aide ("" et "aide", qui utilise la liste des types de make) et "version" (le lanceur la traite seul,
# et chaque point d'entree reduit la sait aussi : voir construit-entrees.ps1).
$script:CommandesSansPointDEntree = @('', 'aide', 'version')

# Les commandes de l'aiguillage qui ont (ou doivent avoir) un point d'entree reduit, triees.
function Get-CommandesAiguillage([string]$CheminAiguillage) {
    if (-not (Test-Path -LiteralPath $CheminAiguillage)) { throw ("EbAiguillage.owl introuvable : " + $CheminAiguillage) }
    $lignes = @(Get-Content -LiteralPath $CheminAiguillage -Encoding UTF8)
    $debut = -1
    for ($rang = 0; $rang -lt $lignes.Count; $rang++) { if ($lignes[$rang] -match '^\tPROC\S+\s+EbExecuteCommande\s*\(') { $debut = $rang; break } }
    if ($debut -lt 0) { throw "EbAiguillage.owl : procedure EbExecuteCommande introuvable" }
    $commandes = New-Object 'System.Collections.Generic.List[string]'
    for ($rang = $debut + 1; $rang -lt $lignes.Count -and $lignes[$rang] -cne "`tFIN"; $rang++) {
        if ($lignes[$rang] -match '^\s*CAS\s+"') {
            foreach ($nom in [regex]::Matches($lignes[$rang], '"([^"]*)"')) {
                $valeur = $nom.Groups[1].Value
                if ($script:CommandesSansPointDEntree -notcontains $valeur -and -not $commandes.Contains($valeur)) { $commandes.Add($valeur) }
            }
        }
    }
    if ($commandes.Count -eq 0) { throw "EbAiguillage.owl : aucune commande trouvee dans EbExecuteCommande" }
    $tableau = $commandes.ToArray()
    [Array]::Sort($tableau, [StringComparer]::Ordinal)
    return $tableau
}
