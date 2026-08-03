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

        # Steam + gamescope + wine/proton tooling and the runGame gamescope
        # wrapper. Imports gaming-optimizations itself.
        steam = import ./steam.nix;

        # Monado as the default OpenXR runtime. Separate from steam so
        # non-VR machines don't get a VR stack.
        vr = import ./vr.nix;

        # Sunshine game-streaming host (+ avahi publishing for discovery).
        sunshine = import ./sunshine.nix;

        # PS3 emulator.
        rpcs3 = import ./rpcs3.nix;

        # Fully wired Star Citizen module — the nix-citizen dependency is
        # bound to this flake's own input, so consumers just add the module;
        # no specialArgs plumbing required.
        star-citizen = import ./star-citizen.nix nix-citizen;

        default = {
          imports = [
            self.nixosModules.steam
            self.nixosModules.star-citizen
          ];
        };
      };
    };
}
