import Cocoa
import ServiceManagement

// Base window height without the developer-only section; DEBUG builds add
// extra room at the bottom for those controls (see SettingsViewController).
private let baseWindowHeight: CGFloat = 300
#if DEBUG
private let windowHeight: CGFloat = baseWindowHeight + 80
#else
private let windowHeight: CGFloat = baseWindowHeight
#endif

class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "KeySwitch Settings"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let viewController = SettingsViewController()
        window.contentViewController = viewController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

class SettingsViewController: NSViewController {

    // NOTE: this view is built entirely in code in loadView() — there is no
    // xib/storyboard connected to this class.

    private var historyLimitField: NSTextField!
    private var historyLimitStepper: NSStepper!
    private var launchAtLoginCheckbox: NSButton!
    private var clipboardShortcutRecorder: ShortcutRecorderView!
    private var transformShortcutRecorder: ShortcutRecorderView!

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: windowHeight))
        view.wantsLayer = true

        // Layout cursor: start at the top and work down, so every section
        // can be added/reordered without recalculating absolute y positions
        // by hand. `cursorTop` is always the y just above the next control.
        var cursorTop = windowHeight - 20

        // ---------- Launch at Login ----------
        cursorTop -= 22
        launchAtLoginCheckbox = NSButton(
            checkboxWithTitle: "Launch KeySwitch at login",
            target: self,
            action: #selector(launchAtLoginToggled(_:))
        )
        launchAtLoginCheckbox.frame = NSRect(x: 20, y: cursorTop, width: 300, height: 22)
        launchAtLoginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        view.addSubview(launchAtLoginCheckbox)

        cursorTop -= 24 // gap + divider
        let divider1 = NSBox(frame: NSRect(x: 20, y: cursorTop, width: 380, height: 1))
        divider1.boxType = .separator
        view.addSubview(divider1)

        // ---------- History Limit ----------
        cursorTop -= 30
        let historyLabel = NSTextField(labelWithString: "History Limit:")
        historyLabel.frame = NSRect(x: 20, y: cursorTop, width: 120, height: 22)
        view.addSubview(historyLabel)

        historyLimitField = NSTextField(frame: NSRect(x: 150, y: cursorTop, width: 60, height: 22))
        historyLimitField.stringValue = String(SettingsManager.shared.historyLimit)
        historyLimitField.alignment = .right
        historyLimitField.target = self
        historyLimitField.action = #selector(historyLimitChanged(_:))
        view.addSubview(historyLimitField)

        historyLimitStepper = NSStepper(frame: NSRect(x: 215, y: cursorTop, width: 19, height: 22))
        historyLimitStepper.minValue = 1
        historyLimitStepper.maxValue = 20
        historyLimitStepper.increment = 1
        historyLimitStepper.integerValue = SettingsManager.shared.historyLimit
        historyLimitStepper.target = self
        historyLimitStepper.action = #selector(historyLimitStepperChanged(_:))
        view.addSubview(historyLimitStepper)

        cursorTop -= 22
        let infoLabel = NSTextField(labelWithString: "Maximum number of clipboard items to store (1-20)")
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.frame = NSRect(x: 20, y: cursorTop, width: 380, height: 18)
        view.addSubview(infoLabel)

        cursorTop -= 20
        let noteLabel = NSTextField(labelWithString: "Note: Up to 10 items are visible without scrolling, all 20 with scrolling")
        noteLabel.font = NSFont.systemFont(ofSize: 10)
        noteLabel.textColor = .tertiaryLabelColor
        noteLabel.frame = NSRect(x: 20, y: cursorTop, width: 380, height: 16)
        view.addSubview(noteLabel)

        cursorTop -= 24 // gap + divider
        let divider2 = NSBox(frame: NSRect(x: 20, y: cursorTop, width: 380, height: 1))
        divider2.boxType = .separator
        view.addSubview(divider2)

        // ---------- Keyboard shortcuts ----------
        cursorTop -= 30
        let shortcutsHeader = NSTextField(labelWithString: "Keyboard Shortcuts")
        shortcutsHeader.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        shortcutsHeader.frame = NSRect(x: 20, y: cursorTop, width: 300, height: 18)
        view.addSubview(shortcutsHeader)

        cursorTop -= 30
        let clipboardShortcutLabel = NSTextField(labelWithString: "Clipboard History:")
        clipboardShortcutLabel.frame = NSRect(x: 20, y: cursorTop, width: 150, height: 22)
        view.addSubview(clipboardShortcutLabel)

        clipboardShortcutRecorder = ShortcutRecorderView(
            keyCode: SettingsManager.shared.clipboardHotKeyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: SettingsManager.shared.clipboardHotKeyModifiers)
        )
        clipboardShortcutRecorder.frame = NSRect(x: 180, y: cursorTop - 1, width: 130, height: 24)
        clipboardShortcutRecorder.onChange = { [weak self] keyCode, modifiers in
            SettingsManager.shared.clipboardHotKeyCode = keyCode
            SettingsManager.shared.clipboardHotKeyModifiers = modifiers.rawValue
            self?.reregisterHotKeys()
        }
        view.addSubview(clipboardShortcutRecorder)

        cursorTop -= 32
        let transformShortcutLabel = NSTextField(labelWithString: "Transform Text:")
        transformShortcutLabel.frame = NSRect(x: 20, y: cursorTop, width: 150, height: 22)
        view.addSubview(transformShortcutLabel)

        transformShortcutRecorder = ShortcutRecorderView(
            keyCode: SettingsManager.shared.transformHotKeyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: SettingsManager.shared.transformHotKeyModifiers)
        )
        transformShortcutRecorder.frame = NSRect(x: 180, y: cursorTop - 1, width: 130, height: 24)
        transformShortcutRecorder.onChange = { [weak self] keyCode, modifiers in
            SettingsManager.shared.transformHotKeyCode = keyCode
            SettingsManager.shared.transformHotKeyModifiers = modifiers.rawValue
            self?.reregisterHotKeys()
        }
        view.addSubview(transformShortcutRecorder)

        cursorTop -= 20
        let shortcutsHint = NSTextField(labelWithString: "Click a shortcut, then press a new key combo (must include a modifier)")
        shortcutsHint.font = NSFont.systemFont(ofSize: 10)
        shortcutsHint.textColor = .tertiaryLabelColor
        shortcutsHint.frame = NSRect(x: 20, y: cursorTop, width: 380, height: 16)
        view.addSubview(shortcutsHint)

        // ---------- Developer-only controls ----------
        // Moved here from the status bar menu so the everyday menu stays
        // clipboard-only. #if DEBUG means this whole block simply doesn't
        // exist in a Release/App Store build.
        #if DEBUG
        cursorTop -= 24
        let divider3 = NSBox(frame: NSRect(x: 20, y: cursorTop, width: 380, height: 1))
        divider3.boxType = .separator
        view.addSubview(divider3)

        cursorTop -= 24
        let debugLabel = NSTextField(labelWithString: "Developer")
        debugLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        debugLabel.textColor = .secondaryLabelColor
        debugLabel.frame = NSRect(x: 20, y: cursorTop, width: 200, height: 18)
        view.addSubview(debugLabel)

        cursorTop -= 32
        let accessibilityButton = NSButton(
            title: "Debug Accessibility…",
            target: self,
            action: #selector(runAccessibilityDiagnostic)
        )
        accessibilityButton.bezelStyle = .rounded
        accessibilityButton.frame = NSRect(x: 20, y: cursorTop, width: 190, height: 26)
        view.addSubview(accessibilityButton)
        #endif
    }

    // MARK: - Launch at Login

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        let enable = sender.state == .on
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("❌ Failed to \(enable ? "register" : "unregister") login item: \(error.localizedDescription)")
            // Reflect the actual (unchanged) state rather than what the
            // user clicked, since the registration call itself failed.
            sender.state = enable ? .off : .on
        }
    }

    // MARK: - History Limit

    @objc private func historyLimitChanged(_ sender: NSTextField) {
        if let value = Int(sender.stringValue), value >= 1 && value <= 20 {
            SettingsManager.shared.historyLimit = value
            historyLimitStepper.integerValue = value
            ClipboardHistoryManager.shared.applyHistoryLimitChange()
        } else {
            sender.stringValue = String(SettingsManager.shared.historyLimit)
        }
    }

    @objc private func historyLimitStepperChanged(_ sender: NSStepper) {
        let value = sender.integerValue
        SettingsManager.shared.historyLimit = value
        historyLimitField.stringValue = String(value)
        ClipboardHistoryManager.shared.applyHistoryLimitChange()
    }

    // MARK: - Shortcuts

    private func reregisterHotKeys() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.registerHotKeys()
        }
    }

    #if DEBUG
    @objc private func runAccessibilityDiagnostic() {
        AccessibilityDebugHelper.shared.performDetailedCheck()
        AccessibilityDebugHelper.shared.showDiagnosticAlert()
    }
    #endif
}
