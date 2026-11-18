# Builds Bruno from this checkout. Adapted from nixpkgs' pkgs/by-name/br/bruno/package.nix.
{
  lib,
  stdenv,
  src,
  version,
  baseVersion,
  npmDeps,
  jq,
  moreutils,
  buildNpmPackage,
  nodejs_24,
  electron_43,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
}:

let
  electron = electron_43;
in
buildNpmPackage {
  pname = "bruno";
  inherit version src npmDeps;

  nodejs = nodejs_24;
  npmFlags = [ "--legacy-peer-deps" ];

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optional (!stdenv.hostPlatform.isDarwin) copyDesktopItems;

  desktopItems = [
    (makeDesktopItem {
      name = "bruno";
      desktopName = "Bruno";
      exec = "bruno %U";
      icon = "bruno";
      comment = "Opensource API Client for Exploring and Testing APIs";
      categories = [ "Development" ];
      startupWMClass = "Bruno";
    })
  ];

  postPatch = ''
    cp ${npmDeps}/package-lock.json package-lock.json

    # Version shown in the sidebar and About page
    for f in packages/bruno-electron/package.json packages/bruno-app/package.json; do
      ${lib.getExe jq} '.version |= "${baseVersion}"' $f | ${moreutils}/bin/sponge $f
    done

    # The build sandbox has no network: don't download remote images at build time.
    substituteInPlace packages/bruno-app/plugins/remote-images/loader.cjs \
      --replace-fail 'const urls = findRemoteImageUrls(source, domains);' 'const urls = [];'
  '';

  postConfigure = ''
    patchShebangs packages/*/node_modules
  '';

  env.ELECTRON_SKIP_BINARY_DOWNLOAD = 1;

  # Skip install scripts. The only native module that matters is `canvas`, an optional dependency of
  # pdfjs-dist used only under plain Node (the renderer uses the browser canvas); canvas 2.x
  # doesn't compile against Node 24's V8 anyway.
  npmRebuildFlags = [ "--ignore-scripts" ];

  buildPhase = ''
    runHook preBuild

    # Same order as scripts/setup.js
    npm run build:graphql-docs
    npm run build:bruno-query
    npm run build:bruno-common
    npm run build:bruno-converters
    npm run build:bruno-requests
    # Inside the Nix build, npm resolves `tsc` here to the root typescript 4.9.5 (which lacks
    # moduleResolution "bundler") instead of this package's own 5.x, so call it explicitly.
    (cd packages/bruno-schema-types && ./node_modules/.bin/tsc -p tsconfig.json)
    npm run build:bruno-filestore
    npm run build:bruno-io
    npm run build:bruno-sqlite
    npm run sandbox:bundle-libraries --workspace=packages/bruno-js

    npm run build --workspace=packages/bruno-app

    # Copies the web build into bruno-electron; with no argument it skips the dist step.
    bash scripts/build-electron.sh

    pushd packages/bruno-electron
    ${
      if stdenv.hostPlatform.isDarwin then
        ''
          cp -r ${electron.dist}/Electron.app ./
          find ./Electron.app -name 'Info.plist' -print0 | xargs -0 chmod +rw

          substituteInPlace electron-builder-config.js \
            --replace-fail "identity: 'Anoop MD (W7LPPWA48L)'" 'identity: null' \
            --replace-fail "afterSign: 'notarize.js'," ""

          npm exec electron-builder -- \
            --dir \
            --config electron-builder-config.js \
            -c.electronDist=./ \
            -c.electronVersion=${electron.version} \
            -c.npmRebuild=false
        ''
      else
        ''
          npm exec electron-builder -- \
            --dir \
            --config electron-builder-config.js \
            -c.electronDist=${electron.dist} \
            -c.electronVersion=${electron.version} \
            -c.npmRebuild=false
        ''
    }
    popd

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    ${
      if stdenv.hostPlatform.isDarwin then
        ''
          mkdir -p $out/Applications $out/bin
          cp -R packages/bruno-electron/out/*/Bruno.app $out/Applications/
          makeWrapper $out/Applications/Bruno.app/Contents/MacOS/Bruno $out/bin/bruno
        ''
      else
        ''
          mkdir -p $out/opt/bruno $out/bin
          cp -r packages/bruno-electron/out/linux*-unpacked/{locales,resources{,.pak}} $out/opt/bruno

          makeWrapper ${lib.getExe electron} $out/bin/bruno \
            --add-flags $out/opt/bruno/resources/app.asar \
            --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
            --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]} \
            --set-default ELECTRON_IS_DEV 0 \
            --inherit-argv0

          for s in 16 32 48 64 128 256 512 1024; do
            size=''${s}x$s
            install -Dm644 packages/bruno-electron/resources/icons/png/$size.png $out/share/icons/hicolor/$size/apps/bruno.png
          done
        ''
    }

    runHook postInstall
  '';

  meta = {
    description = "Open-source IDE for exploring and testing APIs (built from local checkout)";
    homepage = "https://www.usebruno.com";
    license = lib.licenses.mit;
    mainProgram = "bruno";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
