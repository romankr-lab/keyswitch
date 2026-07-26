# KeySwitch

A lightweight macOS menu bar app: **clipboard history** (ready to use) and **keyboard layout text transformation** (in development). No Dock icon — runs from the status bar only.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue) ![Swift](https://img.shields.io/badge/Swift-5-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Clipboard history (⌥ Option + V)** ✅ — Open a menu of recent copies; click an item to copy it to the clipboard and **paste it immediately** into the focused app (no extra ⌘V needed).
- **Pin entries** — Star items to keep them at the top of the list.
- **Text transformation (⌃ Control + T)** 🚧 *In development* — Planned: select text, press the hotkey; the app will convert it between keyboard layouts (e.g. US ↔ Ukrainian) and switch to the next layout. Not yet reliable in all apps.
- **Settings** — Configure history size and toggle clipboard history on or off.
- **Accessibility check on startup** — If access is missing, a window opens with a button that takes you straight to **System Settings → Privacy & Security → Accessibility**.

## Requirements

- macOS 14.0 or later  
- Apple Silicon or Intel  
- **Accessibility** permission (for global hotkeys; required for future text transformation)

## Installation

### From release (recommended)

1. Open the [Releases](https://github.com/romankr-lab/KeySwitch/releases) page.
2. Download the latest `KeySwitch.dmg`.
3. Open the DMG and drag **KeySwitch.app** into **Applications**.
4. Launch KeySwitch from Applications (or Spotlight).
5. When prompted, grant **Accessibility** access in **System Settings → Privacy & Security → Accessibility**.

### Build from source

1. Clone the repo:
   ```bash
   git clone https://github.com/romankr-lab/KeySwitch.git
   cd KeySwitch
   ```
2. Open in Xcode and build (⌘B), or use the script:
   ```bash
   ./build_and_package.sh
   ```
   This produces `KeySwitch.dmg` in the project folder. See [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) for details.

## Usage

| Action | Shortcut | Status |
|--------|----------|--------|
| Clipboard history menu | **⌥ Option + V** | ✅ Works |
| Transform selected text (layout swap) | **⌃ Control + T** | 🚧 In development |

- **Status bar**: Click the KeySwitch icon to open the menu (history, settings, quit).
- **Click to paste**: In the clipboard menu, clicking an item copies it and **pastes it automatically** into the frontmost app.

## Project structure

```
KeySwitch/
├── KeySwitch/           # App source
│   ├── AppDelegate.swift
│   ├── main.swift
│   ├── StatusBarController.swift
│   ├── ClipboardHistoryManager.swift
│   ├── LayoutManager.swift / LayoutTransformer.swift
│   ├── TextSelectionManager.swift
│   ├── AccessibilityPermissionWindow.swift
│   └── ...
├── build_and_package.sh  # Build and create DMG (with background and icon layout)
├── build_and_zip.sh      # Build and create ZIP
├── packaging/            # DMG background image and installer assets
├── DISTRIBUTION.md       # Install & usage guide
└── BUILD_INSTRUCTIONS.md # Build & packaging
```

## License

MIT. See [LICENSE](LICENSE).
