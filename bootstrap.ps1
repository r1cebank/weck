<#
.SYNOPSIS
    Entry point for WECK workstation provisioning.

.DESCRIPTION
    Loads a selected WECK Vault and applies packages, safe Windows tweaks, and
    optional Windows features. Use -DryRun first to inspect planned changes.

.PARAMETER DryRun
    Prints planned actions without changing the system.

.PARAMETER SkipPackages
    Skips winget package installation.

.PARAMETER SkipTweaks
    Skips registry and policy tweaks.

.PARAMETER SkipFeatures
    Skips optional Windows feature handling.

.PARAMETER ConfigPath
    Path to the configuration directory. Defaults to ./config.

.PARAMETER Vault
    Vault name from ./vaults without .json, or a path to a vault JSON file.

.PARAMETER NoRestart
    Prevents automatic restarts. WECK v0.1 never restarts automatically.

.PARAMETER Doctor
    Runs preflight checks only and does not apply packages, tweaks, or features.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipPackages,
    [switch]$SkipTweaks,
    [switch]$SkipFeatures,
    [string]$ConfigPath,
    [string]$Vault = "base",
    [switch]$NoRestart,
    [switch]$Doctor
)

$ErrorActionPreference = "Stop"

$Script:WeckRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $Script:WeckRoot "src/Logging.ps1")
. (Join-Path $Script:WeckRoot "src/Helpers.ps1")
. (Join-Path $Script:WeckRoot "src/Checks.ps1")
. (Join-Path $Script:WeckRoot "src/Vaults.ps1")
. (Join-Path $Script:WeckRoot "src/Winget.ps1")
. (Join-Path $Script:WeckRoot "src/Registry.ps1")
. (Join-Path $Script:WeckRoot "src/Packages.ps1")
. (Join-Path $Script:WeckRoot "src/Tweaks.ps1")
. (Join-Path $Script:WeckRoot "src/Features.ps1")
. (Join-Path $Script:WeckRoot "src/Doctor.ps1")

function New-WeckEmptyResult {
    param(
        [string]$Name,
        [string]$Status
    )

    return [pscustomobject]@{
        Name          = $Name
        Status        = $Status
        Installed     = 0
        Skipped       = 0
        Disabled      = 0
        Failed        = 0
        Changed       = 0
        Unchanged     = 0
        RestartNeeded = 0
        Items         = @()
    }
}

try {
    Initialize-WeckLog -RootPath $Script:WeckRoot

    Write-WeckLog -Level "INFO" -Message "WECK bootstrap started."
    if ($DryRun) {
        Write-WeckLog -Level "WARN" -Message "Dry run mode is enabled. No changes will be made."
    }

    $resolvedConfigPath = Resolve-WeckConfigPath -RootPath $Script:WeckRoot -ConfigPath $ConfigPath
    Write-WeckLog -Level "INFO" -Message ("Configuration path: {0}" -f $resolvedConfigPath)

    $environment = Get-WeckEnvironment
    Show-WeckEnvironmentSummary -Environment $environment

    if (-not $environment.IsAdministrator) {
        Write-WeckLog -Level "WARN" -Message "Administrator privileges were not detected. Some real package, registry, or feature changes may fail."
    }

    $selectedVault = Import-WeckVault -RootPath $Script:WeckRoot -Vault $Vault
    Write-WeckLog -Level "SUCCESS" -Message ("Loaded vault '{0}': {1}" -f $selectedVault.name, $selectedVault.description)

    $tweakDefinitions = Import-WeckJsonFile -Path (Join-Path $resolvedConfigPath "tweaks.json")
    $featureDefinitions = Import-WeckJsonFile -Path (Join-Path $resolvedConfigPath "features.json")

    if ($Doctor) {
        $doctorResult = Invoke-WeckDoctor -Environment $environment -Vault $selectedVault -TweakDefinitions $tweakDefinitions -FeatureDefinitions $featureDefinitions
        if ($doctorResult.Blocked -gt 0) {
            Write-WeckLog -Level "ERROR" -Message ("Doctor found {0} blocked check(s). Resolve blocked items before applying WECK." -f $doctorResult.Blocked)
            exit 2
        }

        Write-WeckLog -Level "SUCCESS" -Message "Doctor checks completed without blockers."
        exit 0
    }

    if ($SkipPackages) {
        Write-WeckLog -Level "WARN" -Message "Package phase skipped by request."
        $packageResult = New-WeckEmptyResult -Name "Packages" -Status "Skipped"
    } else {
        $packageResult = Invoke-WeckPackages -Vault $selectedVault -DryRun:$DryRun -WingetAvailable:$environment.WingetAvailable
    }

    if ($SkipTweaks) {
        Write-WeckLog -Level "WARN" -Message "Tweaks phase skipped by request."
        $tweakResult = New-WeckEmptyResult -Name "Tweaks" -Status "Skipped"
    } else {
        $tweakResult = Invoke-WeckTweaks -Vault $selectedVault -TweakDefinitions $tweakDefinitions -DryRun:$DryRun
    }

    if ($SkipFeatures) {
        Write-WeckLog -Level "WARN" -Message "Features phase skipped by request."
        $featureResult = New-WeckEmptyResult -Name "Features" -Status "Skipped"
    } else {
        $featureResult = Invoke-WeckFeatures -Vault $selectedVault -FeatureDefinitions $featureDefinitions -DryRun:$DryRun -NoRestart:$NoRestart
    }

    Write-WeckSummary -PackageResult $packageResult -TweakResult $tweakResult -FeatureResult $featureResult
    Write-WeckLog -Level "SUCCESS" -Message ("WECK bootstrap finished. Log file: {0}" -f $Script:WeckLogPath)
    exit 0
} catch {
    Write-WeckLog -Level "ERROR" -Message ("WECK bootstrap failed: {0}" -f $_.Exception.Message)
    if ($Script:WeckLogPath) {
        Write-WeckLog -Level "ERROR" -Message ("Log file: {0}" -f $Script:WeckLogPath)
    }
    exit 1
}
