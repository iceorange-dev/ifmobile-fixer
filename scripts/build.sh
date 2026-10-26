#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
for tool in cargo xcodebuild xcodegen python3; do
  command -v "$tool" >/dev/null || { echo "Missing build tool: $tool" >&2; exit 1; }
done

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$project_root/build/rust}"
mkdir -p "$project_root/build" "$project_root/dist"
# Avoid embedding the build user's home directory in Rust panic locations.
export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$HOME=/build"

cargo test --manifest-path rust-core/Cargo.toml --locked --lib exploit::carrier::tests
cargo build --manifest-path rust-core/Cargo.toml --locked --release --target aarch64-apple-ios

framework_tmp="$(mktemp -d "$project_root/build/framework.XXXXXX")"
trap 'rm -rf "$framework_tmp"' EXIT
xcodebuild -create-xcframework \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libairlift_ffi.a" \
  -headers "$project_root/rust-core/include" \
  -output "$framework_tmp/AirliftFFI.xcframework"
rm -rf "$project_root/AirliftFFI.xcframework"
mv "$framework_tmp/AirliftFFI.xcframework" "$project_root/AirliftFFI.xcframework"

xcodegen generate --spec project.yml
if ! xcodebuild -project IFMobileHelper.xcodeproj -scheme IFMobileHelper \
    -configuration Release -sdk iphoneos -derivedDataPath "$project_root/build/xcode" \
    CODE_SIGNING_ALLOWED=NO TARGETED_DEVICE_FAMILY=1 build \
    > "$project_root/build/xcodebuild.log" 2>&1; then
  tail -80 "$project_root/build/xcodebuild.log"
  exit 1
fi
python3 scripts/package.py "$project_root/build/xcode/Build/Products/Release-iphoneos/IFMobileHelper.app" "$project_root/dist"
