{ ... }:
{
  services.monado = {
    enable = true;
    defaultRuntime = true; # Register as default OpenXR runtime
  };
}
