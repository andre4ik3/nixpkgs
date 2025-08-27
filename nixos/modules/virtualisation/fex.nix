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

  # Discard string context to avoid pulling in each guest library as a
  # dependency of the system.
  mkLibPath' = drv: builtins.unsafeDiscardStringContext (mkLibPath drv);
  mkLibPath = drv: "${lib.getLib drv}/lib";

  forwardedLibrarySubmodule = lib.types.submodule ({ name, config, ... }: {
    options = {
      enable = lib.mkEnableOption "forwarding this library" // { default = true; };

      # TODO naming -- guestThunkName? thunkName?
      name = lib.mkOption {
        type = lib.types.str;
        default = "${name}-guest.so";
        defaultText = "‹name›-guest.so";
        description = "The guest thunk name of the library to be forwarded.";
      };

      packages = lib.mkOption {
        type = lib.types.functionTo (lib.types.listOf lib.types.package);
        default = pkgs: [ pkgs.${name} ];
        defaultText = lib.literalExpression "pkgs: [ pkgs.‹name› ]";
        description = ''
          The list of guest packages that contain this library.
        '';
      };

      extraSearchPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = lib.literalExpression ''[ "@PREFIX_LIB@" ]'';
        description = ''
          Extra list of path prefixes where the guest library will be replaced
          from.
        '';
      };

      # TODO naming -- guestNames? guestLibraryNames?
      names = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "${name}.so" ];
        defaultText = lib.literalExpression ''[ "‹name›.so" ]'';
        description = ''
          The possible names of this library in the guest.
        '';
      };

      # === private === #

      searchPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        visible = false;
        internal = true;
        readOnly = true;
        description = ''
          The final list of search paths to forward in the guest.
        '';
      };

      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        visible = false;
        internal = true;
        readOnly = true;
        description = ''
          The final list of library paths to forward in the guest.
        '';
      };
    };

    config.searchPaths = lib.map mkLibPath' (lib.concatMap config.packages cfg.guestPackageSets)
      ++ config.extraSearchPaths;

    config.paths = lib.map (x: "${x.path}/${x.name}") (lib.cartesianProduct {
      path = config.searchPaths;
      name = config.names;
    });
  });

  defaultForwardedLibraries = {
    libGL.names = ["libGL.so" "libGL.so.1" "libGL.so.1.2.0" "libGL.so.1.7.0"];
    libvulkan = {
      packages = pkgs: [ pkgs.vulkan-loader ];
      names = ["libvulkan.so" "libvulkan.so.1" "libvulkan.so.1.4.313"];
    };
    libdrm.names = ["libdrm.so" "libdrm.so.2" "libdrm.so.2.4.0" "libdrm.so.2.124.0"];
    libasound = {
      packages = pkgs: [ pkgs.alsa-lib ];
      names = ["libasound.so" "libasound.so.2" "libasound.so.2.0.0"];
    };
    libwayland-client = {
      packages = pkgs: [ pkgs.wayland ];
      names = ["libwayland-client.so" "libwayland-client.so.0" "libwayland-client.so.0.20.0"  "libwayland-client.so.0.24.0"];
    };
  };

  searchPaths = lib.mapAttrsToList (_: x: x.searchPaths) cfg.forwardedLibraries;
  extraSearchPaths = lib.map mkLibPath (lib.concatMap cfg.extraPackages cfg.guestPackageSets);
  libPath = lib.makeLibraryPath (lib.concatLists searchPaths ++ extraSearchPaths);
in

{
  options.virtualisation.fex = {
    enable = lib.mkEnableOption "the FEX x86 emulator";
    package = lib.mkPackageOption pkgs "fex" { };

    addToNixSandbox = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether to add the FEX emulator to {option}`nix.settings.extra-platforms`.
        Disable this to use remote builders for x86 platforms, while allowing testing binaries locally.
      '';
    };

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
      example = lib.literalExpression ''
        [
          nixpkgs.legacyPackages.x86_64-linux
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

    extraPackages = lib.mkOption {
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = lib.const [ ];
      defaultText = lib.literalExpression "lib.const [ ]";
      description = ''
        Additional packages to add to the guest dynamic library path.
      '';
    };

    # TODO: general emulation settings
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
          ThunkHostLibs = "${cfg.package}/lib/fex-emu/HostThunks";
          # TODO debugging
          SilentLog = "0";
          OutputLog = "stderr";
        };
        ThunksDB = lib.mapAttrs (name: library: if library.enable then 1 else 0) cfg.forwardedLibraries;
      };
    };

    nix.settings = lib.mkIf cfg.addToNixSandbox {
      extra-platforms = [ "x86_64-linux" "i386-linux" ];
      extra-sandbox-paths = [ "/run/binfmt" "${cfg.package}" ];
    };
  };

  meta.maintainers = with lib.maintainers; [ andre4ik3 ];
}
