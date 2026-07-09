<#
.SYNOPSIS
    Logging helpers for WECK.
.DESCRIPTION
    Provides colored console output and timestamped log file writes.
#>

$Script:WeckLogPath = $null

function Initialize-WeckLog {
    <#
    .SYNOPSIS
        Creates a WECK log file.
    .PARAMETER RootPath
        Repository root path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $logDirectory = Join-Path $RootPath "logs"
    if (-not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Script:WeckLogPath = Join-Path $logDirectory ("weck-{0}.log" -f $timestamp)
    New-Item -ItemType File -Path $Script:WeckLogPath -Force | Out-Null
}

function Write-WeckLog {
    <#
    .SYNOPSIS
        Writes a message to the console and log file.
    .PARAMETER Level
        Log level: INFO, WARN, ERROR, SUCCESS, or DEBUG.
    .PARAMETER Message
        Message to write.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO",

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message

    if ($Script:WeckLogPath) {
        Add-Content -Path $Script:WeckLogPath -Value $line
    }

    if ($Level -eq "DEBUG") {
        Write-Verbose $Message
        return
    }

    $color = "Gray"
    switch ($Level) {
        "INFO" { $color = "Cyan" }
        "WARN" { $color = "Yellow" }
        "ERROR" { $color = "Red" }
        "SUCCESS" { $color = "Green" }
    }

    Write-Host $line -ForegroundColor $color
}

function Write-WeckSummary {
    <#
    .SYNOPSIS
        Prints the final WECK run summary.
    .PARAMETER PackageResult
        Package phase result.
    .PARAMETER TweakResult
        Tweak phase result.
    .PARAMETER FeatureResult
        Feature phase result.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [Parameter(Mandatory = $true)]
        [psobject]$TweakResult,

        [Parameter(Mandatory = $true)]
        [psobject]$FeatureResult
    )

    Write-WeckLog -Level "INFO" -Message "Summary"
    Write-WeckLog -Level "INFO" -Message ("Packages: installed={0}, skipped={1}, disabled={2}, failed={3}" -f $PackageResult.Installed, $PackageResult.Skipped, $PackageResult.Disabled, $PackageResult.Failed)
    Write-WeckLog -Level "INFO" -Message ("Tweaks: changed={0}, unchanged={1}, skipped={2}, failed={3}" -f $TweakResult.Changed, $TweakResult.Unchanged, $TweakResult.Skipped, $TweakResult.Failed)
    Write-WeckLog -Level "INFO" -Message ("Features: changed={0}, unchanged={1}, skipped={2}, failed={3}, restartNeeded={4}" -f $FeatureResult.Changed, $FeatureResult.Unchanged, $FeatureResult.Skipped, $FeatureResult.Failed, $FeatureResult.RestartNeeded)
}
