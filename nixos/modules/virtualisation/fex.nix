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

  magics = utils.binfmtMagics;

  forwardedLibrarySubmodule = lib.types.submodule ({ name, config, ... }: {
    options = {
      enable = lib.mkEnableOption "forwarding this library" // { default = true; };

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
          The list of packages that contain this library (both in the guest and
          on the host).
        '';
      };

      extraSearchPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "@PREFIX_LIB@" ];
        defaultText = lib.literalExpression ''[ "@PREFIX_LIB@" ]'';
        description = ''
          Extra list of path prefixes where the guest library will be replaced
          from.
        '';
      };

      # TODO naming
      names = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "${name}.so" ];
        defaultText = lib.literalExpression ''[ "‹name›.so" ]'';
        description = ''
          The possible names of this library in the guest.
        '';
      };

      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        visible = false;
        internal = true;
        readOnly = true;
        description = ''
          The final list of paths where this library will be replaced from in
          the guest.
        '';
      };
    };

    config.paths = let
      packages = lib.concatMap config.packages cfg.guestPackageSets;
      # Discard string context to avoid pulling in each guest library as a
      # dependency.
      mkLibPath = drv: builtins.unsafeDiscardStringContext "${lib.getLib drv}/lib";
      libPaths = lib.map mkLibPath packages ++ config.extraSearchPaths;
      product = lib.cartesianProduct {
        path = libPaths;
        name = config.names;
      };
    in lib.map (x: "${x.path}/${x.name}") product;
  });

  defaultForwardedLibraries = {
    libGL.names = ["libGL.so" "libGL.so.1" "libGL.so.1.2.0" "libGL.so.1.7.0"];
    libvulkan = {
      packages = pkgs: [ pkgs.vulkan-loader ];
      names = ["libvulkan.so" "libvulkan.so.1" "libvulkan.so.1.3.239" "libvulkan.so.${lib.getVersion pkgs.vulkan-loader}"];
    };
    libdrm.names = ["libdrm.so" "libdrm.so.2" "libdrm.so.2.4.0" "libdrm.so.${lib.getVersion pkgs.libdrm}"];
    libasound = {
      packages = pkgs: [ pkgs.alsa-lib ];
      names = ["libasound.so" "libasound.so.2" "libasound.so.2.0.0"];
    };
    wayland = {
      name = "libwayland-client-guest.so";
      names = ["libwayland-client.so" "libwayland-client.so.0" "libwayland-client.so.0.20.0" "libwayland-client.so.0.${lib.removePrefix "1." (lib.getVersion pkgs.wayland)}"];
    };
  };

  hostPackageFuncs = lib.mapAttrsToList (_: lib.getAttr "packages") cfg.forwardedLibraries;
  hostPackages = lib.concatMap (f: f pkgs) hostPackageFuncs;
  libPath = lib.makeLibraryPath (hostPackages ++ cfg.extraSearchPaths);

in

{
  options.virtualisation.fex = {
    enable = lib.mkEnableOption "the FEX x86 emulator";
    package = lib.mkPackageOption pkgs "fex" { };

    guestPackageSets = lib.mkOption {
      type = lib.types.listOf lib.types.pkgs;
      default = [
        pkgs.pkgsCross.gnu32
        pkgs.pkgsCross.gnu64
      ];
      defaultText = lib.literalExpression ''
        [
          pkgs.pkgsCross.gnu32
          pkgs.pkgsCross.gnu64
        ]
      '';
      description = ''
        The list of package sets used to retrieve library paths from on the
        guest.
      '';
    };

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
          Overlay = library.paths;
        }) cfg.forwardedLibraries;
      };
      "fex-emu/Config.json".text = builtins.toJSON {
        Config = {
          Env = [ (lib.toShellVar "LD_LIBRARY_PATH" libPath) ];
          ThunkGuestLibs = "${cfg.package}/share/fex-emu/GuestThunks";
          ThunkHostLibs = "${cfg.package}/share/fex-emu/GuestThunks";
        };
        ThunksDB = lib.mapAttrs (name: library: library.enable) cfg.forwardedLibraries;
      };
    };

    nix.settings = lib.mkIf cfg.addToNixSandbox {
      extra-platforms = [ "x86_64-linux" "i386-linux" ];
      extra-sandbox-paths = [ "/run/binfmt" "${cfg.package}" ];
    };
  };

  meta.maintainers = with lib.maintainers; [ andre4ik3 ];
}
