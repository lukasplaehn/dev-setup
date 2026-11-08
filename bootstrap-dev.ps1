#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Machine setup for git, SSH and the two GitHub accounts
  (lukasplaehn, lukas-plaehn-ai). Run once per machine; safe to re-run.
  Python tooling is separate: run setup-python.ps1 afterwards.

.EXAMPLE
  .\bootstrap-dev.ps1
  .\bootstrap-dev.ps1 -DevRoot E:   # if the Dev Drive has another letter

.NOTES
  - Assumes the Dev Drive is already created and mounted at $DevRoot.
  - Generates one SSH key per account PER MACHINE. Never copy private keys.
  - Commit emails are GitHub noreply addresses, not the Gmail login addresses.
#>
param(
    [string]$DevRoot       = "D:",
    [string]$MachineName   = $env:COMPUTERNAME,
    [string]$PersonalEmail = "28509449+lukasplaehn@users.noreply.github.com",
    [string]$AiEmail       = "266509094+lukas-plaehn-ai@users.noreply.github.com"
)

$ErrorActionPreference = "Stop"
$sshDir = Join-Path $HOME ".ssh"
$root   = $DevRoot.TrimEnd('\','/')
$rootFs = $root -replace '\\','/'          # forward slashes for git

$accounts = @(
    @{ Name = "lukasplaehn";     Alias = "github-personal"; Key = "id_ed25519_personal"; Email = $PersonalEmail },
    @{ Name = "lukas-plaehn-ai"; Alias = "github-ai";       Key = "id_ed25519_ai";       Email = $AiEmail }
)

function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

# --- 0. Prerequisites ------------------------------------------------------
Step "Checking prerequisites"
if (-not (Test-Path "$root\")) { throw "Dev Drive $root not found. Create/mount it first." }
foreach ($tool in "git", "ssh-keygen", "ssh-add") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool not found on PATH." }
}

# --- 1. Folders ------------------------------------------------------------
Step "Creating folder structure on $root"
$dirs = @("repos", "data") +
        ($accounts | ForEach-Object { "repos\$($_.Name)" })
foreach ($d in $dirs) { New-Item -ItemType Directory -Force -Path "$root\$d" | Out-Null }

# --- 2. ssh-agent ----------------------------------------------------------
Step "Enabling Windows ssh-agent"
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent

# --- 3. Keys (one per account, per machine) --------------------------------
Step "SSH keys"
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
foreach ($a in $accounts) {
    $keyPath = Join-Path $sshDir $a.Key
    if (Test-Path $keyPath) {
        Write-Host "  $($a.Key) exists - keeping it"
    } else {
        Write-Host "  Generating $($a.Key) (you will be asked for a passphrase)"
        ssh-keygen -t ed25519 -C "$($a.Name)@$MachineName" -f $keyPath
    }
    ssh-add $keyPath
}

# --- 4. SSH config (host aliases) ------------------------------------------
Step "Writing ~/.ssh/config"
$sshConfig = Join-Path $sshDir "config"
if (Test-Path $sshConfig) { Copy-Item $sshConfig "$sshConfig.bak" -Force }
$blocks = foreach ($a in $accounts) {
@"
Host $($a.Alias)
    HostName github.com
    User git
    IdentityFile ~/.ssh/$($a.Key)
    IdentitiesOnly yes
"@
}
($blocks -join "`r`n`r`n") | Out-File -Encoding ascii $sshConfig   # no BOM: OpenSSH chokes on it

# --- 5. Global git config --------------------------------------------------
Step "Global git config"
git config --global --unset-all user.email      2>$null
git config --global --unset-all user.signingkey 2>$null
$global = [ordered]@{
    "init.defaultBranch" = "main"
    "core.autocrlf"      = "false"
    "core.longpaths"     = "true"
    "core.excludesFile"  = "~/.gitignore_global"
    "core.sshCommand"    = "C:/Windows/System32/OpenSSH/ssh.exe"
    "pull.rebase"        = "true"
    "user.name"          = "Lukas Plaehn"
    "user.useConfigOnly" = "true"
    "gpg.format"         = "ssh"
    "commit.gpgsign"     = "true"
    "tag.gpgSign"        = "true"
}
foreach ($k in $global.Keys) { git config --global $k $global[$k] }
git config --global --replace-all safe.directory "$rootFs/repos/*"

# --- 6. Per-account identity, routed by folder -----------------------------
Step "Per-account git identities"
foreach ($a in $accounts) {
    $inc = Join-Path $HOME ".gitconfig-$($a.Name)"
@"
[user]
    email = $($a.Email)
    signingkey = ~/.ssh/$($a.Key).pub
[url "git@$($a.Alias):"]
    insteadOf = git@github.com:
"@ | Out-File -Encoding ascii $inc
    git config --global "includeIf.gitdir/i:$rootFs/repos/$($a.Name)/.path" "~/.gitconfig-$($a.Name)"
}

# --- 6b. Allowed signers (local verification of SSH-signed commits) -------
Step "Allowed signers file"
$signers = foreach ($a in $accounts) {
    "$($a.Email) namespaces=`"git`" " + (Get-Content (Join-Path $sshDir "$($a.Key).pub") -Raw).Trim()
}
$signers | Out-File -Encoding ascii (Join-Path $sshDir "allowed_signers")
git config --global gpg.ssh.allowedSignersFile "~/.ssh/allowed_signers"

# --- 7. Global gitignore ---------------------------------------------------
Step "Global gitignore"
@'
# Windows
Thumbs.db
desktop.ini
*.lnk
$RECYCLE.BIN/
# Editors
*.swp
*~
.idea/
'@ | Out-File -Encoding ascii (Join-Path $HOME ".gitignore_global")

# --- 8. What's left to do by hand ------------------------------------------
Step "Manual steps on GitHub"
foreach ($a in $accounts) {
    Write-Host "`nLog in as $($a.Name) -> Settings -> SSH and GPG keys -> New SSH key" -ForegroundColor Yellow
    Write-Host "Add TWICE (Authentication + Signing), title: '$MachineName'"
    Get-Content (Join-Path $sshDir "$($a.Key).pub")
}
Write-Host "`nThen test:" -ForegroundColor Yellow
foreach ($a in $accounts) { Write-Host "  ssh -T git@$($a.Alias)" }
Write-Host "`nClone with the alias, into the matching folder, e.g.:"
Write-Host "  git clone git@github-ai:lukas-plaehn-ai/<repo>.git $root\repos\lukas-plaehn-ai\<repo>"
Write-Host "`nNext: run setup-python.ps1 in a normal (non-admin) PowerShell." -ForegroundColor Green
