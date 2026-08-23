{
  config,
  lib,
  utils,
  ...
}:
let
  inherit (utils.systemdUtils.lib) settingsToSections;
  inherit (utils.systemdUtils.unitOptions) unitOption;

  cfg = config.services.resolved;

  dnsmasqResolve = config.services.dnsmasq.enable && config.services.dnsmasq.resolveLocalQueries;

  transformSettings =
    settings:
    lib.mapAttrs (
      key: value:
      # concat lists for options that should result in space-separated values
      if
        builtins.elem key [
          "DNS"
          "Domains"
          "FallbackDNS"
        ]
        && builtins.isList value
      then
        builtins.concatStringsSep " " value
      else
        value
    ) (lib.filterAttrs (key: value: value != null) settings);

  resolvedConf = settingsToSections { Resolve = transformSettings cfg.settings.Resolve; };
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "services" "resolved" "fallbackDns" ]
      [ "services" "resolved" "settings" "Resolve" "FallbackDNS" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "resolved" "domains" ]
      [ "services" "resolved" "settings" "Resolve" "Domains" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "resolved" "llmnr" ]
      [ "services" "resolved" "settings" "Resolve" "LLMNR" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "resolved" "dnssec" ]
      [ "services" "resolved" "settings" "Resolve" "DNSSEC" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "resolved" "dnsovertls" ]
      [ "services" "resolved" "settings" "Resolve" "DNSOverTLS" ]
    )
    (lib.mkRemovedOptionModule [
      "services"
      "resolved"
      "extraConfig"
    ] "Use services.resolved.settings instead")
  ];

  options = {
    services.resolved = {
      enable = lib.mkEnableOption "the Systemd DNS resolver daemon (systemd-resolved)";

      settings.Resolve = lib.mkOption {
        description = ''
          Settings option for systemd-resolved.
          See {manpage}`resolved.conf(5)` for all available options.
        '';
        default = { };
        type = lib.types.submodule {
          freeformType = lib.types.attrsOf unitOption;
          options = {
            DNS = lib.mkOption {
              type = unitOption;
              default = config.networking.nameservers;
              defaultText = lib.literalExpression "config.networking.nameservers";
              description = ''
                List of IP addresses to query as recursive DNS resolvers.
              '';
            };

            DNSOverTLS = lib.mkOption {
              type = unitOption;
              default = false;
              description = ''
                Whether to use TLS encryption for DNS queries. Requires
                nameservers that support DNS-over-TLS.
              '';
            };

            DNSSEC = lib.mkOption {
              type = unitOption;
              default = false;
              description = ''
                Whether to validate DNSSEC for DNS lookups.
              '';
            };

            Domains = lib.mkOption {
              type = unitOption;
              default = config.networking.search;
              defaultText = lib.literalExpression "config.networking.search";
              example = [
                "scope.example.com"
                "example.com"
              ];
              description = ''
                List of search domains used to complete unqualified name lookups.
              '';
            };
          };
        };
      };

      dnsDelegates = lib.mkOption {
        description = ''
          dns-delegate files to be created.
          See {manpage}`systemd.dns-delegate(5)` for more info.
        '';
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.Delegate = lib.mkOption {
              description = ''
                Settings option for systemd dns-delegate files.
                See {manpage}`systemd.dns-delegate(5)` for all available options.
              '';
              type = lib.types.submodule {
                freeformType = lib.types.attrsOf unitOption;
              };
            };
          }
        );
      };

      services = lib.mkOption {
        description = ''
          DNS Service Discovery (dnssd) files to be created.
          See {manpage}`systemd.dnssd(5)` for more info.
        '';
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.Service = lib.mkOption {
              description = ''
                Settings option for systemd dnssd files.
                See {manpage}`systemd.dnssd(5)` for all available options.
              '';
              type = lib.types.submodule {
                freeformType = lib.types.attrsOf unitOption;
              };
            };
          }
        );
      };
    };

    boot.initrd.services.resolved.enable = lib.mkOption {
      default = config.boot.initrd.systemd.network.enable;
      defaultText = "config.boot.initrd.systemd.network.enable";
      description = ''
        Whether to enable resolved for stage 1 networking.
        Uses the toplevel 'services.resolved' options for 'resolved.conf'
      '';
    };

  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {

      assertions = [
        {
          assertion = !config.networking.useHostResolvConf;
          message = "Using host resolv.conf is not supported with systemd-resolved";
        }
      ];

      users.users.systemd-resolve.group = "systemd-resolve";

      # add resolve to nss hosts database if enabled and nscd enabled
      # system.nssModules is configured in nixos/modules/system/boot/systemd.nix
      # added with order 501 to allow modules to go before with mkBefore
      system.nssDatabases.hosts = (lib.mkOrder 501 [ "resolve [!UNAVAIL=return]" ]);

      systemd.additionalUpstreamSystemUnits = [
        "systemd-resolved.service"
        "systemd-resolved-monitor.socket"
        "systemd-resolved-varlink.socket"
      ];

      systemd.services.systemd-resolved = {
        wantedBy = [ "sysinit.target" ];
        aliases = [ "dbus-org.freedesktop.resolve1.service" ];
        reloadTriggers = [
          config.environment.etc."systemd/resolved.conf".source
        ]
        ++ lib.mapAttrsToList (
          name: _: config.environment.etc."systemd/dns-delegate.d/${name}.dns-delegate".source
        ) cfg.dnsDelegates;
        stopIfChanged = false;
      };

      environment.etc = {
        "systemd/resolved.conf".text = resolvedConf;

        # symlink the dynamic stub resolver of resolv.conf as recommended by upstream:
        # https://www.freedesktop.org/software/systemd/man/systemd-resolved.html#/etc/resolv.conf
        "resolv.conf".source = "/run/systemd/resolve/stub-resolv.conf";
      }
      // lib.optionalAttrs dnsmasqResolve {
        "dnsmasq-resolv.conf".source = "/run/systemd/resolve/resolv.conf";
      }
      // lib.mapAttrs' (
        name: value:
        lib.nameValuePair "systemd/dns-delegate.d/${name}.dns-delegate" {
          text = settingsToSections (transformSettings value);
        }
      ) cfg.dnsDelegates
      // lib.mapAttrs' (
        name: value:
        lib.nameValuePair "systemd/dnssd/${name}.dnssd" {
          text = settingsToSections (transformSettings value);
        }
      ) cfg.services;

      # If networkmanager is enabled, ask it to interface with resolved.
      networking.networkmanager.dns = "systemd-resolved";

      # Since we explicitly provide a resolv.conf, disable resolvconf
      networking.resolvconf.enable = false;

      # ... but we still set the package for correct compatibility.
      networking.resolvconf.package = config.systemd.package;

      nix.firewall.extraNftablesRules = [
        "ip daddr { 127.0.0.53, 127.0.0.54 } udp dport 53 accept comment \"systemd-resolved listening IPs\""
      ];

    })

    (lib.mkIf config.boot.initrd.services.resolved.enable {

      assertions = [
        {
          assertion = config.boot.initrd.systemd.enable;
          message = "'boot.initrd.services.resolved.enable' can only be enabled with systemd stage 1.";
        }
      ];

      boot.initrd.systemd = {
        contents = {
          "/etc/systemd/resolved.conf".text = resolvedConf;
        };

        tmpfiles.settings.systemd-resolved-stub."/etc/resolv.conf".L.argument =
          "/run/systemd/resolve/stub-resolv.conf";

        additionalUpstreamUnits = [
          "systemd-resolved.service"
          "systemd-resolved-monitor.socket"
          "systemd-resolved-varlink.socket"
        ];

        users.systemd-resolve = { };
        groups.systemd-resolve = { };
        storePaths = [ "${config.boot.initrd.systemd.package}/lib/systemd/systemd-resolved" ];
        services.systemd-resolved = {
          wantedBy = [ "sysinit.target" ];
          aliases = [ "dbus-org.freedesktop.resolve1.service" ];
        };
      };

    })
  ];

}
