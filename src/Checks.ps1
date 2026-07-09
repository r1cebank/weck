<#
.SYNOPSIS
    Environment detection for WECK.
.DESCRIPTION
    Collects Windows, architecture, virtualization, administrator, and winget state.
#>

function Test-WeckAdministrator {
    <#
    .SYNOPSIS
        Checks whether the current session is elevated.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-WeckWindows)) {
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

function Get-WeckEnvironment {
    <#
    .SYNOPSIS
        Collects environment information for the current machine.
    #>
    [CmdletBinding()]
    param()

    $isWindows = Test-WeckWindows
    $computerSystem = $null
    $operatingSystem = $null

    if ($isWindows) {
        try {
            $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        } catch {
            try {
                $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
            } catch {
                Write-WeckLog -Level "WARN" -Message ("Unable to read computer system details: {0}" -f $_.Exception.Message)
            }
        }

        try {
            $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        } catch {
            try {
                $operatingSystem = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
            } catch {
                Write-WeckLog -Level "WARN" -Message ("Unable to read operating system details: {0}" -f $_.Exception.Message)
            }
        }
    }

    $manufacturer = "Unknown"
    $model = "Unknown"
    if ($computerSystem) {
        $manufacturer = [string]$computerSystem.Manufacturer
        $model = [string]$computerSystem.Model
    }

    $virtualizationPlatform = "Unknown"
    $parallelsDetected = $false
    $machineText = ("{0} {1}" -f $manufacturer, $model)
    if ($machineText -match "Parallels") {
        $virtualizationPlatform = "Parallels Desktop"
        $parallelsDetected = $true
    } elseif ($machineText -match "VMware") {
        $virtualizationPlatform = "VMware"
    } elseif ($machineText -match "VirtualBox") {
        $virtualizationPlatform = "VirtualBox"
    } elseif ($machineText -match "Microsoft Corporation.*Virtual Machine|Hyper-V") {
        $virtualizationPlatform = "Hyper-V"
    } elseif ($computerSystem -and $computerSystem.HypervisorPresent) {
        $virtualizationPlatform = "Hypervisor detected"
    }

    $caption = "Unknown"
    $version = "Unknown"
    $buildNumber = "Unknown"
    $edition = "Unknown"
    if ($operatingSystem) {
        $caption = [string]$operatingSystem.Caption
        $version = [string]$operatingSystem.Version
        $buildNumber = [string]$operatingSystem.BuildNumber
        $edition = $caption
    } elseif (-not $isWindows) {
        $caption = "Non-Windows host"
    }

    $architecture = "Unknown"
    if ($operatingSystem -and $operatingSystem.OSArchitecture) {
        $architecture = [string]$operatingSystem.OSArchitecture
    } else {
        $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }

    $wingetAvailable = Test-WingetAvailable

    return [pscustomobject]@{
        IsWindows              = $isWindows
        WindowsCaption         = $caption
        WindowsVersion         = $version
        BuildNumber            = $buildNumber
        Edition                = $edition
        Architecture           = $architecture
        PowerShellVersion      = $PSVersionTable.PSVersion.ToString()
        IsAdministrator        = (Test-WeckAdministrator)
        Manufacturer           = $manufacturer
        Model                  = $model
        VirtualizationPlatform = $virtualizationPlatform
        ParallelsDetected      = $parallelsDetected
        WingetAvailable        = $wingetAvailable
    }
}

function Show-WeckEnvironmentSummary {
    <#
    .SYNOPSIS
        Prints detected environment information.
    .PARAMETER Environment
        Environment object returned by Get-WeckEnvironment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Environment
    )

    Write-WeckLog -Level "INFO" -Message "Environment"
    Write-WeckLog -Level "INFO" -Message ("Windows: {0}" -f $Environment.WindowsCaption)
    Write-WeckLog -Level "INFO" -Message ("Version/build: {0} / {1}" -f $Environment.WindowsVersion, $Environment.BuildNumber)
    Write-WeckLog -Level "INFO" -Message ("Architecture: {0}" -f $Environment.Architecture)
    Write-WeckLog -Level "INFO" -Message ("PowerShell: {0}" -f $Environment.PowerShellVersion)
    Write-WeckLog -Level "INFO" -Message ("Administrator: {0}" -f $Environment.IsAdministrator)
    Write-WeckLog -Level "INFO" -Message ("Virtualization: {0}" -f $Environment.VirtualizationPlatform)
    Write-WeckLog -Level "INFO" -Message ("Parallels detected: {0}" -f $Environment.ParallelsDetected)
    Write-WeckLog -Level "INFO" -Message ("winget available: {0}" -f $Environment.WingetAvailable)

    if (-not $Environment.IsWindows) {
        Write-WeckLog -Level "WARN" -Message "This host is not Windows. Dry-run and configuration validation are supported; real provisioning requires Windows."
    }
}
