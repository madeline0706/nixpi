{
  description = "raspberry pi 5 - nixpi";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };
  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [ "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=" ];
  };
  outputs = { nixos-raspberrypi, nixpkgs, sops-nix, ... }@inputs: {
    nixosConfigurations.nixpi = nixos-raspberrypi.lib.nixosSystem {
      specialArgs = inputs;
      modules = [
        sops-nix.nixosModules.sops
        ({ pkgs, config, ... }: {
          imports = with nixos-raspberrypi.nixosModules; [
            raspberry-pi-5.base
          ];
          fileSystems = {
            "/boot/firmware" = {
              device = "/dev/disk/by-partlabel/FIRMWARE";
              fsType = "vfat";
            };
            "/" = {
              device = "/dev/disk/by-partlabel/disk-nvme-root";
              fsType = "ext4";
            };
          };
          swapDevices = [{ device = "/dev/disk/by-partlabel/disk-nvme-swap"; }];
          boot.loader.raspberry-pi.bootloader = "kernel";
          networking.hostName = "nixpi";
          services.openssh.enable = true;
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOARmU1gT1eVnYO4yA9TRBbY6DRirqQXjWKnpa+5eMbv madeline@bulbasaur-nix"
          ];
          services.tailscale.enable = true;

          sops.defaultSopsFile = ./secrets/secrets.yaml;
          sops.age.keyFile = "/var/lib/sops-nix/key.txt";
          sops.secrets.FRP_TOKEN = {};

          sops.secrets.restic_password = {};
          sops.secrets.r2_access_key_id = {};
          sops.secrets.r2_secret_access_key = {};

          sops.templates."restic-env" = {
            content = ''
              AWS_ACCESS_KEY_ID=${config.sops.placeholder.r2_access_key_id}
              AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.r2_secret_access_key}
            '';
          };

          sops.templates."frpc.toml" = {
            content = ''
              serverAddr = "192.227.231.178"
              serverPort = 7000

              [auth]
              method = "token"
              token = "${config.sops.placeholder.FRP_TOKEN}"

              [[proxies]]
              name = "minecraft"
              type = "tcp"
              localIP = "127.0.0.1"
              localPort = 25565
              remotePort = 25565
            '';
          };

          users.users.minecraft = {
            isSystemUser = true;
            group = "minecraft";
            home = "/var/lib/minecraft";
          };
          users.groups.minecraft = {};

          systemd.tmpfiles.rules = [
            "d /var/lib/minecraft 0750 minecraft minecraft -"
          ];

          systemd.services.minecraft = {
            description = "Minecraft server";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              ExecStart = "/var/lib/minecraft/start.sh";
              WorkingDirectory = "/var/lib/minecraft";
              User = "minecraft";
              Restart = "on-failure";
              RestartSec = "5s";
            };
          };

          networking.firewall.allowedTCPPorts = [ 25565 ];
          networking.firewall.trustedInterfaces = [ "tailscale0" ];

          systemd.services.frpc = {
            description = "frp client";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.frp}/bin/frpc -c ${config.sops.templates."frpc.toml".path}";
              Restart = "on-failure";
              RestartSec = "5s";
            };
          };

          services.restic.backups.minecraft = {
            repository = "s3:https://3d8695564f8c30d83f912a07c253bf21.r2.cloudflarestorage.com/madelineslovelyworld";
            passwordFile = config.sops.secrets.restic_password.path;
            environmentFile = config.sops.templates."restic-env".path;
            paths = [ "/var/lib/minecraft" "/var/lib/sops-nix/key.txt" ];
            timerConfig = {
              OnCalendar = "America/Los_Angeles *-*-* 03:00:00";
              Persistent = true;
            };
            pruneOpts = [
              "--keep-daily 7"
              "--keep-last 1"
            ];
            initialize = true;
          };

          environment.systemPackages = with pkgs; [
	    btop
            git
            fastfetch
            jdk25
            restic
            awscli2
            jq
          ];
          programs.bash.interactiveShellInit = ''
            _restic() {
              (
                set -a
                source "${config.sops.templates."restic-env".path}"
                exec restic \
                  -r "s3:https://3d8695564f8c30d83f912a07c253bf21.r2.cloudflarestorage.com/madelineslovelyworld" \
                  --password-file "${config.sops.secrets.restic_password.path}" \
                  "$@"
              )
            }
            latest() {
              _restic snapshots --latest 1
            }
            _mc_resolve() {
              local type=''${1:-release}
              local manifest
              manifest=$(curl -sf https://launchermeta.mojang.com/mc/game/version_manifest.json) \
                || { echo "Failed to fetch manifest"; return 1; }
              local version
              version=$(echo "$manifest" | jq -r ".latest.$type")
              local version_url
              version_url=$(echo "$manifest" | jq -r --arg v "$version" '.versions[] | select(.id == $v) | .url')
              local jar_url
              jar_url=$(curl -sf "$version_url" | jq -r '.downloads.server.url') \
                || { echo "Failed to fetch version info"; return 1; }
              printf '%s\n%s\n' "$version" "$jar_url"
            }
            _mc_do() {
              local type=$1
              local info version jar_url
              info=$(_mc_resolve "$type") || return 1
              version=$(echo "$info" | head -1)
              jar_url=$(echo "$info" | tail -1)
              echo "Backing up before update..."
              systemctl start restic-backups-minecraft.service \
                || { echo "Backup failed, aborting update"; return 1; }
              echo "Stopping server and downloading Minecraft $type $version..."
              systemctl stop minecraft
              curl -f -o /var/lib/minecraft/server.jar "$jar_url" \
                || { echo "Download failed, restarting with old jar"; systemctl start minecraft; return 1; }
              systemctl start minecraft
              echo "Done: now running Minecraft $type $version"
            }
            mcup() {
              case "$1" in
                latest)
                  case "$2" in
                    stable)
                      local info
                      info=$(_mc_resolve release) || return 1
                      echo "Latest stable: $(echo "$info" | head -1)"
                      ;;
                    snapshot)
                      local info
                      info=$(_mc_resolve snapshot) || return 1
                      echo "Latest snapshot: $(echo "$info" | head -1)"
                      ;;
                    *) echo "Usage: mcup latest stable|snapshot";;
                  esac
                  ;;
                stable)   _mc_do release;;
                snapshot) _mc_do snapshot;;
                *)
                  echo "mcup latest stable    — show latest stable version"
                  echo "mcup latest snapshot  — show latest snapshot version"
                  echo "mcup stable           — backup and update to latest stable"
                  echo "mcup snapshot         — backup and update to latest snapshot"
                  ;;
              esac
            }
            backup() {
              systemctl start restic-backups-minecraft.service
              journalctl -u restic-backups-minecraft.service -n 50
            }
            snapshots() {
              _restic snapshots
            }
            restore() {
              if [ -z "$1" ]; then echo "Usage: restore <snapshot-id>"; return 1; fi
              systemctl stop minecraft
              _restic restore "$1" --target /
              systemctl start minecraft
            }
            nixpush() {
              cd ~/nix && \
              git add . && \
              git commit -m "''${1:-Update config}" && \
              git push
            }
            nixsync() {
              cd ~/nix && \
              git pull && \
              sudo nixos-rebuild switch --flake .#nixpi
            }
            nixup() {
              cd ~/nix && \
              git add . && \
              git commit -m "''${1:-Update config}" && \
              sudo nixos-rebuild switch --flake .#nixpi && \
              git push
            }
          '';

	  # Experimental
	  boot.kernelParams = [ "preempt=voluntary" ];

          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          system.stateVersion = "25.05";
        })
      ];
    };
  };
}
