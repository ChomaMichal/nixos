{
  config,
  pkgs,
  ...
}: let
  username = "mchoma";
in {
  imports = [
    /etc/nixos/hardware-configuration.nix
    (import ./home.nix {inherit config pkgs username;})
  ];

  networking.hostName = "nixos";
  system.stateVersion = "25.05";

  users.users.${username} = {
    isNormalUser = true;
    description = "${username}";
    extraGroups = ["input" "uinput" "networkmanager" "wheel"];
  };

  # Packages
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    # Apps
    htop
    ghostty
    discord
    spotify
    obsidian
    (import (builtins.fetchTarball {
      url = "https://github.com/youwen5/zen-browser-flake/archive/master.tar.gz";
    }) {inherit pkgs;}).default

    # neovim
    neovim
    fzf
    ripgrep
    xclip
    clang
    tree-sitter

    #lsp
    clang-tools

    # man pages
    man-pages
    alejandra
    readline
    ncurses
    gnumake
  ];

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
  ];
  # Gnome
  services.xserver.enable = true;

  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # to see all possible settings type in
  # gsettings list-schemas
  # for all groups and
  # gsettings list-keys SCHEMA_NAME
  # to get the keys
  programs.dconf = {
    enable = true;
    profiles.user.databases = [
      {
        settings = {
          "org/gnome/desktop/interface" = {
          };
          "org/gnome/desktop/wm/keybindings" = {
            "switch-to-workspace-1" = ["<Alt>1"];
            "switch-to-workspace-2" = ["<Alt>2"];
            "switch-to-workspace-3" = ["<Alt>3"];
            "switch-to-workspace-4" = ["<Alt>4"];
            "switch-to-workspace-5" = ["<Alt>5"];
            "switch-to-workspace-6" = ["<Alt>6"];
            "switch-to-workspace-7" = ["<Alt>7"];
            "switch-to-workspace-8" = ["<Alt>8"];
            "switch-to-workspace-9" = ["<Alt>9"];
            "toggle-fullscreen" = ["<Super>f"];
          };
          "org/gnome/settings-daemon/plugins/media-keys" = {
            "search" = ["<Control>space"];
          };
          "org/gnome/desktop/interface" = {
            enable-animations = false;
            "color-scheme" = "prefer-dark";
            "gtk-theme" = "Adwaita-dark";
          };
          "org/gnome/desktop/peripherals/mouse" = {
            natural-scroll = false;
          };
        };
        lockAll = true; # optional: enforce the settings strictly
      }
    ];
  };

  # Git
  programs.git = {
    enable = true;
    config = {
      user.name = "michalchoma";
      user.email = "michalkk04@gmail.com";
      pull.rebase = false;
    };
  };

  nix.gc.automatic = true;
  nix.gc.dates = "daily";
  nix.gc.options = "--delete-older-than 3d";
  nix.settings.auto-optimise-store = true;

  # Automatic checking of new changes of the config on github and rebuild if there is a new commit
  systemd.timers.nixos-config-rebuild = {
    description = "Run nixos-config-update hourly";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/1"; # every minute
      Persistent = true; # catch up if missed
    };
  };

  systemd.services.nixos-config-pull = {
    description = "Update NixOS config repository";
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = "/home/${username}/nixos"; # adjust this path to where your git repo is
      ExecStart = pkgs.writeShellScript "nixos-config-pull" ''
        set -euo pipefail
        export HOME=/home/${username}
        cd /home/${username}/nixos

        echo "[nixos-config-pull] fetching..."
        ${pkgs.git}/bin/git fetch origin

        # count commits on remote that are not in local
        remoteAheadCount=$(${pkgs.git}/bin/git rev-list HEAD..@{u} --count)

        if [ "$remoteAheadCount" -gt 0 ]; then
          echo "[nixos-config-pull] remote ahead by $remoteAheadCount, pulling..."
          ${pkgs.git}/bin/git pull --ff-only
          echo "[nixos-config-pull] pull done — signaling updated (exit 42)"
          exit 0
        else
          echo "[nixos-config-pull] already up-to-date"
          exit 1
        fi
      '';
      User = "${username}"; # or another user if your repo isn’t root-owned
      Environment = [
        "PATH=${pkgs.git}/bin:${pkgs.openssh}/bin"
        "HOME=/home/${username}" # <--- so git+ssh sees ~/.ssh
      ];
    };
  };

  systemd.services.nixos-config-rebuild = {
    description = "Rebuild NixOS if pull updated the repo";
    unitConfig = {
      Requires = ["nixos-config-pull.service"];
      After = ["nixos-config-pull.service"];
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nixos-config-rebuild" ''
        # Once one command fails the script stops
        set -euo pipefail

        # Rebuild
        ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch \
        --upgrade \
        -I nixos-config=/home/${username}/nixos/configuration.nix \
        -I nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos
      '';
      # run as root (default), so we don't set User
      Environment = [
        "PATH=${pkgs.nix}/bin:${pkgs.nixos-rebuild}/bin:${pkgs.git}/bin:${pkgs.openssh}/bin:${pkgs.bash}/bin"
      ];
    };
  };

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable networking
  networking.networkmanager.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Set your time zone.
  time.timeZone = "Europe/Vienna";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_AT.UTF-8";
    LC_IDENTIFICATION = "de_AT.UTF-8";
    LC_MEASUREMENT = "de_AT.UTF-8";
    LC_MONETARY = "de_AT.UTF-8";
    LC_NAME = "de_AT.UTF-8";
    LC_NUMERIC = "de_AT.UTF-8";
    LC_PAPER = "de_AT.UTF-8";
    LC_TELEPHONE = "de_AT.UTF-8";
    LC_TIME = "de_AT.UTF-8";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
}
