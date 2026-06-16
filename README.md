# nvmx (nvm extended)

Make `.nvmrc` actually do something on Windows — decided per **command**,
without touching anything global.

Repo: https://github.com/UsmanDrigrocha/nvmx

## Why this exists

On Windows, `nvm use 20.19.0` flips a single symlink that **every** terminal
and **every** folder points at. That's why switching in one project "changes
Node everywhere." nvmx instead wraps `node` / `npm` / `npx` so each call:

1. looks for a `.nvmrc` in the current folder or any parent,
2. if found, runs the **matching installed** Node version directly,
3. if not found / not installed / nvm missing, uses your **default** Node.

The override lasts only for that one command, then `PATH` is restored. Nothing
global changes; your default stays the default in every other folder and terminal.

## Install (easiest)

Clone the repo, then double-click **`install.cmd`**:

```powershell
git clone https://github.com/UsmanDrigrocha/nvmx
cd nvmx
```

That's it. `install.cmd` runs the installer with the execution-policy bypass
built in, so you don't have to touch any settings. Then open a new terminal and run:

```powershell
nvmx-status
```

### What the installer does

- Copies `Nvmx.psm1` to `%LOCALAPPDATA%\nvmx\` — a stable local folder, so the
  "downloaded from internet" mark is gone and it keeps working even if you delete
  the original folder.
- Unblocks the copied file.
- Relaxes execution policy to `RemoteSigned` **only if** it's currently set to
  something that would block (CurrentUser scope, no admin needed). That's the
  standard safe developer default, not "security off."
- Adds an idempotent import line to your PowerShell profile.

(Prefer the command line? `powershell -ExecutionPolicy Bypass -File .\Install.ps1`)

## Uninstall (easiest)

From any terminal where nvmx is loaded:

```powershell
Uninstall-Nvmx
```

Or double-click **`uninstall.cmd`**. Either one removes the profile line and
deletes `%LOCALAPPDATA%\nvmx\`. Open a new terminal afterwards.

## Use

Just use `node`, `npm`, `npx` normally.

```text
C:\projects\app-a>  type .nvmrc
18.20.4
C:\projects\app-a>  node -v
v18.20.4          # from .nvmrc, this command only

C:\projects\app-b>  node -v
v22.3.0           # no .nvmrc here -> your default
```

`.nvmrc` accepts a plain version: `20`, `20.19`, or `20.19.0`. Partial versions
match the highest installed patch (e.g. `20` -> newest `20.x.x` you have).

## What runs on the .nvmrc version

nvmx wraps three commands: `node`, `npm`, and `npx`. Those — and anything they
launch as a child process — use the `.nvmrc` version.

- `node app.js`, `npm install`, `npx tsc` -> `.nvmrc` version.
- `npm run dev` where the script is `nodemon src/index.ts` -> `.nvmrc` version
  (npm passes the chosen Node down to nodemon and everything it spawns).
- `nodemon` typed directly at the prompt -> your **default** Node. It isn't one
  of the wrapped names. Run it via `npm run` or `npx nodemon` to get `.nvmrc`.

Rule of thumb: reached through `node`/`npm`/`npx` = `.nvmrc`; typed directly as
some other tool = default.

## Requirements

- [nvm-windows](https://github.com/coreybutler/nvm-windows) with `NVM_HOME` set,
  and the Node versions you reference already installed (`nvm install 20.19.0`).
- PowerShell (Windows PowerShell 5.1 or PowerShell 7+).
- If you use both PowerShell editions, run the installer once in each (they have
  separate profiles).

## Error messages

- **Version not installed** -> warns, says run `nvm install <v>`, uses default.
- **nvm-windows not installed** -> warns `NVM_HOME` isn't set, with a link, uses default.
- **`.nvmrc` uses `lts/*` / `latest`** -> warns it's unsupported, uses default.
- **No Node at all on PATH** -> errors and stops.

## Files

- `Nvmx.psm1` — the module (all the logic; `nvmx-status`, `Uninstall-Nvmx`).
- `Install.ps1` / `Uninstall.ps1` — setup and removal.
- `install.cmd` / `uninstall.cmd` — double-click wrappers (policy bypass built in).
- `site/index.html` + `site/style.css` — a landing page for the project.

## What it does NOT do (yet)

- No `nvm use`, so no global state ever changes.
- No `lts/*` / `latest` resolution (falls back to default).
- PowerShell only — CMD and Git Bash aren't covered.