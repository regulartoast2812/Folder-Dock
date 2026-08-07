# Folder Dock

A compact macOS folder launcher that appears when you move the pointer to the top-center edge of the screen.

## Use

1. Run `./scripts/build-app.sh`.
2. Open `dist/Folder Dock.app`.
3. Add folders with the **+** button or drag folders into the dock.
4. Hover anywhere in the top-center 24 pixels of a display to reveal it.

Saved folders are stored locally in the app's User Defaults. Click a folder to open it; right-click to reveal or remove it.

## Finder-style browser shortcuts

When browsing a saved folder, click once to select an item and double-click to open it.

You can drag any saved folder or browser item directly into another app, including file-upload targets. Dragging a folder back onto the saved-folder shelf adds it to the active folder set.

Drag files or folders from Finder onto the open browser to move them into that folder, or onto a folder tile to move them into that specific folder. Hold `Option` while dropping to copy instead.

- `⌘[` / `⌘]` or Logitech MX side buttons: back / forward
- `⌘↑`: enclosing folder
- `Return` or `⌘O`: open the selected item
- `Space`: Quick Look the selected item
- `⇧⌘N`: new folder
- `⌘R`: refresh
- `⌘N`: open the current folder in Finder
- `⌘W`: return to the folder shelf
- `⌥⌘←` / `⌥⌘→`: previous / next folder set
- `⌘C`, `⌘D`, `⌘I`, `⌘Delete`: copy, duplicate, get info, move selected item to Trash
