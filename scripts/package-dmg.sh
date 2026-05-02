#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/FreeYourPet.app"
DMG_DIR="$ROOT_DIR/build/dmg"
DMG_PATH="$ROOT_DIR/build/FreeYourPet.dmg"
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

SIGN_ID="Developer ID Application: Matteo Mekhail (G724SAH69L)"

echo "==> Signing app..."
codesign --deep --force --options runtime \
    --sign "$SIGN_ID" \
    "$APP_DIR"
codesign --verify --verbose "$APP_DIR"
echo "    App signed and verified"

echo "==> Creating DMG..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "FreeYourPet" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_DIR"

echo "==> Signing DMG..."
codesign --force --sign "$SIGN_ID" "$DMG_PATH"

echo "==> Notarizing..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "notary" \
    --wait

echo "==> Stapling..."
xcrun stapler staple "$DMG_PATH"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')
echo ""
echo "==> Done! Signed & notarized DMG created at:"
echo "    $DMG_PATH ($DMG_SIZE)"
echo ""
echo "    Customers open the DMG and drag FreeYourPet.app to Applications."
