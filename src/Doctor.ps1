<#
.SYNOPSIS
    WECK preflight checks.
.DESCRIPTION
    Reports readiness, warnings, and blockers before applying a Vault.
#>

function New-WeckDoctorResult {
    <#
    .SYNOPSIS
        Creates an empty doctor result.
    #>
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Ready   = 0
        Warning = 0
        Blocked = 0
        Checks  = @()
    }
}

function Add-WeckDoctorCheck {
    <#
    .SYNOPSIS
        Adds a doctor check result.
    .PARAMETER Result
        Doctor result to update.
    .PARAMETER Status
        Check status: READY, WARN, or BLOCKED.
    .PARAMETER Name
        Short check name.
    .PARAMETER Message
        Human-readable status message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Result,

        [ValidateSet("READY", "WARN", "BLOCKED")]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    switch ($Status) {
        "READY" { $Result.Ready++ }
        "WARN" { $Result.Warning++ }
        "BLOCKED" { $Result.Blocked++ }
    }

    $checks = @()
    if ($Result.Checks) {
        $checks += $Result.Checks
    }
    $checks += [pscustomobject]@{
        Status  = $Status
        Name    = $Name
        Message = $Message
    }
    $Result.Checks = $checks
}

function Write-WeckDoctorCheck {
    <#
    .SYNOPSIS
        Logs a single doctor check.
    .PARAMETER Check
        Doctor check object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Check
    )

    $level = "INFO"
    if ($Check.Status -eq "READY") {
        $level = "SUCCESS"
    } elseif ($Check.Status -eq "WARN") {
        $level = "WARN"
    } elseif ($Check.Status -eq "BLOCKED") {
        $level = "ERROR"
    }

    Write-WeckLog -Level $level -Message ("[{0}] {1}: {2}" -f $Check.Status, $Check.Name, $Check.Message)
}

function Get-WeckCommandVersion {
    <#
    .SYNOPSIS
        Attempts to read a command version.
    .PARAMETER Name
        Command name.
    .PARAMETER VersionArgument
        Argument used to print version information.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$VersionArgument = "--version"
    )

    if (-not (Test-WeckCommandAvailable -Name $Name)) {
        return $null
    }

    try {
        $output = & $Name $VersionArgument 2>&1
        return (($output | Select-Object -First 1) | Out-String).Trim()
    } catch {
        return "available"
    }
}

function Test-WeckAppInstallerPackage {
    <#
    .SYNOPSIS
        Checks whether the Microsoft Desktop App Installer package is registered.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-WeckCommandAvailable -Name "Get-AppxPackage")) {
        return $false
    }

    try {
        $package = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
        return ($null -ne $package)
    } catch {
        return $false
    }
}

function Invoke-WeckDoctor {
    <#
    .SYNOPSIS
        Runs WECK preflight checks.
    .PARAMETER Environment
        Environment object returned by Get-WeckEnvironment.
    .PARAMETER Vault
        Loaded vault object.
    .PARAMETER TweakDefinitions
        Parsed tweak definitions.
    .PARAMETER FeatureDefinitions
        Parsed feature definitions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Environment,

        [Parameter(Mandatory = $true)]
        [psobject]$Vault,

        [Parameter(Mandatory = $true)]
        [psobject]$TweakDefinitions,

        [Parameter(Mandatory = $true)]
        [psobject]$FeatureDefinitions
    )

    $result = New-WeckDoctorResult

    if ($Environment.IsWindows) {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Windows host" -Message $Environment.WindowsCaption
    } else {
        Add-WeckDoctorCheck -Result $result -Status "BLOCKED" -Name "Windows host" -Message "Real WECK provisioning requires Windows."
    }

    if ($Environment.IsAdministrator) {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Administrator" -Message "Elevated PowerShell session detected."
    } else {
        Add-WeckDoctorCheck -Result $result -Status "BLOCKED" -Name "Administrator" -Message "Run WECK from an elevated PowerShell session."
    }

    if ($Environment.WindowsCaption -match "Windows 11") {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Windows version" -Message ("Detected {0} build {1}." -f $Environment.WindowsCaption, $Environment.BuildNumber)
    } elseif ($Environment.IsWindows) {
        Add-WeckDoctorCheck -Result $result -Status "WARN" -Name "Windows version" -Message ("WECK targets Windows 11; detected {0}." -f $Environment.WindowsCaption)
    }

    if ($Environment.Edition -match "IoT|Enterprise|LTSC|Pro") {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Windows edition" -Message $Environment.Edition
    } elseif ($Environment.IsWindows) {
        Add-WeckDoctorCheck -Result $result -Status "WARN" -Name "Windows edition" -Message ("Edition is outside the primary target list: {0}" -f $Environment.Edition)
    }

    if ($Environment.Architecture -match "ARM64|ARM|64") {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Architecture" -Message $Environment.Architecture
    } else {
        Add-WeckDoctorCheck -Result $result -Status "WARN" -Name "Architecture" -Message ("Expected ARM64 or x64; detected {0}." -f $Environment.Architecture)
    }

    $powerShellVersion = $null
    try {
        $powerShellVersion = [version]$Environment.PowerShellVersion
    } catch {
        $powerShellVersion = [version]"0.0"
    }

    if ($powerShellVersion -ge [version]"5.1") {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "PowerShell" -Message ("PowerShell {0}" -f $Environment.PowerShellVersion)
    } else {
        Add-WeckDoctorCheck -Result $result -Status "BLOCKED" -Name "PowerShell" -Message ("PowerShell 5.1 or newer required; detected {0}." -f $Environment.PowerShellVersion)
    }

    if ($Environment.ParallelsDetected) {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Parallels" -Message "Parallels Desktop detected."
    } else {
        Add-WeckDoctorCheck -Result $result -Status "WARN" -Name "Parallels" -Message ("Parallels not detected; virtualization is {0}." -f $Environment.VirtualizationPlatform)
    }

    $wingetVersion = Get-WeckCommandVersion -Name "winget" -VersionArgument "--version"
    if ($wingetVersion) {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "winget" -Message $wingetVersion
    } else {
        Add-WeckDoctorCheck -Result $result -Status "BLOCKED" -Name "winget" -Message "winget is required for package installation."
    }

    if (Test-WeckAppInstallerPackage) {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "App Installer" -Message "Microsoft Desktop App Installer package is registered."
    } elseif ($Environment.IsWindows) {
        Add-WeckDoctorCheck -Result $result -Status "WARN" -Name "App Installer" -Message "Desktop App Installer package was not found; launcher dependency prep may need to repair winget."
    }

    $gitVersion = Get-WeckCommandVersion -Name "git" -VersionArgument "--version"
    if ($gitVersion) {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Git" -Message $gitVersion
    } else {
        Add-WeckDoctorCheck -Result $result -Status "BLOCKED" -Name "Git" -Message "Git is required for launcher updates and is installed by the remote launcher."
    }

    if (Test-WeckRegistryProvider) {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Registry provider" -Message "PowerShell Registry provider is available."
    } else {
        Add-WeckDoctorCheck -Result $result -Status "BLOCKED" -Name "Registry provider" -Message "Registry provider is required for tweaks."
    }

    $canReadOptionalFeatures = Test-WeckCommandAvailable -Name "Get-WindowsOptionalFeature"
    $canEnableOptionalFeatures = Test-WeckCommandAvailable -Name "Enable-WindowsOptionalFeature"
    if ($canReadOptionalFeatures -and $canEnableOptionalFeatures) {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Optional features" -Message "Windows optional feature commands are available."
    } else {
        Add-WeckDoctorCheck -Result $result -Status "WARN" -Name "Optional features" -Message "Optional feature commands are unavailable; feature phase may need to be skipped."
    }

    $packages = ConvertTo-WeckArray $Vault.packages
    $tweaks = ConvertTo-WeckArray $Vault.tweaks
    $features = ConvertTo-WeckArray $Vault.features
    Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Vault" -Message ("Loaded '{0}' with {1} package(s), {2} tweak(s), and {3} feature entry/entries." -f $Vault.name, $packages.Count, $tweaks.Count, $features.Count)

    $tweakDefinitions = ConvertTo-WeckArray $TweakDefinitions.tweaks
    if ($tweakDefinitions.Count -gt 0) {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Tweak config" -Message ("Loaded {0} tweak definition(s)." -f $tweakDefinitions.Count)
    } else {
        Add-WeckDoctorCheck -Result $result -Status "BLOCKED" -Name "Tweak config" -Message "No tweak definitions loaded."
    }

    $featureDefinitions = ConvertTo-WeckArray $FeatureDefinitions.features
    if ($featureDefinitions.Count -gt 0) {
        Add-WeckDoctorCheck -Result $result -Status "READY" -Name "Feature config" -Message ("Loaded {0} feature definition(s)." -f $featureDefinitions.Count)
    } else {
        Add-WeckDoctorCheck -Result $result -Status "WARN" -Name "Feature config" -Message "No optional feature definitions loaded."
    }

    foreach ($check in $result.Checks) {
        Write-WeckDoctorCheck -Check $check
    }

    Write-WeckLog -Level "INFO" -Message ("Doctor summary: ready={0}, warn={1}, blocked={2}" -f $result.Ready, $result.Warning, $result.Blocked)
    return $result
}
