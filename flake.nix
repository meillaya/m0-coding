{
  description = "Reusable machine0 NixOS image for coding projects — agents + polyglot toolchain";

  inputs = {
    # The machine0 system images. Our layers are applied on top of its
    # `loaded` profile (dev stack + claude-code + codex + rootless Docker).
    machine0.url = "github:fdmtl/machine0-nixos";

    # DeepSeek Harness (`dsh`): CLI, plugin bundles and presets. modules/
    # coding.nix takes the composed CLI from this flake's own package set;
    # see the comment there for why its NixOS module is not imported.
    deepseek-harness.url = "github:moraxyc/deepseek-harness.nix";
  };

  outputs =
    { self, machine0, deepseek-harness, ... }:
    let
      system = "x86_64-linux";

      # Banner builder. Upstream exports it as a plain function; pass it in
      # as a module arg so modules/coding.nix can style the MOTD.
      mkMotd = machine0.lib.mkMotd;
      motdArg = { _module.args.mkMotd = mkMotd; };

      # Our own extra module arg (mkSystem owns specialArgs, upstream's, so a
      # new input has to travel through `_module.args`). Modules see the
      # parsed flake; `null` means the input was not passed.
      dshArg = { _module.args.deepseekHarness = deepseek-harness; };

      # A "profile" is the module chain that produces one NixOS system.
      # Keep this map in sync with manifest.json (single source of truth for
      # profile -> machine0 image slug, consumed by bin/ scripts).
      #
      # Project profiles go here too, so `machine0 provision <vm> .#<profile>`
      # works from this one directory (provision syncs the flake root; a
      # project flake sitting in a subdirectory with a relative `path:../..`
      # input would resolve outside the synced tree).
      profiles = {
        # The reusable image: loaded profile + the full agent set + the
        # per-project conveniences (direnv/just/compose/db clients).
        coding = [
          machine0.nixosModules.loaded
          motdArg
          dshArg
          ./modules/coding.nix
        ];

        # Template project profile — see projects/example/. Copy the
        # directory, edit the module, add an entry here.
        example = [
          machine0.nixosModules.loaded
          motdArg
          dshArg
          ./modules/coding.nix
          ./projects/example/project.nix
        ];
      };

      mkSystem = machine0.lib.mkSystem;
      mkImage = machine0.lib.mkImage;

      # The two agents this repo packages itself, exposed as flake packages so
      # they can be built/inspected on their own. `bin/m0-dev` uses them to
      # seed a VM's store before provisioning: dsh's kernel bundle is built by
      # node/esbuild and needs more RAM than a `large` (4 GB) VM has — the
      # first attempt was OOM-killed — so the script builds/substitutes them
      # here and pushes the closures instead.
      agentPackages =
        let
          upstreamPkgs = machine0.inputs.nixpkgs.legacyPackages.${system};
        in
        {
          omo = import ./pkgs/omo {
            pkgs = upstreamPkgs;
            nodejs = upstreamPkgs.nodejs_24;
          };
          dsh = deepseek-harness.legacyPackages.${system}.presets.tui;
          zix = import ./pkgs/zix { pkgs = upstreamPkgs; };
        };
    in
    {
      # `machine0 provision <vm> .#coding`  /  --nix-profile coding
      nixosConfigurations = builtins.mapAttrs (_: mkSystem) profiles // {
        default = self.nixosConfigurations.coding;
      };

      # The two agents this repo packages itself are exposed alongside the
      # image outputs as .#omo / .#dsh, plus .#zix for the runtime package CLI.
      # `nix build .#coding` -> gzipped qcow2 image.
      packages.${system} =
        builtins.mapAttrs (_: mkImage) profiles
        // agentPackages
        // {
          default = self.packages.${system}.coding;
        };

      # `nix run .#zix -- pkg add NAME` (the image package list) and
      # `nix run .#zix -- get NAME@VERSION` (a one-off runtime install).
      apps.${system}.zix = {
        type = "app";
        program = "${self.packages.${system}.zix}/bin/zix";
      };

      # For a *project* flake that wants this base plus its own module:
      #   m0coding.lib.mkSystem [ m0coding.nixosModules.coding ./project.nix ]
      # These read machine0's specialArgs, so they must be used through
      # lib.mkSystem (not a plain nixpkgs.lib.nixosSystem).
      nixosModules =
        builtins.mapAttrs (name: modules: {
          imports = modules;
        }) profiles
        // {
          default = self.nixosModules.coding;
        };

      lib = {
        inherit mkSystem mkImage mkMotd;
      };

      # Eval-only guard: `nix flake check` forces the full system eval
      # (catching bad option names, missing packages, module conflicts)
      # without building a system or an image.
      checks.${system}.coding-eval =
        let
          pkgs = machine0.inputs.nixpkgs.legacyPackages.${system};
          drv = (mkSystem profiles.coding).config.system.build.toplevel;
        in
        pkgs.runCommand "coding-eval-guard" { } ''
          echo "${builtins.unsafeDiscardStringContext drv.drvPath}" > "$out"
        '';
    };
}
