#!/usr/bin/env bash
# Create a fresh libvirt VM from the Arch ISO and have the live environment
# start archinstall with this repo's user_configuration.json automatically.
#
# Usage: ./vm-install.sh [-f] [name]
#   -f    delete an existing VM with the same name (and its disk) first
#   name  VM name (default: archtest)
#
# Env overrides: ISO, DISK_GB, RAM_MB, CPUS
#
# One-time host setup (ufw blocks the VM from reaching the config server):
#   sudo ufw allow in on virbr0 to any port 8000 proto tcp
set -euo pipefail

force=0
if [[ ${1:-} == -f ]]; then force=1; shift; fi
name=${1:-archtest}

export LIBVIRT_DEFAULT_URI=qemu:///system
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
iso=${ISO:-$(ls -t "$HOME"/Downloads/archlinux-*-x86_64.iso 2>/dev/null | head -1)}
host_ip=192.168.122.1   # libvirt "default" network bridge (virbr0)
port=8000

[[ -f $iso ]] || { echo "No Arch ISO found; set ISO=/path/to.iso" >&2; exit 1; }
label=$(blkid -o value -s LABEL "$iso")

if virsh dominfo "$name" &>/dev/null; then
  if (( force )); then
    virsh destroy "$name" &>/dev/null || true
    virsh undefine "$name" --remove-all-storage --nvram >/dev/null
  else
    echo "VM '$name' already exists; rerun with -f to replace it." >&2
    exit 1
  fi
fi

# Serve the config plus a boot script. archiso's script= kernel parameter makes
# the live ISO download and run that script on tty1 after autologin.
serve=$(mktemp -d)
cp "$repo/user_configuration.json" "$serve/"
cat >"$serve/install.sh" <<EOF
#!/bin/bash
url=http://$host_ip:$port/user_configuration.json
for _ in \$(seq 30); do
  curl -fsS -o /root/user_configuration.json "\$url" && break
  sleep 2
done
if [[ ! -s /root/user_configuration.json ]]; then
  echo "!! Could not fetch \$url"
  echo "!! On the host: sudo ufw allow in on virbr0 to any port $port proto tcp"
  exit 1
fi
archinstall --config /root/user_configuration.json
EOF
python3 -m http.server "$port" --bind "$host_ip" --directory "$serve" &>/dev/null &
server_pid=$!
trap 'kill $server_pid 2>/dev/null; rm -rf "$serve"' EXIT

# Open the console once the VM is defined.
( sleep 3; virt-manager --connect "$LIBVIRT_DEFAULT_URI" --show-domain-console "$name" ) &>/dev/null &

# --location boots the ISO's kernel directly so we can pass kernel args; after
# the installer reboots, libvirt switches the VM to boot from its disk.
virt-install \
  --name "$name" \
  --osinfo archlinux \
  --memory "${RAM_MB:-8192}" --vcpus "${CPUS:-8}" \
  --disk size="${DISK_GB:-40}",format=qcow2,bus=virtio \
  --network network=default \
  --graphics spice \
  --location "$iso",kernel=arch/boot/x86_64/vmlinuz-linux,initrd=arch/boot/x86_64/initramfs-linux.img \
  --extra-args "archisobasedir=arch archisolabel=$label script=http://$host_ip:$port/install.sh" \
  --noautoconsole --wait -1

echo "Install finished; VM '$name' now boots from its disk."
