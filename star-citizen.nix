# Star Citizen module, parameterised on the nix-citizen flake so it works
# both from the subflake (which binds its own input) and from the parent
# config (which passes inputs.nix-citizen). Import as:
#   (import ./star-citizen.nix nix-citizen-flake)
nix-citizen:
{ pkgs, config, ... }:
{
  imports = [ nix-citizen.nixosModules.default ];

  programs.rsi-launcher = {
    enable = true;

    # The game installs inside this wine prefix at
    # drive_c/Program Files/Roberts Space Industries/StarCitizen —
    # point it somewhere with plenty of space (a symlink works).
    location = "$HOME/Games/star-citizen";

    # wine-astral's OpenXR integration fails to create a Vulkan instance here
    # (loader can't find the Monado runtime manifest inside the FHS sandbox),
    # so run via umu + Proton-GE instead.
    umu.enable = true;

    # Xwayland pointer-warp patch — stops the mouse snapping to screen centre
    # in game menus (compositors spawn Xwayland from PATH, so the overlay's
    # patched build is the one that runs).
    patchXwayland = true;

    # SC saturates the CPU and small pulse buffers underrun — pw-top showed
    # xruns on the sink during play. Give the game a deeper buffer; latency
    # doesn't matter for game audio.
    #
    # radv_zero_vram: SC reads uninitialised VRAM, which shows up as
    # speckling/noise artifacts on RADV (LUG AMD troubleshooting page).
    # Harmless no-op on NVIDIA.
    #
    # PROTON_ENABLE_WAYLAND would be the "proper" cursor fix but the RSI
    # launcher renders as a tiny garbled window under the wine Wayland driver —
    # don't re-enable without a way to scope it to the game only.
    #
    # Host-specific additions merge in from the consuming config —
    # preCommands is types.lines. In particular, on machines with more than
    # one GPU (e.g. a dGPU + iGPU) pin the right adapter or the game may read
    # the wrong card's VRAM:
    #   programs.rsi-launcher.preCommands = ''
    #     export DXVK_FILTER_DEVICE_NAME="AMD Radeon RX 7900 XTX"
    #   '';
    preCommands = ''
      export PULSE_LATENCY_MSEC=120
      export radv_zero_vram=true
      export MANGOHUD=1

      # Software cursor: the only reliable fix for SC's mouse warping to
      # screen centre under Xwayland (the pointer-warp patch, zero-scaling
      # and a primary output all reduce but don't eliminate it). Trade-off:
      # the cursor is drawn in-engine, so it also shows up in render-to-
      # texture UI panels (e.g. inventory) — extra cursors, but usable.
      usercfg="${config.programs.rsi-launcher.location}/drive_c/Program Files/Roberts Space Industries/StarCitizen/LIVE/USER.cfg"
      if [ -d "$(dirname "$usercfg")" ] && ! grep -qs forceSoftwareCursor "$usercfg"; then
        echo 'pl_pit.forceSoftwareCursor = 1' >> "$usercfg"
      fi
    '';

    # Take wine-astral from nix-citizen's own locked package set rather than
    # the overlay's rebuild against our nixpkgs, so it comes from their cachix
    # instead of compiling Wine locally.
    wine = nix-citizen.packages.${pkgs.stdenv.hostPlatform.system}.wine-astral;
  };

  # SC alone hits ~19GB resident and can OOM a 32GB machine once zram and
  # swap are exhausted. zram compresses ~3:1, so 100% of RAM as zram costs
  # ~10GB physical when completely full — worth it to keep SC alive.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  nix.settings = {
    substituters = [
      "https://nix-citizen.cachix.org"
      "https://nix-gaming.cachix.org"
    ];
    trusted-public-keys = [
      "nix-citizen.cachix.org-1:lPMkWc2X8XD4/7YPEEwXKKBg+SVbYTVrAaLA2wQTKCo="
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
    ];
  };
}
