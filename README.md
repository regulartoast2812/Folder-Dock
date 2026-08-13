# Folder Dock

A compact macOS file and folder launcher available from the menu bar or the selected top edge of the screen.

## Quick start

1. Click the Folder Dock menu-bar icon, or move the pointer to the top-center edge of a display.
2. Add files or folders with the **+** button, or drag them from Finder onto the dock.
3. Click a saved item to select it. Double-click a folder to browse it inside Folder Dock, or double-click a file to open it in its default app. Middle-click a folder to open it in a separate Finder window.

Use the gear button to place Folder Dock at the **Top Left**, **Top Center**, or **Top Right** of the screen. The selected edge controls the reveal zone and resize anchor, and its reveal width can be adjusted in Settings. Screen-edge hover can be enabled or disabled independently. Press `⌥E` anywhere to show or hide Folder Dock.

Panels opened by edge hover close shortly after the pointer leaves. After you interact with the panel, it closes when the pointer remains outside for 3 seconds. Panels opened with `⌥E` or the menu-bar button close when you click another app or after 5 seconds without mouse/keyboard interaction. Press `⌥E` again, `Esc`, or **×** to close immediately.

Folder sets, saved items, and preferences stay local in macOS User Defaults and are not included in the repository or release files.

## Install from GitHub

Folder Dock requires macOS 14 or newer.

1. Download the latest `Folder-Dock-*.zip` from [GitHub Releases](https://github.com/regulartoast2812/Folder-Dock/releases/latest).
2. Unzip it and move **Folder Dock.app** into **Applications**.
3. Open the app. If macOS blocks the first launch, right-click the app, choose **Open**, then confirm **Open**. You can also use **System Settings → Privacy & Security → Open Anyway**.
4. Click the Folder Dock menu-bar icon to begin. Edge-hover activation remains available and can be configured in Settings.

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

The browser search bar can filter **This Folder** or search **All Subfolders**. Recursive results are shown as an expandable folder tree, so each match remains visible in its actual folder hierarchy instead of appearing as a detached flat result.

You can drag any saved file, folder, or browser item directly into another app, including file-upload targets. Dragging an item back onto the shelf adds it to the active folder set.

On the saved-item shelf, drag from empty space to draw a selection box across items. Hold the pointer near or beyond either horizontal edge while dragging to auto-scroll through longer sets. You can also use `Command`-click to toggle individual items or `Shift`-click to select a range. Drag any highlighted item to send the complete selection to Finder, an upload field, or another app.

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
