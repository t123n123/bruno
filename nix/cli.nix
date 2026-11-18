# Builds the Bruno CLI (`bru`) from this checkout. Adapted from nixpkgs' pkgs/by-name/br/bruno-cli/package.nix.
{
  lib,
  src,
  version,
  npmDeps,
  buildNpmPackage,
  nodejs_24,
}:

buildNpmPackage {
  pname = "bruno-cli";
  inherit version src npmDeps;

  nodejs = nodejs_24;
  npmWorkspace = "packages/bruno-cli";
  npmFlags = [ "--legacy-peer-deps" ];

  postPatch = ''
    cp ${npmDeps}/package-lock.json package-lock.json
  '';

  postConfigure = ''
    patchShebangs packages/*/node_modules
  '';

  env.ELECTRON_SKIP_BINARY_DOWNLOAD = 1;

  # Skip install scripts, as in the app build (canvas is optional and only used by pdfjs-dist).
  npmRebuildFlags = [ "--ignore-scripts" ];
  npmPackFlags = [ "--ignore-scripts" ];

  buildPhase = ''
    runHook preBuild

    # The workspace packages the CLI depends on, in scripts/setup.js order.
    npm run build:graphql-docs
    npm run build:bruno-query
    npm run build:bruno-common
    npm run build:bruno-converters
    npm run build:bruno-requests
    # See package.nix: use this package's own tsc 5.x, not the root typescript 4.9.5.
    (cd packages/bruno-schema-types && ./node_modules/.bin/tsc -p tsconfig.json)
    npm run build:bruno-filestore
    npm run build:bruno-io
    npm run sandbox:bundle-libraries --workspace=packages/bruno-js

    runHook postBuild
  '';

  # The workspace symlinks in node_modules point into packages/, so ship those too, minus the GUI.
  postInstall = ''
    cp -r packages $out/lib/node_modules/usebruno

    pushd $out/lib/node_modules/usebruno
    rm -r packages/bruno-{app,electron,tests,toml,docs}
    rm -f node_modules/bruno
    rm -f node_modules/@usebruno/{app,tests,toml}

    # Heavy GUI-only dependencies
    rm -rf node_modules/{@tabler,pdfjs-dist,*redux*,prettier,@types*,*react*,*graphiql*,@swagger-api,electron*,app-builder*}
    rm -rf node_modules/.bin

    for pattern in '*.map' '*.map.js' '*.ts'; do
      find . -type f -name "$pattern" -exec rm {} +
    done
    popd
  '';

  postFixup = ''
    wrapProgram $out/bin/bru \
      --prefix NODE_PATH : $out/lib/node_modules/usebruno/packages/bruno-cli/node_modules \
      --prefix NODE_PATH : $out/lib/node_modules
  '';

  meta = {
    description = "CLI of the open-source IDE for exploring and testing APIs (built from local checkout)";
    homepage = "https://www.usebruno.com";
    license = lib.licenses.mit;
    mainProgram = "bru";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
