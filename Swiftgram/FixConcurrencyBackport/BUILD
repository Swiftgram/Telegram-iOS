# Something changed in Telegram versions 11.8.1 -> 11.10
# https://github.com/TelegramMessenger/Telegram-iOS/compare/release-11.8.1...TelegramMessenger:Telegram-iOS:release-11.10
#
# Since then, all binaries and libs are linked to the /usr/lib/swift/libswift_Concurrency.dylib instead of expected @rpath/libswift_Concurrency.dylib,
# this makes swift-stdlib-tool to ignore libswift_Concurrency.dylib and not copy it to the app bundle.
# This causes crash on every system that expects this backport (iOS 14 and below).
# This script will remap the path to @rpath/libswift_Concurrency.dylib in all binaries of the App, it's only needed for iphoneos target in this project.
# This is a temporary fix until minimum OS version will be bumped to iOS 15+ or Xcode version changed to 16.3 (with Swift 6.1 support)

# find "$1" -type f \( -perm +111 -o -name "*.dylib" \) | while read -r bin; do
#   if otool -L "$bin" | grep -q "/usr/lib/swift/libswift_Concurrency.dylib"; then
#     echo "Patching concurrency backport in: $bin"
#     install_name_tool -change /usr/lib/swift/libswift_Concurrency.dylib @rpath/libswift_Concurrency.dylib "$bin"
#   fi
# done

# concurrency-dylib.patch must be applied in build-system/bazel-rules/rules_apple
# cd Swiftgram/FixConcurrencyBackport
# git apply ../../../Swiftgram/FixConcurrencyBackport/concurrency-dylib.patch
# # Make a build
# git apply -R ../../../Swiftgram/FixConcurrencyBackport/concurrency-dylib.patch

# Refs:
# https://stackoverflow.com/questions/79522371/when-building-the-project-with-xcode-16-2-the-app-crashes-due-to-an-incorrect-l
# https://github.com/swiftlang/swift/issues/74303
# https://github.com/bazelbuild/rules_apple/pull/1393

genrule(
    name = "CopyConcurrencyDylib",
    cmd_bash =
"""
    echo 'ditto "$$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.5/iphoneos/libswift_Concurrency.dylib" "$$1/Payload/Swiftgram.app/Frameworks/libswift_Concurrency.dylib"' > $(location CopyConcurrencyDylib.sh)
    echo 'ditto "$$1/Payload/Swiftgram.app/Frameworks/libswift_Concurrency.dylib" "$$1/SwiftSupport/iphoneos/libswift_Concurrency.dylib"' >> $(location CopyConcurrencyDylib.sh)
    echo '' >> $(location CopyConcurrencyDylib.sh)
""",
    outs = [
        "CopyConcurrencyDylib.sh",
    ],
    executable = True,
    visibility = [
        "//visibility:public",
    ]
)