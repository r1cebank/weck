<#
.SYNOPSIS
    winget helpers for WECK.
.DESCRIPTION
    Detects winget and wraps package check/install commands.
#>

function Test-WingetAvailable {
    <#
    .SYNOPSIS
        Checks whether winget is available.
    #>
    [CmdletBinding()]
    param()

    return (Test-WeckCommandAvailable -Name "winget")
}

function Test-WingetPackageInstalled {
    <#
    .SYNOPSIS
        Checks whether a winget package is already installed.
    .PARAMETER Id
        winget package identifier.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    try {
        $output = & winget list --id $Id --exact --accept-source-agreements 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0 -and (($output | Out-String) -match [regex]::Escape($Id))) {
            return $true
        }
    } catch {
        Write-WeckLog -Level "DEBUG" -Message ("winget list failed for {0}: {1}" -f $Id, $_.Exception.Message)
    }

    return $false
}

function Install-WingetPackage {
    <#
    .SYNOPSIS
        Installs a package with winget.
    .PARAMETER Id
        winget package identifier.
    .PARAMETER DryRun
        Reports the command without running it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [switch]$DryRun
    )

    if ($DryRun) {
        Write-WeckLog -Level "INFO" -Message ("Dry run: would install package {0} with winget." -f $Id)
        return [pscustomobject]@{
            Status  = "WouldInstall"
            Message = "Dry run"
        }
    }

    try {
        $output = & winget install --id $Id --exact --source winget --accept-package-agreements --accept-source-agreements 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            return [pscustomobject]@{
                Status  = "Installed"
                Message = (($output | Out-String).Trim())
            }
        }

        return [pscustomobject]@{
            Status  = "Failed"
            Message = ("winget exited with code {0}: {1}" -f $exitCode, (($output | Out-String).Trim()))
        }
    } catch {
        return [pscustomobject]@{
            Status  = "Failed"
            Message = $_.Exception.Message
        }
    }
}
