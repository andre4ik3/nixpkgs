{ config, pkgs, lib, ... }:

let
  pcpCfg = config.services.pcp;
  cfg = pcpCfg.collector;

  inherit (import ./access.nix {
    inherit lib;
    operations = [ "fetch" "store" ];
  }) accessRuleSubmodule mkAccessLines;

  # Mechanism for PMDAs to require an interpreter to be present. Used as
  # follows: `interpreters.require<Lang> "<PMDA>"`. Will throw an error with
  # the name of the PMDA if the interpreter is not present.
  interpreters = let
    mkErrorMsg = lang: name: ''
      The PMDA `${name}` requires ${lang}, but no ${lang} interpreter has been
      set. This usually means that PCP has been built without ${lang} support,
      or {option}`services.pcp.interpreters.${lib.toLower lang}` has been
      set to null. Please do one of the following:

      - Disable this PMDA by setting
        {option}`services.pcp.collector.agents.${name}.enable` to false.

      - Enable ${lang} support by building PCP with `with${lang}` enabled.

      - Manually specify an interpreter path by setting
        {option}`services.pcp.interpreters.${lib.toLower lang}`.
    '';

    requireInterpreter = lang: name: let
      errorMsg = mkErrorMsg lang name;
      interpreter =  pcpCfg.interpreters.${lib.toLower lang};
    in lib.defaultTo (builtins.throw errorMsg) interpreter;
  in {
    requirePython = requireInterpreter "Python";
    requirePerl = requireInterpreter "Perl";
  };

  # Submodule for general PMDA configuration.
  agentSubmodule = { name, config, ... }: {
    options = {
      enable = lib.mkEnableOption ''
        this agent. This option allows disabling default agents
      '' // { default = true; };

      label = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = name;
        defaultText = "‹name›";
        description = "A unique string that identifies this agent.";
      };

      domain = lib.mkOption {
        type = lib.types.ints.between 1 510;
        description = ''
          The domain that this agent will be bound to. Every agent must have a
          unique domain.
        '';
      };

      type = lib.mkOption {
        type = lib.types.enum [ "dso" "socket" "pipe" ];
        description = ''
          The IPC mechanism that `pmcd` will use for communication with this
          agent.
        '';
      };

      path = lib.mkOption {
        type = lib.types.path;
        default = "${pcpCfg.package}/libexec/pcp/pmdas/${name}/pmda_${name}.so";
        defaultText = "‹package›/libexec/pcp/pmdas/‹name›/pmda_‹name›.so";
        description = ''
          For DSO agents, specifies the absolute path to the DSO that will be
          loaded.
        '';
      };

      entryPoint = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "${name}_init";
        defaultText = "‹name›_init";
        description = ''
          For DSO agents, specifies the function that will be invoked when the
          DSO is loaded.
        '';
      };

      addressFamily = lib.mkOption {
        type = lib.types.enum [ "inet" "ipv6" "unix" ];
        description = ''
          For socket agents, specifies the address family that the address is a
          part of.
        '';
      };

      address = lib.mkOption {
        type = lib.types.either lib.types.path lib.types.port;
        description = ''
          For socket agents, specifies the address of the socket to connect to.
          This may either be a UNIX socket name or a port number on the local
          host. Remote agents are not supported, as `pmcd` deals only with
          agents on the same machine.
        '';
      };

      program = lib.mkOption {
        type = lib.types.path;
        default = if config.type == "pipe" then "${pcpCfg.package}/libexec/pcp/pmdas/${name}/pmda${name}" else null;
        defaultText = "‹package›/libexec/pcp/pmdas/‹name›/pmda‹name› for pipe agents, null otherwise";
        description = ''
          For pipe agents, specifies the absolute path to the agent program
          that will be executed.
        '';
      };

      programArguments = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          For pipe agents, specifies the arguments to pass to the agent program
          as part of its command.
        '';
      };

      notReady = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          For pipe agents, specifies whether the agent will be marked as not
          being ready to process requests from `pmcd` when it is first started.
          The agent must then explicitly notify `pmcd` when it is ready to
          process requests.
        '';
      };
    };
  };

  # Submodule for configuring specific PMDAs, based on their attribute name.
  # See `pmda.nix` for implementation.
  agentConfigSubmodule = {
    freeformType = with lib.types; attrsOf (submodule agentSubmodule);

    options = {
      libvirt.config = {
        user = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = "The user to connect to the Libvirt URI as.";
        };

        uri = lib.mkOption {
          type = lib.types.str;
          default = "qemu:///system";
          description = "The Libvirt URI to connect to.";
        };

        backing = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to expose expanded block device information to cover backing
            chains. Only compatible with newer Libvirt versions.
          '';
        };
      };

      linux.config = {
        excludeInterfaces = lib.mkOption {
          type = lib.types.str;
          default = ''
            ^(lo |
              bond[0-9]+ |
              team[0-9]+ |
              tun[0-9]+ |
              virbr[0-9]+ |
              virbr[0-9]+-nic |
              cni[0-9]+ |
              cni-podman[0-9]+ |
              docker[0-9]+ |
              veth[0-9]+ |
              face)$
          '';
          description = ''
            Regular expression that matches interfaces to *exclude* from the
            `network.all.*` metrics calculation when aggregating statistics from
            physical interfaces. Whitespace characters are removed before the
            regular expression is compiled using {manpage}`regcomp(3)`.
          '';
        };

        numaBandwidth = lib.mkOption {
          type = with lib.types; attrsOf (either float int);
          default = {
            "node0" = 1024;
            "node1" = 1024;
          };
          description = ''
            Determines the maximum supported memory bandwidth for each NUMA node.
          '';
        };
      };

      mounts.config = {
        mounts = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [ "/" ];
          description = "The mountpoints to monitor for availability.";
        };
      };

      nginx.config = {
        statusUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://localhost/nginx_status";
          description = ''
            The URL that serves the Nginx `stub_status` module. Requires
            additional configuration in Nginx -- see {manpage}`pmdanginx(1)` for
            details.
          '';
        };

        fetchTimeout = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "The timeout in seconds for fetching the status URL.";
        };
      };

      proc.config = {
        allowedUsers = lib.mkOption {
          type = with lib.types; nullOr (listOf str);
          default = null;
          example = [ "bob" "jenny" "procfsreader" ];
          description = ''
            Names of users permitted access to per-process metrics when
            authenticated. These usernames must be registered with the SASL
            mechanism that `pmcd` has been configured to use.
          '';
        };

        useMapping = lib.mkOption {
          type = lib.types.bool;
          default = false;
          example = true;
          description = ''
            Whether to sample procfs with the identity of the requesting user, or
            the identity of the user that `pmcd` runs as (default). If enabled,
            also enforces allowed users to have a local account.
          '';
        };
      };
    };
  };

  # === Constructing configuration lines === #

  mkAgentLine = agent: lib.concatStringsSep " " (with agent; [
    label
    (builtins.toString domain)
    type
  ] ++ lib.optionals (type == "dso") [
    entryPoint
    path
  ] ++ lib.optionals (type == "socket") [
    addressFamily
    (builtins.toString address)
    (program ? "")
  ] ++ lib.optionals (type == "pipe") [
    "binary"
    program
  ] ++ lib.optionals (type != "dso") programArguments);

  # === Configuration files === #

  pmcdConfig = pkgs.writeText "pmcd.conf" ''
    # This file is generated by Nix. Do not edit!
    # Instead, configure `pmcd` through the `services.pcp.collector` NixOS options.

    # Agent configuration -- generated from `services.pcp.collector.agents`.
    ${lib.concatLines (lib.mapAttrsToList (_: mkAgentLine) cfg.agents)}

    # Access configuration -- generated from `services.pcp.collector.accessRules`.
    [access]
    ${lib.concatLines (lib.flatten (lib.map mkAccessLines cfg.accessRules))}
  '';

  pmcdOptions = pkgs.writeText "pmcd.options" ''
    # This file is generated by Nix. Do not edit!
    # Instead, configure additional command line arguments through the
    # `services.pcp.collector.extraArguments` NixOS option.

    ${lib.concatLines cfg.extraArguments}
  '';

  pmcdEnvironment = pkgs.writeText "pmcd" ''
    # This file is generated by Nix. Do not edit!
    # Instead, configure additional environment variables through the
    # `services.pcp.collector.extraEnvironment` NixOS option.

    ${lib.toShellVars cfg.extraEnvironment}
  '';
in

{
  options.services.pcp.collector = {
    enable = lib.mkEnableOption ''
      the Performance Metrics Collector Daemon (`pmcd`) component of PCP
    '' // { default = true; };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to open the default port in the firewall for `pmcd`.
      '';
    };

    agents = lib.mkOption {
      type = lib.types.submodule agentConfigSubmodule;
      default = { };
      description = ''
        Configuration for Performance Metrics Data Agents (PMDAs).
      '';
    };

    accessRules = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule accessRuleSubmodule);
      default = { };
      description = ''
        Defines the access control configuration for `pmcd`.
      '';
    };

    localOnly = lib.mkOption {
      type = lib.types.bool;
      default = !cfg.openFirewall;
      defaultText = lib.literalExpression ''
        !services.pcp.collector.openFirewall
      '';
      description = ''
        Whether to restrict `pmcd` to only listen for incoming connections on
        the local host.
      '';
    };

    maxPendingClientConnections = lib.mkOption {
      type = lib.types.int;
      default = 5;
      example = 10;
      description = ''
        The maximum number of pending client connections at any one time.
      '';
    };

    rootAgent = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether to offload starting and stopping of agents to `pmdaroot` by
        default. This allows `pmcd` to not require a restart when starting a
        new PMDA.
      '';
    };

    restartAgents = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether to automatically restart any unresponsive or exited PMDAs.
      '';
    };

    waitTimeout = lib.mkOption {
      type = lib.types.int;
      default = 60;
      example = 120;
      description = ''
        Default timeout for waiting on `pmcd` to accept incoming connections.
      '';
    };

    nssInitMode = lib.mkOption {
      type = lib.types.enum [ "readonly" "readwrite" ];
      default = "readonly";
      example = "readwrite";
      description = ''
        Mode for `pmcd` to initialize the NSS certificate database when using
        secure connections. If set to "readwrite" but fails, it will fallback
        and attempt readonly.
      '';
    };

    extraArguments = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional command line arguments to pass to `pmcd`.";
    };

    extraEnvironment = lib.mkOption {
      type = with lib.types; let
        atom = oneOf [ int str bool ];
      in attrsOf (coercedTo atom builtins.toString str);
      default = { };
      description = "Additional environment variables to pass to `pmcd`.";
    };
  };

  config = lib.mkIf (pcpCfg.enable && cfg.enable) {
    assertions = let
      agentAssertions = lib.map (agent: [
        {
          assertion = agent.enable && agent.type == "socket" && agent.addressFamily == "unix" -> lib.types.path.check agent.address;
          message = ''
            services.pcp.collector.agents: `${agent.label}`: Invalid address.
            For socket agents, when `addressFamily` is set to `unix`, `address`
            must be a UNIX socket path.
          '';
        }
        {
          assertion = agent.enable && agent.type == "socket" && agent.addressFamily != "unix" -> lib.types.port.check agent.address;
          message = ''
            services.pcp.collector.agents: `${agent.label}`: Invalid address.
            For socket agents, when `addressFamily` is set to `inet` or `ipv6`,
            `address` must be a valid port number. Connections to hosts other
            than the local host are not supported.
          '';
        }
      ]) (lib.attrValues cfg.agents);
    in (lib.concatLists agentAssertions) ++ [
      {
        assertion = cfg.config.restartAgents -> cfg.config.rootAgent;
        message = ''
          services.pcp.collector.restartAgents: Restarting unresponsive/exited
          PMDAs requires `services.pcp.collector.rootAgent` to be enabled.
        '';
      }
      (let
        domains = lib.mapAttrsToList (_: lib.getAttr "domain") cfg.agents;
      in {
        assertion = lib.allUnique domains;
        message = let
          conflictingDomains = lib.filter (x: lib.count (y: x == y) domains > 1) domains;
          conflictingAgents = lib.filter (agent: builtins.elem agent.domain conflictingDomains);
          conflictingNames = lib.map (agent: "${agent.label} (${agent.domain})") conflictingAgents;
        in ''
          services.pcp.collector.agents: Domain identifier conflict detected.
          The following PMDAs have conflicting domain identifiers:

          ${lib.concatStringsSep ", " conflictingNames}

          Every PMDA must have a unique domain identifier. Please correct this by
          adjusting the domain identifiers of the conflicting PMDAs.
        '';
      })
    ];

    systemd.services.pmcd = {
      enable = true;
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [
        pmcdConfig
        pmcdOptions
        pmcdEnvironment
        config.environment.etc."pcp.conf".source
      ];
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 44321 ];

    services.pcp.collector.extraEnvironment = {
      PMCD_LOCAL = if cfg.localOnly then 1 else 0;
      PMCD_MAXPENDING = cfg.maxPendingClientConnections;
      PMCD_ROOT_AGENT = if cfg.rootAgent then 1 else 0;
      PMCD_RESTART_AGENTS = if cfg.restartAgents then 1 else 0;
      PMCD_WAIT_TIMEOUT = cfg.waitTimeout;
      PCP_NSS_INIT_MODE = cfg.nssInitMode;
    };

    environment.etc = {
      "pcp/pmcd/pmcd.conf".source = pmcdConfig;
      "pcp/pmcd/pmcd.options".source = pmcdOptions;
      "sysconfig/pmcd".source = pmcdEnvironment;
    };

    # TODO: systemd service to run PMDA install/uninstall scripts
    # TODO: maybe store PMDA state in /var/lib/pcp/nixos-state or something

    services.pcp.collector.agents = {
      # Default agents shipped with PCP
      root = {
        domain = 1;
        type = "pipe";
      };
      pmcd = {
        domain = 2;
        type = "dso";
      };
      proc = {
        domain = 3;
        type = "pipe";
        programArguments = [ "-d" "3" ];
      };
      xfs = {
        domain = 11;
        type = "pipe";
        programArguments = [ "-d" "11" ];
      };
      linux = {
        domain = 60;
        type = "pipe";
      };
      pmproxy = {
        domain = 4;
        type = "dso";
        inherit (cfg.agents.mmv) path;
      };
      mmv = {
        domain = 70;
        type = "dso";
      };
      jbd2 = {
        domain = 122;
        type = "dso";
      };
      kvm = {
        domain = 95;
        type = "pipe";
        programArguments = [ "-d" "95" ];
      };

      # Extra agents -- not enabled by default
      docker = {
        enable = lib.mkDefault config.virtualisation.docker.enable;
        domain = 141;
        type = "dso";
      };
      libvirt = {
        enable = lib.mkDefault config.virtualisation.libvirtd.enable;
        domain = 140;
        type = "pipe";
        program = interpreters.requirePython "libvirt";
        programArguments = [ "${pcpCfg.package}/libexec/pcp/pmdas/libvirt/pmdalibvirt.python" ];
      };
      mounts = {
        enable = lib.mkDefault false;
        domain = 72;
        type = "pipe";
      };
      nginx = {
        # not enabled if Nginx is enabled as it requires manual configuration
        enable = lib.mkDefault false;
        domain = 117;
        type = "pipe";
        program = interpreters.requirePerl "nginx";
        programArguments = [ "${pcpCfg.package}/libexec/pcp/pmdas/nginx/pmdanginx.pl" ];
      };
      pipe = {
        enable = lib.mkDefault false;
        domain = 128;
        type = "pipe";
      };
      podman = {
        enable = lib.mkDefault config.virtualisation.podman.enable;
        domain = 33;
        type = "pipe";
      };
      smart = {
        enable = lib.mkDefault config.services.smartd.enable;
        domain = 150;
        type = "pipe";
      };
      sockets = {
        enable = lib.mkDefault false;
        domain = 154;
        type = "pipe";
      };
      zfs = {
        enable = lib.mkDefault config.boot.zfs.enabled;
        domain = 153;
        type = "pipe";
      };
    };

    # Default access rules shipped with PCP
    services.pcp.collector.accessRules = [
      { hosts = [ ".*" ":*" ]; disallow = [ "store" ]; }
      { hosts = [ "local:*" ]; allow = "all"; }
    ];
  };
}
