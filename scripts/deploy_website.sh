#!/bin/bash
# Deploys website/ (plus the latest DMG) to Cloudflare Pages project "orbcast".
# Needs Node.js and a Cloudflare login (npx wrangler login).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f dist/Orbcast.dmg ] || { echo "Run scripts/build.sh && scripts/make_dmg.sh first"; exit 1; }
rm -rf build/site && mkdir -p build/site
cp -R website/. build/site/
cp dist/Orbcast.dmg build/site/Orbcast.dmg
npx -y wrangler@latest pages deploy build/site --project-name orbcast --branch main --commit-dirty=true
