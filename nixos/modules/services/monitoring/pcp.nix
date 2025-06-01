{ config, pkgs, lib, ... }:

let
  cfg = config.services.pcp;
  boolToIntString = bool: if bool then "1" else "0";
  boolToString = bool: if bool then "yes" else "no";

  # Converts an attribute set to a list of key-value pairs. Note that,
  # according to PCP, the file must be able to be parsed by GNU Make, Bash, and
  # their config system, so the syntax disallows quoting values unless needed.
  attrsToKv = attrs: lib.concatMapStringsSep "\n" (elem: "${elem.name}=${lib.escapeShellArg elem.value}") (lib.attrsToList attrs);
in

{
  options.services.pcp = {
    enable = lib.mkEnableOption "the Performance Co-Pilot system performance analysis toolkit";
    package = lib.mkPackageOption pkgs "pcp" { };

    pmcd = {
      localOnly = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = "Whether to restrict connections to be local-only.";
      };

      maxPending = lib.mkOption {
        type = lib.types.int;
        default = 5;
        example = 10;
        description = ''
          Max length to which the queue of pending connections may grow.
        '';
      };

      # TODO: should these two be user customizable at all?
      rootAgent = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Whether to offload starting and stopping of agents to pmdaroot by
          default. This allows pmcd to not require a restart when starting a
          new PMDA.
        '';
      };

      restartAgents = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Whether to restart any unresponsive or exited PMDAs; this should only
          be used with pmdaroot and {option}`rootAgent`, as it requires
          privileges not available to pmcd itself.
        '';
      };

      waitTimeout = lib.mkOption {
        type = lib.types.int;
        default = 60;
        example = 120;
        description = ''
          Default timeout for waiting on pmcd to accept incoming connections.
        '';
      };

      nssInitMode = lib.mkOption {
        type = lib.types.enum [ "readonly" "readwrite" ];
        default = "readonly";
        example = "readwrite";
        description = ''
          Mode for pmcd to initialize the NSS certificate database when using
          secure connections. If set to "readwrite" but fails, it will fallback
          and attempt readonly.
        '';
      };

      extraVariables = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = {};
        example = lib.literalExpression ''
          {
            PCP_DEBUG = "pmapi";
          }
        '';
        description = "Extra environment variables for `pmcd`.";
      };
    };

    pmfind = {
      checkArguments = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "-C" ];
        example = lib.literalExpression ''[ "--containers" ]'';
        description = "The arguments to pass to the `pmfind_check` script.";
      };

      extraVariables = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = {};
        example = lib.literalExpression ''
          {
            PCP_DEBUG = "pmapi";
          }
        '';
        description = "Extra environment variables for `pmfind`.";
      };
    };

    pmie = {
      checkArguments = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "-C" ];
        example = lib.literalExpression ''[ "--containers" ]'';
        description = "The arguments to pass to the `pmie_check` script.";
      };

      dailyArguments = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "-X" "xz" "-x" "3" ];
        example = lib.literalExpression ''[ "--containers" ]'';
        description = "The arguments to pass to the `pmie_daily` script.";
      };

      extraVariables = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = {};
        example = lib.literalExpression ''
          {
            PCP_DEBUG = "pmapi";
          }
        '';
        description = "Extra environment variables for `pmie_timers`.";
      };
    };

    pmlogger = {
      checkArguments = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "-C" ];
        example = lib.literalExpression ''[ "--containers" ]'';
        description = "The arguments to pass to the `pmlogger_check` script.";
      };

      dailyArguments = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "-E" ];
        example = lib.literalExpression ''[ "--containers" ]'';
        description = "The arguments to pass to the `pmlogger_daily` script.";
      };

      primary = {
        localOnly = lib.mkOption {
          type = lib.types.bool;
          default = true;
          example = false;
          description = "Whether to restrict connections to be local-only.";
        };

        maxPending = lib.mkOption {
          type = lib.types.int;
          default = 5;
          example = 10;
          description = ''
            Max length to which the queue of pending connections may grow.
          '';
        };

        interval = lib.mkOption {
          type = lib.types.int;
          default = 10;
          example = 30;
          description = ''
            Default sampling interval pmlogger uses when no more specific
            interval is requested.
          '';
        };

        checkSkipLogconf = lib.mkOption {
          type = lib.types.bool;
          default = false;
          example = true;
          description = ''
            Skip configuration file regeneration and checking when the pmlogger
            configuration comes from pmlogconf. This should only be enabled if
            the PMDA configuration is stable.
          '';
        };

        checkSkipJanitor = lib.mkOption {
          type = lib.types.bool;
          default = false;
          example = true;
          description = ''
            Skip running pmlogger_janitor as part of pmlogger_check.
          '';
        };

        extraVariables = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = {};
          example = lib.literalExpression ''
            {
              PCP_DEBUG = "pmapi";
            }
          '';
          description = "Extra environment variables for `pmlogger`.";
        };
      };

      farm = {
        localOnly = lib.mkOption {
          type = lib.types.bool;
          default = true;
          example = false;
          description = "Whether to restrict connections to be local-only.";
        };

        maxPending = lib.mkOption {
          type = lib.types.int;
          default = 5;
          example = 10;
          description = ''
            Max length to which the queue of pending connections may grow.
          '';
        };

        interval = lib.mkOption {
          type = lib.types.int;
          default = 10;
          example = 30;
          description = ''
            Default sampling interval pmlogger uses when no more specific
            interval is requested.
          '';
        };

        checkSkipLogconf = lib.mkOption {
          type = lib.types.bool;
          default = false;
          example = true;
          description = ''
            Skip configuration file regeneration and checking when the pmlogger
            configuration comes from pmlogconf. This should only be enabled if
            the PMDA configuration is stable.
          '';
        };

        checkSkipJanitor = lib.mkOption {
          type = lib.types.bool;
          default = false;
          example = true;
          description = ''
            Skip running pmlogger_janitor as part of pmlogger_check.
          '';
        };

        extraVariables = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = {};
          example = lib.literalExpression ''
            {
              PCP_DEBUG = "pmapi";
            }
          '';
          description = "Extra environment variables for `pmlogger_farm`.";
        };
      };

      extraVariables = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = {};
        example = lib.literalExpression ''
          {
            PCP_DEBUG = "pmapi";
          }
        '';
        description = "Extra environment variables for `pmlogger_timers`.";
      };
    };

    pmproxy = {
      localOnly = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = "Whether to restrict connections to be local-only.";
      };

      maxPending = lib.mkOption {
        type = lib.types.int;
        default = 5;
        example = 10;
        description = ''
          Max length to which the queue of pending connections may grow.
        '';
      };

      extraVariables = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = {};
        example = lib.literalExpression ''
          {
            PCP_DEBUG = "pmapi";
          }
        '';
        description = "Extra environment variables for `pmproxy`.";
      };
    };

    extraVariables = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = {};
      example = lib.literalExpression ''
        {
          PCP_DEBUG = "pmapi";
        }
      '';
      description = "Extra environment variables for `pcp.conf`.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (config.environment.memoryAllocator.provider == "libc") ''
      PCP does not support alternative memory allocators. You may experience
      segmentation faults, particularly in the Python API.
    '';

    environment.systemPackages = [ cfg.package ];
    systemd.packages = [ cfg.package ];

    systemd.tmpfiles = {
      # Creates the `/var/log/pcp` and `/var/lib/pcp` directory structures
      packages = [ cfg.package ];

      rules = [
        # Ensure correct permissions on the top-level directories
        "d  /var/lib/pcp                 755 root root -"
        "d  /var/lib/pcp/pmcd            700 root root -"

        # Set up the necessary temporary directories
        "d  /var/lib/pcp/tmp/bash        755 pcp  pcp  -"
        "d  /var/lib/pcp/tmp/json        755 pcp  pcp  -"
        "d  /var/lib/pcp/tmp/mmv         755 pcp  pcp  -"
        "d  /var/lib/pcp/tmp/pmie        755 pcp  pcp  -"
        "d  /var/lib/pcp/tmp/pmlogger    755 pcp  pcp  -"
        "d  /var/lib/pcp/tmp/pmproxy     755 pcp  pcp  -"

        # Fixup permissions for the config files
        "d  /var/lib/pcp/config          755 root root -"
        "d  /var/lib/pcp/config/pmda     775 pcp  pcp  -"
        "d  /var/lib/pcp/config/pmie     775 pcp  pcp  -"
        "d  /var/lib/pcp/config/pmlogger 775 pcp  pcp  -"
      ];
    };

    # Set the logger and metric collector to start by default.
    # TODO: services.pcp.pmlogger.enable or whatever
    systemd.services = {
      pmcd = {
        enable = true;
        wantedBy = [ "multi-user.target" ];
      };
      pmlogger = {
        enable = true;
        wantedBy = [ "multi-user.target" ];
      };
    };

    users = {
      users.pcp = {
        isSystemUser = true;
        group = "pcp";
        home = "/var/lib/pcp";
        description = "Performance Co-Pilot";
      };
      groups.pcp = {};
    };

    environment.etc = {
      /* ==================================================================== */
      ## Bootstrap + Global Configuration                                     ##
      /* ==================================================================== */

      # (Mostly) Compile-time configuration
      "pcp.conf".text = lib.concatLines [
        (builtins.readFile "${cfg.package}/etc/pcp.conf")
        (attrsToKv cfg.extraVariables)
      ];

      # Utility script that provides some functions and exports the
      # configuration variables from `pcp.conf`. Adds a small header with
      # `gawk` and `gnused`, as that's what the script requires.
      "pcp.env".text = ''
        export PATH="${lib.makeBinPath [ pkgs.gawk pkgs.gnused cfg.package ]}:$PATH"

        ${builtins.readFile "${cfg.package}/etc/pcp.env"}
      '';

      /* ==================================================================== */
      ## Component Configuration                                              ##
      /* ==================================================================== */

      # TODO: separate this out
      # - some stuff should never be changed e.g. /etc/pcp/pmlogger/rc
      # - some stuff is redundant e.g. /etc/pcp/pmlogger/options.pmstat (CLI
      #   options can be set via systemd unit? or am i missing something?)
      # - some stuff is really low-level /etc/pcp/pmlogger/config.pmstat
      # - some stuff is distributed /etc/pcp/pmlogger/control
      # - and that's just pmlogger -- there's a dozen more components
      # - some stuff is PMDA configs -- e.g. nginx, linux, elasticsearch, ...
      # - some stuff if configs shipped by default but can be customized --
      #   e.g. /etc/pcp/derived
      # - some stuff is again, redundant, /etc/pcp/pmcd/rc.local, pmcd.options
      # - ...
      # ideally split each component into its own subkey under services.pcp?
      "pcp".source = "${cfg.package}/etc/pcp";

      /* ==================================================================== */
      ## Environment Variables                                                ##
      /* ==================================================================== */

      "sysconfig/pmcd".text = attrsToKv (with cfg.pmcd; {
        PMCD_LOCAL = boolToIntString localOnly;
        PMCD_MAXPENDING = builtins.toString maxPending;
        PMCD_ROOT_AGENT = boolToIntString rootAgent;
        PMCD_RESTART_AGENTS = boolToIntString restartAgents;
        PMCD_WAIT_TIMEOUT = builtins.toString waitTimeout;
        PCP_NSS_INIT_MODE = nssInitMode;
      } // extraVariables);

      "sysconfig/pmfind".text = attrsToKv (with cfg.pmfind; {
        PMFIND_CHECK_PARAMS = checkArguments;
      } // extraVariables);

      "sysconfig/pmie_timers".text = attrsToKv (with cfg.pmie; {
        PMIE_CHECK_PARAMS = checkArguments;
        PMIE_DAILY_PARAMS = dailyArguments;
      } // extraVariables);

      "sysconfig/pmlogger".text = attrsToKv (with cfg.pmlogger.primary; {
        PMLOGGER_LOCAL = boolToIntString localOnly;
        PMLOGGER_MAXPENDING = builtins.toString maxPending;
        PMLOGGER_INTERVAL = builtins.toString interval;
        PMLOGGER_CHECK_SKIP_LOGCONF = boolToString checkSkipLogconf;
        PMLOGGER_CHECK_SKIP_JANITOR = boolToString checkSkipJanitor;
      } // extraVariables);

      "sysconfig/pmlogger_farm".text = attrsToKv (with cfg.pmlogger.farm; {
        PMLOGGER_LOCAL = boolToIntString localOnly;
        PMLOGGER_MAXPENDING = builtins.toString maxPending;
        PMLOGGER_INTERVAL = builtins.toString interval;
        PMLOGGER_CHECK_SKIP_LOGCONF = boolToString checkSkipLogconf;
        PMLOGGER_CHECK_SKIP_JANITOR = boolToString checkSkipJanitor;
      } // extraVariables);

      "sysconfig/pmlogger_timers".text = attrsToKv ({
        PMLOGGER_CHECK_PARAMS = cfg.pmlogger.checkArguments;
        PMLOGGER_DAILY_PARAMS = cfg.pmlogger.dailyArguments;
      } // cfg.pmlogger.extraVariables);

      "sysconfig/pmproxy".text = attrsToKv ({
        PMPROXY_LOCAL = boolToIntString cfg.pmproxy.localOnly;
        PMPROXY_MAXPENDING = builtins.toString cfg.pmproxy.maxPending;
      } // cfg.pmproxy.extraVariables);
    };

    /* ====================================================================== */
    ## Integrations                                                           ##
    /* ====================================================================== */

    environment.etc."sasl2/pmcd.conf".source = "${cfg.package}/etc/sasl2/pmcd.conf";
    services.zabbixAgent.modules."zbxpcp.so" = config.package;
  };

  meta.maintainers = with lib.maintainers; [ andre4ik3 ];
}
