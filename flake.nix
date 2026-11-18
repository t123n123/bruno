{
  description = "Bruno — open-source API client, built from this checkout";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Update after any package-lock.json change: set to lib.fakeHash, build, copy the "got:" hash.
      npmDepsHash = "sha256-BjSwfwlGc2SHZQ4K4w5LUSAGqsjddk+yfABzJJnqOGA=";

      # packages/*/package.json carry a placeholder version; bump this with the upstream release tag.
      baseVersion = "4.3.0";
      version = "${baseVersion}-${self.shortRev or self.dirtyShortRev or "dirty"}";
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          npmDeps = pkgs.callPackage ./nix/npm-deps.nix {
            src = self;
            inherit npmDepsHash;
          };
        in
        rec {
          bruno = pkgs.callPackage ./nix/package.nix {
            src = self;
            inherit version baseVersion npmDeps;
          };
          bruno-cli = pkgs.callPackage ./nix/cli.nix {
            src = self;
            inherit version npmDeps;
          };
          default = bruno;
        }
      );

      overlays.default = final: _prev: {
        bruno = self.packages.${final.stdenv.hostPlatform.system}.bruno;
        bruno-cli = self.packages.${final.stdenv.hostPlatform.system}.bruno-cli;
      };

      # Toolchain for `npm run dev` etc.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.nodejs_24 ];
        };
      });
    };
}
