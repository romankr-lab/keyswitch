import Cocoa
import ApplicationServices
import os.log
import Security

/// Utility for diagnosing Accessibility issues (updated to work correctly in release builds)
final class AccessibilityDebugHelper {
    static let shared = AccessibilityDebugHelper()
    private let logger = OSLog(subsystem: "com.romank.keyswitch", category: "AccessibilityDebug")

    private init() {}

    // MARK: - Public methods

    /// Detailed check of all Accessibility-related aspects
    func performDetailedCheck(requestPromptIfNeeded: Bool = false) {
        os_log("========== ACCESSIBILITY DEBUG START ==========", log: logger, type: .info)
        #if DEBUG
        print("========== ACCESSIBILITY DEBUG START ==========")
        #endif

        // 1. Bundle ID
        let bundleID = Bundle.main.bundleIdentifier ?? "UNKNOWN"
        os_log("1. Bundle ID: %{public}@", log: logger, type: .info, bundleID)
        #if DEBUG
        print("1. Bundle ID: \(bundleID)")
        #endif

        // 2. App Path
        let appPath = Bundle.main.bundlePath
        os_log("2. App Path: %{public}@", log: logger, type: .info, appPath)
        #if DEBUG
        print("2. App Path: \(appPath)")
        #endif

        // 3. Executable Path
        let execPath = Bundle.main.executablePath ?? "UNKNOWN"
        os_log("3. Executable Path: %{public}@", log: logger, type: .info, execPath)
        #if DEBUG
        print("3. Executable Path: \(execPath)")
        #endif

        // 4. Code Signature
        checkCodeSignature()

        // 5. Accessibility Trust - WITHOUT prompt
        let isTrustedWithoutPrompt = AXIsProcessTrusted()
        os_log("5. AXIsProcessTrusted() = %{public}@", log: logger, type: .info, String(isTrustedWithoutPrompt))
        #if DEBUG
        print("5. AXIsProcessTrusted() = \(isTrustedWithoutPrompt)")
        #endif

        if !isTrustedWithoutPrompt {
            os_log("   ⚠️ Accessibility is not enabled for this app. Open System Settings → Privacy & Security → Accessibility and enable access for %{public}@", log: logger, type: .fault, bundleID)
        }

        // 6. Accessibility Trust - WITH options (no prompt or prompt if requested)
        let optionsKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: [String: Any] = [optionsKey: requestPromptIfNeeded]
        let isTrustedWithOptions = AXIsProcessTrustedWithOptions(options as CFDictionary)
        os_log("6. AXIsProcessTrustedWithOptions(prompt=%{public}@) = %{public}@", log: logger, type: .info, String(requestPromptIfNeeded), String(isTrustedWithOptions))
        #if DEBUG
        print("6. AXIsProcessTrustedWithOptions(prompt=\(requestPromptIfNeeded)) = \(isTrustedWithOptions)")
        #endif

        // 7. Info.plist - LSUIElement
        let lsuiElement = Bundle.main.infoDictionary?["LSUIElement"] as? Bool ?? false
        os_log("7. LSUIElement in Info.plist: %{public}@", log: logger, type: .info, String(lsuiElement))
        #if DEBUG
        print("7. LSUIElement in Info.plist: \(lsuiElement)")
        #endif

        // 8. Sandboxing
        let isSandboxed = checkSandboxing()
        os_log("8. App is sandboxed: %{public}@", log: logger, type: .info, String(isSandboxed))
        #if DEBUG
        print("8. App is sandboxed: \(isSandboxed)")
        #endif

        // 9. Process ID
        let pid = ProcessInfo.processInfo.processIdentifier
        os_log("9. Process ID: %d", log: logger, type: .info, pid)
        #if DEBUG
        print("9. Process ID: \(pid)")
        #endif

        // 10. Try to access a system element
        testAccessibilityAPI()

        os_log("========== ACCESSIBILITY DEBUG END ==========", log: logger, type: .info)
        #if DEBUG
        print("========== ACCESSIBILITY DEBUG END ==========")
        #endif
    }

    // MARK: - Private methods

    /// Checks the app's code signature with a timeout and safe termination
    private func checkCodeSignature(timeout: TimeInterval = 3.0) {
        let codesignPath = "/usr/bin/codesign"
        guard FileManager.default.isExecutableFile(atPath: codesignPath) else {
            os_log("4. codesign tool not found at %{public}@", log: logger, type: .error, codesignPath)
            #if DEBUG
            print("4. codesign tool not found at \(codesignPath)")
            #endif
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: codesignPath)
        task.arguments = ["-dv", Bundle.main.bundlePath]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        let sema = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in
            sema.signal()
        }

        do {
            try task.run()
        } catch {
            os_log("4. Code Signature check failed to start: %{public}@", log: logger, type: .error, error.localizedDescription)
            #if DEBUG
            print("4. Code Signature check failed to start: \(error.localizedDescription)")
            #endif
            return
        }

        let waitResult = sema.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            task.terminate()
            os_log("4. Code Signature check timed out after %{public}.1f seconds", log: logger, type: .error, timeout)
            #if DEBUG
            print("4. Code Signature check timed out after \(timeout)s")
            #endif
            return
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        let output = [outStr, errStr].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        os_log("4. Code Signature:\n%{public}@", log: logger, type: .info, output)
        #if DEBUG
        print("4. Code Signature:\n\(output)")
        #endif
    }

    /// Checks whether the app is sandboxed (via entitlement or environment)
    private func checkSandboxing() -> Bool {
        // Try to read the entitlement
        if let task = SecTaskCreateFromSelf(nil),
           let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) {
            let enabled = (value as? NSNumber)?.boolValue ?? false
            return enabled
        }
        // Fall back to an environment variable
        let environment = ProcessInfo.processInfo.environment
        return environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Tests basic Accessibility API functionality
    private func testAccessibilityAPI() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            os_log("10. Cannot get frontmost application. Ensure an app window is active.", log: logger, type: .error)
            #if DEBUG
            print("10. Cannot get frontmost application. Ensure an app window is active.")
            #endif
            return
        }

        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Try to get the focused window
        var focusedWindow: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        os_log("10. Test Accessibility API:", log: logger, type: .info)
        os_log("   - Frontmost app: %{public}@ (PID: %d)", log: logger, type: .info, frontApp.localizedName ?? "unknown", frontApp.processIdentifier)
        os_log("   - AXUIElementCopyAttributeValue (FocusedWindow) result: %d (%{public}@)", log: logger, type: .info, focusedResult.rawValue, axErrorToString(focusedResult))
        #if DEBUG
        print("10. Test Accessibility API:")
        print("   - Frontmost app: \(frontApp.localizedName ?? "unknown") (PID: \(frontApp.processIdentifier))")
        print("   - AXUIElementCopyAttributeValue (FocusedWindow) result: \(focusedResult.rawValue) (\(axErrorToString(focusedResult)))")
        #endif

        // Also try to get the list of windows
        var windowsValue: AnyObject?
        let windowsResult = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue)
        os_log("   - AXUIElementCopyAttributeValue (Windows) result: %d (%{public}@)", log: logger, type: .info, windowsResult.rawValue, axErrorToString(windowsResult))
        #if DEBUG
        print("   - AXUIElementCopyAttributeValue (Windows) result: \(windowsResult.rawValue) (\(axErrorToString(windowsResult)))")
        #endif

        if focusedResult == .success || windowsResult == .success {
            os_log("   ✅ Successfully accessed Accessibility API", log: logger, type: .info)
            #if DEBUG
            print("   ✅ Successfully accessed Accessibility API")
            #endif
        } else {
            os_log("   ❌ Failed to access Accessibility API. If AX is disabled, enable it in System Settings → Privacy & Security → Accessibility.", log: logger, type: .error)
            #if DEBUG
            print("   ❌ Failed to access Accessibility API. If AX is disabled, enable it in System Settings → Privacy & Security → Accessibility.")
            #endif
        }
    }

    /// Converts an AXError into a readable string
    private func axErrorToString(_ error: AXError) -> String {
        switch error {
        case .success: return "success"
        case .failure: return "failure"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .invalidUIElementObserver: return "invalidUIElementObserver"
        case .cannotComplete: return "cannotComplete"
        case .attributeUnsupported: return "attributeUnsupported"
        case .actionUnsupported: return "actionUnsupported"
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented: return "notImplemented"
        case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
        case .notificationNotRegistered: return "notificationNotRegistered"
        case .apiDisabled: return "apiDisabled (Accessibility not enabled!)"
        case .noValue: return "noValue"
        case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: return "notEnoughPrecision"
        @unknown default: return "unknown error (\(error.rawValue))"
        }
    }

    /// Shows an alert with the diagnostic results (on the main thread)
    func showDiagnosticAlert() {
        let show: () -> Void = {
            let isTrusted = AXIsProcessTrusted()
            let bundleID = Bundle.main.bundleIdentifier ?? "UNKNOWN"
            let appPath = Bundle.main.bundlePath

            let alert = NSAlert()
            alert.messageText = "Accessibility Diagnostic"
            alert.informativeText = """
            Trusted: \(isTrusted ? "✅ YES" : "❌ NO")
            Bundle ID: \(bundleID)
            Path: \(appPath)

            Check Console.app for detailed logs.
            Search for \"AccessibilityDebug\" category.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open System Settings")

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        if Thread.isMainThread {
            show()
        } else {
            DispatchQueue.main.async { show() }
        }
    }
}
