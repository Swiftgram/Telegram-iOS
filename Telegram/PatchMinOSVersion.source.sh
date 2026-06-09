#!/bin/sh

set -e

name=<<<NAME>>>
version=<<<MIN_OS_VERSION>>>

f="$1/$name"

plist_path="$f/Info.plist"
plutil -replace MinimumOSVersion -string $version "$plist_path"
if [ "$version" == "14.0" ]; then
	binary_path="$f/$(basename $f | sed -e s/\.appex//g)"
	xcrun lipo "$binary_path" -remove armv7 -o "$binary_path" 2>/dev/null || true
fi

# MARK: Swiftgram
find "$1" -type f \( -perm +111 -o -name "*.dylib" \) | while read -r bin; do
  if otool -L "$bin" | grep -q "/usr/lib/swift/libswift_Concurrency.dylib"; then
    echo "Patching concurrency backport in: $bin"
    chmod +w "$(dirname $bin)/"
    install_name_tool -change /usr/lib/swift/libswift_Concurrency.dylib @rpath/libswift_Concurrency.dylib "$bin"
  fi
done