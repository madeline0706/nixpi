{
  description = "raspberry pi 5 - nixpi";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
  };
  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [ "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=" ];
  };
  outputs = { nixos-raspberrypi, nixpkgs, ... }@inputs: {
    nixosConfigurations.nixpi = nixos-raspberrypi.lib.nixosSystem {
      specialArgs = inputs;
      modules = [
        ({ pkgs, ... }: {
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
          environment.systemPackages = with pkgs; [
            git
            fastfetch
          ];
          system.stateVersion = "25.05";
        })
      ];
    };
  };
}
