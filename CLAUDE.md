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
  `m0coding.*` with a default, so project flakes can turn it off.
- Two places define `system.autoUpgrade` in this flake: upstream
  (`core/nix.nix`, `mkDefault` on `flake`) and `modules/coding.nix`
  (`mkForce`). Do not remove the `mkForce` — without it the nightly rebuild
  reverts the VM to the plain `loaded` profile.
- Never put credentials or tokens in this repo; they arrive per VM through
  `machine0 new --profile` (the `machine0-profile-inject` service).

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
- `machine0 images new <vm> <image>` snapshots a VM into a reusable, versioned
  image. `machine0 images new <image> --git-repo <public-repo> --nix-profile
  coding` builds server-side instead (public GitHub only).
- VM sizes: small/medium/large/xl/xxl. Never test on `small` — nix eval OOMs.
- `machine0 suspend <vm>` = snapshot + delete instance, pay only storage.
- SSH user on NixOS images is `nix`; run login-shell commands as
  `machine0 ssh <vm> bash -lc '...'`.
