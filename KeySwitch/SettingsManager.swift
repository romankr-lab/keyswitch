import Foundation
import AppKit

final class SettingsManager {

    static let shared = SettingsManager()

    private init() {
        load()
    }

    private enum Keys {
        static let autoPasteEnabled = "autoPasteEnabled"
        static let historyLimit = "historyLimit"
        static let clipboardHotKeyCode = "clipboardHotKeyCode"
        static let clipboardHotKeyModifiers = "clipboardHotKeyModifiers"
        static let transformHotKeyCode = "transformHotKeyCode"
        static let transformHotKeyModifiers = "transformHotKeyModifiers"
    }

    // Carbon virtual key codes for the default combos (well-known, stable
    // across keyboard layouts): V = 0x09, T = 0x11.
    private static let defaultClipboardKeyCode: UInt32 = 9   // V
    private static let defaultTransformKeyCode: UInt32 = 17  // T
    private static let defaultModifiers: UInt = NSEvent.ModifierFlags.option.rawValue

    /// Whether to try automatically performing ⌘+V after click (experimental)
    var autoPasteEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(autoPasteEnabled, forKey: Keys.autoPasteEnabled)
        }
    }

    /// How many history items to show in menu (recent)
    var historyLimit: Int = 10 {
        didSet {
            UserDefaults.standard.set(historyLimit, forKey: Keys.historyLimit)
        }
    }

    // MARK: - Customizable global hotkeys
    //
    // Both default to Option (⌥) + a letter, per the product's convention:
    // ⌥V opens clipboard history, ⌥T fixes the keyboard layout of the
    // selected text. Stored as raw Carbon keyCode + NSEvent.ModifierFlags
    // rawValue rather than the HotKey package's `Key` enum directly, since
    // that's what both HotKey's `Key(carbonKeyCode:)` and UserDefaults can
    // work with directly.

    var clipboardHotKeyCode: UInt32 = SettingsManager.defaultClipboardKeyCode {
        didSet {
            UserDefaults.standard.set(clipboardHotKeyCode, forKey: Keys.clipboardHotKeyCode)
        }
    }

    var clipboardHotKeyModifiers: UInt = SettingsManager.defaultModifiers {
        didSet {
            UserDefaults.standard.set(clipboardHotKeyModifiers, forKey: Keys.clipboardHotKeyModifiers)
        }
    }

    var transformHotKeyCode: UInt32 = SettingsManager.defaultTransformKeyCode {
        didSet {
            UserDefaults.standard.set(transformHotKeyCode, forKey: Keys.transformHotKeyCode)
        }
    }

    var transformHotKeyModifiers: UInt = SettingsManager.defaultModifiers {
        didSet {
            UserDefaults.standard.set(transformHotKeyModifiers, forKey: Keys.transformHotKeyModifiers)
        }
    }

    private func load() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Keys.autoPasteEnabled) != nil {
            autoPasteEnabled = defaults.bool(forKey: Keys.autoPasteEnabled)
        }

        if defaults.object(forKey: Keys.historyLimit) != nil {
            let saved = defaults.integer(forKey: Keys.historyLimit)
            if saved > 0 {
                historyLimit = saved
            }
        }

        if defaults.object(forKey: Keys.clipboardHotKeyCode) != nil {
            clipboardHotKeyCode = UInt32(defaults.integer(forKey: Keys.clipboardHotKeyCode))
        }
        if defaults.object(forKey: Keys.clipboardHotKeyModifiers) != nil {
            clipboardHotKeyModifiers = UInt(defaults.integer(forKey: Keys.clipboardHotKeyModifiers))
        }
        if defaults.object(forKey: Keys.transformHotKeyCode) != nil {
            transformHotKeyCode = UInt32(defaults.integer(forKey: Keys.transformHotKeyCode))
        }
        if defaults.object(forKey: Keys.transformHotKeyModifiers) != nil {
            transformHotKeyModifiers = UInt(defaults.integer(forKey: Keys.transformHotKeyModifiers))
        }
    }
}
