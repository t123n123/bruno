# npm dependencies of the whole workspace, shared by the app and the CLI builds.
{
  src,
  npmDepsHash,
  fetchNpmDeps,
  npm-lockfile-fix,
}:

# package-lock.json lacks `resolved`/`integrity` for many entries. Fill them in inside the
# fixed-output fetch (it has network access), then reuse that lockfile for the build so
# npmConfigHook's lockfile check passes.
fetchNpmDeps {
  # Stable name, so a new commit reuses the fetched deps when the hash is unchanged.
  name = "bruno-npm-deps";
  inherit src;
  hash = npmDepsHash;
  nativeBuildInputs = [ npm-lockfile-fix ];
  postPatch = ''
    npm-lockfile-fix package-lock.json
  '';
}
