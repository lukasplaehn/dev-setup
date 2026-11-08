# Architecture

How my Windows development machines are set up, what each script in this repo creates, and why. The target state is identical on every machine (Surface laptop, home PC) for both GitHub accounts.

For the step-by-step setup of a new machine, see the [README](../README.md).

## Goals

1. Only code reaches GitHub. Environments, secrets and data never do.
2. Nothing development-related syncs to OneDrive.
3. Data stays on the local machine, outside every repository.
4. Each GitHub account gets its own identity, keys and commit signature, chosen automatically by folder.
5. Any machine can be rebuilt from this repo plus `git pull` and `uv sync`.

## Layers

The setup has three layers. Each layer only holds what belongs to it.

| Layer | Script | Scope | Run as | Holds |
|---|---|---|---|---|
| Machine: identity | `bootstrap-dev.ps1` | Once per machine | Admin | Folders, SSH keys and aliases, git identity routing, signing |
| Machine: Python baseline | `setup-python.ps1` | Once per machine | Normal user | Package caches, interpreters, CLI tools, VS Code |
| Project | `new-project.ps1` | Once per repo | Normal user | Libraries, guardrails, workspace settings, data folder |

The rule between the machine and project layers: **the machine gets tools, the project gets libraries.** No importable library is installed globally. Every library a project imports is declared in its `pyproject.toml` and pinned in `uv.lock`, so `uv sync` rebuilds the same environment on any machine.

## Storage layout

All development work lives on a **Dev Drive**: a ReFS volume stored as a dynamically expanding VHDX, outside OneDrive, mounted as `D:`.

```
D:\
├── repos\
│   ├── lukasplaehn\          ← repos for the personal account
│   │   └── <project>\
│   │       └── .venv\        ← per-project environment (gitignored)
│   └── lukas-plaehn-ai\      ← repos for the AI account
├── data\
│   └── <project>\
│       ├── raw\
│       ├── interim\
│       └── processed\
└── packages\
    ├── uv\                   ← UV_CACHE_DIR
    └── pip\                  ← PIP_CACHE_DIR
```

Design decisions:

- **Dev Drive instead of a folder on C:.** Dev Drive is trusted and Defender scans it asynchronously (performance mode), so git, uv and pytest run faster. Only Defender's `WdFilter` is attached. The VHDX file sits under the user profile but outside Documents and Desktop, so OneDrive's folder backup never touches it.
- **Data outside the repo.** A `.gitignore` entry only protects data until someone runs `git add -f` or a pattern is wrong. Physical separation means git cannot see the data at all. Code finds it through `DATA_DIR` in the project's `.env`.
- **Cache on the same volume as the projects.** uv hardlinks packages from its cache into each `.venv`. Hardlinks only work within one volume, so the cache lives on `D:` next to the projects.
- **Interpreters and tools stay on C:.** uv-managed Python lives in `%LOCALAPPDATA%\uv`, and CLI tools in `%APPDATA%\uv\tools`. Microsoft advises against putting developer tools on a Dev Drive. Tool installs therefore copy instead of hardlinking across volumes, and the resulting uv warning is expected.

## Identity: two GitHub accounts, two machines

| Account | Commit email | Repo folder | SSH alias |
|---|---|---|---|
| `lukasplaehn` | `28509449+lukasplaehn@users.noreply.github.com` | `D:\repos\lukasplaehn\` | `github-personal` |
| `lukas-plaehn-ai` | `266509094+lukas-plaehn-ai@users.noreply.github.com` | `D:\repos\lukas-plaehn-ai\` | `github-ai` |

The Gmail addresses are only the account logins and notification addresses. Commits always use the noreply addresses, so neither Gmail address appears in commit history.

### How the right identity is chosen

1. **The folder selects the git identity.** The global `~/.gitconfig` has an `includeIf "gitdir/i:D:/repos/<account>/"` rule per account. It loads `~/.gitconfig-<account>`, which sets `user.email`, `user.signingkey` and a URL rewrite.
2. **The URL rewrite selects the SSH alias.** In each account's include, `url."git@<alias>:".insteadOf = git@github.com:` means a remote written as `git@github.com:...` is sent through that account's alias.
3. **The alias selects the key.** `~/.ssh/config` maps each alias to `github.com` with its own `IdentityFile` and `IdentitiesOnly yes`. GitHub identifies the account by key alone, so `IdentitiesOnly` stops the agent from offering the wrong key.
4. **Outside those folders, commits fail.** No global `user.email` is set and `user.useConfigOnly = true`. A repo in the wrong place fails with "please tell me who you are" instead of committing under the wrong identity.

`includeIf` only applies once a repository exists. For the first clone, use the alias directly:

```
git clone git@github-ai:lukas-plaehn-ai/<repo>.git D:\repos\lukas-plaehn-ai\<repo>
```

### Keys

There is one ed25519 key per account **per machine**, so four keys in total. Private keys never leave the machine they were generated on. Each public key is added to its GitHub account twice, as an Authentication key and as a Signing key, titled with the machine name. Losing a machine means revoking only that machine's keys.

| File | Purpose |
|---|---|
| `~/.ssh/id_ed25519_personal` (+ `.pub`) | Push and sign for `lukasplaehn` |
| `~/.ssh/id_ed25519_ai` (+ `.pub`) | Push and sign for `lukas-plaehn-ai` |
| `~/.ssh/config` | Host aliases `github-personal`, `github-ai` |
| `~/.ssh/allowed_signers` | Local verification of signed commits |

Keys are passphrase-protected and cached by the Windows `ssh-agent` service. Git uses Windows OpenSSH (`core.sshCommand`) rather than its bundled ssh, so it talks to that agent.

### Commit signing

Commits and tags are signed with the account's SSH key (`gpg.format = ssh`, `commit.gpgsign = true`, `tag.gpgSign = true`). GitHub shows them as Verified. Locally, `git log --show-signature` and `%G?` verify against `~/.ssh/allowed_signers`.

## Python baseline (machine level)

| Component | Detail |
|---|---|
| Package manager | uv |
| Interpreters | 3.12 and 3.13, installed by uv; 3.13 is the global default (`uv python pin --global`) |
| CLI tools | `ruff`, `pre-commit` (with `pre-commit-uv`), each isolated via `uv tool install` |
| Caches | `UV_CACHE_DIR = D:\packages\uv`, `PIP_CACHE_DIR = D:\packages\pip` (user environment variables) |
| VS Code extensions | Python, Pylance, Ruff, Jupyter, Even Better TOML, DotENV |
| VS Code user settings | Ruff formats and organises imports on save, LF line endings, final newline, trailing whitespace trimmed, `.venv` excluded from watcher and search, commit signing on, telemetry off |

There is no python.org or Microsoft Store Python, and nothing is installed into a global site-packages.

## Project template

`new-project.ps1 -Account <account> -Name <name> [-Libs a,b] [-Python 3.12] [-Notebooks]` creates the following.

In `D:\repos\<account>\<name>\`:

| File | Committed | Purpose |
|---|---|---|
| `pyproject.toml` | Yes | Dependencies plus Ruff and pytest configuration |
| `uv.lock` | Yes | Exact pinned dependency versions |
| `.python-version` | Yes | Project interpreter |
| `src/<module>/__init__.py` | Yes | Package (src layout) |
| `src/<module>/config.py` | Yes | Loads `.env`, exposes `DATA_DIR`, `RAW_DIR`, `INTERIM_DIR`, `PROCESSED_DIR` |
| `tests/test_config.py` | Yes | Asserts the data folder is outside the repo |
| `.gitignore` | Yes | Excludes `.venv`, `.env`, data file types and caches |
| `.gitattributes` | Yes | LF everywhere, CRLF for `.ps1`, `.bat`, `.cmd` |
| `.pre-commit-config.yaml` | Yes | Commit guardrails (below) |
| `.vscode/settings.json` | Yes | Interpreter path, `.env` file, pytest |
| `.vscode/extensions.json` | Yes | Recommended extensions |
| `.env.example` | Yes | Template for `.env` |
| `.env` | **No** | `DATA_DIR` for this machine |
| `.venv/` | **No** | Environment, rebuilt with `uv sync` |

In `D:\data\<name>\`, it creates `raw\`, `interim\` and `processed\`. These folders are never in git or OneDrive.

Dependencies:

- **Runtime baseline:** `python-dotenv`, plus anything passed to `-Libs`.
- **Dev group:** `pytest`, `pytest-cov`, `ruff`, plus `ipykernel` with `-Notebooks`.
- **Later additions:** `uv add <lib>` or `uv add --dev <tool>` from inside the project.

### Guardrails on every commit

| Hook | Blocks or fixes |
|---|---|
| `check-added-large-files` (500 KB) | Accidental data dumps |
| `detect-private-key`, `gitleaks` | Secrets |
| `check-merge-conflict`, `check-toml`, `check-yaml` | Broken files |
| `end-of-file-fixer`, `trailing-whitespace` | Whitespace noise |
| `ruff --fix`, `ruff-format` | Lint and formatting |
| `nbstripout` (with `-Notebooks`) | Notebook outputs, which often contain data |

On GitHub, two account settings back these hooks up: push protection for secrets, and vigilant mode, which marks unsigned commits as Unverified.

## Files each machine script creates

`bootstrap-dev.ps1`:

| Location | What |
|---|---|
| `D:\repos\<account>\`, `D:\data\` | Folder structure |
| `~/.ssh/id_ed25519_personal`, `~/.ssh/id_ed25519_ai` | Keys, only if missing |
| `~/.ssh/config` | Host aliases (the previous version is kept as `config.bak`) |
| `~/.ssh/allowed_signers` | Signer list for both accounts |
| `~/.gitconfig` | Global settings and `includeIf` routing |
| `~/.gitconfig-lukasplaehn`, `~/.gitconfig-lukas-plaehn-ai` | Per-account identity and URL rewrite |
| `~/.gitignore_global` | OS and editor junk |
| Windows service | `ssh-agent` set to start automatically |

`setup-python.ps1`:

| Location | What |
|---|---|
| `D:\packages\uv`, `D:\packages\pip` | Cache folders |
| User environment | `UV_CACHE_DIR`, `PIP_CACHE_DIR` |
| `%LOCALAPPDATA%\uv\python` | Interpreters |
| `%APPDATA%\uv\tools` | `ruff`, `pre-commit` |
| `%APPDATA%\Code\User\settings.json` | Baseline settings, only if the file does not exist yet |

All machine scripts are idempotent and safe to re-run.

## Verification

| Check | Expected |
|---|---|
| `fsutil devdrv query D:` (admin) | Trusted developer volume, only `WdFilter` attached |
| `uv cache dir` | `D:\packages\uv` |
| `ssh -T git@github-personal` / `ssh -T git@github-ai` | Greets the matching username |
| Empty commit in each account folder, then `git log -1 --format="%ae %G?"` | Matching noreply email and `G` |
| Commit in any other folder | Fails with "please tell me who you are" |
| First push of a new project | GitHub shows Verified, no `.venv`, `.env` or data |

## Operations

- **Lost or retired machine:** delete that machine's keys (Authentication and Signing) on both GitHub accounts. The other machine is unaffected.
- **Key rotation:** delete the key files, re-run `bootstrap-dev.ps1`, replace the keys on GitHub.
- **Moving between machines:** `git pull`, then `uv sync`. Data does not move with the code. Copy `D:\data\<project>` separately if it is needed.
- **Backup:** GitHub covers code. `D:\data` has no copy anywhere and needs a separate backup.

## Assumptions and known limits

- Windows 11 (build 22621.2338 or later) on both machines, with Defender as the antivirus. Dev Drive performance mode does not apply with third-party antivirus.
- On these machines, `Get-MpPreference` reports `PerformanceModeStatus = 1` when performance mode is on. Use the Windows Security toggle as the authoritative check.
- The pre-commit hook versions in `new-project.ps1` are older known-valid releases. `pre-commit autoupdate` bumps them when a project is created.
- `safe.directory = D:/repos/*` prevents "dubious ownership" errors on the ReFS volume.
