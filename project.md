# WECK

**Workstation Environment Construction Kit**  
**Version:** 0.1.0  
**Target:** Windows 11 ARM64 IoT Enterprise LTSC / Enterprise LTSC  
**Primary Platform:** Parallels Desktop on Apple Silicon

---

# Concept

WECK is inspired by Fallout's **GECK**, the Garden of Eden Creation Kit.

GECK rebuilt settlements from wasteland.

**WECK rebuilds a fresh Windows install into a reproducible developer workstation.**

Tagline:

> Rebuild your workstation.  
> Not your operating system.

---

# Core Idea

WECK is **not** a debloater.

It does not try to tear Windows apart.

Instead, it safely provisions a clean system using declarative configuration.

It should feel like:

- Homebrew for macOS
- cloud-init for Linux
- rustup for toolchains
- Infrastructure-as-Code for Windows developer machines

---

# Lore-Inspired Structure

Instead of generic “profiles,” WECK uses **Vaults**.

A Vault is a reusable workstation configuration.

Examples:

```text
vaults/
    base.json
    rust-dev.json
    node-dev.json
    ai-dev.json
    wmmd-dev.json
    godot-dev.json
```

Example commands:

```powershell
.\bootstrap.ps1 -Vault base
.\bootstrap.ps1 -Vault wmmd-dev
.\bootstrap.ps1 -Vault godot-dev
```

Future CLI concept:

```bash
weck apply vaults/base
weck apply vaults/wmmd-dev
weck doctor
weck survey
weck export
```

---

# Philosophy

Most Windows debloat scripts:

- remove system components
- disable random services
- break Windows Update
- disable Defender
- uninstall built-in packages
- modify undocumented registry values

WECK should do **none** of those.

WECK should:

- install useful software
- configure Windows for developers
- improve privacy using safe policies
- improve usability
- avoid destructive changes
- remain compatible with future Windows updates

If there is uncertainty about whether a tweak is safe:

**Do not apply it by default.**

---

# Design Principles

## Safety First

Never intentionally reduce Windows stability.

Never make changes that break:

- Windows Update
- Defender
- WSL
- Hyper-V
- Docker
- Visual Studio
- Windows Installer
- Event Log
- PowerShell
- Parallels Tools

---

## Idempotent

Running WECK multiple times should produce the same result.

No duplicated work.

No duplicate installations.

No duplicate registry entries.

---

## Vault-Based

Vaults are declarative JSON configuration files.

A vault defines:

- packages
- tweaks
- optional Windows features
- environment preferences
- future dev stack setup

Vaults should be composable later, but initial implementation can load one vault at a time.

---

## Transparent

Every action should be logged.

Every change should explain:

- what it changes
- why it exists
- whether it is reversible

---

## Conservative

Prefer fewer changes.

Never optimize for benchmark numbers.

Optimize for:

- stability
- developer productivity
- long-term maintenance

---

# Target Platform

Primary target:

- Windows 11 ARM64
- Windows 11 IoT Enterprise LTSC
- Windows 11 Enterprise LTSC
- Parallels Desktop
- Apple Silicon

Secondary target:

- Windows 11 Pro
- Windows 11 Enterprise

WECK should detect unsupported systems and print warnings instead of failing whenever practical.

---

# Repository Structure

```text
WECK/

README.md

bootstrap.ps1

config/
    defaults.json
    tweaks.json
    features.json

vaults/
    base.json
    rust-dev.json
    node-dev.json
    ai-dev.json
    wmmd-dev.json
    godot-dev.json

src/
    Checks.ps1
    Logging.ps1
    Vaults.ps1
    Packages.ps1
    Tweaks.ps1
    Features.ps1
    Winget.ps1
    Registry.ps1
    Helpers.ps1

logs/
```

---

# bootstrap.ps1

The bootstrap script is the entry point.

Supported parameters:

```powershell
-DryRun

-Verbose

-SkipPackages

-SkipTweaks

-SkipFeatures

-ConfigPath

-Vault

-NoRestart
```

Example usage:

```powershell
.\bootstrap.ps1 -DryRun -Vault base
.\bootstrap.ps1 -Vault base
.\bootstrap.ps1 -Vault wmmd-dev
.\bootstrap.ps1 -Vault godot-dev -SkipFeatures
```

Execution flow:

```text
Start Logging

↓

Environment Checks

↓

Administrator Check

↓

Windows Edition Detection

↓

Architecture Detection

↓

Parallels Detection

↓

Winget Check

↓

Load Vault

↓

Package Installation

↓

Windows Tweaks

↓

Optional Features

↓

Summary

↓

Exit
```

---

# Environment Detection

Collect:

- Windows version
- build number
- edition
- architecture
- PowerShell version
- administrator status
- virtualization platform
- Parallels detection if possible
- Winget availability

Print a friendly summary.

---

# Logging

Implement logging helpers.

Levels:

```text
INFO
WARN
ERROR
SUCCESS
DEBUG
```

Logs should be written to:

```text
logs/weck-yyyyMMdd-HHmmss.log
```

Also print colored console output.

---

# Vault Format

Each Vault should be JSON.

Example:

```json
{
  "name": "base",
  "description": "Base developer workstation setup.",
  "packages": [
    {
      "id": "Microsoft.PowerShell",
      "enabled": true,
      "category": "Core"
    },
    {
      "id": "Git.Git",
      "enabled": true,
      "category": "Core"
    }
  ],
  "tweaks": [
    "show_file_extensions",
    "show_hidden_files",
    "disable_advertising_id",
    "disable_consumer_features",
    "disable_bing_search",
    "enable_long_paths"
  ],
  "features": [
    {
      "name": "Microsoft-Windows-Subsystem-Linux",
      "enabled": false
    },
    {
      "name": "VirtualMachinePlatform",
      "enabled": false
    }
  ]
}
```

---

# Default Vaults

## base.json

Purpose:

Minimal safe developer setup.

Packages:

- Microsoft.PowerShell
- Microsoft.WindowsTerminal
- Git.Git
- Microsoft.VisualStudioCode
- 7zip.7zip
- voidtools.Everything
- Microsoft.Sysinternals
- GitHub.cli

Tweaks:

- show file extensions
- show hidden files
- open Explorer to This PC
- disable advertising ID
- disable consumer features
- disable suggested content
- disable activity history
- disable Bing web search
- disable Game DVR
- enable long paths

Features:

- none enabled by default

---

## rust-dev.json

Extends base conceptually.

Packages:

- Rustlang.Rustup
- Microsoft.VisualStudio.2022.BuildTools
- Git.Git
- Microsoft.VisualStudioCode

Do not implement inheritance yet unless easy.

---

## node-dev.json

Packages:

- OpenJS.NodeJS.LTS
- pnpm.pnpm
- Git.Git
- Microsoft.VisualStudioCode

---

## ai-dev.json

Packages:

- Python.Python.3.12
- Git.Git
- Microsoft.VisualStudioCode
- Docker.DockerDesktop optional, disabled by default
- Ollama.Ollama optional, disabled by default if available in winget

---

## wmmd-dev.json

Purpose:

Windows workstation for WMMD / MMD / graphics-engine experimentation.

Packages:

- Git.Git
- Microsoft.VisualStudioCode
- Rustlang.Rustup
- Python.Python.3.12
- Microsoft.VisualStudio.2022.BuildTools
- Microsoft.DotNet.SDK.8
- BlenderFoundation.Blender
- Gyan.FFmpeg
- Microsoft.WindowsTerminal
- 7zip.7zip

Features:

- WSL disabled by default
- VirtualMachinePlatform disabled by default

---

## godot-dev.json

Packages:

- Git.Git
- Microsoft.VisualStudioCode
- Python.Python.3.12
- Microsoft.DotNet.SDK.8
- GodotEngine.GodotEngine
- Gyan.FFmpeg
- Krita.Krita
- BlenderFoundation.Blender

---

# Package Installation

Use Winget.

Package list should be loaded from the selected Vault.

Package installer should:

- detect installed software
- skip existing packages
- continue on individual failure
- print summary
- support disabled package entries
- support dry run
- log installed, skipped, failed packages

Do not fail the entire bootstrap because one package failed.

---

# Tweaks

Tweaks should be registry or policy based.

Tweak definitions should live in:

```text
config/tweaks.json
```

Vaults should reference tweak IDs.

Each tweak definition should contain:

```json
{
  "id": "show_file_extensions",
  "name": "Show file extensions",
  "description": "Show known file extensions in Explorer.",
  "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
  "name": "HideFileExt",
  "type": "DWord",
  "value": 0,
  "enabledByDefault": true,
  "reversible": true
}
```

Safe default tweaks:

Explorer:

- show file extensions
- show hidden files
- open This PC

Privacy:

- disable advertising ID
- disable consumer features
- disable suggested content
- disable activity history

Search:

- disable Bing web search

Gaming:

- disable Game DVR

Edge:

- disable startup boost
- disable background mode

Filesystem:

- enable long paths

Appearance:

- dark mode optional

---

# Optional Features

Feature definitions should live in:

```text
config/features.json
```

Default feature candidates:

Disabled by default:

- Microsoft-Windows-Subsystem-Linux
- VirtualMachinePlatform
- Microsoft-Hyper-V-All
- Containers-DisposableClientVM
- NetFx3

Never enable automatically unless requested by a Vault.

Feature behavior:

- check current feature state
- enable only if requested
- continue on feature failure
- log if reboot is required

---

# Things WECK Must NEVER Do

Never uninstall Windows components.

Never uninstall Microsoft Edge.

Never disable:

- Windows Defender
- Windows Update
- Windows Installer
- Event Log
- PowerShell
- WinRM
- Networking
- Windows Security
- Windows Firewall
- WSL
- Hyper-V
- Parallels Tools services

Never run:

```powershell
Remove-AppxPackage *
```

Never disable services blindly.

Never apply registry tweaks from unknown internet scripts.

Never import random REG files.

---

# Error Handling

Every task should:

- catch exceptions
- continue when appropriate
- log errors
- provide useful messages

The bootstrap should not terminate because one package failed.

---

# Code Style

PowerShell should be:

- modular
- readable
- documented
- auditable
- strongly typed where practical

Avoid:

- giant scripts
- clever one-liners
- hidden side effects
- internet copy-paste tweaks

Every public function should include:

- synopsis
- parameters
- description

---

# README Requirements

Generate a professional README including:

- project goals
- Fallout GECK inspiration note
- explanation that WECK is not affiliated with Fallout, Bethesda, or Microsoft
- philosophy
- supported operating systems
- supported architectures
- installation
- usage
- vault system
- configuration
- safety policy
- contribution guide
- license placeholder

---

# Example README Opening

```markdown
# WECK

**Workstation Environment Construction Kit**

WECK is a safe, declarative bootstrap tool for turning a clean Windows installation into a reproducible developer workstation.

Inspired by Fallout's GECK, WECK treats a fresh OS like an empty settlement: first survey the land, then provision the essentials, then make it livable.

WECK is not a debloater. It does not remove Windows components, disable Defender, or break Windows Update. It builds instead of destroys.
```

---

# Future Roadmap

Do not implement everything immediately.

Design the architecture so future versions can include:

## Version 0.2

- vault inheritance
- vault composition
- restore point creation
- better package detection
- package updates
- PSScriptAnalyzer setup

## Version 0.3

- Windows Terminal profile configuration
- PowerShell profile generation
- Git configuration
- SSH key generation
- Dev Drive creation
- WinGet Configuration integration

## Version 0.4

- VS Code extension installer
- Python virtual environment bootstrap
- Rust toolchain profiles
- Node environment management

## Version 0.5

- Docker Desktop setup
- WSL distribution installer
- Kubernetes tooling
- Azure CLI
- AWS CLI
- Terraform

## Version 1.0

Complete reproducible developer workstation.

One command should transform a fresh LTSC VM into a fully configured development environment.

---

# Success Criteria

A successful WECK run should:

- run safely multiple times
- produce detailed logs
- load a selected Vault
- install all enabled packages
- apply only selected safe Windows tweaks
- enable only explicitly requested optional features
- preserve Windows Update
- preserve Defender
- preserve WSL compatibility
- preserve Hyper-V compatibility
- preserve Parallels Tools
- preserve future update compatibility
- be easy to extend
- be understandable after reading the code for only a few minutes

---

# Final Instruction to Codex

Build the initial WECK repository.

Prioritize:

1. Safety
2. Readability
3. Maintainability
4. Correctness
5. Extensibility
6. Performance

Avoid clever code.

Prefer explicit code over concise code.

The project should feel like a professional open source tool that could become the recommended bootstrap solution for Windows developer machines, especially Windows 11 ARM64 LTSC running in Parallels.
