{
  lib,
  buildGoModule,
  stdenv,
  fetchFromGitHub,
  installShellFiles,
  asciidoc,
  databasePath ? "/etc/secureboot",
  nix-update-script,
  pkg-config,
  pcsclite,
}:

buildGoModule (finalAttrs: {
  pname = "sbctl";
  version = "0.18-unstable-2026-09-06";

  src = fetchFromGitHub {
    owner = "Foxboron";
    repo = "sbctl";
    # Verifies signatures made by systemd-sbsign (Foxboron/sbctl@ef8427b).
    rev = "3ae0c7e6c7cb28e4f8b8504ec4e49346497cd490";
    hash = "sha256-hXMNVrOOY2o0JG5ldJi9IZfks4xjQInzZWCkUxA+TK0=";
  };

  vendorHash = "sha256-gLOYs4G4XkP/TQn1We1vUfCYELY7QBum0Q1cwE8CTk4=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/foxboron/sbctl.DatabasePath=${databasePath}"
    "-X github.com/foxboron/sbctl.Version=${finalAttrs.version}"
  ];

  nativeBuildInputs = [
    installShellFiles
    asciidoc
    pkg-config
  ];

  buildInputs = [ pcsclite ];

  postBuild = ''
    make docs/sbctl.conf.5 docs/sbctl.8
  '';

  checkFlags = [
    # https://github.com/Foxboron/sbctl/issues/343
    "-skip"
    "github.com/google/go-tpm-tools/.*"
  ];

  postInstall = ''
    installManPage docs/sbctl.conf.5 docs/sbctl.8
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd sbctl \
      --bash <($out/bin/sbctl completion bash) \
      --fish <($out/bin/sbctl completion fish) \
      --zsh <($out/bin/sbctl completion zsh)
  '';

  passthru.updateScript = nix-update-script { extraArgs = [ "--version=branch" ]; };

  meta = {
    description = "Secure Boot key manager";
    mainProgram = "sbctl";
    homepage = "https://github.com/Foxboron/sbctl";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      Pokeylooted
      Scrumplex
    ];
    # go-uefi does not support darwin at the moment:
    # see upstream on https://github.com/Foxboron/go-uefi/issues/13
    platforms = lib.platforms.linux;
  };
})
