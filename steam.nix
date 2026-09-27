{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.runGame;
in
{

  imports = [ ./gaming-optimizations.nix ];

  options.programs.runGame.scaleFactor = lib.mkOption {
    type = lib.types.float;
    default = 1.0;
    example = 0.75;
    description = ''
      Per-host render scale for the `runGame` gamescope wrapper.

      1.0 (the default) renders at the native monitor resolution — no upscaling.
      A value below 1.0 renders the game at that fraction of the monitor
      resolution and FSR-upscales back to native, trading sharpness for frame
      rate (a big win on weak iGPUs). Values above 1.0 supersample.

      Set it in a host's default.nix, e.g. `programs.runGame.scaleFactor = 0.75;`.
    '';
  };

  config = {

    environment.variables = {
      LD_PRELOAD = "";
      DXVK_HUD = "compiler";
      PULSE_LATENCY_MSEC = 60;
    };

    # Proton passes allowlisted flight sticks (VKB, Virpil, …) straight through
    # as raw HID, but routes the Logitech Extreme 3D Pro through its SDL →
    # virtual-HID layer ("SDL Logitech Extreme 3D pro"), which mangles its axes
    # in SDL-based games (latched/mirrored input — seen in Star Trucker).
    # Launching a game with PROTON_ENABLE_HIDRAW=0x046d/0xc215 forces the raw
    # path instead; this rule makes the hidraw node accessible to the session.
    services.udev.extraRules = ''
      KERNEL=="hidraw*", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c215", MODE="0660", TAG+="uaccess"
    '';

    hardware.steam-hardware.enable = true;

    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      # gamescopeSession.enable = true;

      # Remote Play (incl. streaming flat games to the Steam Frame) can't
      # capture the Wayland desktop over X11 and falls back to "Desktop Black
      # Frame" — a healthy-looking stream of literal black frames. -pipewire
      # switches Steam's capture to the PipeWire screencast portal.
      package = pkgs.steam.override { extraArgs = "-pipewire"; };
    };

    programs.gamescope = {
      enable = true;

      package = pkgs.gamescope.overrideAttrs (_: {
        NIX_CFLAGS_COMPILE = [ "-fno-fast-math" ];
      });
      # capSysNice = true;  # breaks Steam's bwrap sandbox

    };

    environment.systemPackages = with pkgs; [
      steamtinkerlaunch
      mangohud

      (pkgs.writeShellApplication {
        name = "runGame";

        runtimeInputs = with pkgs; [
          jq
          hyprland
          gawk
        ];

        text = ''

          #!/usr/bin/env bash
          # Resolve the largest monitor's geometry from Hyprland. Steam launches
          # this outside a normal Hyprland context, so `hyprctl monitors` can come
          # back empty (no reachable IPC socket) — the old code only checked that
          # the hyprctl *binary* existed, so it handed gamescope an empty -W and
          # crashed ("invalid value for --output-width, \"\""). Gate on the session
          # signature, round the float refresh to an int (gamescope wants an int),
          # then validate every field and fall back to 1080p60 if anything is off.
          W="" H="" R=""
          if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
            read -r W H R <<< "$(hyprctl monitors -j 2>/dev/null | jq -r '
              map({w: .width, h: .height, r: (.refreshRate | round)})
              | max_by(.w * .h)
              | "\(.w) \(.h) \(.r)"
            ' 2>/dev/null)"
          fi
          for v in "$W" "$H" "$R"; do
            case "$v" in
              "" | *[!0-9]*) W=1920; H=1080; R=60; break ;;
            esac
          done

          # Per-host render scale (programs.runGame.scaleFactor). 1.0 = native; a
          # smaller value renders lower and FSR-upscales to the monitor, which is
          # the lever that makes demanding titles playable on a weak iGPU.
          SCALE=${toString cfg.scaleFactor}
          scaleArgs=()
          if awk -v s="$SCALE" 'BEGIN { exit !(s != 1) }'; then
            RW=$(awk -v w="$W" -v s="$SCALE" 'BEGIN { printf "%d", w * s }')
            RH=$(awk -v h="$H" -v s="$SCALE" 'BEGIN { printf "%d", h * s }')
            scaleArgs+=(-w "$RW" -h "$RH")
            # FSR only when upscaling (rendering below native); supersampling
            # downscales fine without it.
            if awk -v s="$SCALE" 'BEGIN { exit !(s < 1) }'; then
              scaleArgs+=(-F fsr)
            fi
            echo "Render scale $SCALE -> ''${RW}x''${RH} upscaled to ''${W}x''${H}"
          fi

          echo "Using display: Width: $W, Height: $H, Refresh: $R"

          PROTON_USE_NTSYNC=1 \
          DXVK_HUD=compiler \
          DXVK_ASYNC=1 \
          PROTON_ENABLE_WAYLAND=1 \
          LD_PRELOAD="" \
          RADV_PERFTEST=gpl \
          gamemoderun \
          gamescope --force-grab-cursor --rt --mangoapp --adaptive-sync \
            -W "$W" -H "$H" -r "$R" "''${scaleArgs[@]}" -- "$@"

        '';
      })

      # support both 32- and 64-bit applications
      wineWow64Packages.stable

      # support 32-bit only
      wine

      # support 64-bit only
      (wine.override { wineBuild = "wine64"; })

      # wine-staging (version with experimental features)
      wineWow64Packages.staging

      # winetricks (all versions)
      winetricks

    ];

  };

}
