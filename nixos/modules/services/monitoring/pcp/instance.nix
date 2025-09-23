{
  lib,
  service,
  argumentsSubmodule,

  extraDescriptions,
}:

let
  baseSubmodule = { name, ... }: {
    options = {
      extraArguments = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Additional command line arguments to pass to this `${service}`
          instance.
        '';
      };

      configFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "config.${name}";
        defaultText = "config.‹name›";
        # TODO: {path} not supported? by markdown docs generator?
        #   {path}`/var/lib/pcp/config/pmlogger/` and can be managed using the

        description = ''
          The configuration file name that this `${service}` instance will use.
          The configuration is located in `/var/lib/pcp/config/${service}/` and
          can be managed using the {command}`${extraDescriptions.configTool}`
          utility. See {manpage}`${extraDescriptions.configTool}(1)` for more
          details.
        '';
      };
    };
  };

  primaryInstance = {
  };
in

{
  freeformType = with lib.types; attrsOf (submodule baseSubmodule);
}
