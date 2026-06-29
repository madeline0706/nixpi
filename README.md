# NixPi - My personal Minecraft world :3  

``! Note: This flake will require some changes if anyone wants to use it.``

This NixOS flake configuration manages my personal Minecraft world, dubbed *Madeline's Lovely World* (stampy reference)

It is not entirely declarative, as I enjoy the ease of running commands to update, for example, the ``server.jar``.

**Features:**

The single ``flake.nix`` manages everything. With it comes support for custom shell commands, deduplicated nightly backups with Restic & Cloudflare R2, Tailscale, and Reverse Proxy support via [FRP](https://github.com/fatedier/frp).

Secrets are encrypted with [SOPS](https://github.com/mic92/sops-nix), and Raspberry Pi support is all thanks to [nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi/tree/develop).

The server can be accessed over LAN, over Tailscale, or via a FRP reverse proxy server. In my usecase, I connect over Tailscale, but in the event that friends are invited in, they can use the reverse proxy to connect, which is also hooked up to a domain, ``guests.spellbound.sh``

## Shell Helpers (Shellpers)

### Server jar management

``mcup``
"mcupdate" allows for dry querying, and updating the server jar via the official Mojang/Minecraft API. The server is first backed up to Cloudflare R2 before proceeding.

```
mcup latest stable    — show latest stable version
mcup latest snapshot  — show latest snapshot version
mcup stable           — backup and update to latest stable
mcup snapshot         — backup and update to latest snapshot
```
### Backup management

``backup / latest / snapshots / restore``
These commands ease the use of Restic. Run ``snapshots`` to get the list of ID's, and use ``restore`` to easily rollback.

