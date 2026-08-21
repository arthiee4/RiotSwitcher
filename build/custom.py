# SCons compilation configuration for ultra-lightweight RiotSwitcher Godot export template
# Target: ~15MB-25MB total build size (2D-only, size-optimized)

target = "template_release"
platform = "windows"
arch = "x86_64"
optimize = "size"
lto = "full"
use_static_cpp = "yes"
debug_symbols = "no"

# Disable 3D subsystem
disable_3d = "yes"
disable_advanced_gui = "no"

# Disable unused modules
module_openxr_enabled = "no"
module_navigation_enabled = "no"
module_gridmap_enabled = "no"
module_csg_enabled = "no"
module_raycast_enabled = "no"
module_meshoptimizer_enabled = "no"
module_mobile_vr_enabled = "no"
module_webrtc_enabled = "no"
module_websocket_enabled = "no"
module_enet_enabled = "no"
module_upnp_enabled = "no"
module_vorbis_enabled = "no"
module_theora_enabled = "no"
module_minimp3_enabled = "no"
d3d12 = "no"
accesskit = "no"
