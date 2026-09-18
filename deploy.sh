#!/usr/bin/env bash
set -euo pipefail

REMOTE_SSH=${REMOTE_SSH:-remote}
REMOTE_PATH=${REMOTE_PATH:-/var/www/display}
PACKAGE_NAME=${PACKAGE_NAME:-xibo-client.tar.gz}
SSH_USER=${SUDO_USER:-${USER:-root}}

XIBO_IMG_DIR=${XIBO_IMG_DIR:-/opt/xibo-img}
DEBIAN_MAJOR=${DEBIAN_MAJOR:-13}
DEBIAN_NETINST_BASE=${DEBIAN_NETINST_BASE:-https://cdimage.debian.org/debian-cd/current/amd64/iso-cd}
USB_MOUNT=${USB_MOUNT:-}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS_DIR="$ROOT_DIR/rootfs"
AUTO_DIR="$ROOT_DIR/auto"
VENTOY_DIR="$ROOT_DIR/ventoy"
VENTOY_FILE="$VENTOY_DIR/ventoy.json"
XIBO_AUTO_FILE="$AUTO_DIR/xibo-auto.cfg"
XIBO_GRUB_FILE="$AUTO_DIR/xibo-grub.cfg"
SECRETS_FILE=${XIBO_SECRETS_FILE:-$ROOT_DIR/xibo.env}
OUTPUT_DIR="/tmp/output"
PACKAGE_FILE="$OUTPUT_DIR/$PACKAGE_NAME"

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[FAIL] Missing command: $1" >&2
        exit 1
    }
}

for cmd in tar scp ssh wget lsblk cp sync sha256sum awk grep mktemp; do
    require_cmd "$cmd"
done

if [[ ! -d "$ROOTFS_DIR" ]]; then
    echo "[FAIL] Missing rootfs directory: $ROOTFS_DIR" >&2
    exit 1
fi

if [[ ! -d "$AUTO_DIR" || ! -f "$VENTOY_FILE" || ! -f "$XIBO_AUTO_FILE" || ! -f "$XIBO_GRUB_FILE" ]]; then
    echo "[FAIL] Missing auto/ or Ventoy/Xibo configuration files" >&2
    exit 1
fi

if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "[FAIL] Missing Xibo secrets file: $SECRETS_FILE" >&2
    echo "       Copy xibo.env.example to xibo.env and fill in the private values." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$SECRETS_FILE"

: "${XIBO_ROOT_PASSWORD_HASH:?Missing XIBO_ROOT_PASSWORD_HASH in $SECRETS_FILE}"
: "${XIBO_CMS_KEY:?Missing XIBO_CMS_KEY in $SECRETS_FILE}"
XIBO_USER_PASSWORD_HASH=${XIBO_USER_PASSWORD_HASH:-$XIBO_ROOT_PASSWORD_HASH}

mkdir -p "$OUTPUT_DIR" "$XIBO_IMG_DIR"

render_xibo_file() {
    local src="$1"
    local dst="$2"
    local content

    content="$(cat "$src")"
    content="${content//__XIBO_ROOT_PASSWORD_HASH__/$XIBO_ROOT_PASSWORD_HASH}"
    content="${content//__XIBO_USER_PASSWORD_HASH__/$XIBO_USER_PASSWORD_HASH}"
    content="${content//__XIBO_CMS_KEY__/$XIBO_CMS_KEY}"
    printf '%s\n' "$content" > "$dst"
}

run_ssh() {
    if [[ "$EUID" -eq 0 && "$SSH_USER" != "root" ]]; then
        sudo -u "$SSH_USER" -H ssh "$@"
    else
        ssh "$@"
    fi
}

run_scp() {
    if [[ "$EUID" -eq 0 && "$SSH_USER" != "root" ]]; then
        sudo -u "$SSH_USER" -H scp "$@"
    else
        scp "$@"
    fi
}

# -----------------------------------------------------------------------------
# 1. Build and publish the Xibo client package
# -----------------------------------------------------------------------------
echo "[1/3] Building $PACKAGE_NAME..."
rm -f "$PACKAGE_FILE"

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp -a "$ROOTFS_DIR/." "$STAGE_DIR/"

CMS_SETTINGS="$STAGE_DIR/home/xibocli/snap/xibo-player/common/cmsSettings.xml"
if [[ -f "$CMS_SETTINGS" ]]; then
    render_xibo_file "$CMS_SETTINGS" "$CMS_SETTINGS.rendered"
    mv -f "$CMS_SETTINGS.rendered" "$CMS_SETTINGS"
fi

tar --owner=0 --group=0 --numeric-owner -czf "$PACKAGE_FILE" -C "$STAGE_DIR" .
tar -tzf "$PACKAGE_FILE" >/dev/null 2>&1 || {
    echo "[FAIL] Package validation failed" >&2
    exit 1
}

REMOTE_PATH=${REMOTE_PATH%/}
REMOTE_TMP="$REMOTE_PATH/$PACKAGE_NAME.tmp"
REMOTE_FINAL="$REMOTE_PATH/$PACKAGE_NAME"

echo "      Uploading to ${REMOTE_SSH}:${REMOTE_FINAL}..."
run_ssh "$REMOTE_SSH" "mkdir -p '$REMOTE_PATH'"
run_scp -q "$PACKAGE_FILE" "$REMOTE_SSH:$REMOTE_TMP"
run_ssh "$REMOTE_SSH" "mv '$REMOTE_TMP' '$REMOTE_FINAL' && chmod 644 '$REMOTE_FINAL'"
echo "[OK]   Server package updated"

# -----------------------------------------------------------------------------
# 2. Check the current Debian netinst release and download only when necessary
# -----------------------------------------------------------------------------
echo "[2/3] Checking current Debian ${DEBIAN_MAJOR} netinst ISO..."

SHA256SUMS="$(wget -qO- "$DEBIAN_NETINST_BASE/SHA256SUMS")" || {
    echo "[FAIL] Could not retrieve Debian SHA256SUMS" >&2
    exit 1
}

DEBIAN_ISO_NAME="$(printf '%s\n' "$SHA256SUMS" \
    | awk -v major="$DEBIAN_MAJOR" '$2 ~ ("^debian-" major "\\.[0-9.]+-amd64-netinst\\.iso$") {print $2}' \
    | sed 's#^\*##' \
    | tail -n1)"

if [[ -z "$DEBIAN_ISO_NAME" ]]; then
    echo "[FAIL] Could not determine current Debian ${DEBIAN_MAJOR} amd64 netinst filename" >&2
    exit 1
fi

DEBIAN_EXPECTED_SHA256="$(printf '%s\n' "$SHA256SUMS" \
    | awk -v file="$DEBIAN_ISO_NAME" '{name=$2; sub(/^\\*/, "", name); if (name == file) {print $1; exit}}')"

if [[ -z "$DEBIAN_EXPECTED_SHA256" ]]; then
    echo "[FAIL] Could not determine SHA-256 for $DEBIAN_ISO_NAME" >&2
    exit 1
fi

DEBIAN_ISO="$XIBO_IMG_DIR/$DEBIAN_ISO_NAME"
DEBIAN_LOCAL_SHA256=""

if [[ -f "$DEBIAN_ISO" ]]; then
    DEBIAN_LOCAL_SHA256="$(sha256sum "$DEBIAN_ISO" | awk '{print $1}')"
fi

if [[ "$DEBIAN_LOCAL_SHA256" == "$DEBIAN_EXPECTED_SHA256" ]]; then
    echo "[OK]   Current netinst already cached: $DEBIAN_ISO_NAME"
else
    if [[ -f "$DEBIAN_ISO" ]]; then
        echo "      Cached ISO checksum does not match. Downloading a fresh copy..."
    else
        echo "      New/current netinst not cached: $DEBIAN_ISO_NAME"
        echo "      Downloading to $XIBO_IMG_DIR..."
    fi

    rm -f "$DEBIAN_ISO.tmp"
    wget -O "$DEBIAN_ISO.tmp" "$DEBIAN_NETINST_BASE/$DEBIAN_ISO_NAME"

    DOWNLOADED_SHA256="$(sha256sum "$DEBIAN_ISO.tmp" | awk '{print $1}')"
    if [[ "$DOWNLOADED_SHA256" != "$DEBIAN_EXPECTED_SHA256" ]]; then
        rm -f "$DEBIAN_ISO.tmp"
        echo "[FAIL] Downloaded Debian netinst checksum mismatch" >&2
        exit 1
    fi

    mv -f "$DEBIAN_ISO.tmp" "$DEBIAN_ISO"
    echo "[OK]   Netinst saved: $DEBIAN_ISO"
fi

DEBIAN_SHA256="$DEBIAN_EXPECTED_SHA256"
echo "[OK]   Current Debian netinst: $DEBIAN_ISO_NAME"
echo "[OK]   SHA-256 verified"

# -----------------------------------------------------------------------------
# 3. Update a mounted Ventoy USB, when present
# -----------------------------------------------------------------------------
find_ventoy_mount() {
    local dev label mnt

    if [[ -n "$USB_MOUNT" && -d "$USB_MOUNT" ]]; then
        printf '%s\n' "$USB_MOUNT"
        return 0
    fi

    while read -r dev label mnt; do
        [[ -z "${mnt:-}" ]] && continue

        if [[ "${label,,}" == "ventoy" || "${label,,}" == "xiboplayer" ]]; then
            printf '%s\n' "$mnt"
            return 0
        fi

        if [[ -d "$mnt/ventoy" && -d "$mnt/ISO" ]]; then
            printf '%s\n' "$mnt"
            return 0
        fi
    done < <(lsblk -prno NAME,LABEL,MOUNTPOINT)

    return 1
}

echo "[3/3] Checking for Ventoy USB..."

if VENTOY_MOUNT="$(find_ventoy_mount)"; then
    echo "      USB found: $VENTOY_MOUNT"

    mkdir -p "$VENTOY_MOUNT/ventoy" "$VENTOY_MOUNT/auto"

    cp -a "$VENTOY_DIR/." "$VENTOY_MOUNT/ventoy/"
    cp -a "$AUTO_DIR/." "$VENTOY_MOUNT/auto/"

    cp -f "$ROOT_DIR/manifest.json" "$VENTOY_MOUNT/manifest.json"
    cp -f "$ROOT_DIR/update-usb.sh" "$VENTOY_MOUNT/update-usb.sh"
    cp -f "$ROOT_DIR/update-usb.ps1" "$VENTOY_MOUNT/update-usb.ps1"
    chmod +x "$VENTOY_MOUNT/update-usb.sh"

    render_xibo_file "$XIBO_AUTO_FILE" "$VENTOY_MOUNT/auto/xibo-auto.cfg"

    USB_ISO_DIR="$VENTOY_MOUNT/ISO/Linux"
    USB_ISO="$USB_ISO_DIR/debian-13-netinst_VTNORMAL.iso"
    USB_SHA_FILE="$USB_ISO_DIR/debian-13-netinst_VTNORMAL.sha256"
    USB_SHA256=""

    mkdir -p "$USB_ISO_DIR"
    [[ ! -f "$USB_SHA_FILE" ]] || USB_SHA256="$(tr -d '[:space:]' < "$USB_SHA_FILE")"

    if [[ -f "$USB_ISO" && "$USB_SHA256" == "$DEBIAN_SHA256" ]]; then
        echo "[OK]   debian-13-netinst_VTNORMAL.iso content already current"
    else
        echo "      Copying $DEBIAN_ISO_NAME to USB as debian-13-netinst_VTNORMAL.iso..."
        cp -f "$DEBIAN_ISO" "$USB_ISO.tmp"
        mv -f "$USB_ISO.tmp" "$USB_ISO"
        printf '%s\n' "$DEBIAN_SHA256" > "$USB_SHA_FILE"
        echo "[OK]   debian-13-netinst_VTNORMAL.iso updated"
    fi

    # Remove old Xibo/Debian installer names so Ventoy shows one deployment entry.
    rm -f "$USB_ISO_DIR/debian-13.iso" \
          "$USB_ISO_DIR/debian-13.sha256" \
          "$USB_ISO_DIR/debian-13.version" \
          "$USB_ISO_DIR/debian-13_VTNORMAL.iso" \
          "$USB_ISO_DIR/debian-13_VTNORMAL.sha256" \
          "$USB_ISO_DIR/debian-13_VTNORMAL.version"

    sync
    echo "[OK]   Ventoy USB updated"
else
    echo "[SKIP] Ventoy USB not found or not mounted"
fi

echo
echo "Deploy complete."
