{
  config,
  pkgs,
  username,
  ...
}: let
  home-manager = builtins.fetchTarball {
    url = "https://github.com/nix-community/home-manager/archive/release-25.05.tar.gz";
  };
in {
  imports = [
    (import "${home-manager}/nixos")
  ];

  home-manager.users.${username} = {
    home.stateVersion = "25.05";
    home.file = {
      ".config/ghostty/config".source = ./dotfiles/ghostty;
      ".bashrc".source = ./dotfiles/bashrc;
      ".config/gdb/gdbinit".source = ./dotfiles/gdbinit;
      ".config/hypr" = {
        source = ./dotfiles/hypr;
        recursive = true;
      };
      ".config/nvim" = {
        source = ./dotfiles/nvim;
        recursive = true;
      };
    };
  };
}
