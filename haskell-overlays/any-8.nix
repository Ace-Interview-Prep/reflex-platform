# haskell-overlays/any-8.nix — GHC 8.x (pre-8.6) overrides
#
# Applied to all GHC 8.x versions below 8.6.0.  Currently empty;
# exists as a placeholder for future compatibility shims.
#
{ lib, haskellLib, getGhcVersion }:
with haskellLib;
self: super: lib.optionalAttrs (lib.versionOlder (getGhcVersion super.ghc) "8.6.0") {
}
