<#
.SYNOPSIS
    General WECK helper functions.
.DESCRIPTION
    Small shared helpers used by the bootstrap modules.
#>

function Resolve-WeckConfigPath {
    <#
    .SYNOPSIS
        Resolves the WECK configuration directory.
    .PARAMETER RootPath
        Repository root path.
    .PARAMETER ConfigPath
        Optional user-supplied config path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [string]$ConfigPath
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        return (Join-Path $RootPath "config")
    }

    if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
        return $ConfigPath
    }

    return (Join-Path (Get-Location).Path $ConfigPath)
}

function Import-WeckJsonFile {
    <#
    .SYNOPSIS
        Loads and parses a JSON file.
    .PARAMETER Path
        JSON file path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON file not found: $Path"
    }

    $content = Get-Content -LiteralPath $Path -Raw
    try {
        return ($content | ConvertFrom-Json)
    } catch {
        throw "Invalid JSON in $Path`: $($_.Exception.Message)"
    }
}

function ConvertTo-WeckArray {
    <#
    .SYNOPSIS
        Normalizes null, scalar, and array JSON values into an array.
    .PARAMETER Value
        Value to normalize.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        return $Value
    }

    return @($Value)
}

function New-WeckPhaseResult {
    <#
    .SYNOPSIS
        Creates a structured phase result.
    .PARAMETER Name
        Phase name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return [pscustomobject]@{
        Name          = $Name
        Status        = "Completed"
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

function Add-WeckResultItem {
    <#
    .SYNOPSIS
        Adds an item record to a phase result.
    .PARAMETER Result
        Result object to update.
    .PARAMETER Item
        Item record to add.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Result,

        [Parameter(Mandatory = $true)]
        [psobject]$Item
    )

    $items = @()
    if ($Result.Items) {
        $items += $Result.Items
    }
    $items += $Item
    $Result.Items = $items
}

function Test-WeckCommandAvailable {
    <#
    .SYNOPSIS
        Checks whether a command is available.
    .PARAMETER Name
        Command name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue
    return ($null -ne $command)
}

function Test-WeckWindows {
    <#
    .SYNOPSIS
        Returns true when running on Windows.
    #>
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -le 5) {
        return $true
    }

    if ($PSVersionTable.ContainsKey("Platform")) {
        return ($PSVersionTable.Platform -eq "Win32NT")
    }

    return $true
}
