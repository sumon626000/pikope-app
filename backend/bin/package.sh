#!/usr/bin/env bash
# Builds dist/billiard-poker-backend.zip: what a server needs, nothing else.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf dist && mkdir -p dist/billiard-poker/public/uploads/avatars
cp -r src sql bin deploy .env.example README.md dist/billiard-poker/
cp public/index.php public/.htaccess dist/billiard-poker/public/
cp public/uploads/.htaccess dist/billiard-poker/public/uploads/
touch dist/billiard-poker/public/uploads/avatars/.gitkeep
rm -f dist/billiard-poker/bin/package.sh
# Syntax-check everything that ships.
find dist/billiard-poker -name '*.php' -print0 | xargs -0 -n1 php -l >/dev/null
(cd dist && python3 - <<'PY'
import os, zipfile
with zipfile.ZipFile('billiard-poker-backend.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk('billiard-poker'):
        for name in sorted(files):
            z.write(os.path.join(root, name))
PY
)
rm -rf dist/billiard-poker
echo "dist/billiard-poker-backend.zip ($(du -h dist/billiard-poker-backend.zip | cut -f1))"
