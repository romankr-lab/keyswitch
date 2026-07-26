import Cocoa
import ObjectiveC
import ApplicationServices

class StatusBarController {

    private var statusItem: NSStatusItem
    private let clipboardManager = ClipboardHistoryManager.shared

    init() {
        NSLog("🎯 StatusBarController init started")

        NSLog("📍 Creating NSStatusItem...")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        NSLog("✅ NSStatusItem created")

        if let button = statusItem.button {
            // Custom brand icon (clipboard glyph) instead of the old "⌘" text.
            // Marked as a template image so macOS automatically renders it in
            // the correct color for the light/dark menu bar and for the
            // selected/highlighted state - no manual tinting needed.
            if let icon = NSImage(named: "StatusBarIcon") {
                icon.isTemplate = true
                button.image = icon
                NSLog("✅ Status bar button created with custom icon")
            } else {
                // Fallback so the app is never left with a blank status item
                // if the asset is ever missing from the bundle.
                button.title = "\u{1F4CB}"
                NSLog("⚠️ StatusBarIcon asset not found, falling back to \u{1F4CB} title")
            }
        } else {
            NSLog("❌ CRITICAL: Failed to create status bar button!")
        }

        NSLog("📍 Creating menu...")
        // Menu for clicking on the icon in the menu bar
        statusItem.menu = makeMenu()
        NSLog("✅ Menu created and assigned")

        // Update menu when clipboard history changes
        NSLog("📍 Setting up NotificationCenter observer...")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadMenu),
            name: .clipboardDidUpdate,
            object: nil
        )
        NSLog("✅ NotificationCenter observer set up")
        NSLog("🎉 StatusBarController init COMPLETED successfully!")
    }

    @objc private func reloadMenu() {
        statusItem.menu = makeMenu()
    }

    /// Called from AppDelegate on ⌥+V — shows menu at cursor location
    func showMenuFromHotKey() {
        let menu = makeMenu()
        let mouseLocation = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: mouseLocation, in: nil)
    }

    /// Builds menu (Recent + Pinned + Settings + system items)
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.minimumWidth = 200
        menu.autoenablesItems = false

        let recent = clipboardManager.visibleRecentItems()
        let pinned = clipboardManager.visiblePinnedItems()

        // ====== RECENT ======
        if recent.isEmpty && pinned.isEmpty {
            let emptyItem = NSMenuItem(
                title: "Clipboard is empty",
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            // Add all items - menu will automatically add scrolling if > 10
            for (index, entry) in recent.enumerated() {
                menu.addItem(makeMenuItem(for: entry, index: index))
            }
        }

        // ====== PINNED ======
        if !pinned.isEmpty {
            menu.addItem(NSMenuItem.separator())

            let pinnedHeader = NSMenuItem(title: "Pinned", action: nil, keyEquivalent: "")
            pinnedHeader.isEnabled = false
            menu.addItem(pinnedHeader)

            for entry in pinned {
                let item = makeMenuItem(for: entry, index: nil, isPinnedSection: true)
                menu.addItem(item)
            }
        }

        // ====== Settings ======
        menu.addItem(NSMenuItem.separator())

        // Settings…
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // "Debug Accessibility…" stays in Settings (still #if DEBUG-only
        // there). "Transform Text (⌃+T)" moved back here - it's a quick
        // manual trigger people actually use, not just a dev-only tool.
        #if DEBUG
        let transformItem = NSMenuItem(
            title: "Transform Text (⌃+T)",
            action: #selector(testTransformText),
            keyEquivalent: ""
        )
        transformItem.target = self
        menu.addItem(transformItem)
        #endif

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    /// Creates NSMenuItem for clipboard entry
    private func makeMenuItem(for entry: ClipboardEntry,
                              index: Int?,
                              isPinnedSection: Bool = false) -> NSMenuItem {

        var title: String
        var thumbnail: NSImage? = nil
        var isImageEntry = false

        switch entry.content {
        case .text(let text):
            var t = text.replacingOccurrences(of: "\n", with: " ")
            if t.count > 60 {
                let end = t.index(t.startIndex, offsetBy: 60)
                t = String(t[..<end]) + "…"
            }
            title = t
        case .image(let data):
            isImageEntry = true
            if let image = NSImage(data: data) {
                thumbnail = Self.thumbnail(for: image)
                let dims = "\(Int(image.size.width))×\(Int(image.size.height))"
                title = "Image (\(dims))"
            } else {
                title = "Image"
            }
        }

        let isPinned = clipboardManager.isPinned(entry)

        // Plain "N. " ordinal prefix for recent items - just a visual index
        // to help orient in the list, not a real keyboard shortcut.
        let ordinal = index.map { "\($0 + 1). " } ?? ""

        let displayTitle: String
        if isImageEntry, let thumb = thumbnail {
            // NSMenuItem always draws item.image BEFORE the title text, no
            // matter what's in the title string - so putting "N. " at the
            // front of the title here would render it AFTER the thumbnail,
            // not before it. Instead, bake the ordinal into the icon itself,
            // to the left of the thumbnail, so it visually leads like it
            // does for text rows.
            displayTitle = isPinned ? "★ " + title : title
            thumbnail = Self.composeOrdinalBadge(ordinal: ordinal, thumbnail: thumb)
        } else {
            displayTitle = ordinal + (isPinned ? "★ " + title : title)
        }

        let item = NSMenuItem(
            title: displayTitle,
            action: #selector(didSelectClipboardItem(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = entry
        item.image = thumbnail
        return item
    }

    /// Draws a plain-text ordinal number ("N. ") immediately to the left of a
    /// clipboard thumbnail, composited into a single image, since NSMenuItem
    /// has no way to place title text before its `.image` (the icon is always
    /// drawn first).
    private static func composeOrdinalBadge(ordinal: String, thumbnail: NSImage) -> NSImage {
        let trimmedOrdinal = ordinal.trimmingCharacters(in: .whitespaces)
        guard !trimmedOrdinal.isEmpty else { return thumbnail }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = trimmedOrdinal.size(withAttributes: attributes)
        let spacing: CGFloat = 4
        let thumbSize = thumbnail.size
        let totalSize = NSSize(width: textSize.width + spacing + thumbSize.width,
                                height: max(textSize.height, thumbSize.height))

        return NSImage(size: totalSize, flipped: false) { rect in
            let textY = (rect.height - textSize.height) / 2
            trimmedOrdinal.draw(at: NSPoint(x: 0, y: textY), withAttributes: attributes)

            let thumbY = (rect.height - thumbSize.height) / 2
            thumbnail.draw(in: NSRect(x: textSize.width + spacing, y: thumbY,
                                       width: thumbSize.width, height: thumbSize.height))
            return true
        }
    }
    
    /// Scales a full-size clipboard image down to a small icon suitable for
        /// use as an NSMenuItem's `.image` (menu bar icons render best around
        /// 16-32pt; the original image size would look enormous and misaligned).
        private static func thumbnail(for image: NSImage, maxDimension: CGFloat = 32) -> NSImage {
            let size = image.size
            guard size.width > 0, size.height > 0 else { return image }

            let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
            let targetSize = NSSize(width: size.width * scale, height: size.height * scale)

            return NSImage(size: targetSize, flipped: false) { rect in
                image.draw(in: rect)
                return true
            }
        }
    
    // Click on history item → copy text to clipboard
    @objc private func didSelectClipboardItem(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? ClipboardEntry else { return }

        // Check if Option key is pressed (for pin/unpin)
        let event = NSApp.currentEvent
        if let event = event, event.modifierFlags.contains(.option) {
            // Option+Click - toggle pin/unpin
            clipboardManager.togglePin(for: entry)
            reloadMenu()
        } else {
            // Normal click - copy to clipboard and paste
            // Store the frontmost app before closing menu
            let frontmostApp = NSWorkspace.shared.frontmostApplication

            sender.menu?.cancelTracking()

            // Small delay to ensure menu is fully closed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.copyEntryToClipboard(entry, restoreFocusTo: frontmostApp)
            }
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow()
    }

    // Debug Accessibility stays in the Settings window
    // (SettingsWindowController.swift, #if DEBUG-only).
    #if DEBUG
    @objc private func testTransformText() {
        print("🧪 Test Transform Text menu item clicked")
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.transformSelectedText()
        }
    }
    #endif

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension StatusBarController {
    func copyEntryToClipboard(_ entry: ClipboardEntry, restoreFocusTo frontmostApp: NSRunningApplication? = nil) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch entry.content {
        case .text(let text):
            pb.setString(text, forType: .string)
            NSLog("📋 Selected from history (text): \(text.prefix(50))...")
            print("📋 Selected from history (text): \(text.prefix(50))...")
        case .image(let data):
            pb.setData(data, forType: .png)
            NSLog("📋 Selected from history (image, \(data.count) bytes)")
            print("📋 Selected from history (image, \(data.count) bytes)")
        }

        // Automatically paste using ⌘+V simulation (works for both text and images)
        pasteTextFromClipboard(restoreFocusTo: frontmostApp)
    }

    /// Simulates ⌘+V to paste text from clipboard
    private func pasteTextFromClipboard(restoreFocusTo frontmostApp: NSRunningApplication? = nil) {
        NSLog("🔧 Starting paste operation...")
        print("🔧 Starting paste operation...")

        // Restore focus to the previous app if needed
        if let app = frontmostApp {
            NSLog("🔧 Restoring focus to: \(app.localizedName ?? "unknown")")
            print("🔧 Restoring focus to: \(app.localizedName ?? "unknown")")
            app.activate(options: [])
        }

        // Longer delay to ensure clipboard is ready, menu is closed, and focus is restored
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSLog("🔧 Creating event source for paste...")
            print("🔧 Creating event source for paste...")

            guard let source = CGEventSource(stateID: .hidSystemState) else {
                NSLog("❌ Failed to create event source for paste")
                print("❌ Failed to create event source for paste")
                return
            }

            // Simulate ⌘+V (V key = 0x09)
            NSLog("🔧 Simulating ⌘+V key down...")
            print("🔧 Simulating ⌘+V key down...")

            let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            vKeyDown?.flags = .maskCommand
            vKeyDown?.post(tap: .cghidEventTap)
            NSLog("🔧 Key down posted")
            print("🔧 Key down posted")

            // Small delay between key down and key up
            usleep(10000) // 10ms

            NSLog("🔧 Simulating ⌘+V key up...")
            print("🔧 Simulating ⌘+V key up...")

            let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            vKeyUp?.flags = .maskCommand
            vKeyUp?.post(tap: .cghidEventTap)
            NSLog("🔧 Key up posted")
            print("🔧 Key up posted")

            NSLog("✅ Paste command (⌘+V) simulated")
            print("✅ Paste command (⌘+V) simulated")
        }
    }
}
