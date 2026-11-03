#!/usr/bin/env bash
# Turn a Minimal archinstall into the Hyprland desktop. Safe to re-run.
#
# Run as root, either:
#   - from the live ISO after archinstall exits:  arch-chroot /mnt bash /root/setup.sh
#   - on the installed system:                    sudo ./setup.sh
#
# The autologin user defaults to the first regular user (UID 1000);
# override with SETUP_USER=name.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo ./setup.sh)" >&2; exit 1; }

user=${SETUP_USER:-$(getent passwd 1000 | cut -d: -f1)}
[[ -n $user ]] || { echo "No user with UID 1000; set SETUP_USER" >&2; exit 1; }

packages=(
  # Hyprland desktop (archinstall's Hyprland profile, with mako instead of dunst)
  hyprland
  uwsm
  xdg-desktop-portal-hyprland
  qt5-wayland
  qt6-wayland
  polkit
  polkit-kde-agent
  kitty
  wofi
  dolphin
  grim
  slurp

  # Notifications
  mako
  libnotify

  # Login
  sddm

  # Base utilities (from archinstall's Desktop profile)
  openssh
  htop
  wget
  smartmontools
  xdg-utils

  # Apps
  firefox
  neovim
)

services=(
  sddm
)

pacman -Syu --needed --noconfirm "${packages[@]}"
systemctl enable "${services[@]}"

# SDDM autologin straight into Hyprland, launched via UWSM.
install -Dm644 /dev/stdin /etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=$user
Session=hyprland-uwsm.desktop
EOF

echo "setup.sh: done (autologin user: $user)"
