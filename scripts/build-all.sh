#!/bin/bash
# Builds every app (or the ones named) and zips each into dist.noindex/ for a release:
#   ./scripts/build-all.sh                   all four
#   ./scripts/build-all.sh WhatsAppClone     just one
# Add --install to also copy the apps into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
INSTALL=""
APPS=()
for a in "$@"; do [ "$a" = "--install" ] && INSTALL="--install" || APPS+=("$a"); done
[ ${#APPS[@]} -eq 0 ] && APPS=(PhotosClone SnapchatClone InstagramClone WhatsAppClone)
mkdir -p dist.noindex
for app in "${APPS[@]}"; do
  echo "== $app"
  (cd "apps/$app" && ./scripts/build-app.sh $INSTALL)
  built="$(ls -d "apps/$app/dist.noindex/"*.app)"
  name="$(basename "$built" .app)"
  rm -f "dist.noindex/$name.zip"
  ditto -c -k --keepParent "$built" "dist.noindex/${name// /-}.zip"
done
if [ ${#APPS[@]} -eq 4 ]; then
  rm -f dist.noindex/All-Apps.zip
  (cd dist.noindex && zip -q All-Apps.zip Photos-Clone.zip Snapchat-Clone.zip Instagram-Clone.zip WhatsApp-Clone.zip)
fi
ls -la dist.noindex
