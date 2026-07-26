import Cocoa
import ApplicationServices
import Darwin.C
import os.log

class TextSelectionManager {
    static let shared = TextSelectionManager()
    private let logger = OSLog(subsystem: "com.romank.keyswitch", category: "TextSelectionManager")

    private init() {}

    /// Checks if Accessibility permissions are granted
    func checkAccessibilityPermissions() -> Bool {
        NSLog("TSM: Checking Accessibility permissions...")

        // Check without showing dialog (status check only)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        NSLog("TSM: AXIsProcessTrustedWithOptions returned: \(isTrusted)")

        // Additional practical test: try to access frontmost app
        if let focusedApp = NSWorkspace.shared.frontmostApplication {
            let appPID = focusedApp.processIdentifier
            NSLog("TSM: Testing with frontmost app: \(focusedApp.localizedName ?? "unknown") (PID: \(appPID))")

            let appRef = AXUIElementCreateApplication(appPID)
            var focusedWindow: AnyObject?
            let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow)

            NSLog("TSM: Practical test (get focused window): \(result == .success ? "SUCCESS" : "FAILED (error: \(result.rawValue))")")

            // If practical test passed, permissions are definitely working
            if result == .success {
                NSLog("TSM: ✅ Accessibility permissions are WORKING (practical test passed)")
                return true
            } else {
                NSLog("TSM: ⚠️ Practical test failed with error: \(result.rawValue)")
            }
        } else {
            NSLog("TSM: ⚠️ No frontmost application found")
        }

        NSLog("TSM: Final result: isTrusted=\(isTrusted)")
        return isTrusted
    }

    /// Gets selected text from the active window via Accessibility API
    func getSelectedText() -> String? {
        NSLog("TSM: getSelectedText() called")

        // First try Accessibility API
        NSLog("TSM: Trying Accessibility API...")
        // FIX: some elements report a selected-text range that exists but is
        // empty (kAXValue == ""), which used to be treated as a successful
        // result and short-circuited the clipboard fallback below — even
        // though the user really did have text selected. Only accept a
        // non-empty result as success; an empty one falls through to ⌘+C.
        if let text = getSelectedTextViaAccessibility(), !text.isEmpty {
            NSLog("TSM: ✅ Successfully got text via Accessibility API (length=\(text.count))")
            return text
        }

        NSLog("TSM: ❌ Accessibility API failed, trying clipboard method...")
        // If failed, use fallback via clipboard
        let clipboardResult = getSelectedTextViaClipboard()
        if clipboardResult != nil {
            NSLog("TSM: ✅ Successfully got text via clipboard (length=\(clipboardResult?.count ?? 0))")
        } else {
            NSLog("TSM: ❌ Clipboard method also failed")
        }
        return clipboardResult
    }

    /// Gets selected text via Accessibility API
    private func getSelectedTextViaAccessibility() -> String? {
        // Get focused window
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            NSLog("TSM: No focused application")
            return nil
        }

        NSLog("TSM: Focused app: \(focusedApp.localizedName ?? "unknown") (PID: \(focusedApp.processIdentifier))")
        let appPID = focusedApp.processIdentifier
        let appRef = AXUIElementCreateApplication(appPID)

        // Get focused window
        var focusedWindow: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        if windowResult != .success {
            NSLog("TSM: Failed to get focused window: error=\(windowResult.rawValue)")
            return nil
        }

        guard let window = focusedWindow as! AXUIElement? else {
            NSLog("TSM: Window is nil")
            return nil
        }

        NSLog("TSM: Got focused window")

        // Method 1: Try to get selected text directly from window (some apps support this)
        var windowSelectedText: AnyObject?
        let windowTextResult = AXUIElementCopyAttributeValue(window, kAXSelectedTextAttribute as CFString, &windowSelectedText)
        if windowTextResult == .success, let text = windowSelectedText as? String, !text.isEmpty {
            NSLog("TSM: Got selected text directly from window: length=\(text.count), preview=\(text.prefix(50))")
            return text
        }

        // Method 2: Try to get focused element
        var focusedElement: AnyObject?
        let elementResult = AXUIElementCopyAttributeValue(window, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if elementResult == .success, let element = focusedElement as! AXUIElement? {
            NSLog("TSM: Got focused element")

            // Try to get selected text via kAXSelectedTextAttribute
            var selectedText: AnyObject?
            let textResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)

            if textResult == .success, let text = selectedText as? String, !text.isEmpty {
                NSLog("TSM: Got selected text via kAXSelectedTextAttribute: length=\(text.count), preview=\(text.prefix(50))")
                return text
            } else {
                NSLog("TSM: kAXSelectedTextAttribute failed: error=\(textResult.rawValue), text=\(selectedText != nil ? "exists but empty" : "nil")")
            }

            // Alternative method: get via kAXSelectedTextRange
            if let text = getSelectedTextViaRange(element) {
                NSLog("TSM: Got selected text via kAXSelectedTextRange: length=\(text.count), preview=\(text.prefix(50))")
                return text
            }
        } else {
            NSLog("TSM: Failed to get focused element: error=\(elementResult.rawValue). Trying to search all elements...")

            // Method 3: Search all elements in window for selected text
            if let text = searchForSelectedTextInWindow(window) {
                NSLog("TSM: Found selected text by searching window elements: length=\(text.count), preview=\(text.prefix(50))")
                return text
            }
        }

        NSLog("TSM: All Accessibility API methods failed")
        return nil
    }

    /// Searches for selected text in all elements of the window
    private func searchForSelectedTextInWindow(_ window: AXUIElement) -> String? {
        NSLog("TSM: Searching for selected text in window elements...")

        // Get all children of the window
        var children: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children)

        guard childrenResult == .success, let childrenArray = children as? [AXUIElement] else {
            NSLog("TSM: Failed to get window children: error=\(childrenResult.rawValue)")
            return nil
        }

        NSLog("TSM: Found \(childrenArray.count) children in window")

        // Search recursively in children
        for child in childrenArray {
            if let text = searchForSelectedTextInElement(child, depth: 0) {
                return text
            }
        }

        return nil
    }

    /// Recursively searches for selected text in an element and its children
    private func searchForSelectedTextInElement(_ element: AXUIElement, depth: Int = 0) -> String? {
        // Limit recursion depth to avoid infinite loops
        guard depth < 10 else { return nil }

        // Try to get selected text from this element
        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)

        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            NSLog("TSM: Found selected text in element (depth=\(depth)): length=\(text.count), preview=\(text.prefix(50))")
            return text
        }

        // Try via range method
        if let text = getSelectedTextViaRange(element) {
            NSLog("TSM: Found selected text via range in element (depth=\(depth)): length=\(text.count), preview=\(text.prefix(50))")
            return text
        }

        // Try to get role to understand what element we're dealing with
        var role: AnyObject?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if roleResult == .success, let roleString = role as? String {
            // For text fields, text areas, and editors, try harder
            if ["AXTextArea", "AXTextField", "AXText", "AXStaticText", "AXScrollArea", "AXWebArea"].contains(roleString) {
                // Try to get all text and check if there's a selection
                var allText: AnyObject?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &allText) == .success,
                   let text = allText as? String, !text.isEmpty {
                    // Check if there's a selected range
                    var selectedRange: AnyObject?
                    if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success {
                        // If there's a selection range, return the text (simplified - could extract range)
                        NSLog("TSM: Found text element with selection range (role=\(roleString)): length=\(text.count)")
                        return text
                    }
                }
            }
        }

        // Recursively search in children (limit depth to avoid infinite recursion)
        var children: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

        if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
            for (index, child) in childrenArray.prefix(50).enumerated() { // Increased limit to 50
                if let text = searchForSelectedTextInElement(child, depth: depth + 1) {
                    NSLog("TSM: Found text in child \(index) at depth \(depth)")
                    return text
                }
            }
        }

        return nil
    }

    /// Alternative method: getting selected text via range
    private func getSelectedTextViaRange(_ element: AXUIElement) -> String? {
        // Get the selection range
        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

        guard rangeResult == .success, let _ = selectedRange else {
            return nil
        }

        // Get the element's full text
        var allText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &allText)

        guard textResult == .success, let text = allText as? String else {
            // Try via kAXTextAttribute
            let textResult2 = AXUIElementCopyAttributeValue(element, kAXTextAttribute as CFString, &allText)
            guard textResult2 == .success, let text2 = allText as? String, !text2.isEmpty else {
                return nil
            }
            return text2
        }

        // If a range exists, extract the corresponding part
        // (simplified - returns the full text if a range exists).
        // FIX: a present-but-empty kAXValue used to be returned as a "found"
        // result, which stopped the caller from continuing to search other
        // elements or falling back to the clipboard method. Treat empty as
        // not-found instead.
        guard !text.isEmpty else {
            return nil
        }
        return text
    }

    /// Alternative method: gets selected text via the clipboard (⌘+C)
    private func getSelectedTextViaClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string) // Save previous contents

        os_log("TSM: Attempting to copy selected text via ⌘+C...", log: logger, type: .info)
        print("TSM: Attempting to copy selected text via ⌘+C...")

        // Simulate ⌘+C to copy the selected text
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("TSM: Failed to create event source")
            return nil
        }

        // Press ⌘+C
        guard let cKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) else {
            print("TSM: Failed to create key down event")
            return nil
        }
        cKeyDown.flags = .maskCommand
        cKeyDown.post(tap: .cghidEventTap)

        guard let cKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
            print("TSM: Failed to create key up event")
            return nil
        }
        cKeyUp.flags = .maskCommand
        cKeyUp.post(tap: .cghidEventTap)

        // Increased delay to give the text time to be copied.
        // FIX: this used to be a DispatchSemaphore that was signaled from a
        // DispatchQueue.main.asyncAfter block. When this method runs on the
        // main thread (which it does — it's called from transformSelectedText,
        // itself dispatched via DispatchQueue.main.async), semaphore.wait()
        // blocks the main thread/queue, so the asyncAfter block — which is
        // also queued on the main queue — can never run to signal it back.
        // That's a permanent deadlock, which is exactly why the app froze
        // when the clipboard fallback kicked in. Waiting on the run loop
        // instead lets queued work keep draining while we "block".
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        // Read the text from the clipboard
        let copiedText = pasteboard.string(forType: .string)

        // Check whether the content actually changed (to avoid returning stale content)
        if let old = oldContents, let new = copiedText, old == new {
            os_log("TSM: Clipboard content did not change - no text was selected or copied", log: logger, type: .error)
            print("TSM: Clipboard content did not change - no text was selected or copied")
            return nil
        }

        // Restore the previous clipboard contents
        if let old = oldContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }

        if let text = copiedText, !text.isEmpty {
            os_log("TSM: ✅ Successfully got selected text via clipboard (length=%d)", log: logger, type: .info, text.count)
            print("TSM: Successfully got selected text via clipboard: \(text.prefix(50))...")
            return text
        }

        os_log("TSM: ❌ No text found in clipboard after ⌘+C", log: logger, type: .error)
        print("TSM: No text found in clipboard after ⌘+C")
        return nil
    }

    /// Replaces the selected text with new text
    func replaceSelectedText(with newText: String) -> Bool {
        // FIX: this used to `return false` immediately if the frontmost app,
        // its focused window, or its focused element couldn't be reached via
        // Accessibility — which is exactly what happens in web-based /
        // Electron-style UIs (the same -25205 error we saw when reading the
        // selection). That meant the keyboard-simulation fallback below was
        // only ever reached if AXUIElementSetAttributeValue itself failed,
        // never when the AX element lookup failed. Now any failure along the
        // AX path falls through to the fallback instead of bailing out early.
        if let focusedApp = NSWorkspace.shared.frontmostApplication {
            let appPID = focusedApp.processIdentifier
            let appRef = AXUIElementCreateApplication(appPID)

            // Get the focused window
            var focusedWindow: AnyObject?
            let windowResult = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow)

            if windowResult == .success, let window = focusedWindow as! AXUIElement? {
                // Get the focused element
                var focusedElement: AnyObject?
                let elementResult = AXUIElementCopyAttributeValue(window, kAXFocusedUIElementAttribute as CFString, &focusedElement)

                if elementResult == .success, let element = focusedElement as! AXUIElement? {
                    // Set the new text
                    let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)

                    if setResult == .success {
                        return true
                    }
                }
            }
        }

        // Fallback: if the AX path didn't work at all, use keyboard simulation
        return replaceSelectedTextWithKeyboardSimulation(newText)
    }

    /// Fallback method: replaces text via keyboard simulation
    private func replaceSelectedTextWithKeyboardSimulation(_ newText: String) -> Bool {
        // Use NSPasteboard to paste
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string) // Save previous contents
        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)

        // Simulate ⌘+V to paste
        let source = CGEventSource(stateID: .hidSystemState)

        // Delete the selected text (Delete key = 0x33)
        let deleteKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)
        deleteKeyDown?.post(tap: .cghidEventTap)
        let deleteKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
        deleteKeyUp?.post(tap: .cghidEventTap)

        // Small delay
        usleep(50000) // 50ms

        // Paste the new text via ⌘+V (V key = 0x09)
        let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vKeyDown?.flags = .maskCommand
        vKeyDown?.post(tap: .cghidEventTap)

        let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vKeyUp?.flags = .maskCommand
        vKeyUp?.post(tap: .cghidEventTap)

        // Restore the previous clipboard contents (optional)
        if let old = oldContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }

        return true
    }
}
