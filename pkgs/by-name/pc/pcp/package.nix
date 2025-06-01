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
  withPython ? true,
  python3Packages,
  makeWrapper,

  # Perl PMDAs
  withPerl ? true,
  perlPackages,

  # pmchart, pmgadgets, etc
  withQt ? true,
  kdePackages,

  nixosTests,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "pcp";
  version = "6.3.7";

  src = fetchFromGitHub {
    owner = "performancecopilot";
    repo = "pcp";
    tag = finalAttrs.version;
    hash = "sha256-fXI9R7pWxs33uS8E+tgzJzhY8tBpoD66jNuSPisJfHE=";
  };

  patches = [
    ./0001-Detect-NixOS-and-build-manpages-on-it.patch
    ./0002-Move-pmlogctl-lockfile-to-run-pcp.patch
    ./0003-Install-files-under-var-and-etc-in-out.patch
    ./0004-Replace-find_library-with-variables-for-library-path.patch
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

    # Replace Python C library placeholders with their full paths
    substituteInPlace src/python/pcp/{mmv.py,pmapi.py.in,pmda.py,pmgui.py,pmi.py} \
      --subst-var-by c ${stdenv.cc.libc}/lib/libc.so.6 \
      --subst-var-by pcp $out/lib/libpcp.so \
      --subst-var-by pcp_mmv $out/lib/libpcp_mmv.so \
      --subst-var-by pcp_pmda $out/lib/libpcp_pmda.so \
      --subst-var-by pcp_gui $out/lib/libpcp_gui.so \
      --subst-var-by pcp_import $out/lib/libpcp_import.so
  '';

  preConfigure = ''
    export AR=$(which gcc-ar)
    export SYSTEMD_TMPFILESDIR="$out/lib/tmpfiles.d"
    export SYSTEMD_SYSUSERSDIR="$out/lib/sysusers.d"
    export SYSTEMD_SYSTEMUNITDIR="$out/lib/systemd/system"
  '';

  configureFlags = [
    "--with-make=make" # by default it tries to find gmake
    "--sysconfdir=/etc"
    "--localstatedir=/var"
  ];

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    bison
    flex
  ] ++ lib.optionals stdenv.hostPlatform.isLinux [
    clang # bpf
    libllvm # bpf -- for llvm-strip command
  ] ++ lib.optional withQt kdePackages.wrapQtAppsHook;

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

    (lib.optionals stdenv.hostPlatform.isLinux [
      avahi

      libbpf # bpf
      libelf # bpf
      bpftrace # bpftrace
      libpfm # perfevent
      systemd # systemd
    ])

    (lib.optionals withPython (with python3Packages; [
      # To wrap pmpython
      makeWrapper

      openpyxl
      pyarrow
      setuptools

      requests # InfluxDB support
      six # json
      jsonpointer # json
      bcc # bcc TODO -- nixpkgs package doesn't have the library?
      libvirt # libvirt
      lxml # libvirt
      psycopg2 # postgresql
      pymongo # mongodb
      rtslib-fb # LIO
    ]))

    (lib.optionals withPerl (with perlPackages; [
      perl
      NetSNMP # SNMP
      DBI # oracle, mysql
      DBDmysql # mysql
      LWP # nginx, activemg
    ]))

    # mssql (SQL Server) PMDA -- Upgrade script looks for perl
    (lib.optional (withPython && withPerl) python3Packages.pyodbc)

    # pmchart, pmgadgets, etc
    (lib.optionals withQt (with kdePackages; [
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
        --prefix PYTHONPATH : ${lib.makeSearchPath python3Packages.python.sitePackages ["$out"]}
    ''}

    ${lib.optionalString withQt ''
      for program in "pmchart" "pmquery" "pmtime" "pmdumptext"; do
        wrapQtApp $out/bin/$program
      done
    ''}
  '';

  passthru = {
    tests = { inherit (nixosTests) pcp; };
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
