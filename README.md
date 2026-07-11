# WECK

**Workstation Environment Construction Kit**

WECK is a safe, declarative bootstrap tool for turning a clean Windows installation into a reproducible developer workstation.

Inspired by Fallout's GECK, WECK treats a fresh OS like an empty settlement: first survey the land, then provision the essentials, then make it livable.

WECK is not a debloater. It does not remove Windows components, disable Defender, or break Windows Update. It builds instead of destroys.

## Status

WECK is currently an initial `0.1.0` scaffold. The bootstrap flow, vault loading, logging, package phase, safe tweak phase, and optional feature phase are implemented with dry-run support.

Run dry-run first:

```powershell
.\bootstrap.ps1 -DryRun -Vault base
```

## Non-Affiliation

WECK is independently developed. It is not affiliated with, endorsed by, or sponsored by Bethesda Softworks, Bethesda Game Studios, Microsoft, or the Fallout franchise.

## Philosophy

Most Windows debloat scripts try to tear Windows apart. WECK takes the opposite approach.

WECK should:

- install useful developer software
- configure Windows through clear declarative files
- improve privacy using conservative policy and registry settings
- remain compatible with Windows Update, Defender, WSL, Hyper-V, Docker, Visual Studio, PowerShell, and Parallels Tools
- explain and log every action
- be safe to run more than once

If a tweak is uncertain, it should not be enabled by default.

## Supported Systems

Primary target:

- Windows 11 ARM64
- Windows 11 IoT Enterprise LTSC
- Windows 11 Enterprise LTSC
- Parallels Desktop on Apple Silicon

Secondary target:

- Windows 11 Pro
- Windows 11 Enterprise

WECK can be inspected and dry-run from non-Windows hosts, but real provisioning requires Windows.

## Safety Policy

WECK must never:

- uninstall Windows components
- uninstall Microsoft Edge
- disable Windows Defender
- disable Windows Update
- disable Windows Installer
- disable Event Log
- disable PowerShell
- disable WinRM
- disable networking
- disable Windows Security
- disable Windows Firewall
- disable WSL
- disable Hyper-V
- disable Parallels Tools services
- run `Remove-AppxPackage *`
- disable services blindly
- import random `.reg` files
- apply registry tweaks copied from unknown internet scripts

WECK `0.1.0` never restarts automatically. Use `-NoRestart` to make that intent explicit in command logs.

## Installation

Clone or copy the repository onto the target Windows machine.

From an elevated PowerShell session:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\bootstrap.ps1 -DryRun -Vault base
```

After reviewing the dry-run output:

```powershell
.\bootstrap.ps1 -Vault base
```

Administrator privileges are recommended for real runs because some winget installs, HKLM policy values, and optional Windows features require elevation.

### Remote Launcher

WECK also includes `install.ps1`, a small remote-friendly launcher that requests administrator privileges, prepares machine dependencies, clones or updates the repository, shows a vault menu, then invokes `bootstrap.ps1`.

Review the script first whenever possible. If you choose to use `iex`, only run it from a URL you control and trust:

```powershell
irm https://raw.githubusercontent.com/r1cebank/weck/main/install.ps1 | iex
```

If the repository URL changes, set it explicitly for the launcher:

```powershell
$env:WECK_REPO_URL = "https://github.com/r1cebank/weck.git"
irm https://raw.githubusercontent.com/r1cebank/weck/main/install.ps1 | iex
```

The launcher requests UAC elevation before dependency preparation. This is expected: App Installer repair, Git installation, HKLM tweaks, and optional Windows features may need administrator privileges.

The launcher defaults to cloning into `%USERPROFILE%\weck`. It prepares dependencies before pulling WECK:

- If winget is missing, it tries to register or install Microsoft App Installer / Windows Package Manager.
- If Git is missing, it installs `Git.Git` with winget.
- After winget and Git are available, it clones or updates `https://github.com/r1cebank/weck.git`.

This is intended for Windows 11 Enterprise LTSC and IoT Enterprise LTSC images where App Installer, winget, or Git may not be present yet.

Non-interactive dry run with dependency preparation:

```powershell
$env:WECK_NONINTERACTIVE = "1"
$env:WECK_VAULT = "base"
$env:WECK_RUN_MODE = "DryRun"
irm https://raw.githubusercontent.com/r1cebank/weck/main/install.ps1 | iex
```

Non-interactive doctor/preflight:

```powershell
$env:WECK_NONINTERACTIVE = "1"
$env:WECK_VAULT = "base"
$env:WECK_RUN_MODE = "Doctor"
irm https://raw.githubusercontent.com/r1cebank/weck/main/install.ps1 | iex
```

Skip dependency installation only when preparing dependencies another way:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/r1cebank/weck/main/install.ps1))) -SkipWingetInstall -SkipGitInstall
```

The elevated launcher window stays open by default so dependency-preparation errors remain visible. Add `-CloseOnFinish` if you want the elevated window to close automatically after a successful run.

Skip the UAC relaunch only for inspection or special testing:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/r1cebank/weck/main/install.ps1))) -NoAdminRelaunch -RunMode DryRun
```

For parameterized use without relying on pipeline `iex`, invoke the downloaded script block directly:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/r1cebank/weck/main/install.ps1))) -Vault wmmd-dev -RunMode DryRun
```

## Usage

Apply the base vault in dry-run mode:

```powershell
.\bootstrap.ps1 -DryRun -Vault base
```

Apply a development vault:

```powershell
.\bootstrap.ps1 -Vault wmmd-dev
```

Skip optional features:

```powershell
.\bootstrap.ps1 -Vault godot-dev -SkipFeatures
```

Inspect only tweaks and features:

```powershell
.\bootstrap.ps1 -DryRun -Vault base -SkipPackages
```

Use a vault JSON file by path:

```powershell
.\bootstrap.ps1 -DryRun -Vault .\vaults\base.json
```

## Parameters

`bootstrap.ps1` supports:

- `-Doctor`: run preflight checks only and do not apply packages, tweaks, or features
- `-DryRun`: print planned actions without changing the system
- `-SkipPackages`: skip winget package handling
- `-SkipTweaks`: skip registry and policy tweaks
- `-SkipFeatures`: skip optional Windows feature handling
- `-ConfigPath`: use an alternate configuration directory
- `-Vault`: vault name or path to a vault JSON file
- `-NoRestart`: document restart suppression; v0.1 never restarts automatically
- `-Verbose`: use PowerShell's built-in verbose output

## Vaults

Vaults are declarative workstation configurations stored under `vaults/`.

Initial vaults:

- `base`
- `rust-dev`
- `node-dev`
- `ai-dev`
- `wmmd-dev`
- `godot-dev`

Vault inheritance and composition are planned for a later release. For now, each vault is self-contained.

Example:

```json
{
  "name": "base",
  "description": "Minimal safe developer workstation setup.",
  "packages": [
    {
      "id": "Git.Git",
      "enabled": true,
      "category": "Core"
    }
  ],
  "tweaks": [
    "show_file_extensions",
    "enable_long_paths"
  ],
  "features": []
}
```

## Configuration

Configuration lives in `config/`.

- `defaults.json`: project defaults and safety flags
- `tweaks.json`: safe registry and policy tweak definitions
- `features.json`: optional Windows feature definitions

Tweak definitions use `valueName` for registry value names to avoid ambiguity with the tweak display `name`.

## Logging

Every run creates a timestamped log file:

```text
logs/weck-yyyyMMdd-HHmmss.log
```

Logs include environment detection, selected vault, package outcomes, tweak outcomes, feature outcomes, errors, and final counts.

## Development

The codebase is intentionally plain PowerShell:

- `bootstrap.ps1` is the entry point
- `src/Checks.ps1` detects environment state
- `src/Logging.ps1` handles console and file logging
- `src/Vaults.ps1` loads and validates vaults
- `src/Packages.ps1` runs the package phase
- `src/Winget.ps1` wraps winget commands
- `src/Tweaks.ps1` runs the tweak phase
- `src/Registry.ps1` wraps registry reads and writes
- `src/Features.ps1` runs the optional feature phase
- `src/Helpers.ps1` contains shared helpers

Prefer readable, explicit code over clever one-liners. Public functions should include comment-based help.

## Validation

Recommended non-mutating checks:

```powershell
.\bootstrap.ps1 -Doctor -Vault base
.\bootstrap.ps1 -DryRun -Vault base
.\bootstrap.ps1 -DryRun -Vault wmmd-dev -SkipFeatures
.\bootstrap.ps1 -DryRun -Vault godot-dev -SkipPackages
```

`-Doctor` exits with code `2` when blocked checks are found, and `0` when no blockers are present.

On a fresh Windows 11 ARM64 VM in Parallels:

1. Run `.\bootstrap.ps1 -Doctor -Vault base`.
2. Run `.\bootstrap.ps1 -DryRun -Vault base`.
3. Review console output and `logs/`.
4. Run `.\bootstrap.ps1 -Vault base`.
5. Run `.\bootstrap.ps1 -Vault base` again to confirm idempotency.

## Roadmap

Future versions may add vault inheritance, restore point creation, PSScriptAnalyzer setup, package updates, Windows Terminal profile configuration, PowerShell profile generation, Git configuration, Dev Drive setup, VS Code extensions, language toolchain profiles, Docker setup, WSL distro installation, and cloud tooling.

## Contributing

Contributions should preserve WECK's safety model:

- no destructive defaults
- no undocumented registry tweaks
- no blind service disabling
- no Windows component removal
- no automatic restarts
- dry-run support for every phase
- clear logs for every action

## License

WECK is released under the MIT License. See [LICENSE](LICENSE).
