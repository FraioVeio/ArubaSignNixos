{
  description = "ArubaSign (Aruba digital signature client) packaged for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [
            "arubasign"
            "arubasign-unwrapped"
          ];
      };
    in
    {
      packages.${system} = rec {
        arubasign-unwrapped = pkgs.callPackage ./package.nix { };
        arubasign = pkgs.callPackage ./fhs.nix { inherit arubasign-unwrapped; };
        default = self.packages.${system}.arubasign;
      };

      apps.${system}.default = {
        type = "app";
        program = nixpkgs.lib.getExe self.packages.${system}.arubasign;
      };

      overlays.default = final: _prev: {
        arubasign-unwrapped = final.callPackage ./package.nix { };
        arubasign = final.callPackage ./fhs.nix { };
      };

      nixosModules.default =
        { config, lib, ... }:
        let
          cfg = config.programs.arubasign;
        in
        {
          options.programs.arubasign = {
            enable = lib.mkEnableOption "ArubaSign digital signature client";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${system}.arubasign;
              description = "The ArubaSign package to use.";
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];
            # Smartcard readers (pcscd + CCID driver).
            services.pcscd.enable = true;
          };
        };

      formatter.${system} = pkgs.nixfmt;
    };
}
