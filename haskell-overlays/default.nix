# haskell-overlays/default.nix — Haskell package-set overlay orchestrator
#
# This module defines and composes all the haskell overlays that
# reflex-platform applies to every GHC package set.  Each overlay is
# a function (self: super: { ... }) that overrides haskell packages.
#
# The main export is `combined`, which folds all constituent overlays
# in a specific order.  The composition order is:
#
#   1. user-custom-pre    (haskellOverlaysPre from the caller)
#   2. reflexPackages      (all reflex ecosystem packages: reflex, reflex-dom, jsaddle, etc.)
#   3. profiling           (enable/disable library profiling)
#   4. untriaged           (version pins and fixes for non-reflex deps)
#   5. exposeAllUnfoldings (optional: -fexpose-all-unfoldings for inlining)
#   6. Android/iOS flags   (platform-specific: -fPIC, -fPIE, linker flags)
#   7. combined-any        (version-gated fixes for GHC 8.x)
#   8. combined-ghc        (native-GHC-only overrides)
#      OR combined-ghcjs   (GHCJS-only overrides: textJSString, fast-weak)
#   9. loadSplices         (cross-compilation: load pre-saved TH splices)
#  10. android / ios / wasm (target-specific nullifications and flags)
#  11. user-custom-post    (haskellOverlaysPost from the caller)
#
# Conditional overlays use `optionalExtension` which returns a no-op
# overlay when the condition is false, keeping the composition clean.
#
{ lib
, haskellLib
, nixpkgs
, useFastWeak
, useReflexOptimizer
, enableLibraryProfiling
, enableTraceReflexEvents
, useTextJSString
, useWebkit2Gtk
, enableExposeAllUnfoldings
, __useTemplateHaskell
, ghcSavedSplices-8_6
, ghcSavedSplices-8_10
, haskellOverlaysPre
, haskellOverlaysPost
}:

let
  inherit (nixpkgs.buildPackages) thunkSet runCommand fetchgit fetchFromGitHub fetchFromBitbucket;
  inherit (nixpkgs) hackGet;
in

rec {
  # Return the overlay when `cond` is true, otherwise a no-op overlay.
  # This avoids wrapping every conditional overlay in `if` blocks.
  optionalExtension = cond: overlay: if cond then overlay else _: _: { };

  # Check if a GHC version matches a major.minor range, e.g.
  # `versionWildcard [8 6]` matches 8.6.0..8.6.x but not 8.7.0.
  versionWildcard = versionList:
    let
      versionListInc = lib.init versionList ++ [ (lib.last versionList + 1) ];
      bottom = lib.concatStringsSep "." (map toString versionList);
      top = lib.concatStringsSep "." (map toString versionListInc);
    in
    version: lib.versionOlder version top && lib.versionAtLeast version bottom;

  # Compose a list of overlays into a single overlay via right-fold.
  foldExtensions = lib.foldr lib.composeExtensions (_: _: { });

  getGhcVersion = ghc: ghc.version;

  ##
  ## Conventional roll ups of all the constituent overlays below.
  ##

  # `super.ghc` is used so that the use of an overlay does not depend on that
  # overlay. At the cost of violating the usual rules on using `self` vs
  # `super`, this avoids a bunch of strictness issues keeping us terminating.
  combined = self: super: foldExtensions [
    user-custom-pre

    reflexPackages
    profiling
    untriaged

    (optionalExtension enableExposeAllUnfoldings exposeAllUnfoldings)

    #(NEW;Dylan Green):
    # We no longer need to set gold as "lld" is default on the
    # android toolchain now
    #(OLD;Dylan Green):
    # Force "gold" on Android due to a linker bug on bfd
    # Also force -fPIC on for Android, we need it either way

    # NOTE(Dylan Green): Please do not only enable based on CPU arch, this will cause
    # more problems then it's worth
    # arm* needs the same linker options, x86* -> arm* does not

    (optionalExtension (super.ghc.stdenv.targetPlatform.isAndroid or false) (self: super:
    {
        mkDerivation = drv: super.mkDerivation (drv // {
          buildFlags = [
            "--ld-option=-fPIE"
            "--ld-option=-pie"
            "--ghc-option=-fPIC"
            "--ghc-option=-fPIE"
          ] ++ (drv.buildFlags or [ ]);

          configureFlags = [ ] ++ (drv.configureFlags or [ ]);
        });
      }))

    # TODO(Dylan): Add this casing to the compiler patch
    (optionalExtension (super.ghc.stdenv.targetPlatform.isiOS && (super.ghc.stdenv.targetPlatform.isx86_64 || super.ghc.version == "8.6.5")) (self: super: {
      mkDerivation = drv: super.mkDerivation (drv // {
        buildFlags = (drv.buildFlags or []) ++ [
          "--ghc-option=-fwhole-archive-hs-libs"
        ];
      });
    }))

    combined-any
    (optionalExtension (!(super.ghc.isGhcjs or false)) combined-ghc)
    (optionalExtension (super.ghc.isGhcjs or false) combined-ghcjs)

    (optionalExtension (with nixpkgs.stdenv; versionWildcard [ 8 6 ] super.ghc.version && !(super.ghc.isGhcjs or false) && hostPlatform != buildPlatform) loadSplices-8_6)
    (optionalExtension (with nixpkgs.stdenv; versionWildcard [ 8 10 ] super.ghc.version && !(super.ghc.isGhcjs or false) && hostPlatform != buildPlatform) loadSplices-8_10)

    (optionalExtension (nixpkgs.stdenv.hostPlatform.useAndroidPrebuilt or false) android)
    (optionalExtension (nixpkgs.stdenv.hostPlatform.isiOS or false) ios)
    (optionalExtension (nixpkgs.stdenv.hostPlatform.isWasm or false) wasm)

    user-custom-post
  ]
    self
    super;

  combined-any = self: super: foldExtensions [
    any
    (optionalExtension (versionWildcard [ 8 ] (getGhcVersion super.ghc)) combined-any-8)
  ]
    self
    super;

  combined-any-8 = self: super: foldExtensions [
    any-8
    (optionalExtension (versionWildcard [ 8 6 ] (getGhcVersion super.ghc)) any-8_6)
    (optionalExtension (lib.versionOlder "8.11" (getGhcVersion super.ghc)) any-head)
  ]
    self
    super;

  combined-ghc = self: super: foldExtensions [
    (self: super: {
      hoogle = self.callHackage "hoogle" "5.0.18.3" {};
      hpack = self.callHackage "hpack" "0.34.5" {};
    })
    (optionalExtension (versionWildcard [ 8 6 ] super.ghc.version) ghc-8_6)
    (optionalExtension (lib.versionOlder "8.11" super.ghc.version) ghc-head)
  ]
    self
    super;

  combined-ghcjs = self: super: foldExtensions [
    (optionalExtension (versionWildcard [ 8 6 ] (getGhcVersion super.ghc)) combined-ghcjs-8_6)
    (optionalExtension (versionWildcard [ 8 10 ] (getGhcVersion super.ghc)) combined-ghcjs-8_10)
  ]
    self
    super;

  combined-ghcjs-8_6 = self: super: foldExtensions [
    ghcjs_8_6
    (optionalExtension useTextJSString textJSString)
    (optionalExtension useTextJSString textJSString-8_6)
    (optionalExtension useTextJSString ghcjs-textJSString-8_6)
    (optionalExtension useFastWeak ghcjs-fast-weak_8_6)
  ]
    self
    super;

  combined-ghcjs-8_10 = self: super: foldExtensions [
    (optionalExtension useTextJSString textJSString)
    (optionalExtension useTextJSString textJSString-8_10)
    (optionalExtension useTextJSString ghcjs-textJSString-8_10)
    (optionalExtension useFastWeak ghcjs-fast-weak_8_10)
    (self: super: rec {
      mkDerivation = drv: super.mkDerivation (drv // {
        setupHaskellDepends = (drv.setupHaskellDepends or []) ++ [
          nixpkgs.buildPackages.stdenv.cc
        ];
        # This is ugly
        preConfigure = (drv.preConfigure or "") + ''
          export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${nixpkgs.buildPackages.gmp}/lib:${nixpkgs.buildPackages.libffi}/lib
        '';
      });
    })
  ]
    self
    super;

  ##
  ## Constituent overlays — each imported from its own file.
  ## See the module-level comment for composition order.
  ##

  # All reflex ecosystem Haskell packages (reflex, reflex-dom, jsaddle,
  # gargoyle, dependent-sum family, etc.).  This is the largest overlay.
  reflexPackages = import ./reflex-packages {
    inherit
      haskellLib lib nixpkgs thunkSet fetchFromGitHub fetchFromBitbucket hackGet
      useFastWeak useReflexOptimizer enableTraceReflexEvents enableLibraryProfiling __useTemplateHaskell
      useWebkit2Gtk
      ;
  };
  # Pass -fexpose-all-unfoldings to every package for cross-module inlining.
  exposeAllUnfoldings = import ./expose-all-unfoldings.nix { };

  # Version-gated overlays applied to BOTH GHC and GHCJS.
  any = _: _: { }; # Placeholder for future universal overrides.
  any-8 = import ./any-8.nix { inherit haskellLib lib getGhcVersion; };
  any-8_6 = import ./any-8.6.nix { inherit haskellLib fetchFromGitHub; inherit (nixpkgs) pkgs; };
  any-head = import ./any-head.nix { inherit haskellLib fetchFromGitHub; };

  # Just for GHC, usually to sync with GHCJS
  ghc-8_6 = _: _: { };
  ghc-head = _: _: { };

  # Controls enableLibraryProfiling for all packages (disabled on iOS always).
  profiling = import ./profiling.nix {
    inherit haskellLib;
    inherit enableLibraryProfiling;
  };

  # Template Haskell splice save/load overlays for cross-compilation.
  # saveSplices: run on native GHC, serializes TH results to disk.
  # loadSplices: run on cross GHC, deserializes TH results from disk.
  saveSplices = ghcVersion: import ./splices-load-save/save-splices.nix {
    inherit lib haskellLib fetchFromGitHub ghcVersion;
  };

  loadSplices-8_6 = import ./splices-load-save/load-splices.nix {
    inherit lib haskellLib fetchFromGitHub;
    isExternalPlugin = false;
    splicedHaskellPackages = ghcSavedSplices-8_6;
  };

  loadSplices-8_10 = import ./splices-load-save/load-splices.nix {
    inherit lib haskellLib fetchFromGitHub;
    isExternalPlugin = true;
    splicedHaskellPackages = ghcSavedSplices-8_10;
  };

  # GHCJS-only overlays — package patches for the JavaScript backend.
  ghcjs_8_6 = import ./ghcjs-8.6 {
    inherit
      lib haskellLib nixpkgs fetchgit fetchFromGitHub
      useReflexOptimizer
      useTextJSString
      enableLibraryProfiling
      ;
  };

  ghcjs-textJSString-8_6 = import ./ghcjs-text-jsstring-8.6 {
    inherit lib fetchgit;
  };

  ghcjs-textJSString-8_10 = import ./ghcjs-text-jsstring-8.10 {
    inherit lib fetchgit;
  };

  textJSString = import ./text-jsstring {
    inherit lib haskellLib fetchFromGitHub versionWildcard;
    inherit (nixpkgs) fetchpatch thunkSet;
  };

  textJSString-8_6 = import ./text-jsstring-8.6 {
    inherit lib haskellLib fetchFromGitHub versionWildcard;
    inherit (nixpkgs) fetchpatch thunkSet;
  };

  textJSString-8_10 = import ./text-jsstring-8.10 {
    inherit lib haskellLib fetchFromGitHub versionWildcard;
    inherit (nixpkgs) fetchpatch thunkSet;
  };

  ghcjs-fast-weak_8_6 = import ./ghcjs-8.6-fast-weak {
    inherit lib;
  };

  ghcjs-fast-weak_8_10 = import ./ghcjs-8.10-fast-weak {
    inherit lib;
  };

  # Target-specific overlays — nullify unsupported packages and
  # adjust build flags for mobile/WASM targets.
  android = import ./android {
    inherit haskellLib;
    inherit nixpkgs;
    inherit thunkSet;
  };
  ios = import ./ios.nix {
    inherit haskellLib;
    inherit (nixpkgs) lib;
  };

  # Version pins and build fixes for non-reflex Haskell dependencies.
  # "Untriaged" because these haven't been categorized into specific overlays.
  untriaged = import ./untriaged.nix {
    inherit haskellLib;
    inherit fetchFromGitHub;
    inherit nixpkgs;
  };

  wasm = import ./wasm;

  # User-provided overlays, applied at the very start and very end of
  # the composition chain so they can both provide base overrides and
  # final fixups.
  user-custom-pre = foldExtensions haskellOverlaysPre;
  user-custom-post = foldExtensions haskellOverlaysPost;
}
