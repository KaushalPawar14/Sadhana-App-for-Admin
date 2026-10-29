#!/usr/bin/env bash
# THE WEBSITE (https://folk-guides.web.app) — STANDING RULE: after ANY Guide app code change, rebuild the web app and redeploy it with this
# script, in the same task, and say so in the report.
#
#   ./deploy-web.sh
#
# Builds the release web bundle and deploys it to the Firebase Hosting site `folk-guides` (firebase.json: index.html / .js / .json are
# no-cache, so the new build is what everyone gets on the next load). Afterwards it restores the generated plugin files and pubspec.lock that
# a Flutter run rewrites, so they never end up in a commit. No AAB.
set -uo pipefail
cd "$(dirname "$0")"
[ -f /d/tmp-fl/env.sh ] && . /d/tmp-fl/env.sh
[ -d /d/tmp-fl/fbshim ] && export PATH="/d/tmp-fl/fbshim:$PATH"

echo "=== 1. flutter build web ==="
flutter build web --release --no-wasm-dry-run || { echo "BUILD FAILED"; git checkout pubspec.lock linux macos windows 2>/dev/null; exit 1; }
git checkout pubspec.lock linux macos windows 2>/dev/null

echo "=== 2. firebase deploy --only hosting:folk-guides ==="
firebase deploy --only hosting:folk-guides --project folk-sadhana-app --non-interactive || { echo "DEPLOY FAILED"; exit 1; }

echo "=== 3. is the new build live? ==="
live=$(curl -s -H 'Cache-Control: no-cache' https://folk-guides.web.app/main.dart.js | wc -c)
local_size=$(wc -c < build/web/main.dart.js)
echo "live main.dart.js: $live bytes; built: $local_size bytes"
[ "$live" = "$local_size" ] && echo "=== website redeployed: https://folk-guides.web.app ===" || { echo "SIZE MISMATCH: the site may still be serving the old build"; exit 1; }
