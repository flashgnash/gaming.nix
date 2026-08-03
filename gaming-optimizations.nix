{ ... }:
{
  # System-wide gaming optimizations, independent of any particular game or
  # launcher. Imported by steam.nix so every host with gaming gets them.

  # NTsync device for Wine/Proton — GE-Proton 10+ and wine-astral use it
  # automatically when /dev/ntsync exists (falls back to fsync otherwise).
  boot.kernelModules = [ "ntsync" ];

  # Windows games under Proton can exceed the default mmap limit (65530),
  # which shows up as crashes in heavy titles. Same value SteamOS ships.
  # (nix-citizen's setLimits sets its own lower value at a weaker priority;
  # this one wins without conflict.)
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;

  programs.gamemode = {
    enable = true;

    settings = {
      general = {
        renice = 10;
      };
    };
    enableRenice = true;
  };
}
