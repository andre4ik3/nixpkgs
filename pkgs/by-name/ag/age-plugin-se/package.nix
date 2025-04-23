{
  lib,
  fetchFromGitHub,
  swiftPackages,
  swift,
  swiftpm,
  nix-update-script,
  swiftpm2nix,
}:

let
  generated = swiftpm2nix.helpers ./generated;
in

swiftPackages.stdenv.mkDerivation (finalAttrs: {
  pname = "age-plugin-se";
  version = "0.1.4";

  src = fetchFromGitHub {
    owner = "remko";
    repo = "age-plugin-se";
    tag = "v${finalAttrs.version}";
    hash = "sha256-sg73DzlW4aXNbIIePZox4JkF10OfsMtPw0q/0DWwgDk=";
  };

  nativeBuildInputs = [
    swift
    swiftpm
  ];

  configurePhase = generated.configure;

  makeFlags = [
    "PREFIX=$(out)"
    "RELEASE=1"
  ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Age plugin for Apple's Secure Enclave";
    homepage = "https://github.com/remko/age-plugin-se/";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      onnimonni
      remko
    ];
    mainProgram = "age-plugin-se";
    platforms = lib.platforms.unix;
  };
})
