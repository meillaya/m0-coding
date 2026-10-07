# zix - packages, pins and sandboxes, vendored from the nixos config repo
# (tools/zix there; this is a mirror so the image builds without the private
# repo). Inside the image it is the runtime acquirer agents use:
#
#   zix get NAME[@VERSION]     install into the user profile now, no repo needed
#   zix get --list             what the profile currently holds
#   zix pkg add NAME           add to modules/packages.nix (the image list)
#
# `get` resolves through nixpkgs-multiverse's store-path index, so an exact
# old version installs without evaluating nixpkgs at all.
{ pkgs, lib ? pkgs.lib }:

pkgs.stdenvNoCC.mkDerivation rec {
  pname = "zix";
  version = "0.2.0";

  src = ../../tools/zix;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/zix $out/bin
    cp -r . $out/lib/zix
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/zix \
      --add-flags "$out/lib/zix/cli.py" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.nix pkgs.git pkgs.coreutils ]}
    runHook postInstall
  '';

  meta = {
    description = "zix - package, pin, sandbox and VM manager for Nix configurations";
    license = lib.licenses.mit;
    mainProgram = "zix";
  };
}
