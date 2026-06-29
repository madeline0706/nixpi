# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

NixOS flake configuration for a Raspberry Pi 5 (`nixpi`). The system boots from an NVMe drive, uses the `nixos-raspberrypi` community flake for Pi 5 support, and is pinned to `nixos-25.05`.

## Key files

- `flake.nix` — the entire system configuration lives here as a single inline module
- `hardware-configuration.nix` — auto-generated hardware config; do not edit manually
- `flake.lock` — lock file pinning input revisions

## Deploying changes

Rebuild and switch on the Pi itself:
```bash
sudo nixos-rebuild switch --flake .#nixpi
```

To build without switching (check for errors):
```bash
nixos-rebuild build --flake .#nixpi
```

To update flake inputs:
```bash
nix flake update
```

## Remote deployment

The Pi is accessible via SSH (root, authorized key from `madeline@bulbasaur-nix`) and Tailscale. To deploy from the dev machine:
```bash
nixos-rebuild switch --flake .#nixpi --target-host root@nixpi --build-host root@nixpi
```

## Secrets (SOPS)

Secrets are managed with `sops-nix`. The age key on the Pi lives at `/var/lib/sops-nix/key.txt`; the public key is in `.sops.yaml`. Secrets are stored in `secrets/secrets.yaml` (encrypted). Currently one secret is defined: `FRP_TOKEN`, used by the frpc service via a generated TOML template at runtime.

To add or rotate a secret:
```bash
sops secrets/secrets.yaml
```

The SOPS age recipient is configured in `.sops.yaml` — any new secrets files must match the `secrets/.*\.yaml$` path regex to be encrypted with the right key.

## Services

- **Tailscale** — enabled; `tailscale0` is a trusted firewall interface (no auth key; run `tailscale up` interactively on first boot)
- **Minecraft** — systemd service running `/var/lib/minecraft/start.sh` as the `minecraft` system user; data lives in `/var/lib/minecraft`; TCP 25565 open in firewall
- **frpc** — frp client tunneling TCP 25565 to `192.227.231.178:7000`; config generated from `sops.templates."frpc.toml"` using the `FRP_TOKEN` secret
- **Restic / AWS CLI** — packages installed; no backup jobs configured yet

## Architecture notes

- Uses `nixos-raspberrypi.lib.nixosSystem` (not the standard `nixpkgs.lib.nixosSystem`) to get Pi 5 support
- The `raspberry-pi-5.base` module provides the minimal Pi 5 bootloader and kernel config
- Bootloader is set to `kernel` mode (not UEFI or U-Boot)
- Binary cache `nixos-raspberrypi.cachix.org` is configured to avoid building Pi-specific packages from source
- The `hardware-configuration.nix` file is present but the `flake.nix` overrides `fileSystems` and `swapDevices` directly — it uses partition labels (`by-partlabel`) rather than UUIDs from the generated file
- The frpc config is rendered at runtime by sops-nix into a secrets-owned path; the `systemd.services.frpc` unit references `config.sops.templates."frpc.toml".path` directly

## Shell helpers (on the Pi)

Three bash functions are injected into root's interactive shell via `programs.bash.interactiveShellInit`:

- `nixpush [msg]` — stage, commit, and push `~/nix`
- `nixsync` — pull `~/nix` and rebuild/switch
- `nixup [msg]` — stage, commit, rebuild/switch, then push
