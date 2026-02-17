{
  lib,
  buildPythonPackage,
  fetchPypi,
  pytestCheckHook,
  hatchling,
}:

buildPythonPackage rec {
  pname = "wcwidth";
  version = "0.6.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-zcTkJi1u+aGlfgGDhMvrEgjYq7xkF2An4sJFXIExMVk=";
  };

  build-system = [ hatchling ];

  nativeCheckInputs = [ pytestCheckHook ];

  # To prevent infinite recursion with pytest
  doCheck = false;

  pythonImportsCheck = [ "wcwidth" ];

  meta = {
    description = "Measures number of Terminal column cells of wide-character codes";
    longDescription = ''
      This API is mainly for Terminal Emulator implementors -- any Python
      program that attempts to determine the printable width of a string on
      a Terminal. It is implemented in python (no C library calls) and has
      no 3rd-party dependencies.
    '';
    homepage = "https://github.com/jquast/wcwidth";
    changelog = "https://github.com/jquast/wcwidth/releases/tag/${version}";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
