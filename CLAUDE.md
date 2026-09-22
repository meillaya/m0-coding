# m0-coding — agent notes

A private flake that layers a `coding` profile on top of
[`github:fdmtl/machine0-nixos`](https://github.com/fdmtl/machine0-nixos) and
freezes it into the reusable machine0 image `m0-coding`.

## Layout

```
flake.nix            # inputs machine0-nixos; defines the `coding` module chain,
                     # nixosConfigurations.coding, packages.coding (qcow2.gz),
                     # nixosModules.coding + lib.mkSystem for project flakes
manifest.json        # profile -> machine0 image slug, read by bin/ scripts
modules/coding.nix   # the only layer this repo adds
pkgs/omo/            # OmO Native (omo.dev) built from a pinned npm lockfile
files/omo/           # OmO user config seeded into ~/.omo (omo.json + settings)
projects/example/    # template for a per-project profile (services, ports)
bin/m0-build         # nix build .#coding -> ./result-image (qcow2.gz)
bin/m0-dev           # create/refresh a VM, provision .#coding, verify agents
bin/m0-snap          # stop VM + snapshot it as the reusable image
bin/m0-new           # create a project VM from the reusable image
```

## Rules for changes

- Read `modules/coding.nix` before editing; keep changes minimal.
- The baseline is machine0's `loaded` profile — do not re-add anything it
  already ships (claude-code, codex, docker, python3/uv, rust, go, bun, gh,
  tmux, zsh/starship). Check `github:fdmtl/machine0-nixos`'s
  `modules/development/packages.nix` first.
- New package or service → `modules/coding.nix`. New toggle → an option under
  `m0coding.*` with a default, so project flakes can turn it off. The two
  exceptions, both for good reasons, are `pkgs/omo/` (the OmO derivation needs
  its npm lockfile next to it) and `files/omo/` (the OmO config payload).
- `omo` is npm-only. It lives in `pkgs/omo/` as a `buildNpmPackage` over a
  pinned `omo-ai@beta` release; version, `package.json`, `package-lock.json`
  and `npmDepsHash` must move together (three commands in that file's header).
  Do not swap it for a bun-global install at activation: the image has to boot
  with the agent already present.
- `dsh` comes from the `deepseek-harness` input's own
  `legacyPackages.<system>.presets.tui`, NOT from its `nixosModules.default`:
  that module applies the flake's overlay to *our* pkgs, and the overlay needs
  `pnpm_11`, which machine0's 25.11 nixpkgs does not carry. Same reason
  `flake.nix` passes the input through `_module.args.deepseekHarness` instead
  of a plain import.
- Project environments are **devenv.sh + direnv** (both in the image, plus the
  devenv.cachix.org substituter added to `nix.settings.substituters`). Prefer
  pointing a project at a `devenv.nix`/devShell over adding language toolchains
  to this image.
- Two places define `system.autoUpgrade` in this flake: upstream
  (`core/nix.nix`, `mkDefault` on `flake`) and `modules/coding.nix`
  (`mkForce`). Do not remove the `mkForce` — without it the nightly rebuild
  reverts the VM to the plain `loaded` profile.
- `bin/m0-dev` seeds a VM's store with `.#omo`/`.#dsh` (flake outputs) before
  provisioning. Keep that step: dsh's kernel bundle is built by node/esbuild
  and OOM-kills a `large` (2 vCPU / 4 GB) VM. Do not "fix" it by moving the
  build to an `xl` builder — a builder's disk size becomes the image's minimum,
  so an xl builder would push every project VM from `large` ($0.052/hr,
  80 GB) to `xl` ($0.104/hr, 160 GB).
- Never put credentials or tokens in this repo; they arrive per VM through
  `machine0 new --profile` (the `machine0-profile-inject` service). That
  includes `~/.omo/agent/auth.json`: `files/omo/` carries OmO *config* only,
  and `m0coding.agents.omo.authFile` exists so a credential file can be
  pointed at on the VM without ever entering the tree.

## Verify after every change

```bash
nix flake check                                    # eval-only guard, fast
nix eval --no-eval-cache '.#nixosConfigurations.coding.config.system.build.toplevel.drvPath'
bin/m0-dev                                         # provision + agent check on a real VM
```

`nix flake check` forces the full system eval, which is what catches bad
package/option names, module conflicts, and priority mistakes. Do not claim a
change works without at least that eval passing.

## machine0 facts worth remembering

- `machine0 provision <vm> .#coding` syncs the *local* flake and runs
  `nixos-rebuild switch` on the VM — no GitHub publish needed while
  iterating. Budget ~10 minutes per build.
- `machine0 images save <vm> <image>` snapshots a VM into a reusable, versioned
  image (the website docs spell it `images new` — same command).
  `machine0 images save <image> --git-repo <public-repo> --nix-profile
  coding` builds server-side instead (public GitHub only). Re-running `save`
  onto an existing image creates a *draft* version you promote with
  `machine0 images versions promote <image> <version>`.
- VM sizes: small/medium/large/xl/xxl. Never test on `small` — nix eval OOMs.
- `machine0 suspend <vm>` = snapshot + delete instance, pay only storage.
- SSH user on NixOS images is `nix`; run login-shell commands as
  `machine0 ssh <vm> bash -lc '...'`.
