{
  description = "MODC NixOS Incus container image with config share apply";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.modc-container = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/lxc-container.nix"
          ../module
          ({ lib, ... }: {
            networking.hostName = "nixos";
            system.stateVersion = "24.11";

            networking = {
              dhcpcd.enable = false;
              useDHCP = false;
              useHostResolvConf = false;
            };

            systemd.network = {
              enable = true;
              networks."50-eth0" = {
                matchConfig.Name = "eth0";
                networkConfig = {
                  DHCP = "ipv4";
                  IPv6AcceptRA = true;
                };
                linkConfig.RequiredForOnline = "routable";
              };
            };
          })
        ];
      };

      packages.${system} = let
        cfg = self.nixosConfigurations.modc-container.config;
      in {
        # Matches nixpkgs Hydra `incusContainerImage` / `incusContainerMeta` artifacts.
        squashfs = cfg.system.build.squashfs;
        metadata = cfg.system.build.metadata;
        incusContainerImage = cfg.system.build.squashfs;
        incusContainerMeta = cfg.system.build.metadata;
      };
    };
}