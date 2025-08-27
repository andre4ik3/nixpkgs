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

  # Library forwarding configuration
  # TODO: cleanup, wrap the FEXInterpreter binary with it
  libPath = lib.makeLibraryPath cfg.package.passthru.forwardedLibraries;
  wrapper = pkgs.writeShellApplication {
    name = "run-with-fex";
    text = ''
      LD_LIBRARY_PATH="${libPath}:''${LD_LIBRARY_PATH:-}" exec "$@"
    '';
  };

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

      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        visible = false;
        internal = true;
        readOnly = true;
        description = ''
          The final list of paths where this library will be searched.
        '';
      };
    };

    config.paths = let
      packages = config.packages pkgsCross64 ++ config.packages pkgsCross32;
      searchPaths = lib.map (p: "${lib.getLib p}/lib") packages ++ config.extraSearchPaths;
      product = lib.cartesianProduct {
        path = searchPaths;
        name = config.names;
      };
    in lib.map (x: "${x.path}/${x.name}") product;
  });

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

    environment.systemPackages = [ cfg.package wrapper ];
    boot.binfmt.registrations = {
      "FEX-x86" = common // magics.i386-linux;
      "FEX-x86_64" = common // magics.x86_64-linux;
    };

    # TODO: fex doesn't actually search here :(
    # need to put it... somewhere idk
    # ln -s /etc/fex-emu/ThunksDB.json ~/.fex-emu/
    environment.etc."fex-emu/ThunksDB.json".text = builtins.toJSON {
      DB = lib.mapAttrs (_: library: {
        Library = library.name;
        Overlay = library.paths;
      }) cfg.forwardedLibraries;
    };

    nix.settings = lib.mkIf cfg.addToNixSandbox {
      extra-platforms = [ "x86_64-linux" "i386-linux" ];
      extra-sandbox-paths = [ "/run/binfmt" "${cfg.package}" ];
    };
  };

  meta.maintainers = with lib.maintainers; [ andre4ik3 ];
}
