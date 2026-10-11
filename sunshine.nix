{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.sunshine;
  # Same settings, but capture through the desktop portal: the portal's source
  # picker decides what is streamed, a window included. Shares the regular
  # instance's config dir, so pairings and credentials are the same.
  shareConf = (pkgs.formats.keyValue { }).generate "sunshine-share.conf" (
    cfg.settings // { capture = "portal"; }
  );
in
{

  services.sunshine = {
    enable = true;
    capSysAdmin = true;
    autoStart = true;
    # openFirewall opens every interface; trust boundary = the tailnet, so
    # the whole Sunshine port block is opened on tailscale0 only instead.
    openFirewall = false;
    # Browser players decode the relayed stream themselves and not every
    # browser has HEVC or AV1; advertise H.264 only so every join negotiates
    # a codec the client can decode.
    settings = {
      hevc_mode = 1;
      av1_mode = 1;
    };
  };

  # Portal-capture twin of sunshine.service, started for a session share
  # (stream-share start). Every capture Sunshine opens is a fresh portal
  # session, so only the first asks the picker; the restore token it is handed
  # covers the rest. Conflicts both ways: starting either stops the other.
  systemd.user.services.sunshine-share = {
    description = "Sunshine, capturing the source picked through the desktop portal";
    conflicts = [ "sunshine.service" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    startLimitIntervalSec = 500;
    startLimitBurst = 5;
    environment.PATH = lib.mkForce null;
    serviceConfig = {
      ExecStart = "${config.security.wrapperDir}/sunshine ${shareConf}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPortRanges = [
      {
        from = 47984;
        to = 48010;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 47984;
        to = 48010;
      }
    ];
  };

  services.web-portal.links = [
    {
      name = "Sunshine";
      port = 47990;
      scheme = "https";
      description = "host Sunshine web UI (pairing, apps)";
      order = 20;
    }
  ];

  services.avahi.publish.enable = true;
  services.avahi.publish.userServices = true;

  # Sunshine's virtual absolute mouse ("Mouse passthrough (absolute)") exposes
  # ABS_X/ABS_Y screen coordinates, so joydev/SDL classify it as a joystick
  # (js*). Games then read it as a stick that rests at full deflection and
  # only moves with the streamed mouse. Strip the joystick tag so SDL/Proton
  # ignore it.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", ATTRS{name}=="Mouse passthrough (absolute)", ENV{ID_INPUT_JOYSTICK}="", ENV{ID_INPUT_MOUSE}="1"
  '';
}
