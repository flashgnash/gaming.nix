{ pkgs, ... }:

let
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
in
{
  environment.systemPackages = [
    pkgs.rpcs3
    rpcs3-overlay-fonts
  ];
  environment.pathsToLink = [ "/share/fonts" ];
}
