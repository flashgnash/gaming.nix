{ pkgs, inputs, ... }:

let
  # rpcs3 moves fast and emulation regressions are fixed upstream weekly;
  # take it from the newer nixpkgs-unstable input rather than the main pin.
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    # rpcs3 bundles unfree firmware-adjacent bits (license is gpl2+gpl3+unfree)
    config.allowUnfree = true;
  };

  # RPCS3's overlay renderer (overlay_fonts.cpp) does NOT use fontconfig: it
  # scans a fixed list of dirs for a file literally named "Arial.ttf" (or
  # DejaVu at hardcoded /usr/share/fonts paths), then falls back to firmware
  # fonts in dev_flash. None of those exist on NixOS, so PPU/LLVM compilation
  # progress overlays abort with errno=2. /run/current-system/sw/share/fonts
  # IS in its search list, so ship a metric-compatible Arial there.
  rpcs3-overlay-fonts = pkgs.runCommand "rpcs3-overlay-fonts" { } ''
    mkdir -p $out/share/fonts
    cp ${pkgs.liberation_ttf}/share/fonts/truetype/LiberationSans-Regular.ttf \
      $out/share/fonts/Arial.ttf
  '';
  # Mesa's device-selection layer (loaded into every Vulkan process) crashes
  # this emulator on some effects — a null-pointer write inside the Vulkan
  # loader the moment LBP2 draws prize bubbles. RPCS3 chooses its GPU in its
  # own settings, so the layer has nothing to add here; off for this binary
  # only, every other Vulkan app keeps it.
  rpcs3 = pkgs.symlinkJoin {
    name = "rpcs3-wrapped";
    paths = [ pkgs-unstable.rpcs3 ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm $out/bin/rpcs3
      makeWrapper ${pkgs-unstable.rpcs3}/bin/rpcs3 $out/bin/rpcs3 --set NODEVICE_SELECT 1
    '';
  };
in
{
  environment.systemPackages = [
    rpcs3
    rpcs3-overlay-fonts
  ];
  environment.pathsToLink = [ "/share/fonts" ];
}
