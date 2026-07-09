<#
.SYNOPSIS
    Remote-friendly WECK installer and launcher.

.DESCRIPTION
    Designed for one-line bootstrap use. It clones or updates the WECK
    repository, shows a vault menu, and invokes bootstrap.ps1 with the selected
    vault. Dry-run is the default interactive choice.

.PARAMETER RepoUrl
    Git repository URL to clone. Defaults to $env:WECK_REPO_URL, then the
    public placeholder for this project.

.PARAMETER InstallRoot
    Directory where WECK should be cloned. Defaults to %USERPROFILE%\weck.

.PARAMETER Branch
    Branch to clone. Defaults to main.

.PARAMETER Vault
    Optional vault name to skip the interactive vault picker.

.PARAMETER RunMode
    Optional run mode: DryRun, Apply, PackagesOnly, TweaksOnly, or FeaturesOnly.

.PARAMETER NonInteractive
    Runs without prompts. Requires -Vault unless the repository default should
    be used. Defaults to DryRun unless -RunMode is supplied.

.PARAMETER SkipGitInstall
    Do not offer to install Git with winget when Git is missing.
#>
[CmdletBinding()]
param(
    [string]$RepoUrl = $env:WECK_REPO_URL,
    [string]$InstallRoot,
    [string]$Branch = $env:WECK_BRANCH,
    [string]$Vault,
    [ValidateSet("DryRun", "Apply", "PackagesOnly", "TweaksOnly", "FeaturesOnly")]
    [string]$RunMode,
    [switch]$NonInteractive,
    [switch]$SkipGitInstall
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
    $RepoUrl = "https://github.com/siyuangao/weck.git"
}

if ([string]::IsNullOrWhiteSpace($Branch)) {
    $Branch = "main"
}

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($env:WECK_INSTALL_ROOT)) {
        $InstallRoot = $env:WECK_INSTALL_ROOT
    } elseif (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $InstallRoot = Join-Path $env:USERPROFILE "weck"
    } else {
        $InstallRoot = Join-Path $env:HOME "weck"
    }
}

if ([string]::IsNullOrWhiteSpace($Vault) -and -not [string]::IsNullOrWhiteSpace($env:WECK_VAULT)) {
    $Vault = $env:WECK_VAULT
}

if ([string]::IsNullOrWhiteSpace($RunMode) -and -not [string]::IsNullOrWhiteSpace($env:WECK_RUN_MODE)) {
    $RunMode = $env:WECK_RUN_MODE
}

if (-not $NonInteractive -and $env:WECK_NONINTERACTIVE -match "^(1|true|yes)$") {
    $NonInteractive = $true
}

function Write-WeckInstallMessage {
    param(
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level,
        [string]$Message
    )

    $color = "Gray"
    switch ($Level) {
        "INFO" { $color = "Cyan" }
        "WARN" { $color = "Yellow" }
        "ERROR" { $color = "Red" }
        "SUCCESS" { $color = "Green" }
    }

    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $color
}

function Test-WeckInstallCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return ($null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue))
}

function Confirm-WeckInstallPrompt {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )

    if ($NonInteractive) {
        return $Default
    }

    $suffix = "[y/N]"
    if ($Default) {
        $suffix = "[Y/n]"
    }

    $answer = Read-Host ("{0} {1}" -f $Prompt, $suffix)
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $Default
    }

    return ($answer -match "^(y|yes)$")
}

function Ensure-WeckGit {
    if (Test-WeckInstallCommand -Name "git") {
        return
    }

    if ($SkipGitInstall) {
        throw "Git is required to clone WECK and was not found."
    }

    if (-not (Test-WeckInstallCommand -Name "winget")) {
        throw "Git is required, and winget is not available to install it."
    }

    if ($NonInteractive) {
        if ($env:WECK_INSTALL_GIT -notmatch "^(1|true|yes)$") {
            throw "Git is required to clone WECK. In non-interactive mode, set WECK_INSTALL_GIT=1 to allow installing Git with winget."
        }
    } else {
        if (-not (Confirm-WeckInstallPrompt -Prompt "Git is missing. Install Git with winget now?" -Default $true)) {
            throw "Git is required to clone WECK."
        }
    }

    Write-WeckInstallMessage -Level "INFO" -Message "Installing Git with winget."
    & winget install --id Git.Git --exact --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install Git."
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (-not (Test-WeckInstallCommand -Name "git")) {
        throw "Git was installed, but git.exe is not available in this session. Open a new PowerShell window and run the installer again."
    }
}

function Sync-WeckRepository {
    Ensure-WeckGit

    if (Test-Path -LiteralPath $InstallRoot) {
        $gitDirectory = Join-Path $InstallRoot ".git"
        if (-not (Test-Path -LiteralPath $gitDirectory)) {
            throw "InstallRoot exists but is not a Git repository: $InstallRoot"
        }

        Write-WeckInstallMessage -Level "INFO" -Message ("Updating WECK in {0}" -f $InstallRoot)
        Push-Location $InstallRoot
        try {
            & git fetch --prune origin
            if ($LASTEXITCODE -ne 0) {
                throw "git fetch failed."
            }

            & git checkout $Branch
            if ($LASTEXITCODE -ne 0) {
                throw "git checkout failed for branch '$Branch'."
            }

            & git pull --ff-only origin $Branch
            if ($LASTEXITCODE -ne 0) {
                throw "git pull failed for branch '$Branch'."
            }
        } finally {
            Pop-Location
        }

        return
    }

    $parent = Split-Path -Parent $InstallRoot
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Write-WeckInstallMessage -Level "INFO" -Message ("Cloning WECK from {0}" -f $RepoUrl)
    & git clone --branch $Branch $RepoUrl $InstallRoot
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed."
    }
}

function Get-WeckVaultNames {
    $vaultDirectory = Join-Path $InstallRoot "vaults"
    if (-not (Test-Path -LiteralPath $vaultDirectory)) {
        throw "Vault directory not found: $vaultDirectory"
    }

    $vaultFiles = Get-ChildItem -LiteralPath $vaultDirectory -Filter "*.json" | Sort-Object Name
    $vaults = @()

    foreach ($vaultFile in $vaultFiles) {
        try {
            $vaultContent = Get-Content -LiteralPath $vaultFile.FullName -Raw | ConvertFrom-Json
            $vaults += [pscustomobject]@{
                Name        = [string]$vaultContent.name
                Description = [string]$vaultContent.description
                Path        = $vaultFile.FullName
            }
        } catch {
            Write-WeckInstallMessage -Level "WARN" -Message ("Skipping invalid vault file {0}: {1}" -f $vaultFile.Name, $_.Exception.Message)
        }
    }

    if ($vaults.Count -eq 0) {
        throw "No valid vault files found."
    }

    return $vaults
}

function Select-WeckVault {
    if (-not [string]::IsNullOrWhiteSpace($Vault)) {
        return $Vault
    }

    if ($NonInteractive) {
        return "base"
    }

    $vaults = @(Get-WeckVaultNames)
    Write-Host ""
    Write-Host "Choose a WECK vault:" -ForegroundColor Cyan

    for ($index = 0; $index -lt $vaults.Count; $index++) {
        Write-Host ("  {0}. {1} - {2}" -f ($index + 1), $vaults[$index].Name, $vaults[$index].Description)
    }

    while ($true) {
        $choice = Read-Host "Vault number"
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $vaults.Count) {
            return $vaults[$number - 1].Name
        }

        Write-WeckInstallMessage -Level "WARN" -Message "Choose a number from the menu."
    }
}

function Select-WeckRunMode {
    $validRunModes = @("DryRun", "Apply", "PackagesOnly", "TweaksOnly", "FeaturesOnly")

    if (-not [string]::IsNullOrWhiteSpace($RunMode)) {
        if ($validRunModes -notcontains $RunMode) {
            throw "Invalid run mode '$RunMode'. Valid values: $($validRunModes -join ', ')."
        }

        return $RunMode
    }

    if ($NonInteractive) {
        return "DryRun"
    }

    Write-Host ""
    Write-Host "Choose what to run:" -ForegroundColor Cyan
    Write-Host "  1. Dry run all phases (recommended first)"
    Write-Host "  2. Apply all phases"
    Write-Host "  3. Dry run packages only"
    Write-Host "  4. Dry run tweaks only"
    Write-Host "  5. Dry run features only"

    while ($true) {
        $choice = Read-Host "Run mode"
        switch ($choice) {
            "1" { return "DryRun" }
            "2" {
                if (Confirm-WeckInstallPrompt -Prompt "This will install packages and apply selected changes. Continue?" -Default $false) {
                    return "Apply"
                }
            }
            "3" { return "PackagesOnly" }
            "4" { return "TweaksOnly" }
            "5" { return "FeaturesOnly" }
            default {
                Write-WeckInstallMessage -Level "WARN" -Message "Choose a number from the menu."
            }
        }
    }
}

function Invoke-WeckBootstrapFromInstaller {
    param(
        [string]$SelectedVault,
        [string]$SelectedRunMode
    )

    $bootstrapPath = Join-Path $InstallRoot "bootstrap.ps1"
    if (-not (Test-Path -LiteralPath $bootstrapPath)) {
        throw "bootstrap.ps1 not found: $bootstrapPath"
    }

    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $bootstrapPath, "-Vault", $SelectedVault, "-NoRestart")

    switch ($SelectedRunMode) {
        "DryRun" {
            $arguments += "-DryRun"
        }
        "Apply" {
        }
        "PackagesOnly" {
            $arguments += @("-DryRun", "-SkipTweaks", "-SkipFeatures")
        }
        "TweaksOnly" {
            $arguments += @("-DryRun", "-SkipPackages", "-SkipFeatures")
        }
        "FeaturesOnly" {
            $arguments += @("-DryRun", "-SkipPackages", "-SkipTweaks")
        }
    }

    Write-WeckInstallMessage -Level "INFO" -Message ("Running WECK vault '{0}' in mode '{1}'." -f $SelectedVault, $SelectedRunMode)
    & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "WECK bootstrap exited with code $LASTEXITCODE."
    }
}

try {
    Write-WeckInstallMessage -Level "INFO" -Message "WECK remote launcher started."
    Write-WeckInstallMessage -Level "WARN" -Message "Only run remote scripts from a repository you trust. Prefer reviewing install.ps1 before using iex."

    Sync-WeckRepository

    $selectedVault = Select-WeckVault
    $selectedRunMode = Select-WeckRunMode

    Invoke-WeckBootstrapFromInstaller -SelectedVault $selectedVault -SelectedRunMode $selectedRunMode
    Write-WeckInstallMessage -Level "SUCCESS" -Message "WECK launcher finished."
} catch {
    Write-WeckInstallMessage -Level "ERROR" -Message $_.Exception.Message
    exit 1
}
