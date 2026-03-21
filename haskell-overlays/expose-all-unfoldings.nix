# haskell-overlays/expose-all-unfoldings.nix — Cross-module inlining
#
# Adds -fexpose-all-unfoldings to every Haskell package.  This GHC flag
# serializes all function unfoldings into .hi files, enabling aggressive
# cross-module inlining.  Critical for performance in the reflex ecosystem
# where core primitives (jsaddle, reflex, reflex-dom-core) rely heavily
# on inlining for zero-cost abstractions.
#
# Enabled by default via the `enableExposeAllUnfoldings` parameter in
# the top-level default.nix.

{ }:

self: super: {
  mkDerivation = drv: super.mkDerivation (drv // {
    configureFlags = (drv.configureFlags or []) ++ [
      "--${if self.ghc.isGhcjs or false then "ghcjs" else "ghc"}-options=-fexpose-all-unfoldings"
    ];
  });
}
