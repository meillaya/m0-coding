# m0-coding — a reusable machine0 NixOS image for coding projects with agents

One NixOS image, frozen once, cloned for every project. It is machine0's
[`loaded` profile](https://github.com/fdmtl/machine0-nixos) (dev stack,
rootless Docker, Claude Code, Codex, the Home Manager zsh) plus the rest of
the agent set and the per-project conveniences a coding VM needs.

This repo is a *private consumer flake*: it takes `machine0-nixos` as an
input and layers one module on top. Nothing here is published, and no
machine0 image has to be rebuilt per project.

## What is in the image

Inherited from machine0's `loaded` profile:

- agents `claude-code` and `codex` (tracked from nixpkgs-unstable)
- gcc/make/cmake, python3 + uv + pipx, rust/cargo, go, bun, node
- rootless Docker, npm, nginx, firewall 80/443
- gh, git, tmux, ripgrep, jq, htop, btop, lsof, chafa, screen
- zsh + starship + zoxide + eza + fzf (Home Manager), `machine0` CLI (authenticated by `--profile`)
- `base` profile's hardened SSH, fail2ban, the machine0 metadata/profile-inject services

Added by `modules/coding.nix`:

- agents `hermes` (NousResearch) and `opencode` — toggleable via `m0coding.agents.*`
- nodejs_22 + pnpm + deno, direnv + nix-direnv (wired into zsh), just, watchexec, hyperfine
- docker compose, git-lfs, git delta, tree, fd, bat, yq-go
- database/CLI clients: psql, redis-cli, sqlite
- NixOS-patched Playwright browsers + `PLAYWRIGHT_*` env for the agents — toggleable via `m0coding.playwright.enable`

Every addition is made at normal priority, so a project flake can override
any of it.

## Setup

```bash
# 1. machine0 CLI + auth (once)
curl -LsSf https://machine0.io/install.sh | sh
machine0 login

# 2. cheap eval guard — catches bad option/package names without building
nix flake check

# 3. create a NixOS VM and provision THIS flake onto it (local sync, no push)
bin/m0-dev                 # vm: m0-dev, size: large, profile: coding
```

`bin/m0-dev` creates `m0-dev` from `nixos-25-11-loaded` if it does not
exist, runs `machine0 provision m0-dev .#coding`, then verifies every agent
and tool is on `PATH`. Size medium or larger — nix builds are hungry.

Iterate on `modules/coding.nix`, re-run `bin/m0-dev`, and the same VM is
rebuilt in place.

## Freeze it into the reusable image

```bash
bin/m0-snap m0-dev             # stop the VM, snapshot it as image "m0-coding"
machine0 images ls
```

From then on a project VM is one command and needs no build:

```bash
bin/m0-new api                 # machine0 new api --image m0-coding --size medium
machine0 ssh api
```

Make it the default so bare `machine0 new <name>` picks it up:

```bash
machine0 config set DEFAULT_VM_IMAGE=m0-coding
```

Snapshots are versioned — re-run `bin/m0-snap` after a change and the image
gets a new version you can promote or roll back. `bin/m0-snap` records the
flake git revision as image metadata.

## The three ways to use it

| Goal | Command |
|---|---|
| Iterate on the image itself | `bin/m0-dev` → edit → `bin/m0-dev` again |
| Freeze + clone for projects | `bin/m0-snap <vm>` → `bin/m0-new <project>` |
| Per-project extra config | see `projects/example/` below |

### Per-project config

Two levels, pick the lightest that works:

1. **devShell in the project repo** (no VM rebuild) — commit a
   `flake.nix`/`shell.nix` + `.envrc` with `use flake`, then `direnv allow`
   on the VM. direnv + nix-direnv are installed for exactly this.
2. **A project profile in this repo** — copy `projects/example/project.nix`
   and build a system from it:

   ```bash
   machine0 provision api "./projects/example#api"
   ```

   or from a separate project flake that consumes this one:

   ```nix
   inputs.m0coding.url = "github:<you>/m0-coding";
   nixosConfigurations.api = m0coding.lib.mkSystem [
     m0coding.nixosModules.coding
     ./project.nix
   ];
   ```

## Server-side image builds (optional)

If you publish this repo publicly you can skip the VM+snapshot step and have
machine0 build the image from git:

```bash
machine0 images new m0-coding \
  --git-repo https://github.com/<you>/m0-coding \
  --nix-profile coding \
  --size large
```

Notes: public GitHub.com repos only (no submodules/LFS — the flake is
fetched as a tarball), the profile must keep the `nix` user and SSH (it
does, it imports `machine0.nixosModules.loaded`), and the builder's disk size
becomes the image's minimum VM size.

## Ops notes

- **Local image builds need machine0's caches.** `bin/m0-build` passes
  `machine0.cachix.org` + `cache.garnix.io` (where hermes-agent's Python
  closure lives). Without them nix compiles ~450 derivations from source;
  with them it is ~44 trivial ones plus ~2.6 GiB of downloads.
- **auto-upgrade is disabled by default.** Upstream sets
  `system.autoUpgrade.flake = "github:fdmtl/machine0-nixos"`, which would
  rebuild the plain `loaded` profile nightly and silently drop this layer.
  Once this repo is published, re-enable it against your own repo:

  ```nix
  m0coding.autoUpgradeFlake = "github:<you>/m0-coding#coding";
  ```

- **Rebuild from the repo, not on the VM.** `/etc/nixos` on a machine0 VM
  holds the *upstream* source; `sudo nixos-rebuild switch` there drops your
  config. Use `machine0 provision <vm> ".#coding"` (or `.path#profile`).
- **Integrations come from `--profile`, not the image.** Claude/Codex/GitHub
  credentials and MCP servers are injected per VM by the machine0 profile
  you pass to `machine0 new --profile`. `machine0-profile-inject` is already
  in the base image.
- **Cost.** A builder/dev VM bills while it runs (large ≈ $0.05/hr,
  per-minute). `machine0 suspend <vm>` stops compute billing; destroy it
  when the snapshot is made. Project VMs from `m0-coding` boot in seconds and
  can be suspended between sessions.
