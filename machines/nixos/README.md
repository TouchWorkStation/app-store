# MODC official NixOS machine images

Guest NixOS modules that apply configuration from a host-managed share. These are **not** Podman/Docker app listings.

## Config share layout

The host (My Own Data Center Server) bind-mounts or exports a read-only directory to the guest at:

**`/modc/nixos-config`**

The guest module waits for the mount, then applies files from that path:

| File on share | Guest action |
| --- | --- |
| `configuration.nix` (required) | Copied to `/etc/nixos/configuration.nix` and applied with `nixos-rebuild switch` |
| `nix-cache.conf` (optional) | Installed as `/etc/nix/nix.conf.d/99-modc-cache.conf` |

After a successful rebuild, a composite SHA-256 of those files is recorded at `/var/lib/modc/nixos-config.sha256`. If the digest is unchanged on a later boot, the apply service exits without rebuilding. If `nixos-rebuild switch` leaves the booted system different from the current generation, the service triggers a reboot.

**Server** owns the host directory backing this share; image builders import only the guest module.

## Using the module

Import `machines/nixos/module` in your NixOS configuration (or image flake). VM images use a 9p virtio mount tag `modc-nixos-config` at `/modc/nixos-config`; container-style images may override `fileSystems."/modc/nixos-config"` in an extra module.