#!/bin/bash
# Builds the hub and every app (or the ones named) and zips each into dist.noindex/ for a release:
#   ./scripts/build-all.sh                   everything
#   ./scripts/build-all.sh RegainHub         just the hub (all apps in one)
#   ./scripts/build-all.sh WhatsAppClone     just one app
# Add --install to also copy the apps into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
INSTALL=""
APPS=()
ALL=(RegainHub PhotosClone SnapchatClone InstagramClone WhatsAppClone AmazonClone)
for a in "$@"; do [ "$a" = "--install" ] && INSTALL="--install" || APPS+=("$a"); done
[ ${#APPS[@]} -eq 0 ] && APPS=("${ALL[@]}")
mkdir -p dist.noindex
for app in "${APPS[@]}"; do
  echo "== $app"
  (cd "apps/$app" && ./scripts/build-app.sh $INSTALL)
  built="$(ls -d "apps/$app/dist.noindex/"*.app)"
  name="$(basename "$built" .app)"
  rm -f "dist.noindex/${name// /-}.zip"
  ditto -c -k --keepParent "$built" "dist.noindex/${name// /-}.zip"
done
if [ ${#APPS[@]} -eq ${#ALL[@]} ]; then
  rm -f dist.noindex/All-Apps.zip
  (cd dist.noindex && zip -q All-Apps.zip Photos-Clone.zip Snapchat-Clone.zip Instagram-Clone.zip WhatsApp-Clone.zip Amazon-Clone.zip)
fi
ls -la dist.noindex
