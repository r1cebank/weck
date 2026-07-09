<#
.SYNOPSIS
    Vault loading and validation for WECK.
.DESCRIPTION
    Resolves named vaults and validates the v0.1 vault contract.
#>

function Resolve-WeckVaultPath {
    <#
    .SYNOPSIS
        Resolves a vault name or path to a JSON file path.
    .PARAMETER RootPath
        Repository root path.
    .PARAMETER Vault
        Vault name or path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Vault
    )

    if ([System.IO.Path]::IsPathRooted($Vault) -or $Vault.EndsWith(".json")) {
        if ([System.IO.Path]::IsPathRooted($Vault)) {
            return $Vault
        }
        return (Join-Path (Get-Location).Path $Vault)
    }

    return (Join-Path (Join-Path $RootPath "vaults") ("{0}.json" -f $Vault))
}

function Test-WeckVault {
    <#
    .SYNOPSIS
        Validates the required v0.1 vault shape.
    .PARAMETER Vault
        Parsed vault object.
    .PARAMETER Path
        Source path, used for error messages.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Vault,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    foreach ($propertyName in @("name", "description", "packages", "tweaks", "features")) {
        if (-not ($Vault.PSObject.Properties.Name -contains $propertyName)) {
            throw "Vault '$Path' is missing required property '$propertyName'."
        }
    }

    foreach ($package in (ConvertTo-WeckArray $Vault.packages)) {
        foreach ($propertyName in @("id", "enabled", "category")) {
            if (-not ($package.PSObject.Properties.Name -contains $propertyName)) {
                throw "Vault '$Path' has a package entry missing '$propertyName'."
            }
        }
    }

    foreach ($feature in (ConvertTo-WeckArray $Vault.features)) {
        foreach ($propertyName in @("name", "enabled")) {
            if (-not ($feature.PSObject.Properties.Name -contains $propertyName)) {
                throw "Vault '$Path' has a feature entry missing '$propertyName'."
            }
        }
    }

    return $true
}

function Import-WeckVault {
    <#
    .SYNOPSIS
        Loads and validates a WECK vault.
    .PARAMETER RootPath
        Repository root path.
    .PARAMETER Vault
        Vault name or path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Vault
    )

    $vaultPath = Resolve-WeckVaultPath -RootPath $RootPath -Vault $Vault
    $selectedVault = Import-WeckJsonFile -Path $vaultPath
    Test-WeckVault -Vault $selectedVault -Path $vaultPath | Out-Null
    return $selectedVault
}
