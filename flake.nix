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

                    nativeBuildInputs = [ python.pkgs.setuptools ];
                    nativeCheckInputs = [ python.pkgs.pytest ];

                    checkPhase = ''
                        runHook preCheck
                        PYTHONPATH=$PWD pytest tests
                        runHook postCheck
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
