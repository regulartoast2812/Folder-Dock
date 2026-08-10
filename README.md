# Folder Dock

A compact macOS folder launcher that appears when you move the pointer to the top-center edge of the screen.

## Quick start

1. Move the pointer to the top-center edge of a display to reveal Folder Dock.
2. Add folders with the **+** button or drag folders onto the dock.
3. Click a saved folder to browse it inside Folder Dock. Middle-click to open it in a separate Finder window.

Folder sets, saved folders, and preferences stay local in macOS User Defaults and are not included in the repository or release files.

## Install from GitHub

Folder Dock requires macOS 14 or newer.

1. Download the latest `Folder-Dock-*.zip` from [GitHub Releases](https://github.com/regulartoast2812/Folder-Dock/releases/latest).
2. Unzip it and move **Folder Dock.app** into **Applications**.
3. Open the app. If macOS blocks the first launch, right-click the app, choose **Open**, then confirm **Open**. You can also use **System Settings → Privacy & Security → Open Anyway**.
4. Move the pointer to the top-center edge of the screen to begin.

App Management permission is optional and is only needed for installing in-app updates. It can be enabled later from **Folder Dock → Settings → Updates → Open App Management**. Folder Dock does not show a permission reminder at launch.

## Build from source

Install Xcode Command Line Tools, then run:

```sh
./scripts/build-app.sh
open "dist/Folder Dock.app"
```

## Publishing updates

Folder Dock uses Sparkle 2 and GitHub Releases. The app performs a silent update probe and only shows an **Update** button beside its build number when a newer signed build is available. Clicking it opens Sparkle's download and install flow.

1. Increase `CFBundleShortVersionString` and/or `CFBundleVersion` in `Resources/Info.plist`.
2. Run `./scripts/prepare-release.sh`.
3. Create a GitHub Release using the tag printed by the script.
4. Upload both generated files from `release/`: the Folder Dock ZIP and `appcast.xml`.

The Sparkle private Ed25519 key is stored in the macOS Keychain under the `ed25519` account and is never committed. Keep a secure backup of that key. The app contains only its public key.

## Finder-style browser shortcuts

When browsing a saved folder, click once to select an item and double-click to open it.

You can drag any saved folder or browser item directly into another app, including file-upload targets. Dragging a folder back onto the saved-folder shelf adds it to the active folder set.

Drag files or folders from Finder onto the open browser to move them into that folder, or onto a folder tile to move them into that specific folder. Hold `Option` while dropping to copy instead.

- `⌘[` / `⌘]` or Logitech MX side buttons: back / forward
- `⌘↑`: enclosing folder
- `Return`: rename one selected item inline, or open Finder-style batch rename for multiple items
- `⌘O`: open the selected item or items
- `⌘Z`: undo the last reversible file action
- `Space`: Quick Look the selected item
- `⇧⌘N`: new folder
- `⌘R`: refresh
- `⌘N`: open the current folder in Finder
- `⌘W`: return to the folder shelf
- `⌥⌘←` / `⌥⌘→`: previous / next folder set
- `⌘C`, `⌘D`, `⌘I`, `⌘Delete`: copy, duplicate, get info, move selected item to Trash
