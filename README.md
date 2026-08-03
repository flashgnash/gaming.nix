# Gaming modules

Self-contained flake of gaming NixOS modules:

- **`star-citizen`** — RSI launcher via [nix-citizen](https://github.com/LovingMelody/nix-citizen)
  (umu + Proton-GE), with the accumulated fixes: Xwayland pointer-warp patch
  (mouse snapping to screen centre in menus), `radv_zero_vram` (AMD speckling
  artifacts; harmless on NVIDIA), a deeper audio buffer for the game, zram at
  100% of RAM (SC alone can hit ~19GB resident), and the nix-citizen/nix-gaming
  binary caches.
- **`gaming-optimizations`** — game-agnostic system tuning: ntsync kernel
  module (Proton-GE 10+ uses it automatically), SteamOS's `vm.max_map_count`,
  and gamemode with renice.
- **`steam`** — Steam (+ remote play/dedicated server firewall), gamescope
  (built with `-fno-fast-math`), mangohud, steamtinkerlaunch, wine/winetricks,
  and a `runGame` wrapper that launches games in gamescope at the largest
  monitor's native resolution (Hyprland; 1080p60 fallback elsewhere).
  Imports `gaming-optimizations`.
- **`vr`** — Monado as the default OpenXR runtime.
- **`sunshine`** — Sunshine game-streaming host (autostart, firewall open,
  avahi service publishing for discovery).
- **`rpcs3`** — PS3 emulator.
- **`default`** — `steam` + `star-citizen`.

## Usage

```nix
{
  inputs.gaming.url = "github:flashgnash/nixos-configuration?dir=flakes/gaming";

  outputs = { nixpkgs, gaming, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        gaming.nixosModules.default
        # ... your other modules
      ];
    };
  };
}
```

## Notes

- The game prefix lives at `$HOME/Games/star-citizen` (override
  `programs.rsi-launcher.location`; a symlink to a big drive works).
- Multi-GPU machines (dGPU + iGPU): pin the right adapter or the game may
  read the wrong card's VRAM:

  ```nix
  programs.rsi-launcher.preCommands = ''
    export DXVK_FILTER_DEVICE_NAME="NVIDIA GeForce RTX 4080";
  '';
  ```

  (Check the exact name with `vulkaninfo --summary`.)
- Wayland compositors with display scaling ≠ 1 or multiple monitors may need
  compositor-side tweaks for correct resolution/cursor behaviour under
  Xwayland (on Hyprland: `xwayland:force_zero_scaling = true` and setting an
  X11 primary output via `xrandr --output <name> --primary`). Full DEs
  (GNOME/KDE) handle this themselves.
- In-game, prefer **Borderless** window mode over Fullscreen — wine's
  exclusive-fullscreen emulation re-introduces mouse-warp issues.
