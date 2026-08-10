#!/bin/sh
set -e

version=$(awk -F'"' '/\.minimum_zig_version/ { print $2 }' build.zig.zon)
echo "Installing Zig version $version using zvm..."

# Development builds are not in zvm's version map, so they carry no published
# SHA-256. Without -s zvm asks for an interactive confirmation, which no CI
# runner can answer, and the install is cancelled.
case "$version" in
*-dev.*) skip_shasum="-s" ;;
*) skip_shasum="" ;;
esac

zvm install $skip_shasum "$version"
zvm use "$version"
