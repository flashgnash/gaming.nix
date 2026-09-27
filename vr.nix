{ pkgs, lib, ... }:
let
  # SteamVR lives in the shared games library (modules/disks/games-library.nix),
  # not ~/.local/share/Steam.
  vrcompositorLauncher = "/var/lib/games/flashgnash/Steam/steamapps/common/SteamVR/bin/linux64/vrcompositor-launcher";
in
{
  services.monado = {
    enable = true;
    # Don't register Monado as the system OpenXR runtime: the Steam Frame
    # streams through SteamVR, so native OpenXR games must resolve to SteamVR
    # (set via SteamVR Settings → OpenXR → "Set SteamVR as OpenXR Runtime",
    # which writes ~/.config/openxr/1/active_runtime.json). With Monado in
    # /etc/xdg and nothing driving it, OpenXR titles launched into a void.
    defaultRuntime = false;
  };

  # SteamVR pops up a "needs superuser" pkexec prompt on every launch to
  # setcap CAP_SYS_NICE on vrcompositor-launcher. Inside Steam's container the
  # pkexec it finds isn't setuid ("pkexec must be setuid root"), so the setcap
  # never sticks and the prompt comes back forever. Apply the capability from
  # the host instead; the path unit re-fires when Steam updates SteamVR and
  # replaces the binary (which clears the xattr).
  # PathChanged only — PathExists is level-triggered and loops the service
  # into its start limit while the binary exists. The initial apply instead
  # comes from the service's own wantedBy at boot/switch.
  systemd.paths.steamvr-setcap = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = vrcompositorLauncher;
  };

  systemd.services.steamvr-setcap = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      launcher=${lib.escapeShellArg vrcompositorLauncher}
      [ -f "$launcher" ] || exit 0
      # Guard against retrigger loops: setcap itself changes the file's xattrs.
      if ${pkgs.libcap}/bin/getcap "$launcher" | grep -q cap_sys_nice; then
        exit 0
      fi
      ${pkgs.libcap}/bin/setcap cap_sys_nice+ep "$launcher"
    '';
  };
}
