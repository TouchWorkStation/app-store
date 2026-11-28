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

## VM QCOW2 image

The `machines/nixos/vm` flake defines `nixosConfigurations.modc-vm` (qemu-guest profile, config-share mount, qemu-guest-agent) and builds a libvirt-style QCOW2 via nixpkgs `make-disk-image` (8 GiB, virtio, growable root).

```bash
cd machines/nixos/vm && nix build .#qcow2 -L
```

The installable artifact is `packages.x86_64-linux.qcow2`; the flake output name is `qcow2` (`result/nixos.qcow2`). The same `make-disk-image` invocation used in `vm/flake.nix` can be reused in CI by evaluating `nixosConfigurations.modc-vm` and calling `import nixpkgs/nixos/lib/make-disk-image.nix` with `format = "qcow2"` and `diskSize = 8192`.

## Incus container image

The `machines/nixos/container` flake defines `nixosConfigurations.modc-container` using nixpkgs `virtualisation/lxc-container.nix`, the shared `../module`, and container networking (`systemd-networkd` on `eth0`). It does **not** declare an fstab entry for `/modc/nixos-config`; the host must attach the config directory with an Incus **disk** device whose `path` is `/modc/nixos-config` (read-only bind from Server’s host directory).

```bash
cd machines/nixos/container && nix build .#squashfs .#metadata -L
```

Outputs mirror Hydra’s `incusContainerImage` / `incusContainerMeta` names as `packages.x86_64-linux.squashfs` and `.metadata` (aliases `incusContainerImage`, `incusContainerMeta`). Import both into Incus, then launch a privileged container with nesting so `nixos-rebuild` can run inside the guest:

```bash
incus image import --alias modc-nixos result/ metadata.tar.gz
incus launch modc-nixos my-modc -c security.nesting=true -c security.privileged=true
incus config device add my-modc nixos-config disk source=/path/on/host/to/config path=/modc/nixos-config readonly=true
```

`security.nesting=true` is required for Nix sandboxing/builds in unprivileged containers; `security.privileged=true` is the usual MODC default when the guest must rebuild itself. Adjust if your threat model allows only nesting with a custom Incus profile.

## CI releases

GitHub Actions workflow [`.github/workflows/nixos-images.yml`](../../.github/workflows/nixos-images.yml) builds both flakes on `ubuntu-latest` (Nix via [DeterminateSystems/nix-installer-action](https://github.com/DeterminateSystems/nix-installer-action)) and attaches checksummed assets to a GitHub release.

| Trigger | Release tag |
| --- | --- |
| Push tag `nixos-v*` (e.g. `nixos-v24.11.0`) | The pushed tag |
| `workflow_dispatch` | `release_tag` input (default `nixos-v24.11.0`) |

Published assets (version slug is the tag without `nixos-v` and without the patch segment, e.g. `24.11`):

- `modc-nixos-<slug>-amd64.qcow2` (+ `.sha256`)
- `modc-nixos-<slug>-amd64.squashfs` (+ `.sha256`)
- `modc-nixos-<slug>-amd64.incus.tar.xz` (squashfs + metadata bundle; + `.sha256`)

After the first release, pin the qcow2 digest in `machines/catalog.json` (`checksums.sha256`) to match `modc-nixos-<slug>-amd64.qcow2.sha256`.