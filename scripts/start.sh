#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/scripts/build.sh"
/usr/bin/open -n "$ROOT_DIR/build/AlwaysPet.app"
