# haskell-overlays/profiling.nix — Library profiling toggle
#
# Overrides mkDerivation to set enableLibraryProfiling for all packages.
# Profiling is always disabled on iOS targets (where cost centres add
# unacceptable overhead and binary size).  On all other targets, it
# respects the global `enableLibraryProfiling` flag from default.nix.
#
{ haskellLib
, enableLibraryProfiling
}:

with haskellLib;

let
  # Enable profiling only when requested AND not targeting iOS.
  preventMobileProfiling = self: (!self.ghc.stdenv.targetPlatform.isiOS) && enableLibraryProfiling;
in

self: super: {

  mkDerivation = expr: super.mkDerivation (expr // {
    enableLibraryProfiling = preventMobileProfiling self;
  });
}
