#!/usr/bin/env bash
# Generate /etc/nixos/boot-device for a machine so a shared NixOS config
# can install the correct bootloader (UEFI or BIOS) and target device.
#
# Output format written to /etc/nixos/boot-device:
#  - UEFI:/dev/disk/by-uuid/<UUID>     (recommended for UEFI)
#  - /dev/disk/by-id/...               (recommended for BIOS whole-disk)
#  - /dev/sda                          (fallback for BIOS)
#
# Usage:
#  sudo ./generate-boot-device.sh         # write file (asks for confirmation)
#  sudo ./generate-boot-device.sh --yes   # write file without prompt
#  ./generate-boot-device.sh --dry-run    # print chosen value, do not write
#
set -euo pipefail

DEVICE_FILE="$HOME/nixos/boot-device"
DRY_RUN=0
ASSUME_YES=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --help|-h)
      cat <<EOF
Usage: $0 [--dry-run] [--yes]
Generates ${DEVICE_FILE} containing either:
  UEFI:/dev/disk/by-uuid/<UUID>  - for UEFI systems (ESP)
  /dev/disk/by-id/<...>          - for BIOS systems (whole disk)
If run without --dry-run the script will write the file (requires root).
EOF
      exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

command_exists() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (or with sudo)." >&2
    exit 1
  fi
}

# prefer stable path by-id if available, otherwise fall back to raw device path
prefer_by_id() {
  local dev="$1"
  # iterate through by-id links to find a match
  for idpath in /dev/disk/by-id/*; do
    [ -e "$idpath" ] || continue
    if [ "$(readlink -f "$idpath")" = "$dev" ]; then
      echo "$idpath"
      return 0
    fi
  done
  # fallback to by-uuid if it exists
  if command_exists blkid; then
    local uuid
    uuid="$(blkid -s UUID -o value "$dev" 2>/dev/null || true)"
    if [ -n "$uuid" ]; then
      echo "/dev/disk/by-uuid/$uuid"
      return 0
    fi
  fi
  # fallback to raw device
  echo "$dev"
  return 0
}

choose_uefi_esp() {
  # Return the device node (e.g. /dev/nvme0n1p1) of the chosen ESP, or empty
  local dev=""
  # 1) prefer mounted /boot or /boot/efi if it's vfat
  if command_exists findmnt && command_exists blkid; then
    for mp in /boot /boot/efi; do
      if findmnt -n -o SOURCE --target "$mp" >/dev/null 2>&1; then
        local src
        src="$(findmnt -n -o SOURCE --target "$mp" || true)"
        if [ -n "$src" ] && [ -b "$src" ]; then
          if blkid -s TYPE -o value "$src" 2>/dev/null | grep -qi vfat; then
            echo "$src"
            return 0
          fi
        fi
      fi
    done
  fi

  # 2) prefer partitions with PARTFLAGS 'esp'
  if command_exists blkid && command_exists lsblk; then
    for p in $(blkid -t TYPE=vfat -o device 2>/dev/null || true); do
      [ -b "$p" ] || continue
      partflags="$(lsblk -no PARTFLAGS "$p" 2>/dev/null || true)"
      if printf '%s\n' "$partflags" | grep -iq esp; then
        echo "$p"
        return 0
      fi
    done
  fi

  # 3) fallback to first vfat partition
  if command_exists blkid; then
    local first
    first="$(blkid -t TYPE=vfat -o device 2>/dev/null | head -n1 || true)"
    if [ -n "$first" ]; then
      echo "$first"
      return 0
    fi
  fi

  # nothing found
  echo ""
  return 1
}

choose_bios_disk() {
  # Return whole-disk device node (e.g. /dev/sda or /dev/nvme0n1)
  # 1) identify the device that holds /
  local src
  if command_exists findmnt; then
    src="$(findmnt -n -o SOURCE / || true)"
  else
    src="$(mount | awk '$3=="/"{print $1; exit}' || true)"
  fi

  if [ -z "$src" ]; then
    echo ""
    return 1
  fi

  # if src is a loop or mapper, try to find the underlying partition
  if [ -b "$src" ]; then
    # try to get parent block device (PKNAME)
    if command_exists lsblk; then
      # PKNAME gives the "parent" block device name (e.g., nvme0n1 for nvme0n1p3)
      pkname="$(lsblk -no PKNAME "$src" 2>/dev/null || true)"
      if [ -n "$pkname" ]; then
        echo "/dev/$pkname"
        return 0
      fi
      # For devices like /dev/mapper/*, find the block device that is an ancestor:
      # lsblk -no NAME,TYPE -r /dev/mapper/whatever  and pick the first "disk" parent.
      # We inspect lsblk (tree) and find the top-level disk that contains this node.
      # Use lsblk -nr -o NAME,TYPE to walk up:
      ancestor="$(lsblk -nr -o NAME,TYPE "$src" 2>/dev/null | awk '$2=="disk"{print $1; exit}' || true)"
      if [ -n "$ancestor" ]; then
        echo "/dev/$ancestor"
        return 0
      fi
    fi
    # if not able via lsblk, try heuristics: strip partition number suffixes
    # e.g. /dev/sda2 -> /dev/sda ; /dev/nvme0n1p7 -> /dev/nvme0n1
    if [[ "$src" =~ ^(/dev/[a-z]+)([0-9]+)$ ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    elif [[ "$src" =~ ^(/dev/nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
  fi

  # If src is not a block device path, or heuristics fail, try listing non-removable disks
  if command_exists lsblk; then
    disks="$(lsblk -ndo NAME,TYPE,RM | awk '$2=="disk" && $3==0 {print "/dev/"$1}')"
    # if only one candidate, pick it
    if [ "$(wc -w <<<"$disks")" -eq 1 ]; then
      echo "$disks"
      return 0
    fi
    # prefer disk containing root (search tree)
    for d in $disks; do
      # check if any partition of $d is mounted on /
      if lsblk -nr -o MOUNTPOINT "${d}"* 2>/dev/null | grep -q '^/$'; then
        echo "$d"
        return 0
      fi
    done
    # fallback to first non-removable disk
    first="$(awk '$2=="disk" && $3==0 {print "/dev/"$1; exit}' /proc/partitions 2>/dev/null || true)"
    if [ -n "$first" ]; then
      echo "$first"
      return 0
    fi
  fi

  echo ""
  return 1
}

main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Warning: not running as root. You may need sudo to write ${DEVICE_FILE}." >&2
  fi

  local is_uefi=0
  [ -d /sys/firmware/efi ] && is_uefi=1

  if [ "$is_uefi" -eq 1 ]; then
    echo "Detected platform: UEFI"
    esp="$(choose_uefi_esp || true)"
    if [ -n "$esp" ]; then
      # prefer stable by-uuid/by-id
      if command_exists blkid; then
        uuid="$(blkid -s UUID -o value "$esp" 2>/dev/null || true)"
      else
        uuid=""
      fi
      if [ -n "$uuid" ]; then
        target="UEFI:/dev/disk/by-uuid/$uuid"
      else
        # try by-id path for the specific partition
        idpath="$(prefer_by_id "$esp")"
        target="UEFI:$idpath"
      fi
      echo "Chosen ESP: $esp"
      echo "Writing: $target"
    else
      echo "No ESP (vfat) partition found automatically." >&2
      echo "You should create ${DEVICE_FILE} manually with: UEFI:/dev/disk/by-uuid/<UUID> or UEFI:/dev/nvme0n1p1" >&2
      exit 2
    fi
  else
    echo "Detected platform: BIOS (legacy)"
    disk="$(choose_bios_disk || true)"
    if [ -z "$disk" ]; then
      echo "Could not reliably determine BIOS disk. Defaulting to /dev/sda" >&2
      disk="/dev/sda"
    fi
    # prefer by-id
    idpath="$(prefer_by_id "$disk")"
    target="$idpath"
    echo "Chosen BIOS disk: $disk"
    echo "Writing: $target"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY RUN: would write to ${DEVICE_FILE}:"
    echo "$target"
    exit 0
  fi

  if [ "$ASSUME_YES" -ne 1 ]; then
    read -rp "Write '${target}' into ${DEVICE_FILE}? [y/N] " ans
    case "$ans" in
      y|Y|yes|YES) : ;;
      *) echo "Aborted."; exit 1;;
    esac
  fi

  # ensure directory exists
  dirname="$(dirname "$DEVICE_FILE")"
  mkdir -p "$dirname"
  echo "$target" > "$DEVICE_FILE"
  chmod 0644 "$DEVICE_FILE"
  echo "Wrote $DEVICE_FILE -> $target"
  echo "You can now run: sudo nixos-rebuild switch -I nixos-config=\$HOME/nixos/configuration.nix --install-bootloader"
}

main "$@"
