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
            paths = [ "/var/lib/minecraft" ];
            timerConfig = {
              OnCalendar = "daily";
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
          ];
          programs.bash.interactiveShellInit = ''
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
