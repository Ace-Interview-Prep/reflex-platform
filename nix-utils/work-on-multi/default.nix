# nix-utils/work-on-multi/default.nix — Combined multi-package dev shell
#
# This module creates a single nix-shell environment that contains the
# union of all dependencies for a set of local Haskell packages.  It is
# used by `project/default.nix` to implement `nix-shell -A shells.ghc`
# and `nix-shell -A shells.ghcjs`.
#
# How it works:
#   1. For each package name in `packageNames`, extract its dependency
#      attributes (libraryHaskellDepends, buildTools, testDepends, etc.)
#      using `getHaskellConfig`.
#   2. Filter out any dependency that IS one of the target packages (since
#      those will be built incrementally by cabal inside the shell).
#   3. Merge (concatenate) all dependency lists across all packages into
#      a single combined dependency set.
#   4. Add dev tools (cabal-install, ghcid, hasktags, etc.) from
#      `generalDevTools'` and any user `shellToolOverrides`.
#   5. Build a synthetic mkDerivation whose .env gives the shell.
#
# The `combinableAttrs` function lists which cabal dependency fields to
# merge.  Notably, test deps are only included when `doCheck` is true for
# the package, and benchmark deps only when `doBenchmark` is true.  This
# prevents test-only deps (like webdriver, aeson) from pulling in
# conflicting versions.
#
{ reflex-platform ? import ../.. { hideDeprecated = false; } }:

let
  inherit (reflex-platform)
    nixpkgs
    ghc
    overrideCabal
    generalDevTools'
    ;
  inherit (nixpkgs) lib;
in

{ envFunc, packageNames, tools ? _: [], shellToolOverrides ? _: _: {} }:

let
  inherit (builtins) listToAttrs filter attrValues all concatLists;
    combinableAttrs = p: [
      "buildDepends"
      "buildTools"
      "executableFrameworkDepends"
      "executableHaskellDepends"
      "executablePkgconfigDepends"
      "executableSystemDepends"
      "executableToolDepends"
      "extraLibraries"
      "libraryFrameworkDepends"
      "libraryHaskellDepends"
      "libraryPkgconfigDepends"
      "librarySystemDepends"
      "libraryToolDepends"
      "pkgconfigDepends"
      "setupHaskellDepends"
    ] ++ lib.optionals (p.doCheck or true) [
      "testDepends"
      "testFrameworkDepends"
      "testHaskellDepends"
      "testPkgconfigDepends"
      "testSystemDepends"
      "testToolDepends"
    ] ++ lib.optionals (p.doBenchmark or false) [
      "benchmarkDepends"
      "benchmarkFrameworkDepends"
      "benchmarkHaskellDepends"
      "benchmarkPkgconfigDepends"
      "benchmarkSystemDepends"
      "benchmarkToolDepends"
    ];

    concatCombinableAttrs = haskellConfigs: lib.filterAttrs
      (n: v: v != [])
      (lib.zipAttrsWith (_: concatLists) (map
        (haskellConfig: lib.listToAttrs (map
          (name: {
            inherit name;
            value = haskellConfig.${name} or [];
          })
          (combinableAttrs haskellConfig)))
        haskellConfigs
        ));

    getHaskellConfig = p: (overrideCabal p (args: {
      passthru = (args.passthru or {}) // {
        out = args;
      };
    })).out;
    notInTargetPackageSet = p: all (pname: (p.pname or "") != pname) packageNames;
    baseTools = generalDevTools' {};
    env = envFunc reflex-platform;
    overriddenTools = baseTools // shellToolOverrides env baseTools;
    depAttrs = lib.mapAttrs (_: v: filter notInTargetPackageSet v) (concatCombinableAttrs (concatLists [
      (map getHaskellConfig (lib.attrVals packageNames env))
      [{
        buildTools = [
          (nixpkgs.buildEnv {
            name = "build-tools-wrapper";
            paths = attrValues overriddenTools ++ tools env;
            pathsToLink = [ "/bin" ];
            extraOutputsToInstall = [ "bin" ];
          })
          overriddenTools.Cabal
        ];
      }]
    ]));

in (env.mkDerivation (depAttrs // {
  pname = "work-on-multi--combined-pkg";
  version = "0";
  license = null;
})).env
