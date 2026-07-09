<#
.SYNOPSIS
    Optional Windows feature phase for WECK.
.DESCRIPTION
    Enables only vault-requested Windows optional features.
#>

function Get-WeckFeatureState {
    <#
    .SYNOPSIS
        Gets the current state of a Windows optional feature.
    .PARAMETER Name
        Feature name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-WeckCommandAvailable -Name "Get-WindowsOptionalFeature")) {
        return [pscustomobject]@{
            Available = $false
            State     = "Unknown"
            Message   = "Get-WindowsOptionalFeature is unavailable."
        }
    }

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop
        return [pscustomobject]@{
            Available = $true
            State     = [string]$feature.State
            Message   = "Feature state read."
        }
    } catch {
        return [pscustomobject]@{
            Available = $true
            State     = "Unknown"
            Message   = $_.Exception.Message
        }
    }
}

function Enable-WeckFeature {
    <#
    .SYNOPSIS
        Enables a Windows optional feature.
    .PARAMETER Name
        Feature name.
    .PARAMETER DryRun
        Reports planned action without enabling the feature.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [switch]$DryRun
    )

    if ($DryRun) {
        return [pscustomobject]@{
            Status        = "WouldChange"
            RestartNeeded = $false
            Message       = "Dry run."
        }
    }

    if (-not (Test-WeckCommandAvailable -Name "Enable-WindowsOptionalFeature")) {
        return [pscustomobject]@{
            Status        = "Failed"
            RestartNeeded = $false
            Message       = "Enable-WindowsOptionalFeature is unavailable."
        }
    }

    try {
        $enabled = Enable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -ErrorAction Stop
        $restartNeeded = $false
        if ($enabled -and ($enabled.PSObject.Properties.Name -contains "RestartNeeded")) {
            $restartNeeded = [bool]$enabled.RestartNeeded
        }

        return [pscustomobject]@{
            Status        = "Changed"
            RestartNeeded = $restartNeeded
            Message       = "Feature enabled."
        }
    } catch {
        return [pscustomobject]@{
            Status        = "Failed"
            RestartNeeded = $false
            Message       = $_.Exception.Message
        }
    }
}

function Find-WeckFeatureDefinition {
    <#
    .SYNOPSIS
        Finds an optional feature definition by name.
    .PARAMETER FeatureDefinitions
        Parsed features.json content.
    .PARAMETER Name
        Feature name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$FeatureDefinitions,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    foreach ($definition in (ConvertTo-WeckArray $FeatureDefinitions.features)) {
        if ($definition.name -eq $Name) {
            return $definition
        }
    }

    return $null
}

function Invoke-WeckFeatures {
    <#
    .SYNOPSIS
        Processes optional Windows features from a vault.
    .PARAMETER Vault
        Loaded vault object.
    .PARAMETER FeatureDefinitions
        Parsed features.json content.
    .PARAMETER DryRun
        Reports planned actions without enabling features.
    .PARAMETER NoRestart
        Documents restart suppression. WECK v0.1 never restarts automatically.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Vault,

        [Parameter(Mandatory = $true)]
        [psobject]$FeatureDefinitions,

        [switch]$DryRun,

        [switch]$NoRestart
    )

    $result = New-WeckPhaseResult -Name "Features"
    $features = ConvertTo-WeckArray $Vault.features

    if ($NoRestart) {
        Write-WeckLog -Level "INFO" -Message "NoRestart is set. WECK v0.1 never restarts automatically."
    }

    foreach ($feature in $features) {
        $name = [string]$feature.name
        $enabled = [bool]$feature.enabled
        $definition = Find-WeckFeatureDefinition -FeatureDefinitions $FeatureDefinitions -Name $name

        if ($null -eq $definition) {
            $result.Failed++
            Add-WeckResultItem -Result $result -Item ([pscustomobject]@{ Name = $name; Status = "Failed"; Message = "Feature definition not found." })
            Write-WeckLog -Level "ERROR" -Message ("Feature definition not found: {0}" -f $name)
            continue
        }

        if (-not $enabled) {
            $result.Disabled++
            Add-WeckResultItem -Result $result -Item ([pscustomobject]@{ Name = $name; Status = "Disabled"; Message = "Feature disabled in vault." })
            Write-WeckLog -Level "INFO" -Message ("Feature disabled: {0}" -f $name)
            continue
        }

        $state = Get-WeckFeatureState -Name $name
        if ($state.Available -and $state.State -eq "Enabled") {
            $result.Unchanged++
            Add-WeckResultItem -Result $result -Item ([pscustomobject]@{ Name = $name; Status = "AlreadyEnabled"; Message = "Feature already enabled." })
            Write-WeckLog -Level "SUCCESS" -Message ("Feature already enabled: {0}" -f $name)
            continue
        }

        if (-not $state.Available -and -not $DryRun) {
            $result.Failed++
            Add-WeckResultItem -Result $result -Item ([pscustomobject]@{ Name = $name; Status = "Failed"; Message = $state.Message })
            Write-WeckLog -Level "ERROR" -Message ("Cannot enable feature {0}: {1}" -f $name, $state.Message)
            continue
        }

        $enableResult = Enable-WeckFeature -Name $name -DryRun:$DryRun
        if ($enableResult.Status -eq "Changed") {
            $result.Changed++
            Write-WeckLog -Level "SUCCESS" -Message ("Enabled feature: {0}" -f $name)
        } elseif ($enableResult.Status -eq "WouldChange") {
            $result.Skipped++
            Write-WeckLog -Level "INFO" -Message ("Dry run: feature would be enabled: {0}" -f $name)
        } else {
            $result.Failed++
            Write-WeckLog -Level "ERROR" -Message ("Feature failed: {0}. {1}" -f $name, $enableResult.Message)
        }

        if ($enableResult.RestartNeeded) {
            $result.RestartNeeded++
            Write-WeckLog -Level "WARN" -Message ("Feature reported restart needed: {0}" -f $name)
        }

        Add-WeckResultItem -Result $result -Item ([pscustomobject]@{ Name = $name; Status = $enableResult.Status; Message = $enableResult.Message })
    }

    return $result
}
