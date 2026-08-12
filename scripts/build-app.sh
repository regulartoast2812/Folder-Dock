#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dir="${project_dir}/dist/Folder Dock.app"
binary_dir="${project_dir}/.build/release"
framework_source="${binary_dir}/Sparkle.framework"

cd "$project_dir"
swift build -c release
"${binary_dir}/FolderDockGuardrails"

rm -rf "$output_dir"
mkdir -p "$output_dir/Contents/MacOS" "$output_dir/Contents/Resources" "$output_dir/Contents/Frameworks"
cp "$binary_dir/FolderDock" "$output_dir/Contents/MacOS/FolderDock"
cp "$project_dir/Resources/Info.plist" "$output_dir/Contents/Info.plist"
ditto "$framework_source" "$output_dir/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$output_dir/Contents/MacOS/FolderDock"

codesign --force --deep --sign - "$output_dir"
codesign --verify --deep --strict "$output_dir"
echo "Built: $output_dir"
