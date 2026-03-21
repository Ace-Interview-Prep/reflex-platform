# haskell-overlays/ios.nix — iOS target adjustments
#
# Applied when building for iOS (isiOS).  Key changes:
#   • Nullify server-side packages unavailable on iOS (websockets, wai,
#     warp, wai-app-static, ghcjs-prim, cabal-doctest)
#   • Disable shared libraries and executables (iOS requires static linking)
#   • Disable haddock generation (not needed for device builds)
#   • Disable optimizations for `free` and `jsaddle` to work around
#     ARM code generation bugs (ekmett/free#176)
#   • Use integer-simple flags (blaze-textual, cryptonite)
#   • Post-fixup reflex-todomvc to create .app bundle structure
#
{ haskellLib, lib }:

self: super: {
  ghcjs-prim = null;
  websockets = null;
  wai = null;
  warp = null;
  wai-app-static = null;

  cabal-doctest = null;
  syb = haskellLib.overrideCabal super.syb (drv: { jailbreak = true; });

  # HACK(matthewbauer):
  # Temporary fix for https://github.com/ekmett/free/issues/176
  # Optimizations are broken on some ARM-based systems for some reason.
  free = haskellLib.appendConfigureFlag super.free "--enable-optimization=0";
  jsaddle = haskellLib.appendConfigureFlag super.jsaddle "--enable-optimization=0";

  blaze-textual = haskellLib.enableCabalFlag super.blaze-textual "integer-simple";
  cryptonite = haskellLib.disableCabalFlag super.cryptonite "integer-gmp";

  reflex-todomvc = haskellLib.overrideCabal super.reflex-todomvc (drv: {
    postFixup = ''
      mkdir $out/reflex-todomvc.app
      cp reflex-todomvc.app/* $out/reflex-todomvc.app/
      cp $out/bin/reflex-todomvc $out/reflex-todomvc.app/
    '';
  });
  mkDerivation = drv: super.mkDerivation (drv // {
    doHaddock = false;
    enableSharedLibraries = false;
    enableSharedExecutables = false;
  });
}
