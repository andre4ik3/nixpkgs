{ pkgs, lib, ... }:

let
  # pcp = pkgs.callPackage ../pcp/package.nix { };
  inherit (pkgs) pcp;
in

{
  name = "pcp";

  nodes.machine = {
    imports = [ ../../extras/pcp-module.nix ];

    services.pcp = {
      enable = true;
      package = pcp;
    };

    # Add helper/utility binaries to PATH
    environment.extraInit = ''
      export PATH="$PATH:${pcp}/libexec/pcp/bin"
      # somehow set up ${pcp.src}...
    '';
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    for unit in ["pmcd", "pmproxy", "pmie", "pmlogger"]:
        machine.systemctl(f"start {unit}.service")
        machine.wait_for_unit(f"{unit}.service")

    # TODO: run as pcpqa user, part of pcp group
    # TODO: these also require to be run in the source repo apparently
    # TODO: and they fail, but exit 0?
    # machine.succeed("${pcp}/var/lib/pcp/testsuite/admin/check-vm")
    # machine.succeed("${pcp}/var/lib/pcp/testsuite/check 000")

    # breakpoint()

    # The Real Deal (TM)
    # machine.succeed("${pcp}/var/lib/pcp/testsuite/check")

    machine.shutdown()
  '';

  meta.maintainers = with lib.maintainers; [ andre4ik3 ];
}
