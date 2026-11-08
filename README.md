# dev-setup

Scripts that build my Windows development machines the same way every time: a Dev Drive for all dev work, two GitHub accounts routed by folder with signed commits, a uv-based Python baseline, and a project template that keeps environments, secrets and data out of git and OneDrive.

The design and the reasoning behind it are in [docs/architecture.md](docs/architecture.md).

## Contents

| Script | Run | Does |
|---|---|---|
| [`bootstrap-dev.ps1`](bootstrap-dev.ps1) | Once per machine, **admin** | Folders, SSH keys and aliases, git identity per account, commit signing |
| [`setup-python.ps1`](setup-python.ps1) | Once per machine, normal shell | uv, package caches on the Dev Drive, Python interpreters, `ruff` and `pre-commit`, VS Code |
| [`new-project.ps1`](new-project.ps1) | Once per project, normal shell | New repo in the right account folder with pinned dependencies, guardrails and a local data folder |

All three are safe to re-run.

## Set up a new machine

Prerequisites: Windows 11 (build 22621.2338 or later), Defender as the antivirus, and Git for Windows installed.

1. **Create the Dev Drive.** Go to Settings → System → Storage → Advanced storage settings → Disks & volumes → Create Dev Drive → Create new VHD. Use the VHDX format, dynamically expanding, 150 to 200 GB. Store it outside Documents and Desktop, for example under `C:\Users\<you>\DevDrive\`. Assign it the letter `D:`.
2. **Turn on Dev Drive protection** in Windows Security → Virus & threat protection → Manage settings.
3. **Check the drive.** In an admin PowerShell, `fsutil devdrv query D:` should report a trusted developer volume with only `WdFilter` attached.
4. **Get this repo.** SSH isn't set up yet, so download it as a ZIP from the GitHub web UI and extract it outside OneDrive (for example to `D:\`).
5. **Run the identity setup** in an admin PowerShell:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   Get-ChildItem *.ps1 | Unblock-File
   .\bootstrap-dev.ps1              # add -DevRoot E: if the Dev Drive is not D:
   ```

6. **Register the keys.** The script prints two public keys. Add each one to its GitHub account (Settings → SSH and GPG keys) **twice**, once as an Authentication key and once as a Signing key, using the machine name as the title. Then test both:

   ```powershell
   ssh -T git@github-personal
   ssh -T git@github-ai
   ```

7. **Run the Python setup** in a normal (non-admin) PowerShell, then open a new terminal:

   ```powershell
   .\setup-python.ps1
   ```

8. **Swap the ZIP for a clone:**

   ```powershell
   git clone git@github-personal:lukasplaehn/dev-setup.git D:\repos\lukasplaehn\dev-setup
   ```

   Then delete the extracted ZIP copy.

The checks in [docs/architecture.md#verification](docs/architecture.md#verification) confirm the result.

## Start a new project

```powershell
.\new-project.ps1 -Account lukasplaehn -Name my-project -Libs polars,httpx
.\new-project.ps1 -Account lukas-plaehn-ai -Name rag-lab -Libs openai -Notebooks
```

Then create an **empty** repo with the same name on GitHub under that account, and push:

```powershell
cd D:\repos\<account>\<name>
git remote add origin git@github.com:<account>/<name>.git
git push -u origin main
```

Add libraries later with `uv add <lib>`, or `uv add --dev <tool>` for dev-only tools. On another machine, `git pull` followed by `uv sync` reproduces the environment exactly.

To clone an existing repo, use the account's SSH alias and the matching folder:

```powershell
git clone git@github-ai:lukas-plaehn-ai/<repo>.git D:\repos\lukas-plaehn-ai\<repo>
```

## Changing this repo

Update [docs/architecture.md](docs/architecture.md) in the same commit as any script change it describes.
