#!/usr/bin/env bash
set -euo pipefail

pushd ~/nixos/ >/dev/null

git pull
nvim configuration.nix

# Early exit if no changes detected in ANY files
if git diff --quiet; then
  echo "No changes detected—exiting."
  popd >/dev/null
  exit 0
fi

# (Optional) Format .nix files if you have a formatter installed
if command -v alejandra >/dev/null; then
  alejandra . &>/dev/null || {
    alejandra .
    echo "Formatting failed!"
    exit 1
  }
fi

git diff -U0

echo "Rebuilding NixOS..."
if ! sudo nixos-rebuild switch -I nixos-config=/home/mchoma/nixos/configuration.nix ; then
  grep --color error nixos-switch.log
  exit 1
fi

current=$(nixos-rebuild list-generations | grep current)
git commit -am "Rebuild succeeded — $current"
git push

popd >/dev/null

echo -e "NixOS Rebuild Successful"
