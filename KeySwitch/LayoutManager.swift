import Cocoa
import Carbon
import ApplicationServices
import os.log

struct KeyboardLayout {
    let id: String
    let name: String
    let source: TISInputSource

    init?(source: TISInputSource) {
        self.source = source

        // Get ID
        guard let idUnmanaged = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        let id = Unmanaged<CFString>.fromOpaque(idUnmanaged).takeUnretainedValue() as String

        // Get name
        var name = id
        if let nameUnmanaged = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            name = Unmanaged<CFString>.fromOpaque(nameUnmanaged).takeUnretainedValue() as String
        }

        self.id = id
        self.name = name
    }
}

class LayoutManager {
    static let shared = LayoutManager()
    private let logger = OSLog(subsystem: "com.romank.keyswitch", category: "LayoutManager")

    private init() {
        os_log("LayoutManager initialized", log: logger, type: .info)
    }

    /// Gets list of all active keyboard layouts
    func getActiveLayouts() -> [KeyboardLayout] {
        os_log("Getting active layouts...", log: logger, type: .info)
        print("🔍 Getting active layouts...")
        var layouts: [KeyboardLayout] = []

        // FIX 1: the real API is TISCreateInputSourceList, not
        // "TISCopyInputSourceList" (which doesn't exist under that name —
        // that's why it couldn't be found either at compile time via a
        // direct Swift call, or at runtime via dlsym; both were correct,
        // the function name itself was simply wrong). No dlopen/dlsym
        // workaround is needed at all once the name is right.
        //
        // FIX 2: includeAllInstalled must be false, not true. With true,
        // this returns every keyboard layout bundled with macOS (272 of
        // them on a typical system) regardless of whether the user has
        // enabled it, which defeats the point of "getActiveLayouts" and
        // makes getNextLayout()'s "switch to the other one" logic cycle
        // through effectively random unrelated languages instead of just
        // the 2-3 layouts the user actually added in System Settings.
        guard let inputSourceListUnmanaged = TISCreateInputSourceList(nil, false) else {
            os_log("❌ TISCreateInputSourceList returned nil", log: logger, type: .error)
            print("❌ TISCreateInputSourceList returned nil")
            return []
        }

        let inputSourceList = inputSourceListUnmanaged.takeRetainedValue()
        os_log("✅ Got input source list from TISCreateInputSourceList", log: logger, type: .info)
        print("✅ Got input source list")

        let count = CFArrayGetCount(inputSourceList)
        let keyboardCategory = kTISCategoryKeyboardInputSource as String
        os_log("📋 Found %d total input sources", log: logger, type: .info, count)
        print("📋 Found \(count) input sources total")

        for i in 0..<count {
            let value = CFArrayGetValueAtIndex(inputSourceList, i)
            let source = Unmanaged<TISInputSource>.fromOpaque(value!).takeUnretainedValue()

            // Get category
            var category: String? = nil
            if let categoryUnmanaged = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) {
                category = Unmanaged<CFString>.fromOpaque(categoryUnmanaged).takeUnretainedValue() as String
            }

            // Get ID for diagnostics
            var sourceID: String? = nil
            if let idUnmanaged = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                sourceID = Unmanaged<CFString>.fromOpaque(idUnmanaged).takeUnretainedValue() as String
            }

            // Check if this is a keyboard layout
            let isKeyboardLayout = category == keyboardCategory

            // Also check if this is not an IME or other input type
            var isSelectable = false
            if let selectableUnmanaged = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) {
                let cfBool = Unmanaged<CFBoolean>.fromOpaque(selectableUnmanaged).takeUnretainedValue()
                isSelectable = CFBooleanGetValue(cfBool)
            }

            os_log("  Source %d: ID=%{public}@ category=%{public}@ isKeyboardLayout=%{public}@ isSelectable=%{public}@",
                   log: logger, type: .debug, i, sourceID ?? "nil", category ?? "nil", String(isKeyboardLayout), String(isSelectable))

            // Add layout if it's a keyboard layout and selectable
            if isKeyboardLayout && isSelectable {
                if let layout = KeyboardLayout(source: source) {
                    os_log("  ✅ Added layout: %{public}@ (%{public}@)", log: logger, type: .info, layout.name, layout.id)
                    print("  ✅ Added layout: \(layout.name) (\(layout.id))")
                    layouts.append(layout)
                } else {
                    os_log("  ❌ Failed to create layout from source %d", log: logger, type: .error, i)
                    print("  ❌ Failed to create layout from source \(i)")
                }
            }
        }

        os_log("🎯 Total keyboard layouts found: %d", log: logger, type: .info, layouts.count)
        print("🎯 Total keyboard layouts found: \(layouts.count)")
        if layouts.isEmpty {
            os_log("⚠️ No keyboard layouts found! Check System Settings → Keyboard → Input Sources", log: logger, type: .error)
            print("⚠️ No keyboard layouts found! Check System Settings → Keyboard → Input Sources")
        }
        return layouts
    }

    /// Gets current active layout
    func getCurrentLayout() -> KeyboardLayout? {
        os_log("🔍 Getting current keyboard layout...", log: logger, type: .info)
        print("🔍 Getting current keyboard layout...")

        guard let currentSourceUnmanaged = TISCopyCurrentKeyboardInputSource() else {
            os_log("❌ TISCopyCurrentKeyboardInputSource returned nil", log: logger, type: .error)
            print("❌ TISCopyCurrentKeyboardInputSource returned nil")
            return nil
        }

        let currentSource = currentSourceUnmanaged.takeRetainedValue()

        guard let layout = KeyboardLayout(source: currentSource) else {
            os_log("❌ Failed to create KeyboardLayout from source", log: logger, type: .error)
            print("❌ Failed to create KeyboardLayout from source")
            return nil
        }

        os_log("✅ Current layout: %{public}@ (%{public}@)", log: logger, type: .info, layout.name, layout.id)
        print("✅ Current layout: \(layout.name) (\(layout.id))")
        return layout
    }

    /// Determines next layout for switching
    func getNextLayout() -> KeyboardLayout? {
        let layouts = getActiveLayouts()
        guard !layouts.isEmpty else { return nil }

        guard let current = getCurrentLayout() else {
            // If we can't determine current, return first one
            return layouts.first
        }

        // Find index of current layout
        guard let currentIndex = layouts.firstIndex(where: { $0.id == current.id }) else {
            return layouts.first
        }

        // If only one layout
        if layouts.count == 1 {
            return nil
        }

        // If two layouts - switch to opposite
        if layouts.count == 2 {
            return layouts[1 - currentIndex]
        }

        // If more than two - switch to next in cycle
        let nextIndex = (currentIndex + 1) % layouts.count
        return layouts[nextIndex]
    }

    /// Switches to specified layout
    func switchToLayout(_ layout: KeyboardLayout) -> Bool {
        let status = TISSelectInputSource(layout.source)
        return status == noErr
    }

    /// Switches to next layout
    @discardableResult
    func switchToNextLayout() -> Bool {
        guard let nextLayout = getNextLayout() else { return false }
        return switchToLayout(nextLayout)
    }
}
