<#
.SYNOPSIS
  Scaffold a new Python project in the right account folder, with its own
  pinned dependencies, local-only data folder and commit guardrails.

.EXAMPLE
  .\new-project.ps1 -Account lukasplaehn -Name property-monitor -Libs httpx,polars
  .\new-project.ps1 -Account lukas-plaehn-ai -Name rag-lab -Libs openai -Notebooks

.NOTES
  - Run in a normal (non-admin) PowerShell after bootstrap-dev.ps1.
  - Libraries go into this project's pyproject.toml / uv.lock only.
  - Add more later from inside the project:  uv add <lib>   /  uv add --dev <tool>
#>
param(
    [Parameter(Mandatory)] [ValidateSet("lukasplaehn", "lukas-plaehn-ai")] [string]$Account,
    [Parameter(Mandatory)] [ValidatePattern("^[a-z][a-z0-9-]*$")] [string]$Name,
    [string[]]$Libs = @(),
    [string]$Python,                      # default: the global uv pin
    [switch]$Notebooks,
    [string]$DevRoot = "D:"
)

$ErrorActionPreference = "Stop"
function Invoke-Native([scriptblock]$Cmd) {
    & $Cmd
    if ($LASTEXITCODE -ne 0) { throw "Failed ($LASTEXITCODE): $Cmd" }
}
function Write-Text($Path, $Content) {           # LF, no BOM
    $full = Join-Path $proj $Path
    New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
    [IO.File]::WriteAllText($full, ($Content -replace "`r`n", "`n"))
}

$root   = $DevRoot.TrimEnd('\', '/')
$proj   = "$root\repos\$Account\$Name"
$data   = "$root\data\$Name"
$module = $Name -replace '-', '_'

if (Test-Path $proj) { throw "$proj already exists." }

# --- 1. Project skeleton (src layout, git init, pinned interpreter) --------
Write-Host "== Creating $proj" -ForegroundColor Cyan
$initArgs = @("init", "--package", "--name", $Name, $proj)
if ($Python) { $initArgs += @("--python", $Python) }
Invoke-Native { uv @initArgs }
Set-Location $proj

# --- 2. Dependencies: baseline + project-specific ---------------------------
Write-Host "== Dependencies" -ForegroundColor Cyan
Invoke-Native { uv add python-dotenv }
$dev = @("pytest", "pytest-cov", "ruff")
if ($Notebooks) { $dev += "ipykernel" }
Invoke-Native { uv add --dev @dev }
if ($Libs.Count) { Invoke-Native { uv add @Libs } }

# --- 3. Local-only data folder, outside the repo ----------------------------
foreach ($d in "raw", "interim", "processed") {
    New-Item -ItemType Directory -Force -Path "$data\$d" | Out-Null
}
Write-Text ".env"         "DATA_DIR=$data`n"
Write-Text ".env.example" "DATA_DIR=D:\data\$Name`n"

Write-Text "src\$module\config.py" @'
"""Project paths. Data lives outside the repo; DATA_DIR comes from .env."""

import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

DATA_DIR = Path(os.environ["DATA_DIR"])
RAW_DIR = DATA_DIR / "raw"
INTERIM_DIR = DATA_DIR / "interim"
PROCESSED_DIR = DATA_DIR / "processed"
'@

Write-Text "tests\test_config.py" @"
from $module import config


def test_data_dir_is_outside_repo():
    repo = config.Path(__file__).resolve().parents[1]
    assert repo not in config.DATA_DIR.resolve().parents
"@

# --- 4. Tool config in pyproject --------------------------------------------
$pyproject = (Get-Content pyproject.toml -Raw).TrimEnd() + "`n" + @'

[tool.ruff]
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "W", "I", "B", "UP", "S", "PD"]
ignore = ["S101"]  # assert is fine in tests

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-q"
'@
Write-Text "pyproject.toml" $pyproject

# --- 5. Git hygiene ---------------------------------------------------------
Write-Text ".gitignore" @'
# Environments and secrets
.venv/
.env
!.env.example

# Data never enters the repo (it lives in DATA_DIR)
data/
*.csv
*.tsv
*.parquet
*.feather
*.xlsx
*.xls
*.json.gz
*.db
*.sqlite
*.duckdb
*.pkl
*.pickle

# Python and tool caches
__pycache__/
*.py[cod]
.pytest_cache/
.ruff_cache/
.mypy_cache/
.coverage
htmlcov/
dist/
build/
*.egg-info/

# Notebooks
.ipynb_checkpoints/
'@

Write-Text ".gitattributes" @'
* text=auto eol=lf
*.ps1 text eol=crlf
*.bat text eol=crlf
*.cmd text eol=crlf
'@

$nbHook = if ($Notebooks) { @'

  - repo: https://github.com/kynan/nbstripout
    rev: 0.7.1
    hooks:
      - id: nbstripout
'@ } else { "" }

Write-Text ".pre-commit-config.yaml" (@'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: check-added-large-files
        args: ["--maxkb=500"]
      - id: check-merge-conflict
      - id: check-toml
      - id: check-yaml
      - id: detect-private-key
      - id: end-of-file-fixer
      - id: trailing-whitespace

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9
    hooks:
      - id: ruff
        args: ["--fix"]
      - id: ruff-format

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks
'@ + $nbHook)

# --- 6. VS Code workspace (project-specific only) ---------------------------
Write-Text ".vscode\settings.json" @'
{
    "python.defaultInterpreterPath": "${workspaceFolder}/.venv/Scripts/python.exe",
    "python.envFile": "${workspaceFolder}/.env",
    "python.testing.pytestEnabled": true,
    "python.testing.pytestArgs": ["tests"]
}
'@
Write-Text ".vscode\extensions.json" @'
{
    "recommendations": [
        "ms-python.python",
        "ms-python.vscode-pylance",
        "charliermarsh.ruff",
        "tamasfe.even-better-toml"
    ]
}
'@

# --- 7. Hooks, first check, signed initial commit --------------------------
Write-Host "== Pre-commit hooks (first run downloads hook environments)" -ForegroundColor Cyan
Invoke-Native { pre-commit autoupdate }
Invoke-Native { pre-commit install }
Invoke-Native { uv sync }
Invoke-Native { uv run pytest }

Invoke-Native { git add -A }                    # hooks only see tracked files
pre-commit run --all-files | Out-Null           # first pass may auto-fix files
Invoke-Native { git add -A }
Invoke-Native { pre-commit run --all-files }    # second pass must be clean
Invoke-Native { git commit -q -m "Initial project scaffold" }

Write-Host "`n== Done: $proj" -ForegroundColor Green
Write-Host "Data folder (local only): $data"
Write-Host "`nNext: create an EMPTY repo '$Name' on GitHub as $Account, then:"
Write-Host "  git remote add origin git@github.com:$Account/$Name.git"
Write-Host "  git push -u origin main"
Write-Host "`nOpen it:  code $proj"
