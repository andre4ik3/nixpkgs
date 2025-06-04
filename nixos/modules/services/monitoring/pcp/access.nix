{ operations, lib }:

let
  accessRuleSubmodule = {
    options = {
      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "The usernames this rule should apply for.";
      };

      groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "The group names this rule should apply for.";
      };

      hosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        # TODO: hostname validation, see `pmcd(1)` manpage
        default = [];
        description = "The hostnames this rule should apply for.";
      };

      disallow = lib.mkOption {
        type = with lib.types; either (enum [ "all" ]) (listOf (enum operations));
        default = [ ];
        description = ''
          The actions that the principles specified in this rule will be
          prevented from performing. Note that {option}`allow` rules take
          precedence over {option}`disallow` rules.
        '';
      };

      allow = lib.mkOption {
        type = with lib.types; either (enum [ "all" ]) (listOf (enum operations));
        default = [ ];
        description = ''
          The actions that the principles specified in this rule will be
          allowed to perform. Note that {option}`allow` rules take precedence
          over {option}`disallow` rules.
        '';
      };
    };
  };

  mkAccessLines = rule: let
    mkAccessLine = ruleType: principalType: principals: operations: let
      strPrincipals = lib.concatStringsSep "," (lib.map (x: ''"${x}"'') principals);
      strOperations = if operations == "all" then "all" else lib.concatStringsSep "," operations;
    in "${ruleType} ${principalType} ${strPrincipals} : ${strOperations} ;";

    usersAllow = mkAccessLine "allow" "users" rule.users rule.allow;
    groupsAllow = mkAccessLine "allow" "groups" rule.groups rule.allow;
    hostsAllow = mkAccessLine "allow" "hosts" rule.hosts rule.allow;

    usersDisallow = mkAccessLine "disallow" "users" rule.users rule.disallow;
    groupsDisallow = mkAccessLine "disallow" "groups" rule.groups rule.disallow;
    hostsDisallow = mkAccessLine "disallow" "hosts" rule.hosts rule.disallow;

    allowLines = lib.optionals (rule.allow != []) [
      (lib.optional (rule.users != []) usersAllow)
      (lib.optional (rule.groups != []) groupsAllow)
      (lib.optional (rule.hosts != []) hostsAllow)
    ];

    disallowLines = lib.optionals (rule.disallow != []) [
      (lib.optional (rule.users != []) usersDisallow)
      (lib.optional (rule.groups != []) groupsDisallow)
      (lib.optional (rule.hosts != []) hostsDisallow)
    ];
  in lib.flatten [ allowLines disallowLines ];
in

{
  inherit accessRuleSubmodule mkAccessLines;
}
