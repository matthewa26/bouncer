#!/usr/bin/env bash
# Runs Bouncer's Windows tests in a local QEMU Windows 11 ARM64 VM on an Apple Silicon Mac.
#
#   windows-vm.sh create <Windows11-arm64.iso>   one-time hands-off install and provisioning (hours)
#   windows-vm.sh test                           boot a throwaway copy, run every Windows test
#   windows-vm.sh reprovision                    re-run provisioning on the real disk after editing it
#   windows-vm.sh boot                           boot a throwaway copy in the background, for debugging
#   windows-vm.sh ssh [command]                  shell into a running VM
#   windows-vm.sh screenshot <file.png>          capture a running VM's screen, for debugging
#
# Needs: qemu and wimlib (brew install qemu wimlib). VM state lives in $BOUNCER_VM_DIR
# (~/.cache/bouncer-windows-vm).
# `test` runs with QEMU's -snapshot, so every run starts from the freshly provisioned disk.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
state=${BOUNCER_VM_DIR:-$HOME/.cache/bouncer-windows-vm}
ssh_port=${BOUNCER_VM_SSH_PORT:-2222}
qemu_share=$(dirname "$(dirname "$(command -v qemu-system-aarch64)")")/share/qemu
virtio_url=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
swift_version=6.4.2
pwsh_version=7.7.0
openssh_tag=10.4.0.0p1-Preview
openssh_version=10.4.0.0
git_tag=v2.56.1.windows.1
git_version=2.56.1

# Prints a message and exits non-zero.
die() { echo "windows-vm: $*" >&2; exit 1; }

# Prints QEMU's machine, firmware, disk, network, and monitor arguments shared by every boot.
qemu_args() {
  printf '%s\n' -M virt -accel hvf -cpu host -smp 6 -m 8G \
    -drive "if=pflash,format=raw,readonly=on,file=$qemu_share/edk2-aarch64-code.fd" \
    -drive "if=pflash,format=raw,file=$state/efivars.fd" \
    -device ramfb -device qemu-xhci -device usb-kbd -device usb-tablet \
    -device nvme,drive=disk,serial=bouncer -drive "if=none,id=disk,format=qcow2,file=$state/disk.qcow2" \
    -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$ssh_port-:22" \
    -monitor "unix:$state/monitor.sock,server,nowait" -display none
}

# Prints QEMU arguments attaching a read-only ISO as a USB drive.
usb_iso() {
  printf '%s\n' -device "usb-storage,drive=$1" -drive "if=none,id=$1,media=cdrom,readonly=on,file=$2"
}

# Sends one command to a running VM's QEMU monitor.
monitor() { printf '%s\n' "$1" | nc -U "$state/monitor.sock" >/dev/null 2>&1 || true; }

# Runs a command in the VM over SSH as the provisioned administrator.
vm_ssh() {
  ssh -i "$state/id_ed25519" -p "$ssh_port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR -o ConnectTimeout=5 bouncer@127.0.0.1 "$@"
}

# Waits up to $1 seconds for the VM's SSH server to accept a login.
wait_for_ssh() {
  local deadline=$((SECONDS + $1))
  until vm_ssh 'exit 0' 2>/dev/null; do
    [ "$SECONDS" -lt "$deadline" ] || die "SSH didn't come up within $1 seconds"
    sleep 10
  done
}

# Converts the Windows ISO into a FAT32 MBR disk image, so it attaches over NVMe instead of slow
# emulated USB; UEFI firmware boots FAT32, and install.wim is split into .swm pieces under 4 GB.
# MBR matters: a GPT image gets its own EFI System partition, and Setup refuses to install while it
# can see two on fixed disks.
build_install_disk() {
  local iso_mount disk_mount
  iso_mount=$(hdiutil attach -nobrowse -readonly "$1" | tail -1 | cut -f3)
  hdiutil create -quiet -size 10g -fs "MS-DOS FAT32" -layout MBRSPUD -volname WININSTALL "$state/install.dmg"
  disk_mount=$(hdiutil attach -nobrowse "$state/install.dmg" | tail -1 | cut -f3)
  rsync -r --exclude sources/install.wim "$iso_mount/" "$disk_mount/"
  wimlib-imagex split "$iso_mount/sources/install.wim" "$disk_mount/sources/install.swm" 3800 >/dev/null
  hdiutil detach -quiet "$disk_mount" && hdiutil detach -quiet "$iso_mount"
  hdiutil convert -quiet "$state/install.dmg" -format UDTO -o "$state/install.cdr"
  mv "$state/install.cdr" "$state/install.img" && rm "$state/install.dmg"
}

# Writes the config ISO: the answer file with a fresh password, the provisioning script, and the SSH key.
build_config_iso() {
  local staging="$state/config"
  rm -rf "$staging" && mkdir -p "$staging"
  sed "s/__PASSWORD__/$(cat "$state/password")/g" "$here/autounattend.xml" > "$staging/autounattend.xml"
  cp "$here/provision.ps1" "$staging/" && cp "$state/id_ed25519.pub" "$staging/authorized_keys"
  printf 'swift=%s\npwsh=%s\nopenssh_tag=%s\nopenssh=%s\ngit_tag=%s\ngit=%s\n' "$swift_version" \
    "$pwsh_version" "$openssh_tag" "$openssh_version" "$git_tag" "$git_version" > "$staging/versions.txt"
  rm -f "$state/config.iso"
  hdiutil makehybrid -quiet -iso -joliet -default-volume-name CONFIG -o "$state/config.iso" "$staging"
}

# Generates the VM's SSH key, account password, disk, and UEFI variable store.
create_state() {
  mkdir -p "$state" && chmod 700 "$state"
  [ -f "$state/virtio-win.iso" ] || curl -fL -o "$state/virtio-win.iso" "$virtio_url"
  [ -f "$state/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C bouncer-windows-vm -f "$state/id_ed25519"
  [ -f "$state/password" ] || (umask 077 && openssl rand -hex 12 > "$state/password")
  qemu-img create -q -f qcow2 "$state/disk.qcow2" 64G
  cp "$qemu_share/edk2-arm-vars.fd" "$state/efivars.fd" && chmod 600 "$state/efivars.fd"
}

# Installs Windows hands-off from the ISO and provisions it; the VM powers off when done.
create() {
  [ -n "${1:-}" ] && [ -f "$1" ] || die "usage: windows-vm.sh create <Windows11-arm64.iso>"
  [ ! -f "$state/disk.qcow2" ] || die "a VM already exists in $state; delete it to start over"
  create_state
  build_config_iso
  [ -f "$state/install.img" ] || build_install_disk "$1"
  echo "Installing and provisioning Windows; watch with: windows-vm.sh screenshot shot.png"
  run_installer
  check_provisioned
}

# Boots with the install disk, virtio drivers, and config ISO attached; returns when provisioning powers off.
run_installer() {
  # Copy-on-write, not read-only: Windows writes to fixed NVMe disks and drops one that refuses writes.
  local install="if=none,id=install,format=raw,snapshot=on,file=$state/install.img"
  # shellcheck disable=SC2046
  qemu-system-aarch64 $(qemu_args) -device nvme,drive=install,serial=install -drive "$install" \
    $(usb_iso virtio "$state/virtio-win.iso") $(usb_iso config "$state/config.iso")
}

# Boots the provisioned disk once to confirm provisioning succeeded, then marks the VM ready.
check_provisioned() {
  boot_snapshot
  trap shutdown_vm EXIT
  wait_for_ssh 600
  vm_ssh 'if (Test-Path C:\provision.done) { exit 0 } else { Get-Content C:\provision.log -Tail 40; exit 1 }' \
    || die "provisioning failed; see the log above"
  touch "$state/ready"
  echo "VM ready. Run: windows-vm.sh test"
}

# Re-runs the current provisioning script on the real disk, for changes made after `create`.
# Provisioning skips finished steps, so this only does what's new, then powers the VM off.
reprovision() {
  [ -f "$state/disk.qcow2" ] || die "no VM; run: windows-vm.sh create <iso>"
  build_config_iso
  # shellcheck disable=SC2046
  qemu-system-aarch64 $(qemu_args) -daemonize -pidfile "$state/qemu.pid"
  trap shutdown_vm EXIT
  wait_for_ssh 600
  push_and_run_provisioning
  while kill -0 "$(cat "$state/qemu.pid" 2>/dev/null)" 2>/dev/null; do sleep 5; done
  check_provisioned
}

# Copies the current provisioning files into a running VM and runs them; the VM powers off when done.
push_and_run_provisioning() {
  # Files copied from the config ISO keep its read-only attribute.
  vm_ssh 'attrib -r C:\provision\*'
  scp_to "$state/config/provision.ps1" "$state/config/versions.txt" C:/provision/
  vm_ssh 'Remove-Item C:\provision.done -ErrorAction SilentlyContinue' \
    '; powershell -NoProfile -ExecutionPolicy Bypass -File C:\provision\provision.ps1' || true
}

# Copies local files into the VM with scp; the last argument is the destination path.
scp_to() {
  scp -q -i "$state/id_ed25519" -P "$ssh_port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${@:1:$#-1}" "bouncer@127.0.0.1:${!#}"
}

# Boots the VM in the background with -snapshot, so nothing it writes reaches the disk image.
boot_snapshot() {
  # shellcheck disable=SC2046
  qemu-system-aarch64 $(qemu_args) -snapshot -daemonize -pidfile "$state/qemu.pid"
}

# Shuts the VM down over SSH, falling back to QEMU's power button, and waits for QEMU to exit.
shutdown_vm() {
  vm_ssh 'Stop-Computer -Force' 2>/dev/null || monitor 'system_powerdown'
  for _ in $(seq 60); do
    [ -f "$state/qemu.pid" ] && kill -0 "$(cat "$state/qemu.pid")" 2>/dev/null || return 0
    sleep 2
  done
  monitor 'quit'
}

# Copies the working tree into a throwaway VM, runs every Windows test, and returns their result.
run_tests() {
  [ -f "$state/ready" ] || die "no provisioned VM; run: windows-vm.sh create <iso>"
  boot_snapshot
  trap shutdown_vm EXIT
  wait_for_ssh 600
  (cd "$repo" && git ls-files -co --exclude-standard -z | tar --null -T - -czf "$state/checkout.tar.gz")
  scp_to "$state/checkout.tar.gz" C:/checkout.tar.gz
  vm_ssh 'New-Item -ItemType Directory -Force C:\bouncer | Out-Null; tar -xzf C:\checkout.tar.gz -C C:\bouncer'
  vm_ssh 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\bouncer\Scripts\windows-vm\run-tests.ps1'
}

case "${1:-}" in
  create) create "${2:-}" ;;
  test) run_tests ;;
  boot) boot_snapshot ;;
  reprovision) reprovision ;;
  ssh) shift; vm_ssh "$@" ;;
  screenshot)
    monitor "screendump $state/screen.ppm" && sleep 1
    sips -s format png "$state/screen.ppm" --out "${2:?usage: windows-vm.sh screenshot <file.png>}" >/dev/null ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
