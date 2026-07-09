<#
.SYNOPSIS
    Package phase for WECK.
.DESCRIPTION
    Installs enabled vault packages through winget only.
#>

function Invoke-WeckPackages {
    <#
    .SYNOPSIS
        Processes package entries from a vault.
    .PARAMETER Vault
        Loaded vault object.
    .PARAMETER DryRun
        Reports planned actions without installing packages.
    .PARAMETER WingetAvailable
        Whether winget is available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Vault,

        [switch]$DryRun,

        [bool]$WingetAvailable
    )

    $result = New-WeckPhaseResult -Name "Packages"
    $packages = ConvertTo-WeckArray $Vault.packages

    if (-not $WingetAvailable) {
        Write-WeckLog -Level "WARN" -Message "winget is not available. Enabled package entries will be skipped."
    }

    foreach ($package in $packages) {
        $id = [string]$package.id
        $enabled = [bool]$package.enabled

        if (-not $enabled) {
            $result.Disabled++
            Add-WeckResultItem -Result $result -Item ([pscustomobject]@{ Id = $id; Status = "Disabled"; Message = "Package disabled in vault." })
            Write-WeckLog -Level "INFO" -Message ("Package disabled: {0}" -f $id)
            continue
        }

        if (-not $WingetAvailable) {
            $result.Skipped++
            Add-WeckResultItem -Result $result -Item ([pscustomobject]@{ Id = $id; Status = "Skipped"; Message = "winget unavailable." })
            Write-WeckLog -Level "WARN" -Message ("Skipping package because winget is unavailable: {0}" -f $id)
            continue
        }

        if (Test-WingetPackageInstalled -Id $id) {
            $result.Skipped++
            Add-WeckResultItem -Result $result -Item ([pscustomobject]@{ Id = $id; Status = "AlreadyInstalled"; Message = "Package already installed." })
            Write-WeckLog -Level "SUCCESS" -Message ("Package already installed: {0}" -f $id)
            continue
        }

        $installResult = Install-WingetPackage -Id $id -DryRun:$DryRun
        if ($installResult.Status -eq "Installed") {
            $result.Installed++
            Write-WeckLog -Level "SUCCESS" -Message ("Installed package: {0}" -f $id)
        } elseif ($installResult.Status -eq "WouldInstall") {
            $result.Skipped++
            Write-WeckLog -Level "INFO" -Message ("Dry run: package would be installed: {0}" -f $id)
        } else {
            $result.Failed++
            Write-WeckLog -Level "ERROR" -Message ("Package failed: {0}. {1}" -f $id, $installResult.Message)
        }

        Add-WeckResultItem -Result $result -Item ([pscustomobject]@{ Id = $id; Status = $installResult.Status; Message = $installResult.Message })
    }

    return $result
}
