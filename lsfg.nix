{ pkgs, ... }:
# Frame generation for RPCS3 through the lsfg-vk layer, scoped to one launch:
# `rpcs3-fg` enables the layer for that process only and hands it its
# settings in the environment, so no other Vulkan app ever loads it. The
# layer runs Lossless Scaling's model, so Lossless Scaling must be installed
# from Steam (the DLL is loaded from the library).
let
  dll = "/home/flashgnash/.local/share/Steam/steamapps/common/Lossless Scaling/Lossless.dll";
  rpcs3-fg = pkgs.writeShellApplication {
    name = "rpcs3-fg";
    text = ''
      # 2x: a 30 fps title presents at 60. flow_scale is kept low because the
      # flow runs at the swapchain size, 3440x1440 fullscreen here.
      export NODEVICE_SELECT=1
      export VK_ADD_LAYER_PATH=${pkgs.lsfg-vk}/share/vulkan/implicit_layer.d
      export LSFG_LEGACY=1
      export LSFG_PROCESS=rpcs3
      export LSFG_DLL_PATH="${dll}"
      export LSFG_MULTIPLIER=''${LSFG_MULTIPLIER:-2}
      export LSFG_FLOW_SCALE=''${LSFG_FLOW_SCALE:-0.5}
      export LSFG_PERFORMANCE_MODE=''${LSFG_PERFORMANCE_MODE:-1}
      exec rpcs3 "$@"
    '';
  };
in
{
  environment.systemPackages = [ rpcs3-fg ];
}
