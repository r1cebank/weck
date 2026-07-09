<#
.SYNOPSIS
    Registry helpers for WECK.
.DESCRIPTION
    Applies idempotent registry values with dry-run support.
#>

function Test-WeckRegistryProvider {
    <#
    .SYNOPSIS
        Checks whether the PowerShell Registry provider is available.
    #>
    [CmdletBinding()]
    param()

    $provider = Get-PSProvider -PSProvider Registry -ErrorAction SilentlyContinue
    return ($null -ne $provider)
}

function Get-WeckRegistryValue {
    <#
    .SYNOPSIS
        Reads a registry value if available.
    .PARAMETER Path
        Registry key path.
    .PARAMETER ValueName
        Registry value name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ValueName
    )

    if (-not (Test-WeckRegistryProvider)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $ValueName -ErrorAction Stop
        return $item.$ValueName
    } catch {
        return $null
    }
}

function Set-WeckRegistryValue {
    <#
    .SYNOPSIS
        Sets a registry value only when needed.
    .PARAMETER Path
        Registry key path.
    .PARAMETER ValueName
        Registry value name.
    .PARAMETER Type
        Registry property type.
    .PARAMETER Value
        Desired value.
    .PARAMETER DryRun
        Reports planned changes without writing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ValueName,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        $Value,

        [switch]$DryRun
    )

    $hasRegistry = Test-WeckRegistryProvider
    if (-not $hasRegistry) {
        if ($DryRun) {
            return [pscustomobject]@{
                Status  = "WouldChange"
                Message = "Registry provider unavailable on this host; dry-run reports intended change."
            }
        }

        return [pscustomobject]@{
            Status  = "Failed"
            Message = "Registry provider unavailable."
        }
    }

    $currentValue = Get-WeckRegistryValue -Path $Path -ValueName $ValueName
    if ($null -ne $currentValue -and ([string]$currentValue) -eq ([string]$Value)) {
        return [pscustomobject]@{
            Status  = "Unchanged"
            Message = "Desired value already present."
        }
    }

    if ($DryRun) {
        return [pscustomobject]@{
            Status  = "WouldChange"
            Message = ("Would set {0}\\{1} from '{2}' to '{3}'." -f $Path, $ValueName, $currentValue, $Value)
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        New-ItemProperty -LiteralPath $Path -Name $ValueName -PropertyType $Type -Value $Value -Force | Out-Null
        return [pscustomobject]@{
            Status  = "Changed"
            Message = ("Set {0}\\{1}." -f $Path, $ValueName)
        }
    } catch {
        return [pscustomobject]@{
            Status  = "Failed"
            Message = $_.Exception.Message
        }
    }
}
