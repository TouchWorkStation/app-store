{
  description = "MODC NixOS libvirt image with config share apply";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      make-disk-image = import "${nixpkgs}/nixos/lib/make-disk-image.nix";
    in
    {
      nixosConfigurations.modc-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/profiles/qemu-guest.nix"
          ../module
          ({ lib, pkgs, ... }: {
            networking.hostName = "nixos";
            services.qemuGuest.enable = true;
            system.stateVersion = "24.11";

            # QCOW2 / virtio disk layout (make-disk-image + grow on first boot).
            fileSystems."/" = {
              device = "/dev/disk/by-label/nixos";
              fsType = "ext4";
              autoResize = true;
            };
            boot.growPartition = true;
            boot.kernelParams = [ "console=ttyS0" ];
            boot.loader.grub.device = lib.mkDefault "/dev/vda";

            # Prefer virtiofs when Server adds it; 9p tag must match libvirt.
            fileSystems."/modc/nixos-config" = {
              device = "modc-nixos-config";
              fsType = "9p";
              options = [ "ro" "trans=virtio" "version=9p2000.L" "nofail" ];
            };
          })
        ];
      };

      packages.${system}.qcow2 = make-disk-image {
        inherit (pkgs) lib pkgs;
        config = self.nixosConfigurations.modc-vm.config;
        # qcow2-compressed stays under GitHub's 2 GiB release asset limit.
        format = "qcow2-compressed";
        diskSize = 8192;
        partitionTableType = "hybrid";
        installBootLoader = true;
      };
    };
}