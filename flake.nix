{
    description = "chargectl - charge control for the PinePhone and its keyboard case";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
        flake-utils.url = "github:numtide/flake-utils";
    };

    outputs =
        {
            self,
            nixpkgs,
            flake-utils,
        }:
        flake-utils.lib.eachDefaultSystem (
            system:
            let
                pkgs = nixpkgs.legacyPackages.${system};
            in
            {
                packages.default = pkgs.stdenv.mkDerivation {
                    pname = "chargectl";
                    version = "0.1.0";
                    src = ./.;

                    nativeBuildInputs = [
                        pkgs.meson
                        pkgs.ninja
                        pkgs.vala
                        pkgs.pkg-config
                        pkgs.wrapGAppsHook3
                    ];

                    # GTK3 and libhandy, which is what phosh itself draws with.
                    # GTK4 renders through GSK, and on hardware without GLES 3.0
                    # that means rasterising a scene graph in software; GTK3
                    # draws with cairo directly and has no scene graph at all.
                    buildInputs = [
                        pkgs.glib
                        pkgs.json-glib
                        pkgs.gtk3
                        pkgs.libhandy
                    ];

                    doCheck = true;
                };

                apps.default = {
                    type = "app";
                    program = "${self.packages.${system}.default}/bin/chargectl";
                };

                devShells.default = pkgs.mkShell {
                    nativeBuildInputs = [
                        pkgs.meson
                        pkgs.ninja
                        pkgs.vala
                        pkgs.pkg-config
                    ];

                    buildInputs = [
                        pkgs.glib
                        pkgs.json-glib
                        pkgs.gtk3
                        pkgs.libhandy
                    ];
                };
            }
        )
        // {
            nixosModules.default = import ./module.nix self;
        };
}
