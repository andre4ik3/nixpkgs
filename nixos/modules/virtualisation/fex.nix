{ config, pkgs, lib, utils, ... }:

let
  cfg = config.virtualisation.fex;

  common = {
    # Settings taken from the files in `lib/binfmt.d` of the `fex` package
    preserveArgvZero = true;
    openBinary = true;
    matchCredentials = true;
    fixBinary = true;
    offset = 0;
    interpreter = lib.getExe' cfg.package "FEXInterpreter";
    wrapInterpreterInShell = false;
  };

  # magics = lib.importJSON ./binary-magics.json;
  magics = utils.binfmtMagics;

  pkgsCross32 = pkgs.pkgsCross.gnu32;
  pkgsCross64 = pkgs.pkgsCross.gnu64;

  forwardedLibrarySubmodule = lib.types.submodule ({ name, config, ... }: {
    options = {
      enable = lib.mkEnableOption "forwarding this library";

      name = lib.mkOption {
        type = lib.types.str;
        default = "${name}-guest.so";
        defaultText = "‹name›-guest.so";
        description = "The name of the guest library to be forwarded.";
      };

      packages = lib.mkOption {
        type = lib.types.functionTo (lib.types.listOf lib.types.package);
        default = pkgs: [ pkgs.${name} ];
        defaultText = lib.literalExpression "pkgs: [ pkgs.‹name› ]";
        description = ''
          The list of packages where the host library will be searched for.
        '';
      };

      extraSearchPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "@PREFIX_LIB@" ];
        defaultText = lib.literalExpression ''[ "@PREFIX_LIB@" ]'';
        description = ''
          Extra list of paths where the host library will be searched for.
        '';
      };

      # TODO naming
      names = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "${name}.so" ];
        defaultText = lib.literalExpression ''[ "‹name›.so" ]'';
        description = ''
          The possible names of this library on the host.
        '';
      };

      finalPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        visible = false;
        internal = true;
        readOnly = true;
        description = ''
          The final list of packages where this library will be searched.
        '';
      };

      finalPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        visible = false;
        internal = true;
        readOnly = true;
        description = ''
          The final list of paths where this library will be searched.
        '';
      };
    };

    config = {
      finalPackages = config.packages pkgsCross64 ++ config.packages pkgsCross32;
      finalPaths = lib.map (x: "${x.path}/${x.name}") (lib.cartesianProduct {
        path = lib.map (p: "${lib.getLib p}/lib") config.finalPackages
          ++ config.extraSearchPaths;
        name = config.names;
      });
    };
  });

  # TODO: inferring package name from attribute name is cool and all, but it's
  # better to use the proper attribute names. or does it even matter?
  defaultForwardedLibraries = {
    libGL.names = ["libGL.so" "libGL.so.1" "libGL.so.1.2.0" "libGL.so.1.7.0"];
    libvulkan = {
      packages = pkgs: [ pkgs.vulkan-loader ];
      names = ["libvulkan.so" "libvulkan.so.1" "libvulkan.so.1.3.239" "libvulkan.so.${lib.getVersion pkgsCross64.vulkan-loader}"];
      extraSearchPaths = [
        # does not actually catch it by that path:
        "/usr/lib/pressure-vessel/overrides/lib/x86_64-linux-gnu"
        "/usr/lib/pressure-vessel/overrides/lib/i386-linux-gnu"
        "@HOME@/.local/share/Steam/ubuntu12_32/steam-runtime/usr/lib/x86_64-linux-gnu"
        "@HOME@/.local/share/Steam/ubuntu12_32/steam-runtime/usr/lib/i386-linux-gnu"
        "@PREFIX_LIB@"
      ];
    };
    libdrm.names = ["libdrm.so" "libdrm.so.2" "libdrm.so.2.4.0" "libdrm.so.${lib.getVersion pkgsCross64.libdrm}"];
    libasound = {
      packages = pkgs: [ pkgs.alsa-lib ];
      names = ["libasound.so" "libasound.so.2" "libasound.so.2.0.0"];
    };
    wayland = {
      name = "libwayland-client-guest.so";
      names = ["libwayland-client.so" "libwayland-client.so.0" "libwayland-client.so.0.20.0" "libwayland-client.so.0.${lib.removePrefix "1." (lib.getVersion pkgsCross64.wayland)}"];
    };
  };

  forwardedPackages = lib.concatLists (lib.mapAttrsToList (_: lib.getAttr "finalPackages") cfg.forwardedLibraries);
  libPath = lib.makeLibraryPath (forwardedPackages ++ cfg.extraSearchPaths);

in

{
  options.virtualisation.fex = {
    enable = lib.mkEnableOption "the FEX x86 emulator";
    package = lib.mkPackageOption pkgs "fex" { };

    forwardedLibraries = lib.mkOption {
      type = lib.types.attrsOf forwardedLibrarySubmodule;
      default = defaultForwardedLibraries;
      description = "Guest libraries to forward to host-native versions.";
    };

    extraSearchPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ] ;
      description = ''
        List of extra library search paths to make available to guest executables.
      '';
    };

    addToNixSandbox = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether to add the FEX emulator to {option}`nix.settings.extra-platforms`.
        Disable this to use remote builders for x86 platforms, while allowing testing binaries locally.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.singleton {
      assertion = pkgs.hostPlatform.isAarch64;
      message = "FEX emulation is only supported on aarch64.";
    };

    environment.systemPackages = [ cfg.package ];
    boot.binfmt.registrations = {
      "FEX-x86" = common // magics.i386-linux;
      "FEX-x86_64" = common // magics.x86_64-linux;
    };

    environment.etc = {
      "fex-emu/ThunksDB.json".text = builtins.toJSON {
        DB = lib.mapAttrs (_: library: {
          Library = library.name;
          Overlay = library.finalPaths;
        }) cfg.forwardedLibraries;
      };
      "fex-emu/Config.json".text = builtins.toJSON {
        Config = {
          Env = [ (lib.toShellVar "LD_LIBRARY_PATH" libPath) ];
          ThunkGuestLibs = "${cfg.package}/share/fex-emu/GuestThunks";
          ThunkHostLibs = "${cfg.package}/share/fex-emu/GuestThunks";
        };
        # TODO: use forwardedLibraries for this
        ThunksDB = {
          wayland = 1;
          libdrm = 1;
          libasound = 1;
          libGL = 1;
          fex_thunk_test = 0;
          asound = 0;
          libvulkan = 1;
          drm = 1;
          Vulkan = 1;
          WaylandClient = 1;
          GL = 1;
        };
      };
    };

    nix.settings = lib.mkIf cfg.addToNixSandbox {
      extra-platforms = [ "x86_64-linux" "i386-linux" ];
      extra-sandbox-paths = [ "/run/binfmt" "${cfg.package}" ];
    };
  };

  meta.maintainers = with lib.maintainers; [ andre4ik3 ];
}
