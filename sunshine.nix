{ ... }:
{

  services.sunshine = {
    enable = true;
    capSysAdmin = true;
    autoStart = true;
    openFirewall = true;
  };

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
