#!/usr/bin/env bash
# Rebuilds assets/fonts/MynaIcons.ttf from mapping.py: Myna SVGs (@iconify-json/mynaui), strokes outlined
# with oslllo-svg-fixer, packed with fantasticon. Then regenerate lib/myna_icons.dart and lib/app_icons.dart
# from MynaIcons.json (see git history of those files for the generator snippet).
set -euo pipefail
work=$(mktemp -d); cd "$work"
npm init -y >/dev/null; npm i @iconify-json/mynaui fantasticon oslllo-svg-fixer >/dev/null
echo "Write svg/<glyph>.svg for every value in mapping.py, run svg-fixer to fixed/, then:"
echo "npx fantasticon fixed -o out -n MynaIcons -t ttf -g json --normalize true --round 10 --font-height 1000"
