{ config, pkgs, lib, ... }:

let
  pcpCfg = config.services.pcp;

  inherit (pcpCfg) package;
  inherit (pcpCfg.collector) agents;

  # See `pmcd.nix` for the option definitions. The definitions can't be
  # included here due to limitations of the NixOS module system and my
  # insistence/stubbornness on using `services.pcp.collector.agents` for both
  # agent definitions and configurations.

  agentConfigurations = {
    kvm = cfg: {
      environment.etc."pcp/kvm/kvm.conf".source = "${package}/etc/pcp/kvm/kvm.conf";
    };

    libvirt = cfg: {
      environment.etc."pcp/libvirt/libvirt.conf".text = ''
        [pmda]
        user = ${cfg.user}
        uri = ${cfg.uri}
        backing = ${if cfg.backing then "True" else "False"}
      '';
    };

    linux = cfg: {
      environment.etc = {
        "pcp/linux/interfaces.conf".text = cfg.excludeInterfaces;
        "pcp/linux/samplebandwidth.conf".text = ''
          Version:1.0
          ${lib.concatMapAttrsStringSep "\n" (k: v: "${k}:${builtins.toString v}") cfg.numaBandwidth}
        '';
      };
    };

    mounts = cfg: {
      environment.etc."pcp/mounts/mounts.conf".text = lib.concatLines cfg.mounts;
    };

    nginx = cfg: {
      environment.etc."pcp/nginx/nginx.conf".text = ''
        $nginx_status_url = "${cfg.statusUrl}";
        $nginx_fetch_timeout = ${builtins.toString cfg.fetchTimeout};
      '';
    };

    proc = cfg: {
      environment.etc = {
        "pcp/proc/access.conf".text = ''
          ${lib.optionalString (cfg.allowedUsers != null) ''
            allowed: ${lib.concatStringsSep ", " cfg.allowedUsers}
          ''}
          mapped: ${if cfg.useMapping then "true" else "false"}
        '';
        "pcp/proc/samplehotproc.conf".source = "${package}/etc/pcp/proc/samplehotproc.conf";
      };
    };
  };

  agentConfigurations' = lib.mapAttrsToList (name: func: lib.mkIf agents.${name}.enable (func agents.${name}.config)) agentConfigurations;
in

{
  config = lib.mkIf (pcpCfg.enable && pcpCfg.collector.enable) (lib.mkMerge agentConfigurations');

  # TODO: detect when PMDAs change, call `${package}/libexec/pcp/pmdas/${name}/{Install,Remove}` when that happens
  # TODO: maybe as a systemd service? what's the dependency that makes it so if the child restarts the parent does too
}
