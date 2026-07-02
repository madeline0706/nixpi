# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

NixOS flake configuration for a Raspberry Pi 5 (`nixpi`). The system boots from an NVMe drive, uses the `nixos-raspberrypi` community flake for Pi 5 support, and is pinned to `nixos-25.05`.

## Key files

- `flake.nix` — the entire system configuration lives here as a single inline module
- `flake.lock` — lock file pinning input revisions
- `secrets/secrets.yaml` — sops-encrypted secrets (safe to commit; encrypted at rest)

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

Secrets are managed with `sops-nix`. The age key on the Pi lives at `/var/lib/sops-nix/key.txt`. Secrets are stored in `secrets/secrets.yaml` (encrypted).

Current secrets: `FRP_TOKEN`, `restic_password`, `r2_access_key_id`, `r2_secret_access_key`.

To add or rotate a secret (on the Pi, or with the age key available locally):
```bash
SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops secrets/secrets.yaml
```

Any new secrets files must match the `secrets/.*\.yaml$` path regex in `.sops.yaml` to be encrypted with the right key.

## Services

- **Tailscale** — enabled; `tailscale0` is a trusted firewall interface (no auth key; run `tailscale up` interactively on first boot)
- **Minecraft** — systemd service running `/var/lib/minecraft/start.sh` as the `minecraft` system user; data lives in `/var/lib/minecraft`; TCP 25565 open in firewall
- **frpc** — frp client tunneling TCP 25565 to `192.227.231.178:7000`; config generated from `sops.templates."frpc.toml"` using the `FRP_TOKEN` secret

## Architecture notes

- Uses `nixos-raspberrypi.lib.nixosSystem` (not the standard `nixpkgs.lib.nixosSystem`) to get Pi 5 support
- The `raspberry-pi-5.base` module provides the minimal Pi 5 bootloader and kernel config
- Bootloader is set to `kernel` mode (not UEFI or U-Boot)
- Binary cache `nixos-raspberrypi.cachix.org` is configured to avoid building Pi-specific packages from source
- `fileSystems` and `swapDevices` are defined inline in `flake.nix` using partition labels (`by-partlabel`); `hardware-configuration.nix` is gitignored and not imported
- The frpc and restic-env configs are rendered at runtime by sops-nix; services reference `config.sops.templates.<name>.path` directly

## Backups

Daily restic backups of `/var/lib/minecraft` and `/var/lib/sops-nix/key.txt` run at 3AM America/Los_Angeles, uploaded to Cloudflare R2 (`madelineslovelyworld` bucket). Retention: 7 daily snapshots.

To restore: run `snapshots` to find the ID, then `restore <id>`. The `--target /` flag tells restic to write files back to their original absolute paths.

## Shell helpers (on the Pi)

Bash functions injected into root's interactive shell via `programs.bash.interactiveShellInit`:

**NixOS:**
- `nixpush [msg]` — stage, commit, and push `~/nix`
- `nixsync` — pull `~/nix` and rebuild/switch
- `nixup [msg]` — stage, commit, rebuild/switch, then push

**Backups:**
- `backup` — run a backup immediately and tail the logs
- `snapshots` — list all snapshots with IDs and timestamps
- `latest` — show the most recent snapshot
- `restore <snapshot-id>` — stop the Minecraft server, restore snapshot to original paths, restart

**Minecraft server jar:**
- `mcup` — print usage
- `mcup latest stable` — show latest stable version (dry run)
- `mcup latest snapshot` — show latest snapshot version (dry run)
- `mcup stable` — backup, then update server jar to latest stable
- `mcup snapshot` — backup, then update server jar to latest snapshot
