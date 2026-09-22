# m0-coding — a reusable machine0 NixOS image for coding projects with agents

One NixOS image, frozen once, cloned for every project. It is machine0's
[`loaded` profile](https://github.com/fdmtl/machine0-nixos) (dev stack,
rootless Docker, Claude Code, Codex, the Home Manager zsh) plus the rest of
the agent set (**OmO Native**, **DeepSeek Harness**, Hermes, OpenCode),
**devenv.sh**, and the per-project conveniences a coding VM needs.

This repo is a *private consumer flake*: it takes `machine0-nixos` as an
input and layers one module on top. Nothing here is published to GitHub, and
no machine0 image has to be rebuilt per project.

## Current state

| Thing | Value |
|---|---|
| Image | `m0-coding` — version 3, `READY`/`ACTIVE`, region `eu`, 38.39 GB, **Min. Disk 80 GB** |
| Image metadata | `flakeRev 6b03889` with `uncommitted: false` (v2 was frozen from the pre-commit tree; v3 re-freezes the same VM against the committed revision) |
| `dev` VM | SUSPENDED, `large`, `eu` — created from image v1 with `--profile default`; gh + codex + machine0 credentials injected |
| `m0-dev` VM | STOPPED — the image-iteration box; `bin/m0-dev` resumes it automatically. Its store already holds the built `omo`/`dsh`, so re-provisions are fast |
| `DEFAULT_VM_IMAGE` | `m0-coding` (bare `machine0 new <name>` picks it up) |
| Profile system packages | 189 (187 + `omo` + `dsh`) |
| Proven | the image builds end to end locally; a clone boots with every tool and no provisioning; `devenv shell` builds a real project env using the devenv cache; on a provisioned VM `omo --version` → `omo 5.0.0-0.beta.82 (engine: senpi 2026.9.22)`, `dsh --version` → `0.1.6-alpha.2`, and `~/.omo/{omo.json,agent/settings.json}` match `files/omo/` byte for byte |

Not yet done: `claude-code` is installed but **not authenticated** (its OAuth
requires an interactive paste — see *Credentials*), and the repo has never
been published, so the server-side `--git-repo` image build path is untested.

## What is in the image

Inherited from machine0's `loaded` profile:

- agents `claude-code` and `codex` (tracked from nixpkgs-unstable)
- gcc/make/cmake, python3 + uv + pipx, rust/cargo, go, bun, node
- rootless Docker, npm, nginx, firewall 80/443
- gh, git, tmux, ripgrep, jq, htop, btop, lsof, chafa, screen
- zsh + starship + zoxide + eza + fzf (Home Manager), `machine0` CLI
- `base` profile's hardened SSH, fail2ban, the machine0 metadata/profile-inject services

Added by `modules/coding.nix`:

- agents `hermes` (NousResearch) and `opencode` — toggleable via `m0coding.agents.*`
- **OmO Native** (`omo`, omo.dev) — the multi-model agent harness, packaged
  from a pinned `omo-ai@beta` npm release in `pkgs/omo/`. There is no nixpkgs
  package, and the release is not a self-contained bundle (the senpi engine
  needs its own `node_modules`), so it is a real `npm ci` tree; the wrapper
  pins nixpkgs' node 24 because omo only re-execs under bun when it finds
  bun >= 1.4 and 25.11 ships bun 1.3.3. Toggle: `m0coding.agents.omo.enable`
- **DeepSeek Harness** (`dsh`) — the `presets.tui` composition from
  `github:moraxyc/deepseek-harness.nix`, taken from that flake's own package
  set (its overlay wants `pnpm_11`, which 25.11 nixpkgs does not have — see
  the module comment) and shipped with its binary cache added to
  `nix.settings.substituters`. Toggle: `m0coding.agents.dsh.enable`
- **devenv.sh 2.1.2** + direnv + nix-direnv, so any project gets its own
  reproducible environment. It comes from **nixpkgs-unstable**, not the 25.11
  release channel, which still ships the 1.11.x line and prints an
  out-of-date warning on every `devenv shell`. The `devenv.cachix.org` binary
  cache and its public key are added to `nix.settings.substituters`
  (concatenated with upstream's, not replacing them)
- nodejs_22 + pnpm + deno, just, watchexec, hyperfine
- docker compose, git-lfs, git delta, tree, fd, bat, yq-go
- database/CLI clients: psql, redis-cli, sqlite
- NixOS-patched Playwright browsers + `PLAYWRIGHT_*` env for the agents — toggleable via `m0coding.playwright.enable`

Every package and service addition is made at normal priority, so a project
profile can override any of it (the MOTD is the exception — see the banner
priority ladder in `modules/coding.nix`).

## Prerequisites (all of these bit us once)

```bash
# 1. CLI + login. Node is already present here, so npm is the shorter path;
#    the vendor script (curl -LsSf https://machine0.io/install.sh | sh)
#    installs its own Node via nvm first.
npm install -g @machine0/cli
machine0 login                       # interactive
machine0 account                     # check Wallet Balance — VM creation fails at $0.00

# 2. An SSH private key at the path the CLI expects (it wants id_rsa even for
#    ed25519). Register it as the default key; a PUBLIC key is enough for
#    ssh/provision (a MANAGED key is only needed for server-side deploys and
#    the in-browser terminal).
ssh-keygen -t ed25519 -f ~/.ssh/id_rsa -N ""
machine0 keys new <name> --type PUBLIC --publicKeyPath ~/.ssh/id_rsa.pub --default
```

Cost reference: `large` $0.052/hr, `medium` $0.034/hr, `small` $0.013/hr —
per-minute, and a stopped VM still bills. `machine0 suspend <vm>` is the way
to stop paying for compute while keeping the disk.

## Workflows

### 1. Iterate on the image itself

```bash
nix flake check          # cheap eval guard: catches bad options/packages, no build
bin/m0-dev               # create (or resume) m0-dev, provision .#coding, verify
```

`bin/m0-dev` creates `m0-dev` from `nixos-25-11-loaded` if missing, starts it
if it is stopped/suspended, makes the dsh binary cache trusted on it, **seeds
its store with `.#omo` + `.#dsh`** (see the ops note — the dsh kernel build
OOM-kills a 4 GB VM), runs `machine0 provision m0-dev .#coding` (a local sync —
no GitHub publish needed), then verifies every tool (now `omo` and `dsh`
included), the seeded OmO config, Docker, and the injected credentials. Edit
`modules/coding.nix`, re-run it, and the same VM is rebuilt in place. The
first run is the slow one (it builds `omo` + `dsh` on *this* machine); after
that a provision is back to ~5–10 minutes.

To build the image locally instead (validates the image path end to end):
`bin/m0-build` → `./result-image/nixos-image-*.qcow2.gz`.

### 2. Freeze it and clone it per project

```bash
bin/m0-snap m0-dev             # stop the VM, snapshot it as image "m0-coding"
bin/m0-new api                 # project VM from the image — seconds, no build
machine0 ssh api
```

Snapshots are versioned: re-run `bin/m0-snap` after a change and the image
gets a new version (promote/roll back with `machine0 images versions`). The
script records the flake git revision as image metadata.

**Size floor is `large`.** A builder's disk size becomes the image's minimum,
so the `large` (80 GB) builder produced `Min. Disk 80 GB` — `medium` (60 GB)
cannot boot this image. Rebuild with `--size medium` if you only want smaller
VMs. `bin/m0-new` therefore defaults to `large`.

### 3. Per-project configuration

Lightest first:

1. **devenv / devShell in the project repo — the intended path** (no VM
   rebuild at all):

   ```bash
   # on the VM, in the project
   devenv init                    # or hand-write devenv.nix
   echo 'use devenv' > .envrc     # `use flake` works too
   direnv allow
   devenv shell
   ```

   Agents pick the environment up automatically: direnv + nix-direnv are wired
   into the `nix` user's zsh, and `devenv.cachix.org` is already trusted, so
   the first shell substitutes rather than compiles.

2. **A project profile in this repo** — copy `projects/example/` (postgres +
   redis + a firewall port + a banner) and add an entry to the `profiles` map
   in `flake.nix`:

   ```bash
   machine0 provision <vm> ".#example"
   ```

   Profiles live in the root flake rather than in `projects/`, deliberately:
   `machine0 provision <vm> ./subdir#profile` syncs *that directory only*, so a
   project flake with a relative `path:../..` input would resolve outside the
   synced tree.

3. **A separate project flake that consumes this one** (once published):

   ```nix
   inputs.m0coding.url = "github:<you>/m0-coding";
   nixosConfigurations.api = m0coding.lib.mkSystem [
     m0coding.nixosModules.coding
     ./project.nix
   ];
   ```

## Agent configuration: OmO comes from this repo, credentials never do

`modules/coding.nix` seeds OmO's user config once per home, copy-if-missing
(so the agent's own rewrites of those files survive a rebuild):

| repo file | lands at | what it is |
|---|---|---|
| `files/omo/omo.json` | `~/.omo/omo.json` | agent + category model routing |
| `files/omo/agent/settings.json` | `~/.omo/agent/settings.json` | theme, default provider/model, thinking levels |

The rest of a real OmO home (`auth.json`, `models-store.json`, `sessions/`,
`extensions/` — the last three are generated at runtime) is machine state and
is deliberately **not** in this repo: `auth.json` is a credential store. Give
a VM credentials one of two ways:

1. **Environment** — the engine reads `OPENROUTER_API_KEY`,
   `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` and `DEEPSEEK_API_KEY` from the
   environment, so the machine0 profile inject (`~/.machine0/env.sh`, sourced
   by every login shell) is enough. `dsh` uses the same mechanism for
   `DEEPSEEK_API_KEY`.
2. **`m0coding.agents.omo.authFile = "path/on/the/vm.json"`** — installed as
   `~/.omo/agent/auth.json` (0600) the first time a home is activated.

Bumping the agent means editing `pkgs/omo/package.json`, the `version` in
`pkgs/omo/default.nix`, refreshing the lockfile and re-running
`prefetch-npm-deps` — the exact three commands are in that file's header.

## Credentials come from the profile, at create time

The image has the *clients*; auth is injected per VM by a machine0 profile.
Injection happens **only when the VM is created**, so a VM created without
`--profile` never gets credentials — `bin/m0-new` and `bin/m0-dev` both pass
`M0_PROFILE` (default `default`).

```bash
machine0 integrations connect github -y     # browser + localhost callback
machine0 integrations connect codex -y      # same
machine0 integrations connect claude-code   # INTERACTIVE ONLY
machine0 integrations check                 # verify
```

- `claude-code` cannot be connected non-interactively: it needs a callback
  code pasted into a real terminal (or `--auth api-key` reading a key on
  stdin — a secret, so run that yourself, not through an agent).
- `machine0 profiles deploy <vm>` *looks* like the retrofit path, but it
  fails with `ssh exec requires a managed key` on VMs created with a PUBLIC
  key. Create a fresh VM from the image instead.
- Verify from inside a VM: `gh api user -q .login`, `test -s ~/.codex/auth.json`,
  `ls ~/.claude`, `ls ~/.machine0/`.

## Scripts

| Script | What it does |
|---|---|
| `bin/m0-dev [vm] [size] [flake-profile]` | create/resume a VM, `provision .#coding`, verify tools + auth. Env: `M0_PROFILE`, `M0_BASE_IMAGE` |
| `bin/m0-snap <vm> [image] [description]` | stop the VM and snapshot it into the versioned reusable image |
| `bin/m0-new <project> [size] [m0-profile]` | create a project VM from the frozen image. Env: `M0_IMAGE` |
| `bin/m0-build [flake-profile]` | build the image locally (`./result-image`), with machine0's caches |

`manifest.json` is the single source of truth for profile → image slug and the
size floor; the scripts read it.

## Ops notes

- **The dsh closure is big, only partially cached, and needs RAM to build.**
  `modules/coding.nix` adds `deepseek-harness-nix.cachix.org` and its key to
  `nix.settings.substituters`, so the image and every clone substitute what
  the upstream cache has. Two paths need help because they run *before* the
  new substituters are live: `bin/m0-dev` writes the same cache into the
  VM's `/etc/nix/nix.conf`, restarts `nix-daemon`, and only then provisions
  (a switch makes new `nix.settings` live only after it finishes), and
  `bin/m0-build` passes the key on the command line (this workstation sets
  `trusted-users = mei`, so that is honored).
- **A `large` VM cannot *build* dsh; `bin/m0-dev` seeds its store instead.**
  dsh's kernel bundle is compiled by node/esbuild and the first attempt got
  the build OOM-killed on a 2 vCPU / 4 GB box (load average 30). So the script
  builds/substitutes `.#omo` and `.#dsh` **here**, asks the VM which of those
  store paths it lacks, and pipes only those in (`nix-store --export |
  machine0 ssh … 'sudo nix-store --import'` — root, because the daemon rejects
  unsigned paths from an untrusted client). The VM then only pulls the base
  system from the binary caches and the provision stays inside a `large` VM.
  That is deliberate: the builder's disk size becomes the image's minimum, so
  moving the build to an `xl` VM would push every project VM from `large`
  ($0.052/hr, 80 GB) to `xl` ($0.104/hr, 160 GB).
- **`nix build .#omo` / `.#dsh`** build the two agents on their own (that is
  what the seeding step uses); they are the same derivations the image ships.
- **Local builds need machine0's caches.** `bin/m0-build` passes
  `machine0.cachix.org` + `cache.garnix.io`. Without them nix compiles ~450
  derivations from source; with them it is ~44 trivial ones plus ~2.6 GiB of
  downloads (~18 min, producing a ~3.9 GiB `.qcow2.gz` from an 11 GiB closure).
- **auto-upgrade is disabled by default.** Upstream sets
  `system.autoUpgrade.flake = "github:fdmtl/machine0-nixos"`, which would
  rebuild the plain `loaded` profile nightly and silently drop this layer.
  Once this repo is published, re-enable it against your own repo:

  ```nix
  m0coding.autoUpgradeFlake = "github:<you>/m0-coding#coding";
  ```

- **Rebuild from the repo, not on the VM.** `/etc/nixos` on a machine0 VM
  holds the *upstream* source; `sudo nixos-rebuild switch` there drops your
  config. Use `machine0 provision <vm> .#coding`.
- **`machine0 ssh` re-parses its arguments.** It joins argv into one string
  that the remote shell then parses, so `machine0 ssh <vm> bash -lc '<script>'`
  silently collapses (the `-lc` eats the next argument, giving an empty result
  or `bash: -c: option requires an argument`). Pass the script as a single
  argument.
- **CLI spellings drift from the website.** `machine0 images save` is the
  installed spelling of the documented `images new`; a brand-new image name
  self-promotes from `CREATING` to `READY`/`ACTIVE`, while re-saving onto an
  existing name creates a *draft* version.
- **Snapshots are region-bound** (`eu` here); creating a VM in another region
  triggers a server-side transfer.

## Server-side image builds (optional, untested here)

If you publish this repo publicly you can skip the VM+snapshot step:

```bash
machine0 images save m0-coding \
  --git-repo https://github.com/<you>/m0-coding \
  --nix-profile coding \
  --size large
```

Public GitHub.com repos only (no submodules/LFS — the flake is fetched as a
tarball), the profile must keep the `nix` user and SSH (it does: it imports
`machine0.nixosModules.loaded`), and the builder's disk size becomes the
image's minimum VM size.
