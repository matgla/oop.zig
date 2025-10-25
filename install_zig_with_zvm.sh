#!/bin/sh

version=$(awk -F'"' '/\.minimum_zig_version/ { print $2 }' build.zig.zon)
echo "Installing Zig version $version using zvm..."

zvm install $version
zvm use $version