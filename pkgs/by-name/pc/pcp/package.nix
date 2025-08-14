{
  fetchFromGitHub,
  stdenv,
  lib,

  # Build inputs
  autoreconfHook,
  pkg-config,
  bison,
  flex,

  # Used at runtime in shell scripts
  which,
  gawk,
  gnused,

  # Secure sockets
  openssl,
  cyrus_sasl,

  # Zeroconf/discovery
  avahi ? null,

  # Web
  libuv,
  zlib,

  # Curses -- atop
  readline,
  ncurses,

  # Linux PMDAs
  libbpf ? null,
  libelf ? null,
  clang ? null,
  libllvm ? null,
  bpftrace ? null,
  libpfm ? null,
  systemd ? null,
  bpftools ? null, # TODO move somewhere more appropriate

  # Python PMDAs, API, dstat, pcp ps, etc.
  withPython ? false,
  python3 ? null,

  # Perl PMDAs
  withPerl ? false,
  perl ? null,

  # pmchart, pmgadgets, etc
  withQt ? false,
  qtPackages ? kdePackages,
  kdePackages ? null, # Qt6 works also, but not for SoQt (pmview)

  # TODO darwin stuffs
  cctools,
  libtool,
  gettext,

  nixosTests,
  llvmPackages_20,
}:

let
  inherit (stdenv.hostPlatform) isDarwin isLinux;

  pythonDeps = scopedPkgs: with scopedPkgs; [
    # To build Python API
    setuptools

    # So PCP can find itself
    # TODO: breaks
    # (placeholder "out")

    openpyxl # pcp2xlsx
    pyarrow # pcp2arrow
    setuptools

    requests # InfluxDB support
    six # json
    jsonpointer # json
    libvirt # libvirt
    lxml # libvirt
    psycopg2 # postgresql
    pymongo # mongodb
  ]
  ++ lib.optionals isLinux [
    bcc # bcc TODO -- nixpkgs package doesn't have the library?
    rtslib-fb # LIO
  ]
  # mssql (SQL Server) PMDA -- Upgrade script looks for perl
  ++ lib.optional withPerl pyodbc;

  perlDeps = scopedPkgs: with scopedPkgs; [
    NetSNMP # SNMP
    DBI # oracle, mysql
    DBDmysql # mysql
    LWP # nginx, activemg
  ];

  wrappedPython = python3.withPackages pythonDeps;
  wrappedPerl = perl.withPackages perlDeps;
in

# stdenv.mkDerivation (finalAttrs: {
llvmPackages_20.stdenv.mkDerivation (finalAttrs: {
  pname = "pcp";
  version = "6.3.8";

  src = fetchFromGitHub {
    owner = "performancecopilot";
    repo = "pcp";
    tag = finalAttrs.version;
    hash = "sha256-iSE+VP7UfpKrWONdkrgVX/HLTHzChpCH/2JSsm+O9eo=";
  };

  patches = [
    ./0001-Detect-NixOS-and-build-manpages-on-it.patch
    ./0002-Move-pmlogctl-lockfile-to-run-pcp.patch
    ./0003-Install-files-under-var-and-etc-in-out.patch
    ./0004-Replace-find_library-with-variables-for-library-path.patch
    ./0005-Find-SoQt-using-pkg-config.patch
    ./0006-pmview-install-desktop-files.patch
    ./no-etc-writes.patch
  ];

  # Remove a few hardcoded references to FHS paths in the build and install process
  postPatch = ''
    # Remove vendored bpftool
    rm -rf vendor/{github.com/libbpf/bpftool,GNUmakefile}

    substituteInPlace GNUmakefile \
      --replace-fail "/usr/lib/tmpfiles.d" "$out/lib/tmpfiles.d" \
      --replace-fail " vendor" ""

    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      substituteInPlace src/include/builddefs.in \
        --replace-fail "BPFTOOL =" "BPFTOOL = ${lib.getExe' bpftools "bpftool"} #"
    ''}

    # Replace `/var/tmp` with `/tmp` throughout build scripts
    substituteInPlace scripts/* src/pmdas/*/mk.rewrite src/python/pcp/fixup \
      src/pmdas/linux/add_{snmp,netstat}_field src/libpcp/src/check-errorcodes \
      --replace-quiet "tmp=/var/tmp" "tmp=/tmp"

    ${lib.optionalString withPython ''
      # Replace Python C library placeholders with their full paths
      substituteInPlace src/python/pcp/{mmv.py,pmapi.py.in,pmda.py,pmgui.py,pmi.py} \
        --subst-var-by c ${stdenv.cc.libc}/lib/libc.so.6 \
        --subst-var-by pcp $out/lib/libpcp.so \
        --subst-var-by pcp_mmv $out/lib/libpcp_mmv.so \
        --subst-var-by pcp_pmda $out/lib/libpcp_pmda.so \
        --subst-var-by pcp_gui $out/lib/libpcp_gui.so \
        --subst-var-by pcp_import $out/lib/libpcp_import.so
    ''}
  '';

  preConfigure = ''
    ${lib.optionalString isLinux ''
      export AR=$(which gcc-ar)
      export SYSTEMD_TMPFILESDIR="$out/lib/tmpfiles.d"
      export SYSTEMD_SYSUSERSDIR="$out/lib/sysusers.d"
      export SYSTEMD_SYSTEMUNITDIR="$out/lib/systemd/system"
    ''}
    ${lib.optionalString isDarwin ''
      export AR=$(which ar)
    ''}
  '';

  configureFlags = [
    "--with-make=make" # by default it tries to find gmake
    "--sysconfdir=/etc"
    "--localstatedir=/var"
  ];

  nativeBuildInputs = [
    (autoreconfHook.override { libtool = cctools; })
    pkg-config
    bison
    flex
  ]
  ++ lib.optionals isLinux [
    clang # bpf
    libllvm # bpf -- for llvm-strip command
  ]
  ++ lib.optionals isDarwin [
    # TODO
    cctools
    libtool
  ]
  ++ lib.optional withQt qtPackages.wrapQtAppsHook;

  # needed to compile BPF
  hardeningDisable = lib.optional stdenv.hostPlatform.isLinux "zerocallusedregs";

  buildInputs = builtins.concatLists [
    [
      which
      gawk
      gnused

      openssl
      cyrus_sasl

      readline
      ncurses

      libuv
      zlib

      # TODO: postfix? -- needs qshape
    ]

    (lib.optionals isLinux [
      avahi

      libbpf # bpf
      libelf # bpf
      bpftrace # bpftrace
      libpfm # perfevent
      systemd # systemd
    ])

    (lib.optionals withPython [ python3 ] ++ (pythonDeps python3.pkgs))

    # Without base perl it complains about `crypto.h`
    (lib.optionals withPerl [ perl ] ++ (perlDeps perl.pkgs))

    # pmchart, pmgadgets, pmview, etc
    (lib.optionals withQt (with qtPackages; [
      qtbase
      qtsvg
      qt3d
    ]))
  ];

  # Environment variables for installation -- see `install-sh` script for docs.
  # The `DIST_TMPFILES` option in particular generates a `tmpfiles.d` file that
  # automatically sets up the structure of `/var/lib/pcp`.
  preInstall = ''
    export NO_CHOWN=true
    export DIST_TMPFILES=$out/lib/tmpfiles.d/pcp.conf
  '';

  # Only wrap necessary binaries
  dontWrapQtApps = true;

  postFixup = ''
    ${lib.optionalString withPython ''
      wrapProgram $out/bin/pmpython \
        --prefix PYTHONPATH : $out/${python3.sitePackages}
    ''}

    ${lib.optionalString withQt ''
      for program in "pmchart" "pmview" "pmquery" "pmtime" "pmdumptext"; do
        if [ -x $out/bin/$program ]; then
          wrapQtApp $out/bin/$program
        fi
      done

      mkdir -p $out/share/icons/hicolor/48x48
      ln -s $out/share/pcp-gui/pixmaps $out/share/icons/hicolor/48x48/apps
    ''}
  '';

  passthru = {
    tests = { inherit (nixosTests) pcp; };
  } // lib.optionalAttrs withPython {
    python = python3;
    inherit pythonDeps;
  } // lib.optionalAttrs withPerl {
    inherit perl perlDeps;
  };

  meta = {
    description = "System performance analysis toolkit";
    homepage = "https://pcp.io";
    changelog = "https://github.com/performancecopilot/pcp/blob/${finalAttrs.version}/CHANGELOG";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.unix;
    maintainers = with lib.maintainers; [ andre4ik3 ];
  };
})
