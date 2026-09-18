#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${MANIFEST:-$ROOT_DIR/manifest.json}"
TARGET="${TARGET:-$ROOT_DIR}"
PROFILE="${PROFILE:-full}"
FORCE=0
ALL_COMPONENTS=0

usage() {
    cat <<'EOF'
Usage: update-usb.sh [--target PATH] [--profile NAME] [--all] [--force]

Defaults:
  --target   directory containing this script
  --profile  full

Examples:
  ./update-usb.sh
  ./update-usb.sh --profile standard
  ./update-usb.sh --target /media/$USER/Ventoy --profile full
  ./update-usb.sh --all --force
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --all) ALL_COMPONENTS=1; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[FAIL] Unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[FAIL] Missing required command: $1" >&2
        exit 1
    }
}

for cmd in curl python3 sha256sum awk grep sed sort cp mkdir mv; do
    require_cmd "$cmd"
done

[[ -f "$MANIFEST" ]] || { echo "[FAIL] Manifest not found: $MANIFEST" >&2; exit 1; }
mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"
STATE_FILE="$TARGET/.it-toolkit-state.tsv"

echo "IT Toolkit USB updater"
echo "Target : $TARGET"
if [[ "$ALL_COMPONENTS" -eq 1 ]]; then
    echo "Profile: ALL enabled components"
else
    echo "Profile: $PROFILE"
fi
echo

# Copy small public toolkit files when the updater is executed from a checkout
# and a different target (USB root) was explicitly selected.
if [[ "$TARGET" != "$ROOT_DIR" ]]; then
    echo "[SYNC] Toolkit configuration files"
    mkdir -p "$TARGET/auto" "$TARGET/ventoy" "$TARGET/tools"
    cp -a "$ROOT_DIR/ventoy/." "$TARGET/ventoy/"
    cp -a "$ROOT_DIR/tools/." "$TARGET/tools/" 2>/dev/null || true

    # Keep a rendered/private Xibo preseed already present on the USB.
    # All other public automation files can be refreshed safely.
    find "$ROOT_DIR/auto" -maxdepth 1 -type f ! -name 'xibo-auto.cfg' -print0 |
        while IFS= read -r -d '' file; do
            cp -f "$file" "$TARGET/auto/"
        done

    cp -f "$ROOT_DIR/manifest.json" "$TARGET/manifest.json"
    cp -f "$ROOT_DIR/update-usb.sh" "$TARGET/update-usb.sh"
    [[ ! -f "$ROOT_DIR/update-usb.ps1" ]] || cp -f "$ROOT_DIR/update-usb.ps1" "$TARGET/update-usb.ps1"
fi

component_rows() {
    python3 - "$MANIFEST" "$PROFILE" "$ALL_COMPONENTS" <<'PY'
import json, sys
path, profile, all_components = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
with open(path, encoding="utf-8") as f:
    data = json.load(f)
for c in data.get("components", []):
    if not c.get("enabled", True):
        continue
    d = c.get("download", {})
    if not d.get("enabled", False):
        continue
    if not all_components and profile not in c.get("profiles", []):
        continue
    chk = c.get("checksum", {})
    fields = [
        c.get("id", ""),
        c.get("name", ""),
        c.get("destination", ""),
        c.get("filename", ""),
        d.get("method", "direct"),
        d.get("provider", ""),
        d.get("url") or "",
        "1" if chk.get("required", False) else "0",
        chk.get("value") or ""
    ]
    print("\t".join(str(x).replace("\t", " ") for x in fields))
PY
}

resolve_url() {
    local provider="$1"
    local base="$2"
    local html version name

    case "$provider" in
        debian)
            local sums
            sums="$(curl -fsSL --retry 3 "$base/SHA256SUMS")"
            name="$(printf '%s\n' "$sums" |
                awk '$2 ~ /^debian-13\.[0-9.]+-amd64-netinst\.iso$/ {print $2}' |
                sed 's/^\*//' | sort -V | tail -n1)"
            [[ -n "$name" ]] || return 1
            printf '%s/%s\n' "$base" "$name"
            ;;
        systemrescue)
            html="$(curl -fsSL --retry 3 "$base")"
            name="$(printf '%s' "$html" |
                grep -oE 'systemrescue-[0-9]+\.[0-9]+-amd64\.iso' |
                sort -Vu | tail -n1)"
            [[ -n "$name" ]] || return 1
            version="${name#systemrescue-}"
            version="${version%-amd64.iso}"
            printf 'https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/%s/%s/download\n' "$version" "$name"
            ;;
        rescuezilla)
            python3 - "$base" <<'PY'
import json, sys, urllib.request
req = urllib.request.Request(sys.argv[1], headers={"User-Agent": "IT-Toolkit-USB"})
with urllib.request.urlopen(req, timeout=30) as r:
    data = json.load(r)
assets = [a.get("browser_download_url","") for a in data.get("assets", [])]
preferred = [u for u in assets if u.lower().endswith(".iso") and "64bit" in u.lower() and "alternative" not in u.lower()]
if not preferred:
    preferred = [u for u in assets if u.lower().endswith(".iso") and "64bit" in u.lower()]
if not preferred:
    preferred = [u for u in assets if u.lower().endswith(".iso")]
if not preferred:
    raise SystemExit(1)
print(preferred[0])
PY
            ;;
        clonezilla)
            html="$(curl -fsSL --retry 3 "$base")"
            version="$(printf '%s' "$html" |
                grep -oE 'clonezilla_live_stable/[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' |
                sed 's#clonezilla_live_stable/##' |
                sort -Vu | tail -n1)"
            [[ -n "$version" ]] || return 1
            name="clonezilla-live-${version}-amd64.iso"
            printf 'https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/%s/%s/download\n' "$version" "$name"
            ;;
        proxmox)
            html="$(curl -fsSL --retry 3 "$base")"
            name="$(printf '%s' "$html" |
                grep -oE 'proxmox-ve_[0-9][0-9A-Za-z._-]*\.iso' |
                sort -Vu | tail -n1)"
            [[ -n "$name" ]] || return 1
            printf '%s%s\n' "$base" "$name"
            ;;
        *)
            [[ -n "$base" ]] || return 1
            printf '%s\n' "$base"
            ;;
    esac
}

resolve_expected_sha256() {
    local provider="$1"
    local base="$2"
    local resolved="$3"

    case "$provider" in
        debian)
            local sums source_name
            source_name="${resolved##*/}"
            sums="$(curl -fsSL --retry 3 "$base/SHA256SUMS")"
            printf '%s\n' "$sums" |
                awk -v file="$source_name" '{
                    name=$2
                    sub(/^\*/, "", name)
                    if (name == file) {print $1; exit}
                }'
            ;;
        *)
            printf '\n'
            ;;
    esac
}

remote_signature() {
    local url="$1"
    local headers effective etag modified length

    headers="$(curl -fsSIL --retry 2 --max-time 45 "$url" 2>/dev/null || true)"
    effective="$(curl -fsSL -o /dev/null -w '%{url_effective}' --retry 2 --max-time 45 "$url" 2>/dev/null || true)"
    etag="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^etag:/ {sub(/^[^:]+:[[:space:]]*/, ""); gsub("\r",""); v=$0} END{print v}')"
    modified="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^last-modified:/ {sub(/^[^:]+:[[:space:]]*/, ""); gsub("\r",""); v=$0} END{print v}')"
    length="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^content-length:/ {sub(/^[^:]+:[[:space:]]*/, ""); gsub("\r",""); v=$0} END{print v}')"

    if [[ -z "$etag$modified$length" ]]; then
        printf '\n'
    else
        printf '%s|%s|%s|%s\n' "$effective" "$etag" "$modified" "$length"
    fi
}

state_get() {
    local id="$1"
    [[ -f "$STATE_FILE" ]] || return 0
    awk -F '\t' -v id="$id" '$1 == id {print $2; exit}' "$STATE_FILE"
}

state_set() {
    local id="$1" sig="$2" sha="$3"
    local tmp
    tmp="${STATE_FILE}.tmp"
    if [[ -f "$STATE_FILE" ]]; then
        awk -F '\t' -v id="$id" '$1 != id' "$STATE_FILE" > "$tmp"
    else
        : > "$tmp"
    fi
    printf '%s\t%s\t%s\n' "$id" "$sig" "$sha" >> "$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

fail_or_continue() {
    local required="$1" message="$2"
    echo "[FAIL] $message" >&2
    if [[ "$required" == "1" ]]; then
        exit 1
    fi
}

while IFS=$'\t' read -r id name destination filename method provider url checksum_required checksum_value; do
    [[ -n "$id" ]] || continue

    echo "[$id] $name"
    dest_dir="$TARGET/$destination"
    dest_file="$dest_dir/$filename"
    mkdir -p "$dest_dir"

    if [[ "$filename" != *_VTNORMAL.iso ]]; then
        echo "[FAIL] Manifest filename does not end in _VTNORMAL.iso: $filename" >&2
        exit 1
    fi

    resolved_url="$url"
    if [[ "$method" == "dynamic" ]]; then
        if ! resolved_url="$(resolve_url "$provider" "$url")"; then
            fail_or_continue "$checksum_required" "Could not resolve current download for $name"
            echo
            continue
        fi
    fi

    [[ -n "$resolved_url" ]] || {
        fail_or_continue "$checksum_required" "No download URL for $name"
        echo
        continue
    }

    expected_sha="$checksum_value"
    if [[ -z "$expected_sha" ]]; then
        expected_sha="$(resolve_expected_sha256 "$provider" "$url" "$resolved_url" || true)"
    fi

    sig="$(remote_signature "$resolved_url")"
    old_sig="$(state_get "$id")"

    if [[ "$FORCE" -eq 0 && -f "$dest_file" && -n "$sig" && "$sig" == "$old_sig" ]]; then
        echo "[OK]   Already current: $filename"
        echo
        continue
    fi

    tmp="${dest_file}.part"
    echo "       Source: $resolved_url"
    echo "       Saving: $dest_file"

    if ! curl -fL --retry 3 --retry-delay 2 -C - -o "$tmp" "$resolved_url"; then
        rm -f "$tmp"
        fail_or_continue "$checksum_required" "Download failed: $name"
        echo
        continue
    fi

    actual_sha="$(sha256sum "$tmp" | awk '{print $1}')"

    if [[ -n "$expected_sha" && "$actual_sha" != "$expected_sha" ]]; then
        rm -f "$tmp"
        fail_or_continue "1" "SHA-256 mismatch for $name"
    fi

    if [[ "$checksum_required" == "1" && -z "$expected_sha" ]]; then
        rm -f "$tmp"
        fail_or_continue "1" "Checksum required but unavailable for $name"
    fi

    mv -f "$tmp" "$dest_file"
    printf '%s\n' "$actual_sha" > "${dest_file%.iso}.sha256"
    state_set "$id" "$sig" "$actual_sha"

    echo "[OK]   Updated: $filename"
    [[ -z "$expected_sha" ]] || echo "[OK]   SHA-256 verified"
    echo
done < <(component_rows)

echo "Toolkit update complete."
