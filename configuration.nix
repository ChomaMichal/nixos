{
  config,
  pkgs,
  ...
}: let
  username = "mchoma";

  # Per-machine file that controls bootloader behavior.
  # Format (one line):
  #   - UEFI:/dev/disk/by-uuid/<UUID>    (recommended for UEFI)
  #   - BIOS:/dev/disk/by-id/<...>       (or simply a device path for BIOS)
  deviceFile = "/etc/nixos/boot-device";

  # Safely read the first non-empty line of the file into a string.
  lines =
    if builtins.pathExists deviceFile
    then builtins.split "\n" (builtins.readFile deviceFile)
    else [""];
  firstLine = builtins.head lines;
  trimmed = builtins.replaceStrings ["\r" "\t" " "] ["" "" ""] firstLine;

  # If empty -> AUTO. Parse "MODE:TARGET" if present, else treat as a target path.
  parts =
    if trimmed == ""
    then ["AUTO"]
    else builtins.split ":" trimmed;
  hasParts = builtins.length parts > 1;
  mode =
    if hasParts
    then builtins.elemAt parts 0
    else "AUTO";
  target =
    if hasParts
    then builtins.elemAt parts 1
    else
      (
        if trimmed == "AUTO"
        then ""
        else trimmed
      );

  # detect host firmware mode
  isUEFI = builtins.pathExists "/sys/firmware/efi";

  # decide which loader to enable
  useSystemdBoot =
    if mode == "UEFI"
    then true
    else if mode == "BIOS"
    then false
    else isUEFI;

  # grub target device (string) or "nodev"
  grubDevice =
    if useSystemdBoot
    then "nodev"
    else
      (
        if target == ""
        then "/dev/sda"
        else target
      );

  # espDevice should be either null or a string (device path). Not a list.
  espDevice =
    if useSystemdBoot
    then
      (
        if target == ""
        then null
        else target
      )
    else null;
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

  nixpkgs.config.allowUnfree = true;
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];
  environment.systemPackages = with pkgs; [
    htop
    ghostty
    discord
    spotify
    (writeShellScriptBin "spotify" ''
      exec ${pkgs.spotify}/bin/spotify \
        --ozone-platform=wayland \
        --enable-features=WaylandWindowDecorations,UseOzonePlatform \
        "$@"
    '')
    obsidian
    (import (builtins.fetchTarball {
      url = "https://github.com/youwen5/zen-browser-flake/archive/master.tar.gz";
    }) {inherit pkgs;}).default
    google-chrome

    neovim
    fzf
    ripgrep
    xclip
    clang
    tree-sitter
    valgrind

    firefox

    nodejs
    clang-tools
    vscode
    man-pages
    alejandra
    readline
    ncurses
    gnumake
    libllvm

    waybar
    dunst
    rofi-wayland
    swww
    kitty
    wl-clipboard
    kdePackages.dolphin
    wofi
  ];

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [];

  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  programs.dconf = {
    enable = true;
    profiles.user.databases = [
      {
        settings = {
          "org/gnome/desktop/interface" = {};
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
        lockAll = true;
      }
    ];
  };

  programs.git = {
    enable = true;
    config = {
      user.name = "michalchoma";
      user.email = "michalkk04@gmail.com";
      pull.rebase = false;
    };
  };

  nix.settings.auto-optimise-store = true;

  systemd.timers.nixos-config-rebuild = {
    description = "Run nixos-config-update hourly";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/1";
      Persistent = true;
    };
  };

  systemd.services.nixos-config-pull = {
    description = "Update NixOS config repository";
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = "/home/${username}/nixos";
      ExecStart = pkgs.writeShellScript "nixos-config-pull" ''
        set -euo pipefail
        export HOME=/home/${username}
        cd /home/${username}/nixos

        echo "[nixos-config-pull] fetching..."
        ${pkgs.git}/bin/git fetch origin

        remoteAheadCount=$(${pkgs.git}/bin/git rev-list HEAD..@{u} --count || echo 0)

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
      User = "${username}";
      Environment = [
        "PATH=${pkgs.git}/bin:${pkgs.openssh}/bin"
        "HOME=/home/${username}"
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
        set -euo pipefail
        ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch \
          --upgrade \
          -I nixos-config=/home/${username}/nixos/configuration.nix \
          -I nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos
      '';
      Environment = [
        "PATH=${pkgs.nix}/bin:${pkgs.nixos-rebuild}/bin:${pkgs.git}/bin:${pkgs.openssh}/bin:${pkgs.bash}/bin"
      ];
    };
  };

  # Bootloader: per-machine controlled by /etc/nixos/boot-device
  boot.loader.systemd-boot.enable = useSystemdBoot;
  boot.loader.efi.canTouchEfiVariables = useSystemdBoot;

  boot.loader.grub.enable = !useSystemdBoot;
  boot.loader.grub.device = grubDevice;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  networking.networkmanager.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  time.timeZone = "Europe/Vienna";

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

  services.printing.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
}
