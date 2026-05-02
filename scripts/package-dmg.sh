#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/AlwaysPet.app"
DMG_DIR="$ROOT_DIR/build/dmg"
DMG_PATH="$ROOT_DIR/build/AlwaysPet.dmg"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
PETS_DIR="$RESOURCES_DIR/pets"

echo "==> Building app..."
"$ROOT_DIR/scripts/build.sh"

echo "==> Bundling pets..."
rm -rf "$PETS_DIR"
mkdir -p "$PETS_DIR"

CODEX_PETS="$HOME/.codex/pets"
if [[ -d "$CODEX_PETS" ]]; then
    for pet_dir in "$CODEX_PETS"/*/; do
        [[ -f "$pet_dir/pet.json" ]] || continue
        pet_name="$(basename "$pet_dir")"
        echo "    Bundling pet: $pet_name"
        cp -R "$pet_dir" "$PETS_DIR/$pet_name"
    done
fi

BUNDLED_COUNT=$(find "$PETS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
echo "    $BUNDLED_COUNT pet(s) bundled"

echo "==> Creating DMG..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "AlwaysPet" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_DIR"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')
echo ""
echo "==> Done! DMG created at:"
echo "    $DMG_PATH ($DMG_SIZE)"
echo ""
echo "    Customers open the DMG and drag AlwaysPet.app to Applications."
