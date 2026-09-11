# Example: a project profile layered on the coding image.
#
# Copy this directory to projects/<name>/ and edit. Two ways to use it:
#
#   # A. rebuild an existing VM onto this profile (local sync, no publish)
#   machine0 provision <vm> "./projects/example#api"
#
#   # B. from the project's own repo flake, consuming this one as an input:
#   #   inputs.m0coding.url = "github:<you>/m0-coding";
#   #   nixosConfigurations.api = m0coding.lib.mkSystem [
#   #     m0coding.nixosModules.coding
#   #     ./projects/example/project.nix
#   #   ];
#
# Keep it minimal: anything the project's devShell can provide (compilers,
# language servers, linters) belongs in the repo, not the image. This file is
# for things a devShell cannot do — system services, ports, kernel/security
# settings, image contents.
{
  pkgs,
  lib,
  ...
}:
{
  # ── Trim what this project does not need ─────────────────────────────────
  # Every toggle you turn off shrinks the image and the build time.
  m0coding.playwright.enable = false;
  m0coding.agents.opencode.enable = false;

  # ── Project runtime ──────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    postgresql # pin: pkgs.postgresql_17
    redis
    httpie
  ];

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql;
    ensureDatabases = [ "api" ];
    ensureUsers = [
      {
        name = "api";
        ensureDBOwnership = true;
      }
    ];
    # Local-only: the module default is already listen_addresses =
    # "localhost", and the machine0 firewall does not open 5432.
  };

  services.redis.servers.api = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
  };

  # ── Reachability ─────────────────────────────────────────────────────────
  # The image already serves HTTPS at <vm>.mac0.io on 80/443 (nginx).
  # Add the app port only if you really want it world-reachable.
  networking.firewall.allowedTCPPorts = [ 3000 ];

  # ── Banner ───────────────────────────────────────────────────────────────
  # mkOverride 10 beats the coding profile's mkForce (50), which beats
  # upstream loaded's normal priority (100).
  machine0.motd.text = lib.mkOverride 10 ''
    [ m0 ] api project
      $ cd ~/api && direnv allow
      $ just dev          # postgres + redis are up on localhost
  '';
}
