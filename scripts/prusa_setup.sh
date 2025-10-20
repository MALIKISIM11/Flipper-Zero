#!/usr/bin/env bash
set -Eeuo pipefail

# Prusa USB/serial setup and recovery script
# - Resets USB controller (briefly disconnects USB devices)
# - Disables USB autosuspend
# - Adds udev rules for Prusa printers and ModemManager ignore
# - Adds your user to serial groups (dialout/uucp/tty/lock/plugdev as available)
# - Installs PrusaSlicer via native package or Flatpak fallback
#
# Usage examples:
#   sudo bash scripts/prusa_setup.sh              # do everything automatically
#   sudo bash scripts/prusa_setup.sh --no-slicer  # skip installing PrusaSlicer
#   sudo bash scripts/prusa_setup.sh --disable-modemmanager # stop/disable ModemManager service
#   sudo bash scripts/prusa_setup.sh --slicer=flatpak        # force Flatpak method
#

if [[ $EUID -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

readonly REAL_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "${USER}")}
readonly SCRIPT_NAME="$(basename "$0")"

log() { printf "\e[1;32m[%s]\e[0m %s\n" "$SCRIPT_NAME" "$*"; }
warn() { printf "\e[1;33m[%s]\e[0m %s\n" "$SCRIPT_NAME" "$*"; }
err() { printf "\e[1;31m[%s]\e[0m %s\n" "$SCRIPT_NAME" "$*"; }

HAVE_CMD() { command -v "$1" >/dev/null 2>&1; }

DO_RESET=1
DO_UDEV=1
DO_GROUPS=1
DO_SLICER=1
DISABLE_MM=0
SLICER_METHOD="auto" # auto|pkg|flatpak|appimage

for arg in "$@"; do
  case "$arg" in
    --no-reset|--skip-reset) DO_RESET=0 ;;
    --no-udev|--skip-udev) DO_UDEV=0 ;;
    --no-groups|--skip-groups) DO_GROUPS=0 ;;
    --no-slicer|--skip-slicer) DO_SLICER=0 ;;
    --disable-modemmanager) DISABLE_MM=1 ;;
    --slicer=*) SLICER_METHOD="${arg#*=}" ;;
    -h|--help)
      cat <<EOF
Prusa USB/serial setup and recovery

Options:
  --no-reset, --skip-reset        Skip USB controller reset
  --no-udev, --skip-udev          Skip udev rules creation
  --no-groups, --skip-groups      Skip adding user to serial groups
  --no-slicer, --skip-slicer      Skip installing PrusaSlicer
  --disable-modemmanager          Stop/disable ModemManager service (optional)
  --slicer=<auto|pkg|flatpak|appimage>  Choose installation method for PrusaSlicer
  -h, --help                      Show this help
EOF
      exit 0
      ;;
    *) warn "Ignoring unknown option: $arg" ;;
  esac
done

get_primary_serial_group() {
  local candidates=(dialout uucp tty plugdev lock)
  local g
  for g in "${candidates[@]}"; do
    if getent group "$g" >/dev/null; then
      echo "$g"
      return 0
    fi
  done
  # Fallback
  echo "dialout"
}

add_user_to_serial_groups() {
  local -a groups_to_try=(dialout uucp tty plugdev lock)
  local g added=0
  for g in "${groups_to_try[@]}"; do
    if getent group "$g" >/dev/null; then
      if id -nG "$REAL_USER" | tr ' ' '\n' | grep -Fxq "$g"; then
        log "User '$REAL_USER' already in group '$g'"
      else
        log "Adding user '$REAL_USER' to group '$g'"
        usermod -aG "$g" "$REAL_USER" || warn "Failed to add $REAL_USER to $g"
        added=1
      fi
    fi
  done
  if [[ "$added" == "1" ]]; then
    warn "You must log out and back in (or reboot) for new group membership to take effect."
  fi
}

reset_usb_controller() {
  log "Disabling USB autosuspend on all devices"
  shopt -s nullglob
  for p in /sys/bus/usb/devices/*/power/control; do
    echo on >"$p" 2>/dev/null || true
  done
  shopt -u nullglob

  log "Reloading xHCI PCI driver (USB3 controller)"
  modprobe -r xhci_pci 2>/dev/null || true
  sleep 1
  modprobe xhci_pci 2>/dev/null || true

  # Additional unbind/rebind of xhci_hcd/xhci_pci if available
  local drv
  for drv in xhci_hcd xhci_pci; do
    if [[ -d "/sys/bus/pci/drivers/$drv" ]]; then
      log "Unbinding/binding controllers under $drv"
      local d path
      for path in "/sys/bus/pci/drivers/$drv"/*:*; do
        [[ -e "$path" && -L "$path" ]] || continue
        d="${path##*/}"
        echo "$d" >"/sys/bus/pci/drivers/$drv/unbind" 2>/dev/null || true
        sleep 0.2
        echo "$d" >"/sys/bus/pci/drivers/$drv/bind" 2>/dev/null || true
      done
    fi
  done
}

pkg_manager=""

detect_pkg_manager() {
  if HAVE_CMD apt-get; then pkg_manager=apt; return; fi
  if HAVE_CMD dnf; then pkg_manager=dnf; return; fi
  if HAVE_CMD pacman; then pkg_manager=pacman; return; fi
  if HAVE_CMD zypper; then pkg_manager=zypper; return; fi
  pkg_manager=unknown
}

pkg_install() {
  local pkg="$1"
  case "$pkg_manager" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get update -y || true
      DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" || return 1
      ;;
    dnf)
      dnf install -y "$pkg" || return 1
      ;;
    pacman)
      pacman -Sy --noconfirm "$pkg" || return 1
      ;;
    zypper)
      zypper --non-interactive install -y "$pkg" || return 1
      ;;
    *) return 1 ;;
  esac
}

ensure_usbutils() {
  if HAVE_CMD lsusb; then return 0; fi
  detect_pkg_manager
  log "Installing usbutils (lsusb)"
  pkg_install usbutils || warn "Failed to install usbutils; continuing."
}

ensure_flatpak() {
  if HAVE_CMD flatpak; then return 0; fi
  detect_pkg_manager
  log "Installing Flatpak"
  pkg_install flatpak || return 1
}

install_prusaslicer_pkg() {
  detect_pkg_manager
  log "Installing PrusaSlicer via package manager ($pkg_manager)"
  case "$pkg_manager" in
    apt)
      pkg_install prusa-slicer || return 1
      ;;
    dnf)
      pkg_install prusa-slicer || return 1
      ;;
    pacman)
      pkg_install prusa-slicer || return 1
      ;;
    zypper)
      pkg_install prusa-slicer || return 1
      ;;
    *) return 1 ;;
  esac
}

install_prusaslicer_flatpak() {
  ensure_flatpak || return 1
  if ! flatpak remotes | grep -q '^flathub'; then
    log "Adding Flathub remote"
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
  fi
  log "Installing PrusaSlicer Flatpak"
  flatpak install -y flathub com.prusa3d.PrusaSlicer || return 1
}

install_prusaslicer() {
  case "$SLICER_METHOD" in
    pkg)
      install_prusaslicer_pkg || { err "Package install failed"; return 1; }
      ;;
    flatpak)
      install_prusaslicer_flatpak || { err "Flatpak install failed"; return 1; }
      ;;
    appimage)
      warn "AppImage method not implemented; using Flatpak fallback"
      install_prusaslicer_flatpak || install_prusaslicer_pkg || return 1
      ;;
    auto|*)
      if install_prusaslicer_pkg; then return 0; fi
      warn "Native package not available; trying Flatpak"
      install_prusaslicer_flatpak || return 1
      ;;
  esac
}

collect_prusa_vidpids() {
  # Prints unique lines: VID PID (space-separated) for connected devices likely to be Prusa
  ensure_usbutils || true
  local found=0
  if HAVE_CMD lsusb; then
    # Try lsusb vendor string matching
    while read -r line; do
      # Example: Bus 001 Device 006: ID 2c99:0002 Prusa Research, s.r.o.
      if grep -iq "prusa" <<<"$line"; then
        local id
        id=$(sed -nE 's/.* ID ([0-9a-fA-F]{4}):([0-9a-fA-F]{4}).*/\1 \2/p' <<<"$line" || true)
        if [[ -n "$id" ]]; then echo "$id"; found=1; fi
      fi
    done < <(lsusb || true)
  fi

  # Also query tty devices via udevadm for vendor hints
  shopt -s nullglob
  local dev props vid pid
  for dev in /dev/ttyACM* /dev/ttyUSB*; do
    props=$(udevadm info -q property -n "$dev" 2>/dev/null || true)
    if grep -iqE '^ID_VENDOR=.*prusa|^ID_VENDOR_FROM_DATABASE=.*prusa' <<<"$props"; then
      vid=$(sed -nE 's/^ID_VENDOR_ID=([0-9a-fA-F]{4})/\1/p' <<<"$props" | head -n1)
      pid=$(sed -nE 's/^ID_MODEL_ID=([0-9a-fA-F]{4})/\1/p' <<<"$props" | head -n1)
      if [[ -n "$vid" && -n "$pid" ]]; then echo "$vid $pid"; found=1; fi
    fi
  done
  shopt -u nullglob

  return 0
}

write_udev_rules() {
  local rules_file="/etc/udev/rules.d/80-prusa.rules"
  local primary_group
  primary_group=$(get_primary_serial_group)
  log "Primary serial group detected: $primary_group"

  local tmp
  tmp=$(mktemp)
  {
    echo "# Prusa printer udev rules"
    echo "# Generated by $SCRIPT_NAME on $(date -Is)"
    echo "# Ensures stable access, proper permissions, and avoids ModemManager probing"

    # Device-specific rules based on current connections
    local seen=()
    local vid pid key
    while read -r vid pid; do
      key="$vid:$pid"
      if printf '%s\n' "${seen[@]}" | grep -Fxq "$key"; then continue; fi
      seen+=("$key")
      echo "SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"$vid\", ATTRS{idProduct}==\"$pid\", GROUP=\"$primary_group\", MODE=\"0660\", TAG+=\"uaccess\", ENV{ID_MM_DEVICE_IGNORE}=\"1\", SYMLINK+=\"prusa-%k\""
    done < <(collect_prusa_vidpids | sort -u)

    # Generic matches by manufacturer (safe, specific)
    echo "SUBSYSTEM==\"tty\", ATTRS{manufacturer}==\"Prusa Research\", GROUP=\"$primary_group\", MODE=\"0660\", TAG+=\"uaccess\", ENV{ID_MM_DEVICE_IGNORE}=\"1\", SYMLINK+=\"prusa-%k\""
    echo "SUBSYSTEM==\"tty\", ATTRS{product}==\"*Prusa*\", GROUP=\"$primary_group\", MODE=\"0660\", TAG+=\"uaccess\", ENV{ID_MM_DEVICE_IGNORE}=\"1\", SYMLINK+=\"prusa-%k\""
  } >"$tmp"

  if [[ -s "$rules_file" ]]; then
    if ! cmp -s "$tmp" "$rules_file"; then
      log "Updating existing $rules_file (backup saved)"
      cp -a "$rules_file"{".bak.$(date +%s)",} || true
      mv "$tmp" "$rules_file"
    else
      log "Udev rules unchanged"
      rm -f "$tmp"
    fi
  else
    log "Writing $rules_file"
    mv "$tmp" "$rules_file"
  fi

  log "Reloading udev rules and triggering tty devices"
  udevadm control --reload-rules || true
  udevadm trigger -s tty || true
}

maybe_disable_modemmanager() {
  if systemctl list-unit-files | grep -q '^ModemManager.service'; then
    if [[ "$DISABLE_MM" == "1" ]]; then
      warn "Disabling ModemManager service per request"
      systemctl stop ModemManager || true
      systemctl disable ModemManager || true
      systemctl mask ModemManager || true
    else
      log "ModemManager detected; udev rules will mark Prusa devices to be ignored by it"
    fi
  fi
}

main() {
  log "Starting Prusa USB/serial setup for user '$REAL_USER'"

  if [[ "$DO_RESET" == "1" ]]; then
    reset_usb_controller || warn "USB reset encountered issues"
  else
    warn "Skipping USB reset as requested"
  fi

  if [[ "$DO_UDEV" == "1" ]]; then
    write_udev_rules || warn "Failed to write udev rules"
  else
    warn "Skipping udev rules as requested"
  fi

  maybe_disable_modemmanager

  if [[ "$DO_GROUPS" == "1" ]]; then
    add_user_to_serial_groups || warn "Failed to adjust user groups"
  else
    warn "Skipping group changes as requested"
  fi

  if [[ "$DO_SLICER" == "1" ]]; then
    if install_prusaslicer; then
      log "PrusaSlicer installed successfully"
    else
      warn "PrusaSlicer installation failed (both native and Flatpak attempts)."
    fi
  else
    warn "Skipping PrusaSlicer installation as requested"
  fi

  log "Done. If you were added to new groups, log out/in."
  log "If the printer was connected, unplug and replug its USB cable now."
  log "You should see a stable symlink like /dev/prusa-ttyACM0 when connected."
}

main "$@"
