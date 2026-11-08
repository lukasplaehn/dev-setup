<#
.SYNOPSIS
  Python baseline for one Windows machine: package caches on the Dev Drive,
  uv-managed interpreters, isolated CLI tools and VS Code. Run after
  bootstrap-dev.ps1, once per machine; safe to re-run. No admin needed.

  Machine-wide = tools only. Importable libraries belong in each project's
  pyproject.toml (see new-project.ps1).

.EXAMPLE
  .\setup-python.ps1
  .\setup-python.ps1 -DevRoot E: -DefaultPython 3.12
#>
param(
    [string]$DevRoot          = "D:",
    [string[]]$PythonVersions = @("3.12", "3.13"),
    [string]$DefaultPython    = "3.13"
)

$ErrorActionPreference = "Stop"
$root = $DevRoot.TrimEnd('\','/')
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

# --- 1. uv ---------------------------------------------------------------------
Step "Checking uv"
if (-not (Test-Path "$root\")) { throw "Dev Drive $root not found." }
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing uv via winget"
    winget install --id astral-sh.uv -e --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "Machine")
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        throw "uv installed but not on PATH yet. Open a new terminal and re-run."
    }
}

# --- 2. Package caches on the Dev Drive ----------------------------------------
Step "Pointing package caches at the Dev Drive"
foreach ($d in "packages\uv", "packages\pip") { New-Item -ItemType Directory -Force -Path "$root\$d" | Out-Null }
[Environment]::SetEnvironmentVariable("UV_CACHE_DIR",  "$root\packages\uv",  "User")
[Environment]::SetEnvironmentVariable("PIP_CACHE_DIR", "$root\packages\pip", "User")
$env:UV_CACHE_DIR  = "$root\packages\uv"      # this session too
$env:PIP_CACHE_DIR = "$root\packages\pip"

# --- 3. Interpreters, CLI tools, VS Code ---------------------------------
#     Tools only. No importable libraries are installed globally: those
#     belong in each project's pyproject.toml.
Step "Python interpreters (uv-managed)"
uv python install @PythonVersions
uv python pin --global $DefaultPython

Step "Global CLI tools (isolated via uv tool)"
uv tool install ruff
uv tool install pre-commit --with pre-commit-uv
uv tool update-shell

if (Get-Command code -ErrorAction SilentlyContinue) {
    Step "VS Code extensions"
    $extensions = @(
        "ms-python.python",
        "ms-python.vscode-pylance",
        "charliermarsh.ruff",
        "ms-toolsai.jupyter",
        "tamasfe.even-better-toml",
        "mikestead.dotenv"
    )
    foreach ($e in $extensions) { code --install-extension $e --force | Out-Null }

    Step "VS Code user settings (editor-wide baseline)"
    $userSettings = Join-Path $env:APPDATA "Code\User\settings.json"
    if (Test-Path $userSettings) {
        Write-Warning "  $userSettings exists - not overwriting. Merge the baseline block from this script by hand."
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $userSettings) | Out-Null
@'
{
    "[python]": {
        "editor.defaultFormatter": "charliermarsh.ruff",
        "editor.formatOnSave": true,
        "editor.codeActionsOnSave": {
            "source.fixAll": "explicit",
            "source.organizeImports": "explicit"
        }
    },
    "python.terminal.activateEnvironment": true,
    "python.analysis.typeCheckingMode": "basic",
    "files.eol": "\n",
    "files.insertFinalNewline": true,
    "files.trimTrailingWhitespace": true,
    "files.watcherExclude": { "**/.venv/**": true },
    "search.exclude": { "**/.venv": true },
    "git.enableCommitSigning": true,
    "telemetry.telemetryLevel": "off"
}
'@ | Out-File -Encoding ascii $userSettings
    }
} else {
    Write-Warning "Skipping VS Code setup: 'code' not on PATH (VS Code > Command Palette > Shell Command)."
}

Write-Host "`n== Done. Open a NEW terminal so PATH and cache variables take effect." -ForegroundColor Green
Write-Host "Check with:  uv cache dir ; uv python list --only-installed ; pre-commit --version"
