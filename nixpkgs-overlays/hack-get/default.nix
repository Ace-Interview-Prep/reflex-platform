# nixpkgs-overlays/hack-get/default.nix — Thunk resolution primitives
#
# This overlay adds three attributes to nixpkgs:
#
#   filterGit :: Path -> Derivation
#     Strip .git, tags, TAGS, and dist from a source path so that nix
#     store hashes are stable across git metadata changes.
#
#   hackGet :: Path -> Derivation
#     Resolve a "thunk" directory to a nix source derivation.  A thunk
#     is a directory containing either:
#       • github.json — fetched via fetchFromGitHub
#       • git.json    — fetched via fetchgit (or builtins.fetchGit for
#                        SSH URLs with '@' in them)
#       • thunk.nix   — newer obelisk-style thunks with their own fetch logic
#       • (none of the above) — treated as an unpacked checkout, filtered
#                        through filterGit for the store path.
#     This is the mechanism that lets reflex-platform pin all its
#     Haskell dependencies as lightweight JSON pointers rather than
#     full git submodules.
#
#   thunkSet :: Path -> AttrSet
#     Apply hackGet to every subdirectory of a given path, returning
#     { <dirname> = <resolved source>; ... }.  Used to bulk-resolve
#     the dep/ directories throughout the overlay tree.
#
{ lib }:

self:

{
  filterGit = builtins.filterSource (path: type: !(builtins.any (x: x == baseNameOf path) [".git" "tags" "TAGS" "dist"]));

  # Resolve a thunk directory to a fetchable source derivation.
  # Supports three thunk formats: obelisk thunk.nix, git.json, github.json.
  # Falls back to treating the path as an unpacked checkout.
  hackGet = p:
    let
      contents = builtins.readDir p;

      contentsMatch = { required, optional }:
           (let all = required // optional; in all // contents == all)
        && builtins.intersectAttrs required contents == required;

      # Newer obelisk thunks include the feature of hackGet with a thunk.nix file in the thunk.
      isObeliskThunkWithThunkNix =
        let
          packed = jsonFileName: {
            required = { ${jsonFileName} = "regular"; "default.nix" = "regular"; "thunk.nix" = "regular"; };
            optional = { ".attr-cache" = "directory"; };
          };
        in builtins.any (n: contentsMatch (packed n)) [ "git.json" "github.json" ];

      filterArgs = x: removeAttrs x [ "branch" ];
      hasValidThunk = name: if builtins.pathExists (p + ("/" + name))
        then
          contentsMatch {
            required = { ${name} = "regular"; };
            optional = { "default.nix" = "regular"; ".attr-cache" = "directory"; };
          }
          || throw "Thunk at ${toString p} has files in addition to ${name} and optionally default.nix and .attr-cache. Remove either ${name} or those other files to continue (check for leftover .git too)."
        else false;
    in
      if isObeliskThunkWithThunkNix then import (p + /thunk.nix)
      else if hasValidThunk "git.json" then (
        let gitArgs = filterArgs (builtins.fromJSON (builtins.readFile (p + "/git.json")));
        in if builtins.elem "@" (lib.stringToCharacters gitArgs.url)
          then builtins.fetchGit (builtins.removeAttrs gitArgs ["sha256" "fetchSubmodules"])
          else self.fetchgit gitArgs
        )
      else if hasValidThunk "github.json" then
        self.fetchFromGitHub (filterArgs (builtins.fromJSON (builtins.readFile (p + "/github.json"))))
      else {
        name = baseNameOf p;
        outPath = self.filterGit p;
      };

  # Make an attribute set of source derivations for a directory containing thunks:
  thunkSet = dir: lib.mapAttrs (name: _: self.hackGet (dir + "/${name}")) (lib.filterAttrs (_: type: type == "directory" || type == "symlink") (builtins.readDir dir));
}
