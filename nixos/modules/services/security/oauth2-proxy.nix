{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.services.oauth2-proxy;
  format = pkgs.formats.toml { };

  configFile =
    pkgs.runCommand "oauth2-proxy-validated.cfg"
      {
        src = format.generate "oauth2-proxy.cfg" cfg.settings;
        nativeBuildInputs = [ cfg.package ];
      }
      ''
        oauth2-proxy --config="$src" --config-test
        ln -s "$src" "$out"
      '';
in
{
  options.services.oauth2-proxy = {
    enable = lib.mkEnableOption "oauth2-proxy";
    package = lib.mkPackageOption pkgs "oauth2-proxy" { };

    settings = lib.mkOption {
      default = { };
      type = lib.types.submodule {
        freeformType = lib.types.attrsOf format.type;
      };
      description = ''
        Configuration options for OAuth2 Proxy.

        To see all available options and their usage, consult the [upstream documentation][1].

        [1]: https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview/#config-options
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Environment file for specifying additional options at runtime (e.g. secrets).

        Consult the [upstream documentation][1] for more information on using environment variables to override settings.

        [1]: https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview/#environment-variables
      '';
      example = "/run/keys/oauth2-proxy";
    };
  };

  imports = [
    (lib.mkRenamedOptionModule [ "services" "oauth2_proxy" ] [ "services" "oauth2-proxy" ])
    (lib.mkRenamedOptionModule [ "services" "oauth2-proxy" "keyFile" ] [ "services" "oauth2-proxy" "environmentFile" ])
  ];

  config = lib.mkIf cfg.enable {
    systemd.services.oauth2-proxy = {
      description = "OAuth2 Proxy";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Restart = "on-failure";
        ExecStart = utils.escapeSystemdExecArgs [
          (lib.getExe cfg.package)
          "--config=${configFile}"
        ];
        EnvironmentFile = cfg.environmentFile;

        DynamicUser = true;

        # Hardening options from upstream example service file
        LimitNOFILE = 65535;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectControlGroups = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictNamespaces = true;
        MemoryDenyWriteExecute = true;
        PrivateDevices = true;
        CapabilityBoundingSet = [ ];
      };
    };
  };
}
