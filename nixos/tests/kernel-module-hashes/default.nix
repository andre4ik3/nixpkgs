{
  lib,
  pkgs,
  latestKernel,
  ...
}:

let
  patchNames = builtins.attrNames (
    lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".patch" name) (
      builtins.readDir ./patches
    )
  );
  patches = map (name: {
    inherit name;
    patch =
      let
        latestPatch = ./patches/7.3 + "/${name}";
      in
      if latestKernel && builtins.pathExists latestPatch then latestPatch else ./patches + "/${name}";
  }) patchNames;
  testModule =
    {
      stdenv,
      kernel,
      kernelModuleMakeFlags,
    }:
    stdenv.mkDerivation {
      pname = "module-hash-test";
      inherit (kernel) version;
      src = pkgs.writeTextDir "hash_test.c" ''
        #include <linux/module.h>
        static int __init hash_test_init(void) { return 0; }
        static void __exit hash_test_exit(void) { }
        module_init(hash_test_init);
        module_exit(hash_test_exit);
        MODULE_LICENSE("GPL");
        MODULE_DESCRIPTION("module hash fixture");
      '';
      nativeBuildInputs = kernel.moduleBuildDependencies;
      makeFlags = kernelModuleMakeFlags ++ [
        "-C"
        "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
        "M=$(PWD)"
        "INSTALL_MOD_PATH=${placeholder "out"}"
        "INSTALL_MOD_DIR=extra"
        "DEPMOD=true"
      ];
      preBuild = ''printf 'obj-m = hash_test.o\n' > Kbuild'';
      installTargets = [ "modules_install" ];
      dontStrip = true;
      __structuredAttrs = true;
    };
in
{
  _module.args.latestKernel = lib.mkDefault false;
  name = "kernel-module-hashes";

  meta.platforms = lib.platforms.x86_64;

  nodes.machine =
    { config, ... }:
    {
      boot.kernelPackages = if latestKernel then pkgs.linuxPackages_latest else pkgs.linuxPackages;
      boot.kernel.moduleHashes.enable = true;
      boot.kernelPatches = lib.init patches ++ [
        (
          lib.last patches
          // {
            features.moduleHashes = true;
            structuredExtraConfig = {
              LOCK_DOWN_KERNEL_FORCE_INTEGRITY = lib.mkForce lib.kernel.yes;
              MODULE_HASHES = lib.kernel.yes;
              MODULE_SIG = lib.mkForce lib.kernel.no;
              MODULE_SIG_ALL = lib.mkForce (lib.kernel.option lib.kernel.no);
              SECURITY_LOCKDOWN_LSM = lib.mkForce lib.kernel.yes;
            };
          }
        )
      ];

      boot.extraModulePackages = [
        (config.boot.kernelPackages.callPackage testModule { })
      ]
      ++ lib.optionals (!latestKernel) [
        config.boot.kernelPackages.${pkgs.zfs.kernelModuleAttribute}
        config.boot.kernelPackages.lkrg
      ];
      boot.initrd.kernelModules = [ "tcp_hybla" ];
      security.lsm = [ "lockdown" ];
      environment.systemPackages = [ pkgs.xz ];
      boot.extraModprobeConfig = "options lkrg pcfi_validate=0 umh_validate=0";
    };

  testScript =
    { nodes, ... }:
    let
      kernelPackages = nodes.machine.boot.kernelPackages;
      rawModule = "${
        kernelPackages.callPackage testModule { }
      }/lib/modules/${kernelPackages.kernel.modDirVersion}/extra/hash_test.ko.xz";
    in
    ''
      machine.wait_for_unit("multi-user.target")

      with subtest("lockdown accepts finalized modules and the initrd"):
        machine.succeed("grep -F '[integrity]' /sys/kernel/security/lockdown")
        machine.succeed("test -d /sys/module/tcp_hybla")
        machine.succeed("modprobe hash_test")
        machine.succeed("xz -cd $(modinfo -n hash_test) > /tmp/hashed.ko")
        machine.succeed("modprobe -r hash_test")
      if ${if latestKernel then "False" else "True"}:
        with subtest("ZFS and LKRG are authenticated"):
          machine.succeed("modprobe zfs")
          machine.succeed("grep -E '^zfs ' /proc/modules")
          machine.succeed("modprobe lkrg")
          machine.succeed("grep -E '^lkrg ' /proc/modules")

      machine.copy_from_host("${rawModule}", "/tmp/raw.ko.xz")
      machine.succeed("xz -cd /tmp/raw.ko.xz > /tmp/raw.ko")
      machine.succeed("sed 's/module hash fixture/module hash changed/' /tmp/hashed.ko > /tmp/tampered.ko")
      machine.fail("cmp /tmp/hashed.ko /tmp/tampered.ko")
      machine.succeed("head -c -1 /tmp/hashed.ko > /tmp/truncated.ko")
      # The marker is 28 bytes; the preceding byte is the low byte of sig_len.
      machine.succeed(r"cp /tmp/hashed.ko /tmp/malformed.ko; size=$(wc -c < /tmp/malformed.ko); printf '\001' | dd of=/tmp/malformed.ko bs=1 seek=$((size - 29)) conv=notrunc status=none")

      for level in ["integrity", "confidentiality"]:
        with subtest(f"{level} lockdown rejects missing and invalid proofs"):
          if level == "confidentiality":
            machine.succeed("echo confidentiality > /sys/kernel/security/lockdown")
          machine.succeed(f"grep -F '[{level}]' /sys/kernel/security/lockdown")
          machine.succeed("insmod /tmp/hashed.ko")
          machine.succeed("rmmod hash_test")
          for module in ["raw", "tampered", "truncated", "malformed"]:
            machine.succeed(f"modinfo -F vermagic /tmp/{module}.ko | grep -F $(uname -r)")
            status, output = machine.execute(f"insmod /tmp/{module}.ko 2>&1")
            assert status != 0, f"loaded {module} module"
            if module == "tampered":
              assert "Key was rejected by service" in output, output
            if module == "malformed":
              assert "Bad message" in output, output
          machine.fail("test -d /sys/module/hash_test")
    '';
}
