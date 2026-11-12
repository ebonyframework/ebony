# Ajoute le dossier bin d'une version d'ebony au PATH de l'UTILISATEUR, ou retire ebony du PATH (-Retire). Jamais le PATH de la machine, aucun droit d'administrateur requis.
# Appele par bin\ebony.cmd apres un "ebony install" ou un "ebony uninstall" reussi : OWL ne peut ni lire ni ecrire l'environnement ni le registre.
#   -Dossier      le dossier bin a ajouter (il doit contenir ebony.cmd). Sans objet avec -Retire.
#   -Base         le dossier qui contient les versions installees (...\Programs\ebony) : les entrees des AUTRES versions y sont retirees du PATH (ou toutes, avec -Retire),
#                 les fichiers ne sont jamais touches
#   -NomVariable  la variable modifiee, Path par defaut. Les tests utilisent une autre variable (EBONY_TEST_PATH) pour ne jamais toucher au vrai PATH.
#   -Retire       retire du PATH toutes les entrees d'ebony (celles qui sont sous -Base et finissent par \bin), meme si le dossier n'existe plus (entree orpheline)
# Le PATH est lu et ecrit dans le registre sans expansion (une entree %USERPROFILE%\bin reste %USERPROFILE%\bin), son type (REG_SZ ou REG_EXPAND_SZ) est conserve,
# les autres entrees et leur ordre sont conserves, et le resultat est idempotent. Ce fichier reste ASCII : les accents sont fabriques avec [char].
param(
    [string]$Dossier = '',
    [Parameter(Mandatory = $true)][string]$Base,
    [string]$NomVariable = 'Path',
    [switch]$Retire
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$eAigu = [string][char]0xE9
$aGrave = [string][char]0xE0

function Normalise([string]$Chemin) { return $Chemin.Trim().TrimEnd('\').ToLowerInvariant() }

try {
    if (-not $Retire) {
        if ($Dossier.Trim() -eq '') { throw "le dossier a ajouter n'est pas indiqu$eAigu" }
        if (-not (Test-Path -LiteralPath (Join-Path $Dossier 'ebony.cmd'))) {
            throw ("le lanceur est introuvable : " + (Join-Path $Dossier 'ebony.cmd'))
        }
    }

    $cleEnvironnement = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $valeurBrute = $cleEnvironnement.GetValue($NomVariable, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $genreValeur = [Microsoft.Win32.RegistryValueKind]::ExpandString
        if ($null -ne $valeurBrute) { $genreValeur = $cleEnvironnement.GetValueKind($NomVariable) } else { $valeurBrute = '' }

        $entrees = @($valeurBrute -split ';' | Where-Object { $_.Trim() -ne '' })
        $cibleNormalisee = ''
        if (-not $Retire) { $cibleNormalisee = Normalise $Dossier }
        $prefixeBase = (Normalise $Base) + '\'
        $nouvellesEntrees = New-Object System.Collections.Generic.List[string]
        $entreesRetirees = New-Object System.Collections.Generic.List[string]
        $cibleDejaLa = $false
        foreach ($entree in $entrees) {
            $entreeNormalisee = Normalise $entree
            if ((-not $Retire) -and ($entreeNormalisee -eq $cibleNormalisee)) {
                if (-not $cibleDejaLa) { $cibleDejaLa = $true; $nouvellesEntrees.Add($entree) }
                continue
            }
            if ($entreeNormalisee.StartsWith($prefixeBase) -and $entreeNormalisee.EndsWith('\bin')) { $entreesRetirees.Add($entree); continue }
            $nouvellesEntrees.Add($entree)
        }
        if ((-not $Retire) -and (-not $cibleDejaLa)) { $nouvellesEntrees.Add($Dossier.TrimEnd('\')) }

        $nouvelleValeur = $nouvellesEntrees -join ';'
        if ($nouvelleValeur -eq ($entrees -join ';')) {
            if ($Retire) { Write-Host ("Aucune entr" + $eAigu + "e d'ebony dans le PATH utilisateur : rien " + $aGrave + " retirer.") }
            else { Write-Host ("Le dossier est d" + $eAigu + "j" + $aGrave + " dans le PATH utilisateur : " + $Dossier) }
            exit 0
        }

        $cleEnvironnement.SetValue($NomVariable, $nouvelleValeur, $genreValeur)

        # Prevenir les programmes ouverts (explorateur, nouveaux terminaux) que l'environnement a change.
        Add-Type -Namespace EbonyNative -Name Environnement -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
        $reponse = [UIntPtr]::Zero
        [void][EbonyNative.Environnement]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$reponse)

        if ($Retire) {
            Write-Host ("PATH utilisateur mis " + $aGrave + " jour : ebony retir" + $eAigu)
            foreach ($retiree in $entreesRetirees) { Write-Host ("  retir" + $eAigu + " : " + $retiree) }
        }
        else {
            Write-Host ("PATH utilisateur mis " + $aGrave + " jour : ajout" + $eAigu + " " + $Dossier)
            foreach ($retiree in $entreesRetirees) { Write-Host ("  retir" + $eAigu + " (autre version d'ebony) : " + $retiree) }
        }
        Write-Host ("Ouvrez un nouveau terminal pour que le changement soit pris en compte.")
    }
    finally { $cleEnvironnement.Close() }
}
catch {
    Write-Host ("ebony : le PATH n'a pas " + $eAigu + "t" + $eAigu + " modifi" + $eAigu + " : " + $_.Exception.Message)
    exit 1
}
