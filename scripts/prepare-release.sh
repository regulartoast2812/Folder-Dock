#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_path="${project_dir}/dist/Folder Dock.app"
release_dir="${project_dir}/release"
info_plist="${project_dir}/Resources/Info.plist"
appcast_tool="${project_dir}/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

"${script_dir}/build-app.sh"

short_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info_plist")
build_number=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist")
release_tag="v${short_version}-b${build_number}"
archive_name="Folder-Dock-${short_version}-b${build_number}.zip"
archive_path="${release_dir}/${archive_name}"
appcast_path="${release_dir}/appcast.xml"
release_work_dir=$(mktemp -d)

cleanup() {
    rm -rf "$release_work_dir"
}
trap cleanup EXIT

mkdir -p "$release_dir"
rm -f "$archive_path" "$appcast_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
cp "$archive_path" "$release_work_dir/$archive_name"

"$appcast_tool" \
    --download-url-prefix "https://github.com/regulartoast2812/Folder-Dock/releases/download/${release_tag}/" \
    --link "https://github.com/regulartoast2812/Folder-Dock" \
    -o "$appcast_path" \
    "$release_work_dir"

echo "Prepared signed release ${release_tag}:"
echo "  ${archive_path}"
echo "  ${appcast_path}"
echo "Create a GitHub Release tagged ${release_tag} and upload both files."
