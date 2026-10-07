# Packages for the m0-coding image, managed by zix.
#
#   nix run .#zix -- pkg add NAME     (writes into the marker block below)
#   nix run .#zix -- pkg rm NAME
#
# The marker block is rewritten in place; leave the two marker lines (exactly
# two leading spaces as they are) alone. Runtime installs (`zix get NAME`)
# do NOT come here - they land in the invoking user's nix profile.
{ pkgs }:
with pkgs;
[
  # BEGIN zix: entries managed by `nix run .#zix -- pkg ...` - do not edit by hand
  # END zix
]
