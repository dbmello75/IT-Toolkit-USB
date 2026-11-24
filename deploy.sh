#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPLAY_DIR="${DISPLAY_AUTOINSTALL_DIR:-$ROOT_DIR/../Displays/Players/AutoInstall}"
USB_MOUNT=${USB_MOUNT:-}
PROFILE=${PROFILE:-full}
REMOTE_SSH=${REMOTE_SSH:-remote}
REMOTE_PATH=${REMOTE_PATH:-/var/www/display}
TOOLKIT_REMOTE_PATH=${TOOLKIT_REMOTE_PATH:-${REMOTE_PATH%/}/toolkit}
TOOLKIT_REMOTE_PATH=${TOOLKIT_REMOTE_PATH%/}
SSH_USER=${SUDO_USER:-${USER:-root}}

case "${1:-}" in
    -h|--help)
        echo "Usage: USB_MOUNT=/path/to/Ventoy PROFILE=full $0 [--check]"
        echo "--check validates local inputs without publishing or updating the USB."
        exit 0
        ;;
    --check|"") ;;
    *) echo "[FAIL] Unknown option: $1" >&2; exit 2 ;;
esac
(( $# <= 1 )) || exit 2

if [[ ! -f "$DISPLAY_DIR/deploy.sh" ]]; then
    echo "[FAIL] Displays AutoInstall not found. Use the VicPro checkout or set DISPLAY_AUTOINSTALL_DIR." >&2
    exit 1
fi
bash "$DISPLAY_DIR/deploy.sh" --check

work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
stage="$work_dir/files"
mkdir -p "$stage"/{auto,config,tools,ventoy}
cp -a "$ROOT_DIR/ventoy/." "$stage/ventoy/"
mkdir -p "$stage/tools/GLPI"
cp -p "$ROOT_DIR"/tools/{update-usb.sh,update-usb.ps1,Windows-Info.cmd,Windows-Info.ps1} "$stage/tools/"
cp "$ROOT_DIR"/tools/GLPI/{GLPI-Agent.cmd,GLPI.env.example} "$stage/tools/GLPI/"
cp "$ROOT_DIR"/auto/{en-us_bios-key.xml,en-us_safe-part.xml,pt-br_bios-key.xml,pt-br_safe-part.xml,zorin-autoinstall.yaml} "$stage/auto/"
cp "$ROOT_DIR/config/manifest.json" "$stage/config/"
cp "$DISPLAY_DIR"/auto/{xibo-auto.cfg,xibo-grub.cfg} "$stage/auto/"

python3 - "$stage" "$PROFILE" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
config = json.loads((root / "ventoy/ventoy.json").read_text())
manifest = json.loads((root / "config/manifest.json").read_text())
if sys.argv[2] not in manifest["profiles"]:
    sys.exit(f"[FAIL] Unknown profile: {sys.argv[2]}")

def check_file(path):
    if not path.startswith("/") or not (root / path.lstrip("/")).is_file():
        sys.exit(f"[FAIL] Missing Ventoy file: {path}")

images = {
    f"/{component['destination']}/{component['filename']}"
    for component in manifest["components"]
}
for section, rules in config.items():
    plugin = section.removesuffix("_legacy").removesuffix("_uefi")
    if plugin not in {"menu_alias", "menu_tip", "auto_install", "conf_replace"}:
        continue
    seen = set()
    for rule in rules:
        image = rule["iso" if plugin == "conf_replace" else "image"]
        key = (image, rule.get("org"))
        if key in seen:
            sys.exit(f"[FAIL] Duplicate {section} rule for {key}")
        seen.add(key)
        if plugin in {"auto_install", "conf_replace"} and image not in images:
            sys.exit(f"[FAIL] {section} image missing from manifest: {image}")
        if plugin == "auto_install":
            templates = rule["template"]
            for template in [templates] if isinstance(templates, str) else templates:
                check_file(template)
        if plugin == "conf_replace":
            check_file(rule["new"])
PY

if [[ "${1:-}" == "--check" ]]; then
    echo "[OK] Toolkit files and Ventoy paths validated."
    exit 0
fi

if [[ -z "$USB_MOUNT" ]] || ! mountpoint -q -- "$USB_MOUNT"; then
    echo "[FAIL] Set USB_MOUNT to the mounted Ventoy data partition." >&2
    exit 1
fi

run_remote() {
    if [[ "$EUID" -eq 0 && "$SSH_USER" != "root" ]]; then
        sudo -u "$SSH_USER" -H "$@"
    else
        "$@"
    fi
}

package=it-toolkit-files.tar.gz
checksum=it-toolkit-files.sha256
# The active preseed contains local account password hashes. Keep the boot files
# together on the administratively prepared USB and out of the public archive.
tar --exclude=./auto/xibo-auto.cfg --exclude=./auto/xibo-grub.cfg \
    --owner=0 --group=0 --numeric-owner -czf "$work_dir/$package" -C "$stage" .
(cd "$work_dir" && sha256sum "$package" > "$checksum")

# Prepare ISOs before publishing or activating the new configuration.
mkdir -p "$USB_MOUNT/config"
MANIFEST="$stage/config/manifest.json" bash "$stage/tools/update-usb.sh" \
    --target "$USB_MOUNT" --profile "$PROFILE" --skip-toolkit-refresh

bash "$DISPLAY_DIR/deploy.sh"

menu="$work_dir/ventoy.json"
mv "$stage/ventoy/ventoy.json" "$menu"
cp -a "$stage/." "$USB_MOUNT/"
cp "$menu" "$USB_MOUNT/ventoy/ventoy.json.tmp"
mv -f "$USB_MOUNT/ventoy/ventoy.json.tmp" "$USB_MOUNT/ventoy/ventoy.json"

run_remote ssh "$REMOTE_SSH" "mkdir -p '$TOOLKIT_REMOTE_PATH'"
for file in "$package" "$checksum"; do
    run_remote scp -q "$work_dir/$file" "$REMOTE_SSH:$TOOLKIT_REMOTE_PATH/$file.tmp"
done
run_remote ssh "$REMOTE_SSH" "chmod 644 '$TOOLKIT_REMOTE_PATH/$package.tmp' '$TOOLKIT_REMOTE_PATH/$checksum.tmp' && mv '$TOOLKIT_REMOTE_PATH/$package.tmp' '$TOOLKIT_REMOTE_PATH/$package' && mv '$TOOLKIT_REMOTE_PATH/$checksum.tmp' '$TOOLKIT_REMOTE_PATH/$checksum'"

cp "$work_dir/$checksum" "$USB_MOUNT/config/$checksum"
sync -f "$USB_MOUNT"
echo "[OK] Toolkit published and USB synchronized."
