{
  description = "Gaming NixOS modules: Star Citizen (via nix-citizen/umu) and general gaming optimizations";

  inputs = {
    nix-citizen.url = "github:LovingMelody/nix-citizen";
  };

  outputs =
    { self, nix-citizen, ... }:
    {
      nixosModules = {
        gaming-optimizations = import ./gaming-optimizations.nix;

        # Fully wired Star Citizen module — the nix-citizen dependency is
        # bound to this flake's own input, so consumers just add the module;
        # no specialArgs plumbing required.
        star-citizen = import ./star-citizen.nix nix-citizen;

        default = {
          imports = [
            self.nixosModules.gaming-optimizations
            self.nixosModules.star-citizen
          ];
        };
      };
    };
}
