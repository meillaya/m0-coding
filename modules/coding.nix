# The `coding` layer — what makes this a *reusable coding image*.
#
# Applied on top of machine0's `loaded` profile (see flake.nix), so it
# already inherits: gcc/make/cmake, python3 + uv, rust, go, bun, rootless
# Docker, gh, tmux, the agents `claude-code` and `codex`, and the Home
# Manager zsh/starship shell.
#
# This layer adds:
#   * the rest of the agent set (Hermes, OpenCode) — toggleable
#   * the polyglot project toolchain (node/pnpm/deno, direnv+nix-direnv,
#     docker compose, git-lfs/delta, just/watchexec/hyperfine)
#   * database clients (psql, redis-cli, sqlite) so a project VM can reach
#     a DB without a rebuild
#   * a one-shot `machine0 skills install` hint in the MOTD + a
#     `m0-bootstrap-skills` helper for the agents
#
# Everything is layered with normal priority so a project flake can still
# override any of it (or import this module and add its own).
{
  config,
  pkgs,
  lib,
  inputs,
  mkMotd,
  nixpkgsUnstable ? null,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  cfg = config.m0coding;

  hermesPkg = inputs.hermes-agent.packages.${system}.default;

  # devenv from nixpkgs-unstable: 25.11 ships 1.11.x while the ecosystem is on
  # 2.x (devenv shell warns about the gap). Same convention this repo already
  # uses for claude-code / codex / playwright-driver via lib/overlays.nix.
  devenvPkg =
    if nixpkgsUnstable != null then
      (import nixpkgsUnstable {
        inherit system;
        config.allowUnfree = true;
      }).devenv
    else
      pkgs.devenv;

  nonNixShellPackages = with pkgs; [
    # ── Runtimes / package managers on top of loaded's python+rust+go+bun ──
    nodejs_22
    pnpm
    deno

    # ── Per-project workflow ──────────────────────────────────────────────
    direnv # `use flake` / `use devenv` in .envrc, wired into zsh below
    nix-direnv # cached devShell envs
    devenvPkg # devenv.sh: per-project dev environments (nix + devenv.nix)
    just # task runner — most repos carry a justfile
    watchexec # re-run on change
    hyperfine # benchmark before/after a change

    # ── Git quality of life ───────────────────────────────────────────────
    git-lfs
    delta
    tree

    # ── Data / API plumbing ───────────────────────────────────────────────
    sqlite
    postgresql # client (psql, pg_dump) — no server enabled
    redis # client (redis-cli)
    yq-go # YAML/JSON/TOML swiss army knife
    fd
    bat

    # ── Containers ────────────────────────────────────────────────────────
    docker-compose # `docker compose` — Docker itself comes from loaded
  ];

  # Playwright browsers for the agents' web/QA work. ~1.5 GB, so it is a
  # toggle; PLAYWRIGHT_* env vars are exported for the `nix` user.
  playwrightBrowsers = pkgs.playwright-driver.browsers;
in
{
  imports = [
    # Registers the hermes NixOS module (options/services stay off until
    # `services.hermes-agent.enable` — upstream's hermes profile does the
    # same and leaves setup to the interactive `hermes setup` wizard).
    inputs.hermes-agent.nixosModules.default
  ];

  # ── Options ──────────────────────────────────────────────────────────────
  options.m0coding = {
    agents.hermes.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the Hermes Agent CLI (NousResearch/hermes-agent).";
    };

    agents.opencode.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the OpenCode CLI.";
    };

    playwright.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Ship NixOS-patched Playwright browsers for the agents.";
    };

    # Point the nightly nixos-rebuild at *your* repo once this flake is
    # pushed. Left null the auto-upgrade is disabled: upstream's default
    # (`github:fdmtl/machine0-nixos`) would rebuild the plain `loaded`
    # profile nightly and silently drop every customization in this flake.
    autoUpgradeFlake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "github:you/m0-coding#coding";
      description = ''
        Flake ref the nightly auto-upgrade rebuilds from, e.g.
        "github:<owner>/<repo>#coding". Null disables auto-upgrade.
      '';
    };
  };

  # ── Config ───────────────────────────────────────────────────────────────
  config = {
    environment.systemPackages = nonNixShellPackages
      ++ lib.optionals cfg.agents.hermes.enable [ hermesPkg ]
      ++ lib.optionals cfg.agents.opencode.enable [ pkgs.opencode ]
      ++ lib.optionals cfg.playwright.enable [ playwrightBrowsers ];

    # devenv.sh pulls prebuilt toolchains from its own cache; without it
    # every `devenv shell` on a fresh project compiles from source. These are
    # *additional* definitions of the list options, so they concatenate with
    # upstream core/nix.nix's list rather than replacing it.
    nix.settings = {
      substituters = [ "https://devenv.cachix.org" ];
      trusted-public-keys = [
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ];
    };

    # direnv in the `nix` user's zsh, so dropping `use flake` in a repo's
    # .envrc gives agents the project's devShell automatically.
    home-manager.users.nix = {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        silent = true;
      };
    }
    // lib.optionalAttrs cfg.playwright.enable {
      home.sessionVariables = {
        PLAYWRIGHT_BROWSERS_PATH = "${playwrightBrowsers}";
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      };
    };

    # Upstream pins auto-upgrade to its own repo (core/nix.nix sets flake
    # with mkDefault and enable = true). Left alone, the nightly rebuild
    # would rebuild the plain `loaded` profile and silently drop this
    # layer — so we always take control of both fields: point it at your
    # repo (autoUpgradeFlake) or turn it off.
    system.autoUpgrade =
      if cfg.autoUpgradeFlake != null then
        {
          enable = lib.mkForce true;
          flake = lib.mkForce cfg.autoUpgradeFlake;
        }
      else
        {
          enable = lib.mkForce false;
        };

    # Priority ladder for the banner: upstream `loaded` sets it at normal
    # priority (100), we take it with mkForce (50) — the same level the
    # openclaw/hermes profiles use — and a project profile overrides us with
    # `lib.mkOverride 10` (see projects/example/project.nix).
    machine0.motd.text = lib.mkForce (
      mkMotd {
        title = "[ m0 ] NixOS 25.11 · coding";
        body = [
          "# Agents"
          "$ claude          # Claude Code"
          "$ codex           # OpenAI Codex"
          "$ hermes setup    # Hermes Agent (first run)"
          "$ opencode        # OpenCode"
          ""
          "# Per-project environments (devenv.sh + direnv):"
          "$ devenv init     # writes devenv.nix / devenv.yaml"
          "$ direnv allow    # after: echo 'use devenv' > .envrc"
          ""
          "# Give the agents machine0's own skills (once):"
          "$ machine0 skills install"
          ""
          "# Also installed: just, docker compose, pnpm, deno, psql/redis-cli."
          "-> https://devenv.sh/getting-started"
        ];
      }
    );
  };
}
