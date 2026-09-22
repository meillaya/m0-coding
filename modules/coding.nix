# The `coding` layer — what makes this a *reusable coding image*.
#
# Applied on top of machine0's `loaded` profile (see flake.nix), so it
# already inherits: gcc/make/cmake, python3 + uv, rust, go, bun, rootless
# Docker, gh, tmux, the agents `claude-code` and `codex`, and the Home
# Manager zsh/starship shell.
#
# This layer adds:
#   * the rest of the agent set (Hermes, OpenCode, OmO Native) — toggleable
#   * the DeepSeek Harness CLI (`dsh`) — toggleable
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
  deepseekHarness ? null,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  cfg = config.m0coding;

  hermesPkg = inputs.hermes-agent.packages.${system}.default;

  # ── OmO Native (`omo`) ───────────────────────────────────────────────────
  # OmO (omo.dev) is npm-only (there is no nixpkgs package), so it is built
  # from the pinned release in pkgs/omo — which is a real `npm ci` tree, not
  # a bundle. omo-ai requires node >= 24 while the image's own node is 22, so
  # the package is built against, and wrapped with, nixpkgs' node 24.
  omoPkg = import ../pkgs/omo {
    inherit pkgs;
    nodejs = pkgs.nodejs_24;
  };

  # The user's OmO config, seeded per home by the activation script below.
  omoDefaults = ../files/omo;

  # ── DeepSeek Harness (`dsh`) ─────────────────────────────────────────────
  # Deliberately taken from the dsh flake's OWN package set instead of
  # importing its NixOS module: that module applies its overlay to *our*
  # pkgs, and the overlay needs nixpkgs-unstable attrs (`pnpm_11`) that
  # machine0's 25.11 nixpkgs does not carry. `presets.tui` is the documented
  # TUI composition (headless bundle + a profile materialized under
  # $DSH_HOME/profiles/nix-tui, used when dsh is started without --profile).
  dshPkg =
    if deepseekHarness != null then
      deepseekHarness.legacyPackages.${system}.presets.tui
    else
      null;

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

    agents.omo.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install OmO Native (the `omo` coding agent from omo.dev) and seed the
        per-user omo.json / settings.json defaults.
      '';
    };

    agents.omo.authFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/omo-auth.json";
      description = ''
        Optional path to an OmO credential store, installed as
        ~/.omo/agent/auth.json (mode 0600) the first time a home is
        activated. Left null on purpose: credentials never live in this repo.
        Provider keys may instead arrive through the environment
        (OPENROUTER_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY,
        DEEPSEEK_API_KEY), e.g. from the machine0 profile inject, or be
        entered on the VM with `omo`'s own login.
      '';
    };

    agents.dsh.enable = lib.mkOption {
      type = lib.types.bool;
      default = deepseekHarness != null;
      description = ''
        Install the DeepSeek Harness CLI (`dsh`). Needs the `deepseek-harness`
        flake input (defaults to on when the root flake passes it in; a flake
        that imports this module directly must pass it itself).
      '';
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
      ++ lib.optional cfg.agents.omo.enable omoPkg
      ++ lib.optional (cfg.agents.dsh.enable && dshPkg != null) dshPkg
      ++ lib.optionals cfg.playwright.enable [ playwrightBrowsers ];

    assertions = [
      {
        assertion = !cfg.agents.dsh.enable || dshPkg != null;
        message = ''
          m0coding.agents.dsh.enable is on but the `deepseek-harness` flake
          input was not passed to this module. Import the module through this
          repo's root flake, or pass it yourself:
            { _module.args.deepseekHarness = inputs.deepseek-harness; }
        '';
      }
    ];

    # devenv.sh pulls prebuilt toolchains from its own cache; without it
    # every `devenv shell` on a fresh project compiles from source. `dsh` is
    # a large prebuilt closure (pnpm workspace + plugin bundles) that its own
    # cache is what keeps a VM rebuild from compiling. These are *additional*
    # definitions of the list options, so they concatenate with upstream
    # core/nix.nix's list rather than replacing it.
    nix.settings = {
      substituters =
        [ "https://devenv.cachix.org" ]
        ++ lib.optional cfg.agents.dsh.enable "https://deepseek-harness-nix.cachix.org";
      trusted-public-keys = [
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ]
      ++ lib.optional cfg.agents.dsh.enable "deepseek-harness-nix.cachix.org-1:5NrkwLN9veNMhiINtU5ZeV4isXFhFsOwn6Ms7J1M+TA=";
    };

    # direnv in the `nix` user's zsh, so dropping `use flake` in a repo's
    # .envrc gives agents the project's devShell automatically.
    #
    # The function form is on purpose: inside it `lib` is Home Manager's
    # extended lib (the one carrying `lib.hm` and `lib.hm.dag`).
    home-manager.users.nix =
      { lib, ... }:
      {
        programs.direnv = {
          enable = true;
          nix-direnv.enable = true;
          silent = true;
        };

        # Seed OmO's per-user config on the first activation, then leave it
        # alone: omo rewrites omo.json (migration stamps) and settings.json
        # (tip/changelog state) while it runs, so re-asserting these files on
        # every rebuild would fight the agent instead of the drift it would
        # catch. auth.json is never part of this repo — see
        # m0coding.agents.omo.authFile.
        #
        # NOTE: the `//` below must stay *inside* this `home` attrset. At the
        # module level a shallow merge would replace the whole `home` key and
        # silently drop the activation entry (it did, until the VM check
        # caught it: `omo: NO config`).
        home =
          {
            activation.m0SeedOmoConfig = lib.mkIf cfg.agents.omo.enable (
              lib.hm.dag.entryAfter [ "writeBoundary" ] (
                ''
                  seed_omo_file() {
                    if [ -e "$2" ]; then
                      echo "m0: $2 already exists, leaving it alone"
                    else
                      ${pkgs.coreutils}/bin/install -D -m "$3" "$1" "$2"
                      echo "m0: seeded $2"
                    fi
                  }
                  seed_omo_file ${omoDefaults}/omo.json "$HOME/.omo/omo.json" 0644
                  seed_omo_file ${omoDefaults}/agent/settings.json "$HOME/.omo/agent/settings.json" 0644
                ''
                + lib.optionalString (cfg.agents.omo.authFile != null) ''
                  seed_omo_file ${cfg.agents.omo.authFile} "$HOME/.omo/agent/auth.json" 0600
                ''
              )
            );
          }
          // lib.optionalAttrs cfg.playwright.enable {
            sessionVariables = {
              PLAYWRIGHT_BROWSERS_PATH = "${playwrightBrowsers}";
              PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
            };
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
          "$ omo             # OmO Native (omo.json seeded)"
          "$ dsh             # DeepSeek Harness (TUI)"
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
