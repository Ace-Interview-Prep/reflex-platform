# haskell-overlays/wasm/default.nix — WebAssembly target adjustments
#
# Applied when building for WASM (isWasm).  Disables everything that
# isn't needed or doesn't work in WASM: shared libs, haddock, tests,
# profiling, dead code elimination, and all jsaddle backends.
#
self: super: {
  jsaddle-warp = null;
  jsaddle-webkitgtk = null;
  jsaddle-webkit2gtk = null;
  jsaddle-wkwebview = null;
  mkDerivation = args: super.mkDerivation (args // {
    dontStrip = true;
    enableSharedExecutables = false;
    enableSharedLibraries = false;
    enableDeadCodeElimination = false;
    doHaddock = false;
    doCheck = false;
    enableLibraryProfiling = false;
  });
}

