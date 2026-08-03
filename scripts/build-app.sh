#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dir="${project_dir}/dist/Folder Dock.app"
binary_dir="${project_dir}/.build/release"

cd "$project_dir"
swift build -c release

rm -rf "$output_dir"
mkdir -p "$output_dir/Contents/MacOS" "$output_dir/Contents/Resources"
cp "$binary_dir/FolderDock" "$output_dir/Contents/MacOS/FolderDock"
cp "$project_dir/Resources/Info.plist" "$output_dir/Contents/Info.plist"

codesign --force --deep --sign - "$output_dir"
echo "Built: $output_dir"
