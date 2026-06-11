{
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  z3-solver,
  miasm,
  lib,
}:

buildPythonPackage {
  pname = "msynth";
  version = "0-unstable-2026-06-06";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mrphrazer";
    repo = "msynth";
    rev = "e64aaaea0f292cf6245de1cd9a9d6fcc2d9c4853";
    hash = "sha256-+Nyf1UplOz4NFZjKJ/AW/fU2su+qn5xSN+k6/UomO7A=";
  };

  build-system = [ setuptools ];

  dependencies = [
    z3-solver
    miasm
  ];

  meta = {
    description = "Code deobfuscation framework to simplify Mixed Boolean-Arithmetic (MBA) expressions";
    license = lib.licenses.gpl3Plus; # from setup.py
  };
}
