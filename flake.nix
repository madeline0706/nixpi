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

          sops.templates."frpc.toml" = {
            content = ''
              serverAddr = "TODO_FRP_SERVER_IP"
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

          environment.systemPackages = with pkgs; [
            git
            fastfetch
            jdk25
            restic
            awscli2
          ];
          system.stateVersion = "25.05";
        })
      ];
    };
  };
}
