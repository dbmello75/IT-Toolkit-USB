#!/bin/bash

rotation_file="/etc/xibo-display-rotation"
autostart_dir="/home/xibocli/.config/autostart"
autostart_file="$autostart_dir/display-rotation.desktop"

apply_rotation() {
    local rotation
    rotation="$(cat "$rotation_file" 2>/dev/null || true)"

    case "$rotation" in
        normal|left|right) ;;
        *) exit 0 ;;
    esac

    xrandr --query 2>/dev/null | awk '/ connected/{print $1}' | while read -r output; do
        [[ -n "$output" ]] || continue
        xrandr --output "$output" --rotate "$rotation"
    done
}

# Called automatically inside the xibocli graphical session.
if [[ "${1:-}" == "--apply" ]]; then
    apply_rotation
    exit 0
fi

echo ""
echo "Monitor orientation"
echo "-------------------"
echo "ENTER - Do not change orientation (default)"
echo "1     - Normal       | TV logo at the BOTTOM"
echo "2     - Rotate LEFT  | TV logo on the RIGHT side"
echo "3     - Rotate RIGHT | TV logo on the LEFT side"
echo ""
read -rp "Choose orientation [ENTER/1/2/3]: " choice

if [[ -z "$choice" ]]; then
    echo "Orientation unchanged."
    exit 0
fi

case "$choice" in
    1)
        rotation="normal"
        ;;
    2)
        rotation="left"
        ;;
    3)
        rotation="right"
        ;;
    *)
        echo "Invalid choice. Orientation was not changed."
        exit 1
        ;;
esac

printf '%s\n' "$rotation" > "$rotation_file"

mkdir -p "$autostart_dir"
cat > "$autostart_file" <<'EOF'
[Desktop Entry]
Type=Application
Name=Display Rotation
Exec=/usr/local/bin/orientation.sh --apply
Terminal=false
EOF

chown -R xibocli:xibocli "$autostart_dir"
chmod 644 "$autostart_file"

# Try to apply immediately when the graphical session is available.
apply_rotation || true

case "$rotation" in
    normal)
        echo "Orientation set to Normal on all connected displays."
        ;;
    left)
        echo "Orientation set to Rotate LEFT on all connected displays."
        ;;
    right)
        echo "Orientation set to Rotate RIGHT on all connected displays."
        ;;
esac

echo "The rotation will be applied automatically at each xibocli login."
sleep 2
