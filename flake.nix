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
                python = pkgs.python3;
            in
            {
                packages.default = python.pkgs.buildPythonApplication {
                    pname = "chargectl";
                    version = "0.1.0";
                    src = ./.;
                    format = "pyproject";

                    nativeBuildInputs = [
                        python.pkgs.setuptools
                        pkgs.gobject-introspection
                        pkgs.wrapGAppsHook4
                    ];

                    # Both toolkits, because both front ends ship: chargectl-gui
                    # on GTK4 and libadwaita, chargectl-gui3 on GTK3 and
                    # libhandy. They exist side by side to be compared on
                    # hardware where the choice costs something.
                    buildInputs = [
                        pkgs.gtk4
                        pkgs.libadwaita
                        pkgs.gtk3
                        pkgs.libhandy
                    ];

                    propagatedBuildInputs = [ python.pkgs.pygobject3 ];
                    nativeCheckInputs = [ python.pkgs.pytest ];

                    dontWrapGApps = true;
                    makeWrapperArgs = [ "\${gappsWrapperArgs[@]}" ];

                    checkPhase = ''
                        runHook preCheck
                        PYTHONPATH=$PWD pytest tests
                        runHook postCheck
                    '';

                    postInstall = ''
                        install -Dm444 data/io.github.beatlink.Chargectl.desktop \
                            -t $out/share/applications
                        install -Dm444 data/io.github.beatlink.Chargectl.svg \
                            $out/share/icons/hicolor/scalable/apps/io.github.beatlink.Chargectl.svg
                    '';
                };

                apps.default = {
                    type = "app";
                    program = "${self.packages.${system}.default}/bin/chargectl";
                };

                devShells.default = pkgs.mkShell {
                    buildInputs = [
                        (python.withPackages (ps: [
                            ps.pytest
                            ps.flake8
                        ]))
                    ];
                };
            }
        )
        // {
            nixosModules.default = import ./module.nix self;
        };
}
