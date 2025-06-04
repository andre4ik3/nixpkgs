{ config, lib, ... }:

let
  cfg = config.services.pcp;

  pythonInterpreter = let
    hasPython = cfg.package.passthru ? python;
    pythonDeps = (p: (cfg.package.passthru.pythonDeps p) ++ [ cfg.package ]);
    python = cfg.package.passthru.python.withPackages pythonDeps;
  in if hasPython then python.interpreter else null;

  perlInterpreter = let
    hasPerl = cfg.package.passthru ? python;
    perlDeps = (p: (cfg.package.passthru.perlDeps p) ++ [ cfg.package ]);
    perl = cfg.package.passthru.perl.withPackages perlDeps;
  in if hasPerl then perl.interpreter else null;

in

{
  options.services.pcp.interpreters = {
    python = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = pythonInterpreter;
      internal = true;
      description = ''
        The Python interpreter to use for PCP components written in Python.
      '';
    };

    perl = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = perlInterpreter;
      internal = true;
      description = ''
        The Perl interpreter to use for PCP components written in Perl.
      '';
    };
  };

  config.services.pcp.extraEnvironment = {
    PCP_PYTHON_PROG = lib.defaultTo "" cfg.interpreters.python;
    PCP_PERL_PROG = lib.defaultTo "" cfg.interpreters.perl;
  };
}
