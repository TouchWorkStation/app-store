{ lib, pkgs, ... }:
{
  # Mount path is /modc/nixos-config. VMs add a 9p/virtiofs fstab entry in the
  # image flake; Incus disk devices provide the path for containers (no fstab).

  systemd.services.modc-nixos-config-apply = {
    description = "Apply MODC NixOS configuration from mounted share";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.coreutils pkgs.nixos-rebuild pkgs.nix pkgs.util-linux ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      MOUNT=/modc/nixos-config
      STAMP=/var/lib/modc/nixos-config.sha256
      DEST=/etc/nixos
      mkdir -p /var/lib/modc "$DEST"
      # Wait up to ~2 minutes for the share (slow virtiofs/9p or Incus disk).
      for i in $(seq 1 60); do
        if [ -d "$MOUNT" ] && [ -f "$MOUNT/configuration.nix" ]; then break; fi
        sleep 2
      done
      if [ ! -f "$MOUNT/configuration.nix" ]; then
        echo "modc-nixos-config: no configuration.nix on mount; skipping"
        exit 0
      fi
      NEW=$(find "$MOUNT" -type f \( -name 'configuration.nix' -o -name 'nix-cache.conf' \) -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')
      OLD=""
      [ -f "$STAMP" ] && OLD=$(cat "$STAMP")
      if [ "$NEW" = "$OLD" ]; then
        echo "modc-nixos-config: unchanged"
        exit 0
      fi
      cp -a "$MOUNT/configuration.nix" "$DEST/configuration.nix"
      if [ -f "$MOUNT/nix-cache.conf" ]; then
        mkdir -p /etc/nix/nix.conf.d
        cp -a "$MOUNT/nix-cache.conf" /etc/nix/nix.conf.d/99-modc-cache.conf
      fi
      if ! nixos-rebuild switch; then
        echo "modc-nixos-config: nixos-rebuild failed" >&2
        exit 1
      fi
      echo "$NEW" > "$STAMP"
      if [ "$(readlink -f /run/booted-system)" != "$(readlink -f /run/current-system)" ]; then
        systemctl reboot
      fi
    '';
  };
}
