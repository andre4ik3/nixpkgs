---
name: verify-kernel-module-authentication
description: Verify module-hash authentication and signing changes by booting the LTS and latest NixOS test VMs.
---

Run from this nixpkgs checkout on an x86_64 Linux builder with `/dev/kvm`:

```sh
nix-build . -A nixosTests.kernel-module-hashes -A nixosTests.kernel-module-hashes-latest --cores 20 --max-jobs 1 --out-link ./result-module-hashes
```

Inspect the VM output for successful initrd and external-module loading, rejection of missing, modified, truncated, and malformed proofs, and both integrity and confidentiality lockdown. The LTS case also loads ZFS and LKRG.

A cached test result does not boot another VM. For a fresh run, build the test's `.driver` attribute, create an empty output directory, and invoke its `bin/nixos-test-driver -o <output-directory>`.

For the signing backend, `nixosTests.kernel-module-verification` explicitly opts into `MODULE_SIG_ALL`.
