<#
.SYNOPSIS
    Safe tweak phase for WECK.
.DESCRIPTION
    Applies only tweak IDs selected by the active vault.
#>

function Find-WeckTweakDefinition {
    <#
    .SYNOPSIS
        Finds a tweak definition by ID.
    .PARAMETER TweakDefinitions
        Parsed tweaks.json content.
    .PARAMETER Id
        Tweak ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$TweakDefinitions,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    foreach ($definition in (ConvertTo-WeckArray $TweakDefinitions.tweaks)) {
        if ($definition.id -eq $Id) {
            return $definition
        }
    }

    return $null
}

function Invoke-WeckTweaks {
    <#
    .SYNOPSIS
        Applies safe registry tweaks referenced by a vault.
    .PARAMETER Vault
        Loaded vault object.
    .PARAMETER TweakDefinitions
        Parsed tweaks.json content.
    .PARAMETER DryRun
        Reports planned actions without writing registry values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Vault,

        [Parameter(Mandatory = $true)]
        [psobject]$TweakDefinitions,

        [switch]$DryRun
    )

    $result = New-WeckPhaseResult -Name "Tweaks"
    $tweakIds = ConvertTo-WeckArray $Vault.tweaks

    foreach ($tweakId in $tweakIds) {
        $id = [string]$tweakId
        $definition = Find-WeckTweakDefinition -TweakDefinitions $TweakDefinitions -Id $id

        if ($null -eq $definition) {
            $result.Failed++
            Add-WeckResultItem -Result $result -Item ([pscustomobject]@{ Id = $id; Status = "Failed"; Message = "Tweak definition not found." })
            Write-WeckLog -Level "ERROR" -Message ("Tweak definition not found: {0}" -f $id)
            continue
        }

        $setResult = Set-WeckRegistryValue -Path $definition.path -ValueName $definition.valueName -Type $definition.type -Value $definition.value -DryRun:$DryRun
        if ($setResult.Status -eq "Changed") {
            $result.Changed++
            Write-WeckLog -Level "SUCCESS" -Message ("Applied tweak: {0}" -f $definition.name)
        } elseif ($setResult.Status -eq "Unchanged") {
            $result.Unchanged++
            Write-WeckLog -Level "SUCCESS" -Message ("Tweak already applied: {0}" -f $definition.name)
        } elseif ($setResult.Status -eq "WouldChange") {
            $result.Skipped++
            Write-WeckLog -Level "INFO" -Message ("Dry run: tweak would be applied: {0}" -f $definition.name)
        } else {
            $result.Failed++
            Write-WeckLog -Level "ERROR" -Message ("Tweak failed: {0}. {1}" -f $definition.name, $setResult.Message)
        }

        Add-WeckResultItem -Result $result -Item ([pscustomobject]@{ Id = $id; Status = $setResult.Status; Message = $setResult.Message })
    }

    return $result
}
