{
  stdenvNoCC,
  gzip,
  kmod,
  xz,
  zstd,
  kernel,
  modules,
}:

stdenvNoCC.mkDerivation {
  name = "${kernel.name}-modules-hashed";

  dontUnpack = true;
  dontStrip = true;

  nativeBuildInputs = [
    gzip
    kmod
    xz
    zstd
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -aL ${modules}/. "$out/"
    chmod -R u+w "$out"

    moduleRoot="$out/lib/modules/${kernel.modDirVersion}"
    test -d "$moduleRoot"

    mapfile -d "" moduleFiles < <(
      find "$moduleRoot" -type f \
        \( -name '*.ko' -o -name '*.ko.gz' -o -name '*.ko.xz' -o -name '*.ko.zst' \) \
        -print0 | LC_ALL=C sort -z
    )
    if [ "''${#moduleFiles[@]}" -eq 0 ]; then
      echo "No modules found in $moduleRoot" >&2
      exit 1
    fi

    declare -a rawModules compressions
    manifest="$TMPDIR/modules.list"
    : > "$manifest"

    for module in "''${moduleFiles[@]}"; do
      case "$module" in
        *.ko)
          raw="$module"
          compression=none
          ;;
        *.ko.gz)
          raw="''${module%.gz}"
          compression=gzip
          test ! -e "$raw"
          gzip -cd -- "$module" > "$raw"
          ;;
        *.ko.xz)
          raw="''${module%.xz}"
          compression=xz
          test ! -e "$raw"
          xz -cd -- "$module" > "$raw"
          ;;
        *.ko.zst)
          raw="''${module%.zst}"
          compression=zstd
          test ! -e "$raw"
          zstd -q -d -c -- "$module" > "$raw"
          ;;
      esac

      rawModules+=("$raw")
      compressions+=("$compression")
      printf '%s\n' "$raw" >> "$manifest"
    done

    mkdir -p "$out/nix-support"
    ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build/scripts/modules-merkle-tree \
      "$manifest" "$out/nix-support/module-hashes-root"

    for index in "''${!rawModules[@]}"; do
      raw="''${rawModules[$index]}"
      cat "$raw.merkle" >> "$raw"
      rm "$raw.merkle"

      case "''${compressions[$index]}" in
        none) ;;
        gzip) gzip -n -f -- "$raw" ;;
        xz) xz --check=crc32 --lzma2=dict=1MiB -f -- "$raw" ;;
        zstd) zstd --rm -f -q -- "$raw" ;;
      esac
    done

    find "$moduleRoot" -maxdepth 1 -type f -name 'modules.*' \
      ! -name 'modules.builtin*' ! -name modules.order -delete
    depmod -b "$out" -a ${kernel.modDirVersion}

    # Compressed modules can hide store references from Nix's scanner.
    printf '%s\n' ${modules} > "$out/nix-support/extra-refs"

    runHook postInstall
  '';

  passthru.moduleHashesFinalized = true;
}
