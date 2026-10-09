{ ... }:
{

  services.sunshine = {
    enable = true;
    capSysAdmin = true;
    autoStart = true;
    # openFirewall opens every interface; trust boundary = the tailnet, so
    # the whole Sunshine port block is opened on tailscale0 only instead.
    openFirewall = false;
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
