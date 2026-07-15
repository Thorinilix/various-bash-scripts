#!/usr/bin/env bash
#
# make_bootable_usb.sh
#
# Writes an ISO/IMG file to a USB drive using dd, creating a bootable USB.
#
# USAGE:
#   sudo ./make_bootable_usb.sh -i /path/to/image.iso -d /dev/sdX
#
# OPTIONS:
#   -i    Path to the source ISO/IMG file (required)
#   -d    Target device, e.g. /dev/sdb (required) - NOT a partition like /dev/sdb1
#   -b    Block size for dd (default: 4M)
#   -y    Skip confirmation prompt (use with caution)
#   -h    Show this help message
#
# WARNING: This will ERASE ALL DATA on the target device. Double-check the
# device path before confirming. Writing to the wrong device can destroy
# your operating system or other important data.

set -euo pipefail

BLOCK_SIZE="4M"
SKIP_CONFIRM=false
IMAGE=""
DEVICE=""

usage() {
    grep '^#' "$0" | sed 's/^#//; s/^ //' | sed -n '2,20p'
    exit 1
}

while getopts "i:d:b:yh" opt; do
    case "$opt" in
        i) IMAGE="$OPTARG" ;;
        d) DEVICE="$OPTARG" ;;
        b) BLOCK_SIZE="$OPTARG" ;;
        y) SKIP_CONFIRM=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# --- Validation -------------------------------------------------------

if [[ -z "$IMAGE" || -z "$DEVICE" ]]; then
    echo "Error: both -i (image) and -d (device) are required." >&2
    usage
fi

if [[ $EUID -ne 0 ]]; then
    echo "Error: this script must be run as root (use sudo)." >&2
    exit 1
fi

if [[ ! -f "$IMAGE" ]]; then
    echo "Error: image file '$IMAGE' not found." >&2
    exit 1
fi

if [[ ! -b "$DEVICE" ]]; then
    echo "Error: '$DEVICE' is not a valid block device." >&2
    exit 1
fi

# Refuse to target a partition (e.g. /dev/sdb1) - we want the whole disk
if [[ "$DEVICE" =~ [0-9]+$ ]]; then
    echo "Error: '$DEVICE' looks like a partition, not a whole disk." >&2
    echo "Target the whole device instead, e.g. /dev/sdb rather than /dev/sdb1." >&2
    exit 1
fi

# Try to detect if the target device is the boot/root disk and refuse
ROOT_DEV="$(findmnt -no SOURCE / 2>/dev/null || true)"
if [[ -n "$ROOT_DEV" ]]; then
    ROOT_DISK="$(lsblk -no PKNAME "$ROOT_DEV" 2>/dev/null || true)"
    if [[ -n "$ROOT_DISK" && "/dev/$ROOT_DISK" == "$DEVICE" ]]; then
        echo "Error: '$DEVICE' appears to be your system disk. Refusing to proceed." >&2
        exit 1
    fi
fi

# --- Show device info before proceeding --------------------------------

echo "=============================================="
echo " Bootable USB Creator"
echo "=============================================="
echo "Source image : $IMAGE"
IMAGE_SIZE_BYTES=$(stat -c%s "$IMAGE" 2>/dev/null || stat -f%z "$IMAGE")
echo "Image size   : $(numfmt --to=iec-i --suffix=B "$IMAGE_SIZE_BYTES" 2>/dev/null || echo "${IMAGE_SIZE_BYTES} bytes")"
echo "Target device: $DEVICE"
echo "Block size   : $BLOCK_SIZE"
echo
echo "Device details:"
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT "$DEVICE" 2>/dev/null || true
echo "=============================================="
echo

DEVICE_SIZE_BYTES=$(blockdev --getsize64 "$DEVICE" 2>/dev/null || echo 0)
if [[ "$DEVICE_SIZE_BYTES" -gt 0 && "$IMAGE_SIZE_BYTES" -gt "$DEVICE_SIZE_BYTES" ]]; then
    echo "Error: image ($IMAGE_SIZE_BYTES bytes) is larger than target device ($DEVICE_SIZE_BYTES bytes)." >&2
    exit 1
fi

# --- Confirmation --------------------------------------------------------

if [[ "$SKIP_CONFIRM" != true ]]; then
    echo "!!! WARNING !!!"
    echo "This will PERMANENTLY ERASE ALL DATA on $DEVICE."
    echo
    read -r -p "Type the device path again to confirm ($DEVICE): " CONFIRM_DEVICE
    if [[ "$CONFIRM_DEVICE" != "$DEVICE" ]]; then
        echo "Confirmation did not match. Aborting." >&2
        exit 1
    fi
fi

# --- Unmount any mounted partitions on the target device -----------------

echo "Unmounting any mounted partitions on $DEVICE..."
for part in $(lsblk -lno NAME "$DEVICE" | tail -n +2); do
    MOUNTPOINT="/dev/$part"
    if mount | grep -q "^$MOUNTPOINT "; then
        umount "$MOUNTPOINT" || {
            echo "Error: failed to unmount $MOUNTPOINT" >&2
            exit 1
        }
    fi
done

# --- Write the image -------------------------------------------------------

echo
echo "Writing image to device. This may take several minutes..."
echo "(Press Ctrl+T during the write if your dd supports SIGINFO/status updates.)"
echo

if dd if="$IMAGE" of="$DEVICE" bs="$BLOCK_SIZE" status=progress conv=fsync; then
    echo
    echo "Write complete. Syncing..."
    sync
    echo "Done. It is now safe to remove $DEVICE (after unplugging)."
else
    echo "Error: dd command failed." >&2
    exit 1
fi