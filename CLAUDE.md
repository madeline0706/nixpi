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

## Services

- **Tailscale** — enabled; no auth key configured (assume interactive `tailscale up` on first boot)
- **frp client** — `services.frp` (role = client) tunnels TCP 25565 to a remote frp server; set `serverAddr` in `flake.nix` before deploying
- **Restic / AWS CLI** — packages installed; no backup jobs or credentials configured yet

## Architecture notes

- Uses `nixos-raspberrypi.lib.nixosSystem` (not the standard `nixpkgs.lib.nixosSystem`) to get Pi 5 support
- The `raspberry-pi-5.base` module provides the minimal Pi 5 bootloader and kernel config
- Bootloader is set to `kernel` mode (not UEFI or U-Boot)
- Binary cache `nixos-raspberrypi.cachix.org` is configured to avoid building Pi-specific packages from source
- The `hardware-configuration.nix` file is present but the `flake.nix` overrides `fileSystems` and `swapDevices` directly — it uses partition labels (`by-partlabel`) rather than UUIDs from the generated file
