{ lib, ... }:
{
  name = "systemd-initrd-luks-tpm2";

  nodes.machine =
    { pkgs, ... }:
    {
      # Use systemd-boot
      virtualisation = {
        emptyDiskImages = [ 512 ];
        useBootLoader = true;
        # Booting off the TPM2-encrypted device requires an available init script
        mountHostNixStore = true;
        efi.OVMF = pkgs.OVMFFull; # this really should be the default. Only OVMFFull contains TCG
        useEFIBoot = true;
        tpm.enable = true;
      };
      boot.loader.systemd-boot.enable = true;

      boot.initrd.availableKernelModules = [ "tpm_tis" ];

      environment.systemPackages = with pkgs; [ cryptsetup ];

      specialisation.boot-luks.configuration = {
        # Exercise measured-OS services without requiring a UKI in this VM.
        boot.kernelParams = [ "systemd.tpm2_measured_os=1" ];
        # Cryptsetup must wait until the measurement socket is listening.
        boot.initrd.systemd.sockets.systemd-pcrextend.socketConfig.ExecStartPre =
          "${pkgs.coreutils}/bin/sleep 5";
        boot.initrd.systemd.storePaths = [ "${pkgs.coreutils}/bin/sleep" ];
        boot.initrd.luks.devices = lib.mkVMOverride {
          cryptroot = {
            device = "/dev/vdb";
            crypttabExtraOpts = [
              "tpm2-device=auto"
              "tpm2-measure-pcr=yes"
            ];
          };
        };
        virtualisation.rootDevice = "/dev/mapper/cryptroot";
      };
    };

  testScript =
    { nodes, ... }:
    let
      boot-luks = nodes.machine.specialisation.boot-luks.configuration.system.build.toplevel;
    in
    # python
    ''
      # Create encrypted volume
      machine.wait_for_unit("multi-user.target")
      assert int(machine.succeed("cat /sys/class/tpm/tpm0/pcr-sha256/15"), 16) == 0
      machine.succeed("echo -n supersecret | cryptsetup luksFormat -q --iter-time=1 /dev/vdb -")
      machine.succeed("echo -n supersecret | cryptsetup luksOpen -q /dev/vdb cryptroot")
      machine.succeed("mkfs.ext4 /dev/mapper/cryptroot")
      machine.succeed("PASSWORD=supersecret SYSTEMD_LOG_LEVEL=debug systemd-cryptenroll --tpm2-pcrs= --tpm2-device=auto /dev/vdb |& systemd-cat")

      # Boot from the encrypted disk
      machine.succeed("${boot-luks}/bin/switch-to-configuration boot")
      machine.succeed("sync")
      machine.crash()

      # Boot and decrypt the disk
      machine.wait_for_unit("multi-user.target")
      assert "/dev/mapper/cryptroot on / type ext4" in machine.succeed("mount")
      pcr15 = machine.succeed("cat /sys/class/tpm/tpm0/pcr-sha256/15").strip()
      machine.log(f"PCR 15 after TPM2 root unlock: {pcr15}")
      assert int(pcr15, 16) != 0, "LUKS volume key was not measured into PCR 15"
    '';
}
