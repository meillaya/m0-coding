# OmO Native — the `omo` coding agent (npm package `omo-ai`, beta channel).
#
# There is no nixpkgs package for it, so this is the npm release, pinned.
# Two details make it more than a one-liner:
#
#   * `omo-ai` is not a self-contained bundle (unlike upstream's machine0-cli).
#     It depends on `@code-yeongyu/senpi` — the agent engine — whose own
#     dependency tree (Claude Agent SDK, esbuild platform binaries, ...) is
#     needed at RUNTIME, and whose files omo-ai's `postinstall` patches in
#     place. So this is a real npm install: `npm ci` from package-lock.json,
#     plus `npm rebuild` (which runs that postinstall).
#   * the launcher re-execs itself under bun only when it finds bun >= 1.4 on
#     PATH, otherwise it stays on node. nixpkgs 25.11 ships bun 1.3.3, so the
#     wrapper pins node 24 (`engines.node` is ">=24") and the runtime choice
#     stays deterministic: omo runs on node inside the image.
#
# Bump procedure (version, lockfile and hash move together):
#   1. npm view omo-ai@beta version
#   2. set `version` below AND in pkgs/omo/package.json
#   3. (cd pkgs/omo && npm install --package-lock-only --ignore-scripts)
#   4. prefetch-npm-deps pkgs/omo/package-lock.json  -> npmDepsHash
{ pkgs, nodejs, lib ? pkgs.lib }:

pkgs.buildNpmPackage rec {
  pname = "omo";
  version = "5.0.0-0.beta.82";

  # package.json + package-lock.json live next to this file. `src` covers the
  # whole directory; only the two manifests reach the dependency cache.
  src = ./.;

  # Recompute with `prefetch-npm-deps pkgs/omo/package-lock.json`.
  npmDepsHash = "sha256-nbG0NauZF5fkyFccu/tV3t4ATIGtJXVHsnKtUenRW7s=";

  inherit nodejs;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  # The root package has no build step — the product IS the omo-ai dependency.
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/omo $out/bin
    cp -r . $out/lib/omo/site
    makeWrapper ${nodejs}/bin/node $out/bin/omo \
      --add-flags "$out/lib/omo/site/node_modules/omo-ai/bin/omo.js" \
      --prefix PATH : "${nodejs}/bin:$out/lib/omo/site/node_modules/.bin"
    runHook postInstall
  '';

  meta = {
    description = "OmO (Oh My OpenAgent) Native — multi-model agent orchestration harness";
    homepage = "https://omo.dev";
    license = lib.licenses.mit;
    mainProgram = "omo";
  };
}
