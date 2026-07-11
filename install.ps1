<#
.SYNOPSIS
    Remote-friendly WECK installer and launcher.

.DESCRIPTION
    Designed for one-line bootstrap use. It prepares machine dependencies
    first, then clones or updates the WECK repository, shows a vault menu, and
    invokes bootstrap.ps1 with the selected vault. Dry-run is the default
    interactive choice.

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
    Optional run mode: Doctor, DryRun, Apply, PackagesOnly, TweaksOnly, or FeaturesOnly.

.PARAMETER NonInteractive
    Runs without prompts. Requires -Vault unless the repository default should
    be used. Defaults to DryRun unless -RunMode is supplied.

.PARAMETER SkipGitInstall
    Do not install Git with winget when Git is missing.

.PARAMETER SkipWingetInstall
    Do not bootstrap winget/App Installer when winget is missing.

.PARAMETER InstallerUrl
    URL used to re-download this launcher when elevation is needed from an
    iex/pipeline invocation.

.PARAMETER NoAdminRelaunch
    Do not request UAC elevation before dependency preparation.

.PARAMETER CloseOnFinish
    Close the elevated launcher window after it finishes. By default, elevated
    relaunches stay open so LTSC dependency errors remain visible.
#>
[CmdletBinding()]
param(
    [string]$RepoUrl = $env:WECK_REPO_URL,
    [string]$InstallRoot,
    [string]$Branch = $env:WECK_BRANCH,
    [string]$InstallerUrl = $env:WECK_INSTALLER_URL,
    [string]$Vault,
    [string]$RunMode,
    [switch]$NonInteractive,
    [switch]$SkipGitInstall,
    [switch]$SkipWingetInstall,
    [switch]$NoAdminRelaunch,
    [switch]$CloseOnFinish
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
    $RepoUrl = "https://github.com/r1cebank/weck.git"
}

if ([string]::IsNullOrWhiteSpace($InstallerUrl)) {
    $InstallerUrl = "https://raw.githubusercontent.com/r1cebank/weck/main/install.ps1"
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

function Test-WeckInstallWindows {
    if ($PSVersionTable.PSVersion.Major -le 5) {
        return $true
    }

    if ($PSVersionTable.ContainsKey("Platform")) {
        return ($PSVersionTable.Platform -eq "Win32NT")
    }

    return $true
}

function Test-WeckInstallAdministrator {
    if (-not (Test-WeckInstallWindows)) {
        return $false
    }

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Enable-WeckInstallTls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-WeckInstallMessage -Level "WARN" -Message ("Unable to force TLS 1.2: {0}" -f $_.Exception.Message)
    }
}

function Update-WeckInstallPath {
    $pathParts = @(
        [System.Environment]::GetEnvironmentVariable("Path", "Machine"),
        [System.Environment]::GetEnvironmentVariable("Path", "User"),
        $env:Path
    )

    $env:Path = (($pathParts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ";")
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

function ConvertTo-WeckPowerShellArgument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return ('"{0}"' -f ($Value -replace '"', '\"'))
}

function Add-WeckRelaunchArgument {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    [void]$Arguments.Add(("-{0}" -f $Name))
    [void]$Arguments.Add((ConvertTo-WeckPowerShellArgument -Value $Value))
}

function Get-WeckPowerShellExecutable {
    $candidates = @()

    if (-not [string]::IsNullOrWhiteSpace($PSHOME)) {
        $candidates += (Join-Path $PSHOME "powershell.exe")
        $candidates += (Join-Path $PSHOME "pwsh.exe")
    }

    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        $candidates += (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $command = Get-Command -Name "powershell.exe" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $command = Get-Command -Name "pwsh.exe" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Unable to find powershell.exe for elevated relaunch."
}

function Request-WeckAdministrator {
    if ($NoAdminRelaunch) {
        Write-WeckInstallMessage -Level "WARN" -Message "Admin relaunch was skipped by request. Dependency preparation may fail."
        return
    }

    if (-not (Test-WeckInstallWindows)) {
        return
    }

    if (Test-WeckInstallAdministrator) {
        Write-WeckInstallMessage -Level "SUCCESS" -Message "Administrator privileges are available."
        return
    }

    if (-not $NonInteractive) {
        if (-not (Confirm-WeckInstallPrompt -Prompt "WECK needs administrator privileges to prepare winget, Git, and machine-wide settings. Relaunch elevated now?" -Default $true)) {
            throw "Administrator privileges are required for dependency preparation."
        }
    }

    Enable-WeckInstallTls12

    $launcherPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($launcherPath) -or -not (Test-Path -LiteralPath $launcherPath)) {
        $launcherRoot = Join-Path $env:TEMP "weck-launcher"
        if (-not (Test-Path -LiteralPath $launcherRoot)) {
            New-Item -ItemType Directory -Path $launcherRoot -Force | Out-Null
        }

        $launcherPath = Join-Path $launcherRoot "install.ps1"
        Write-WeckInstallMessage -Level "INFO" -Message ("Downloading elevated launcher from {0}" -f $InstallerUrl)
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $launcherPath -UseBasicParsing -ErrorAction Stop
    }

    $powerShellPath = Get-WeckPowerShellExecutable
    $arguments = New-Object System.Collections.ArrayList
    if (-not $CloseOnFinish) {
        [void]$arguments.Add("-NoExit")
    }
    [void]$arguments.Add("-NoProfile")
    [void]$arguments.Add("-ExecutionPolicy")
    [void]$arguments.Add("Bypass")
    [void]$arguments.Add("-File")
    [void]$arguments.Add((ConvertTo-WeckPowerShellArgument -Value $launcherPath))

    Add-WeckRelaunchArgument -Arguments $arguments -Name "RepoUrl" -Value $RepoUrl
    Add-WeckRelaunchArgument -Arguments $arguments -Name "InstallRoot" -Value $InstallRoot
    Add-WeckRelaunchArgument -Arguments $arguments -Name "Branch" -Value $Branch
    Add-WeckRelaunchArgument -Arguments $arguments -Name "InstallerUrl" -Value $InstallerUrl
    Add-WeckRelaunchArgument -Arguments $arguments -Name "Vault" -Value $Vault
    Add-WeckRelaunchArgument -Arguments $arguments -Name "RunMode" -Value $RunMode

    if ($NonInteractive) {
        [void]$arguments.Add("-NonInteractive")
    }
    if ($SkipGitInstall) {
        [void]$arguments.Add("-SkipGitInstall")
    }
    if ($SkipWingetInstall) {
        [void]$arguments.Add("-SkipWingetInstall")
    }
    [void]$arguments.Add("-NoAdminRelaunch")
    if ($CloseOnFinish) {
        [void]$arguments.Add("-CloseOnFinish")
    }

    Write-WeckInstallMessage -Level "INFO" -Message "Requesting administrator privileges with UAC."
    try {
        Start-Process -FilePath $powerShellPath -ArgumentList ([string[]]$arguments) -Verb RunAs -ErrorAction Stop | Out-Null
    } catch {
        throw "UAC relaunch failed: $($_.Exception.Message)"
    }

    Write-WeckInstallMessage -Level "INFO" -Message "Elevated WECK launcher started. Continue in the administrator PowerShell window."
    exit 0
}

function Test-WeckWinget {
    if (-not (Test-WeckInstallCommand -Name "winget")) {
        return $false
    }

    try {
        & winget --version | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Register-WeckAppInstallerPackage {
    if (-not (Test-WeckInstallCommand -Name "Add-AppxPackage")) {
        return $false
    }

    try {
        $existingPackage = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
        if ($null -eq $existingPackage) {
            return $false
        }

        Write-WeckInstallMessage -Level "INFO" -Message "Registering existing Microsoft Desktop App Installer package."
        Add-AppxPackage -RegisterByFamilyName -MainPackage "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe" -ErrorAction Stop
        Update-WeckInstallPath
        return (Test-WeckWinget)
    } catch {
        Write-WeckInstallMessage -Level "WARN" -Message ("Existing App Installer registration failed: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Repair-WeckWingetWithModule {
    if (-not (Test-WeckInstallCommand -Name "Install-Module")) {
        Write-WeckInstallMessage -Level "WARN" -Message "Install-Module is unavailable; cannot use Microsoft.WinGet.Client bootstrap path."
        return $false
    }

    try {
        Enable-WeckInstallTls12

        if (Test-WeckInstallCommand -Name "Install-PackageProvider") {
            Write-WeckInstallMessage -Level "INFO" -Message "Ensuring NuGet package provider is available."
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        }

        Write-WeckInstallMessage -Level "INFO" -Message "Installing Microsoft.WinGet.Client from PowerShell Gallery."
        Install-Module -Name Microsoft.WinGet.Client -Force -AllowClobber -Repository PSGallery -Scope CurrentUser -ErrorAction Stop
        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop

        Write-WeckInstallMessage -Level "INFO" -Message "Repairing Windows Package Manager."
        if (Test-WeckInstallAdministrator) {
            Repair-WinGetPackageManager -AllUsers -ErrorAction Stop
        } else {
            Repair-WinGetPackageManager -ErrorAction Stop
        }

        Update-WeckInstallPath
        return (Test-WeckWinget)
    } catch {
        Write-WeckInstallMessage -Level "WARN" -Message ("Microsoft.WinGet.Client bootstrap failed: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Install-WeckWingetFromAkaMs {
    if (-not (Test-WeckInstallCommand -Name "Add-AppxPackage")) {
        Write-WeckInstallMessage -Level "WARN" -Message "Add-AppxPackage is unavailable; cannot install App Installer bundle directly."
        return $false
    }

    try {
        Enable-WeckInstallTls12

        $downloadRoot = Join-Path $env:TEMP "weck-winget"
        if (-not (Test-Path -LiteralPath $downloadRoot)) {
            New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
        }

        $bundlePath = Join-Path $downloadRoot "Microsoft.DesktopAppInstaller.msixbundle"
        Write-WeckInstallMessage -Level "INFO" -Message "Downloading App Installer bundle from https://aka.ms/getwinget."
        Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile $bundlePath -UseBasicParsing -ErrorAction Stop

        Write-WeckInstallMessage -Level "INFO" -Message "Installing App Installer bundle."
        Add-AppxPackage -Path $bundlePath -ErrorAction Stop
        Update-WeckInstallPath
        return (Test-WeckWinget)
    } catch {
        Write-WeckInstallMessage -Level "WARN" -Message ("Direct App Installer install failed: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Ensure-WeckWinget {
    if (Test-WeckWinget) {
        Write-WeckInstallMessage -Level "SUCCESS" -Message "winget is available."
        return
    }

    if ($SkipWingetInstall) {
        throw "winget is required before WECK can install dependencies, and -SkipWingetInstall was set."
    }

    if (-not (Test-WeckInstallWindows)) {
        throw "winget bootstrap requires Windows."
    }

    if (-not $NonInteractive) {
        if (-not (Confirm-WeckInstallPrompt -Prompt "winget is missing. Install/repair App Installer now?" -Default $true)) {
            throw "winget is required before WECK can install dependencies."
        }
    }

    Write-WeckInstallMessage -Level "INFO" -Message "Preparing winget/App Installer before cloning WECK."

    if (Register-WeckAppInstallerPackage) {
        Write-WeckInstallMessage -Level "SUCCESS" -Message "winget became available after App Installer registration."
        return
    }

    if (Repair-WeckWingetWithModule) {
        Write-WeckInstallMessage -Level "SUCCESS" -Message "winget installed through Microsoft.WinGet.Client repair."
        return
    }

    if (Install-WeckWingetFromAkaMs) {
        Write-WeckInstallMessage -Level "SUCCESS" -Message "winget installed from App Installer bundle."
        return
    }

    throw "Unable to install winget/App Installer automatically. Install Microsoft App Installer manually, then rerun this script."
}

function Ensure-WeckGit {
    if (Test-WeckInstallCommand -Name "git") {
        Write-WeckInstallMessage -Level "SUCCESS" -Message "Git is available."
        return
    }

    if ($SkipGitInstall) {
        throw "Git is required before WECK can be cloned, and -SkipGitInstall was set."
    }

    Ensure-WeckWinget

    if (-not $NonInteractive) {
        if (-not (Confirm-WeckInstallPrompt -Prompt "Git is missing. Install Git with winget now?" -Default $true)) {
            throw "Git is required before WECK can be cloned."
        }
    }

    Write-WeckInstallMessage -Level "INFO" -Message "Installing Git with winget before cloning WECK."
    & winget install --id Git.Git --exact --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install Git."
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (-not (Test-WeckInstallCommand -Name "git")) {
        throw "Git was installed, but git.exe is not available in this session. Open a new PowerShell window and run the installer again."
    }
}

function Ensure-WeckDependencies {
    Write-WeckInstallMessage -Level "INFO" -Message "Preparing dependencies before pulling WECK."
    Ensure-WeckWinget
    Ensure-WeckGit
}

function Sync-WeckRepository {
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
    $validRunModes = @("Doctor", "DryRun", "Apply", "PackagesOnly", "TweaksOnly", "FeaturesOnly")

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
    Write-Host "  1. Doctor / preflight checks"
    Write-Host "  2. Dry run all phases (recommended before apply)"
    Write-Host "  3. Apply all phases"
    Write-Host "  4. Dry run packages only"
    Write-Host "  5. Dry run tweaks only"
    Write-Host "  6. Dry run features only"

    while ($true) {
        $choice = Read-Host "Run mode"
        switch ($choice) {
            "1" { return "Doctor" }
            "2" { return "DryRun" }
            "3" {
                if (Confirm-WeckInstallPrompt -Prompt "This will install packages and apply selected changes. Continue?" -Default $false) {
                    return "Apply"
                }
            }
            "4" { return "PackagesOnly" }
            "5" { return "TweaksOnly" }
            "6" { return "FeaturesOnly" }
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
        "Doctor" {
            $arguments += "-Doctor"
        }
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

    Request-WeckAdministrator
    Ensure-WeckDependencies
    Sync-WeckRepository

    $selectedVault = Select-WeckVault
    $selectedRunMode = Select-WeckRunMode

    Invoke-WeckBootstrapFromInstaller -SelectedVault $selectedVault -SelectedRunMode $selectedRunMode
    Write-WeckInstallMessage -Level "SUCCESS" -Message "WECK launcher finished."
} catch {
    Write-WeckInstallMessage -Level "ERROR" -Message $_.Exception.Message
    exit 1
}
