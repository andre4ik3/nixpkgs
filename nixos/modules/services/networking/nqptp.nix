{ config, lib, pkgs, ... }:

let
  cfg = config.services.nqptp;
in

{
  ###### interface

  options.services.nqptp = {
    enable = lib.mkEnableOption "NQPTP";
    package = lib.mkPackageOption pkgs "nqptp" { };

    openFirewall = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = "Whether to open the firewall for NQPTP.";
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    systemd.packages = [ cfg.package ];

    users.users.nqptp = {
      group = "nqptp";
      isSystemUser = true;
    };

    users.groups.nqptp = {};

    networking.firewall.allowedUDPPorts = lib.mkIf cfg.openFirewall [ 319 320 ];
  };
}
