# Given a kernel build (with modules in $kernel/lib/modules/VERSION),
# produce a module tree in $out/lib/modules/VERSION that contains only
# the modules identified by `rootModules', plus their dependencies.
# Also generate an appropriate modules.dep.

{
  lib,
  stdenvNoCC,
  kernel,
  firmware,
  nukeReferences,
  rootModules,
  kmod,
  allowMissing ? false,
  extraFirmwarePaths ? [ ],
}:

let
  preserveModuleBytes = kernel.moduleHashesFinalized or false;
in
stdenvNoCC.mkDerivation {
  name = kernel.name + "-shrunk";
  builder = ./modules-closure.sh;
  nativeBuildInputs = [ kmod ] ++ lib.optional (!preserveModuleBytes) nukeReferences;
  inherit
    kernel
    firmware
    rootModules
    allowMissing
    extraFirmwarePaths
    ;
  preserveModuleBytes = lib.boolToString preserveModuleBytes;
  ${if preserveModuleBytes then null else "allowedReferences"} = [ "out" ];
}
