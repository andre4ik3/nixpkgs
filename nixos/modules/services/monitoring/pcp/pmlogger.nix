{ config, pkgs, lib, ... }:

let
  pcpCfg = config.services.pcp;
  cfg = pcpCfg.archiver;

  baseInstanceSubmodule = { config, name, ... }: {
    options = {
      directory = lib.mkOption {
        type = lib.types.str;
        default = "PCP_ARCHIVE_DIR/${name}";
        defaultText = "PCP_ARCHIVE_DIR/‹name›";
        #   archive directory -- by default, {path}`/var/log/pcp/pmlogger`.
        description = ''
          The directory name where this `pmlogger` instance will store metrics
          archives gathered from the specified remote host.

          `PCP_ARCHIVE_DIR` will be replaced with the path to `pmlogger`'s
          archive directory -- by default, `/var/log/pcp/pmlogger`.
        '';
      };

      reportSizes = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to report record sizes and archive growth rate.
        '';
      };

      samplingInterval = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        defaultText = lib.literalExpression "services.pcp.archiver.samplingInterval";
        description = ''
          The sampling interval (in seconds) to use. By default, the interval
          specified by {option}`services.pcp.archiver.samplingInterval` is used.
        '';
      };

      volumeSize = lib.mkOption {
        type = with lib.types; nullOr (either int str);
        default = null;
        example = "100Mb";
        description = ''
          The maximum volume size, in terms of records, file size, or time
          units, that a single archive volume can grow to. After reaching this
          size, `pmlogger` will switch and start a new archive volume. By
          default, no limit is set, making the archive a single-volume dataset.
        '';
      };

      endSize = lib.mkOption {
        type = with lib.types; nullOr (either int str);
        default = null;
        example = "10Gb";
        description = ''
          The maximum archive size that this `pmlogger` instance will collect
          before terminating. This may either be an integer, which specifies
          the maximum number of records, or a suffixed string, which specifies
          the maximum file size. By default, no limit is set, meaning the
          instance will run indefinitely.
        '';
      };

      endTime = lib.mkOption {
        type = lib.types.nullOr lib.types.str; # TODO: PCP time format validation
        default = null;
        example = "10mins";
        description = ''
          The time period that this `pmlogger` instance will run for before
          terminating, in the format specified in {manpage}`PCPIntro(1)`. By
          default, no limit is set, meaning the instance will run indefinitely.
        '';
      };

      configFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "config.${name}";
        defaultText = "config.‹name›";
        # TODO: {path} not supported? by markdown docs generator?
        #   {path}`/var/lib/pcp/config/pmlogger/` and can be managed using the

        description = ''
          The configuration file name that this `pmlogger` instance will use to
          determine what metrics to archive. The configuration is located in
          `/var/lib/pcp/config/pmlogger/` and can be managed using the
          {command}`pmlc` utility. See {manpage}`pmlc(1)` for more details.
        '';
      };

      extraArguments = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Additional command line arguments to pass to this `pmlogger`
          instance.
        '';
      };
    };

    config.extraArguments = builtins.concatLists (with config; [
      (lib.optional reportSizes "-r")
      (lib.optionals (samplingInterval != null) [ "-t" samplingInterval ])
      (lib.optionals (volumeSize != null) [ "-v" volumeSize ])
      (lib.optionals (endSize != null) [ "-s" endSize ])
      (lib.optionals (endTime != null) [ "-T" endTime ])
      (lib.optionals (configFile != null) [ "-c" configFile ])
    ]);
  };

  primaryInstanceSubmodule = {
    imports = [ baseInstanceSubmodule ];

    options = {
      enable = lib.mkEnableOption ''
        the local `pmlogger` instance that archives metrics from the local
        `pmcd` instance
      '' // {
        default = pcpCfg.collector.enable;
        defaultText = lib.literalExpression "services.pcp.collector.enable";
      };
    };

    # TODO: add these to docs
    config = {
      directory = lib.mkDefault "PCP_ARCHIVE_DIR/LOCALHOSTNAME";
      volumeSize = lib.mkDefault "100Mb";
      endSize = lib.mkDefault "24h10m";
      configFile = lib.mkDefault "config.default";
    };
  };

  secondaryInstanceSubmodule = { config, name, ... }: {
    imports = [ baseInstanceSubmodule ];

    options = {
      enable = lib.mkEnableOption "this `pmlogger` instance" // { default = true; };

      hostName = lib.mkOption {
        type = lib.types.str;
        default = name;
        defaultText = "‹name›";
        description = ''
          The host name of this instance. `pmlogger` will look up this name and
          connect to the `pmcd` instance running on this host.
        '';
      };

      useSocks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to start this `pmlogger` instance under the control of
          `pmsocks`, so as to connect to a `pmcd` instance through a firewall.
        '';
      };

      useLocalTimeZone = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to use the local time zone instead of the time zone of the
          remote host.
        '';
      };
    };

    config.extraArguments = (lib.optional config.useLocalTimeZone "-y");
  };

  mkInstanceLine = instance: lib.concatStringsSep " " (with instance; [
    hostName
    "n"
    (if useSocks then "y" else "n")
    directory
  ] ++ extraArguments);

  pmloggerConfig = pkgs.writeText "pmlogger.control" ''
    # This file is generated by Nix. Do not edit!
    # Instead, configure `pmlogger` through the `services.pcp.archiver` NixOS options.

    # Configuration format version.
    $version=1.1

    # Primary instance -- generated from `services.pcp.archiver.localInstance`.
    ${lib.optionalString cfg.localInstance.enable (with cfg.localInstance; ''
      LOCALHOSTNAME y n ${directory} ${lib.concatStringsSep " " extraArguments}
    '')}

    # Secondary instances -- generated from `services.pcp.archiver.instances`.
    ${lib.concatLines (lib.mapAttrsToList (_: mkInstanceLine) cfg.instances)}
  '';

  pmloggerEnvironment = pkgs.writeText "pmlogger" ''
    # This file is generated by Nix. Do not edit!
    # Instead, configure additional environment variables through the
    # `services.pcp.archiver.extraEnvironment` NixOS option.

    ${lib.toShellVars cfg.extraEnvironment}
  '';
in

{
  options.services.pcp.archiver = {
    enable = lib.mkEnableOption ''
      the Performance Metrics Archiver (`pmlogger`) component of PCP
    '' // { default = true; };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to open the default port in the firewall for `pmlogger`.
      '';
    };

    localOnly = lib.mkOption {
      type = lib.types.bool;
      default = !cfg.openFirewall;
      defaultText = lib.literalExpression ''
        !services.pcp.archiver.openFirewall
      '';
      description = ''
        Whether to restrict `pmlogger` to only listen for incoming connections
        on the local host.
      '';
    };

    samplingInterval = lib.mkOption {
      type = lib.types.int;
      default = 30;
      example = 10;
      description = ''
        The default sampling interval (in seconds) to use for `pmlogger`
        instances.
      '';
    };

    # TODO: instances.primary or instances.local or something
    localInstance = lib.mkOption {
      type = lib.types.submodule primaryInstanceSubmodule;
      default = { };
      description = ''
        Defines the local (primary) instance for `pmlogger` to archive.
      '';
    };

    instances = lib.mkOption {
      type = with lib.types; attrsOf (submodule secondaryInstanceSubmodule);
      default = { };
      description = ''
        Defines additional (secondary) instances for `pmlogger` to archive.
      '';
    };

    extraEnvironment = lib.mkOption {
      type = with lib.types; let
        atom = oneOf [ int str bool ];
      in attrsOf (coercedTo atom builtins.toString str);
      default = { };
      description = ''
        Extra environment variables for `pmlogger` and `pmlogger_farm`.
      '';
    };
  };

  config = lib.mkIf (pcpCfg.enable && cfg.enable) {
    systemd.services = {
      pmlogger = {
        enable = true;
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [
          pmloggerConfig
          pmloggerEnvironment
          config.environment.etc."pcp.conf".source
        ];
      };
      pmlogger_farm = {
        enable = true;
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [
          pmloggerConfig
          pmloggerEnvironment
          config.environment.etc."pcp.conf".source
        ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 4330 ];

    services.pcp.archiver.extraEnvironment = {
      PMLOGGER_LOCAL = if cfg.localOnly then 1 else 0;
      PMLOGGER_INTERVAL = cfg.samplingInterval;
    };

    environment.etc = {
      # RC script used as part of the systemd service
      "pcp/pmlogger/rc".source = "${pcpCfg.package}/etc/pcp/pmlogger/rc";
      "pcp/pmlogger/control".source = pmloggerConfig;
      "sysconfig/pmlogger".source = pmloggerEnvironment;
      "sysconfig/pmlogger_farm".source = pmloggerEnvironment;

      # TODO
      "pcp/pmlogger/options.pmstat".source = "${pcpCfg.package}/etc/pcp/pmlogger/options.pmstat";
      "pcp/pmlogger/class.d/pmfind".source = "${pcpCfg.package}/etc/pcp/pmlogger/class.d/pmfind";
    };
  };
}
