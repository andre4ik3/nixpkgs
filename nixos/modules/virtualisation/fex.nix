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

  wrapHostThunk = { name, rpaths }: pkgs.runCommandLocal "fex-host-thunk-${name}-wrapped" {
    fex = lib.getLib cfg.package;
    buildInputs = [ pkgs.patchelf ];
    libPath = "lib/fex-emu/HostThunks";
    lib = "${name}-host.so";
  } ''
    doPatch() {
      mkdir -p "$(dirname "$out/$1")"
      patchelf "$fex/$1" \
        --output "$out/$1" \
        ${lib.concatMapStringsSep " " (rpath: "--add-rpath ${rpath}") rpaths}
    }

    echo "patching host thunk '$lib'..."

    doPatch "$libPath/$lib"
    if [ -f "$fex/$libPath_32/$lib" ]; then
      doPatch "$libPath_32/$lib"
    fi
  '';

  forwardedLibrarySubmodule = lib.types.submodule ({ name, config, ... }: {
    options = {
      enable = lib.mkEnableOption "forwarding this library" // { default = true; };

      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        defaultText = "‹name›";
        description = ''
          The thunk name of the library to be forwarded.
          The value "{option}`name`-host.so" will be used as the host thunk
          name, and "{option}`name`-guest.so" as the guest thunk name.
        '';
      };

      packages = lib.mkOption {
        type = lib.types.functionTo (lib.types.listOf lib.types.package);
        default = pkgs: [ pkgs.${name} ];
        defaultText = lib.literalExpression "pkgs: [ pkgs.‹name› ]";
        description = ''
          Packages to add to both {option}`hostPackages` and
          {option}`guestPackages`.
        '';
      };

      hostPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = ''
          The list of host packages that contain this library. These packages
          will be built, and their library paths (suffixed with `/lib`) will be
          added as RPATHs to the host thunk.
        '';
      };

      extraHostPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Extra list of paths which will be added verbatim as RPATHs to the
          host thunk.
        '';
      };

      guestPackages = lib.mkOption {
        type = lib.types.functionTo (lib.types.listOf lib.types.package);
        default = pkgs: [ ];
        defaultText = lib.literalExpression "pkgs: [ ]";
        description = ''
          The list of guest packages that contain this library. These packages
          will not be built, but their paths (suffixed with {option}`names`)
          will be redirected at runtime to the guest thunk.
        '';
      };

      extraGuestPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = lib.literalExpression ''[ "@PREFIX_LIB@" ]'';
        description = ''
          Extra list of prefixes, which will be suffixed with {option}`names`
          and redirected at runtime to the guest thunk.
        '';
      };

      names = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "${name}.so" ];
        defaultText = lib.literalExpression ''[ "‹name›.so" ]'';
        description = ''
          The possible names of the object file of this library. They will be
          prefixed with {option}`extraGuestPaths` and {option}`guestPackages`,
          and the resulting paths will be redirected at runtime to the guest
          thunk.
        '';
      };

      # === private === #

      wrappedHostThunk = lib.mkOption {
        type = lib.types.package;
        visible = false;
        internal = true;
        readOnly = true;
        description = ''
          The host thunk for this library, with {option}`finalHostPaths` added
          as RPATHs.
        '';
      };

      finalGuestPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        visible = false;
        internal = true;
        readOnly = true;
        description = ''
          The final list of paths to forward to the guest thunk.
        '';
      };
    };

    config = {
      wrappedHostThunk = wrapHostThunk {
        inherit (config) name;
        rpaths = lib.map mkLibPath (config.packages pkgs ++ config.hostPackages)
          ++ config.extraHostPaths;
      };

      finalGuestPaths = lib.map (x: "${x.path}/${x.name}") (lib.cartesianProduct {
        name = config.names;
        path = lib.map mkLibPath' (
          (lib.concatMap (
            set: config.packages set ++ config.guestPackages set
          ) cfg.guestPackageSets) ++ config.extraGuestPaths);
      });
    };
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

  # searchPaths = lib.mapAttrsToList (_: x: x.searchPaths) cfg.forwardedLibraries;
  # extraSearchPaths = lib.map mkLibPath (lib.concatMap cfg.extraPackages cfg.guestPackageSets);
  # libPath = lib.makeLibraryPath (lib.concatLists searchPaths ++ extraSearchPaths);

  hostThunks = pkgs.symlinkJoin {
    name = "fex-host-thunks-wrapped";
    paths = lib.mapAttrsToList (_: library: library.wrappedHostThunk) cfg.forwardedLibraries;
  };
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

    # TODO split lib paths in FEX package so wrong thunks don't get put in path
    environment.systemPackages = [ cfg.package ];
    boot.binfmt.registrations = {
      "FEX-x86" = common // magics.i386-linux;
      "FEX-x86_64" = common // magics.x86_64-linux;
    };

    environment.etc = {
      "fex-emu/ThunksDB.json".text = builtins.toJSON {
        DB = lib.mapAttrs (_: library: {
          Library = "${library.name}-guest.so";
          Overlay = library.finalGuestPaths;
        }) cfg.forwardedLibraries;
      };
      "fex-emu/Config.json".text = builtins.toJSON {
        Config = {
          # Env = [ (lib.toShellVar "LD_LIBRARY_PATH" libPath) ];
          ThunkGuestLibs = "${cfg.package}/share/fex-emu/GuestThunks";
          ThunkHostLibs = "${hostThunks}/lib/fex-emu/HostThunks";
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
