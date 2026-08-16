{ pkgs, ... }:
{

  imports = [ ./gaming-optimizations.nix ];

  environment.variables = {
    LD_PRELOAD = "";
    DXVK_HUD = "compiler";
    PULSE_LATENCY_MSEC = 60;
  };

  hardware.steam-hardware.enable = true;

  # Proton passes allowlisted flight sticks (VKB, Virpil, …) straight through
  # as raw HID, but routes the Logitech Extreme 3D Pro through its SDL →
  # virtual-HID layer ("SDL Logitech Extreme 3D pro"), which mangles its axes
  # in SDL-based games (latched/mirrored input — seen in Star Trucker).
  # Launching a game with PROTON_ENABLE_HIDRAW=0x046d/0xc215 forces the raw
  # path instead; this rule makes the hidraw node accessible to the session.
  services.udev.extraRules = ''
    KERNEL=="hidraw*", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c215", MODE="0660", TAG+="uaccess"
  '';

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    # gamescopeSession.enable = true;
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
      ];

      text = ''

        #!/usr/bin/env bash
        # Get width, height, refresh of largest monitor (Hyprland); fall
        # back to 1080p60 on other compositors.
        if command -v hyprctl >/dev/null 2>&1; then
          read -r W H R <<< "$(hyprctl monitors -j | jq -r '
            map({w: .width, h: .height, r: .refreshRate})
            | max_by(.w * .h)
            | "\(.w) \(.h) \(.r)"
          ')"
        else
          W=1920 H=1080 R=60
        fi


        echo "Using display: Width: $W, Height: $H, Refresh: $R"

        PROTON_USE_NTSYNC=1 \
        DXVK_HUD=compiler \
        DXVK_ASYNC=1 \
        PROTON_ENABLE_WAYLAND=1 \
        LD_PRELOAD="" \
        RADV_PERFTEST=gpl \
        gamemoderun \
        gamescope --force-grab-cursor --rt --mangoapp --adaptive-sync -W "$W" -H "$H" -r "$R" -- "$@"


                
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

}
