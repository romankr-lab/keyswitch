import Cocoa
import ApplicationServices

class AccessibilityPermissionWindowController: NSWindowController {

    static let shared = AccessibilityPermissionWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "KeySwitch - Accessibility Permission Required"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating

        super.init(window: window)

        let viewController = AccessibilityPermissionViewController()
        window.contentViewController = viewController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.close()
    }
}

class AccessibilityPermissionViewController: NSViewController {

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        // Title label
        let titleLabel = NSTextField(labelWithString: "Accessibility Permission Required")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Message label
        let messageLabel = NSTextField(wrappingLabelWithString: "KeySwitch needs Accessibility permissions to work properly.\n\nPlease grant access in System Settings to enable text transformation and clipboard features.")
        messageLabel.font = NSFont.systemFont(ofSize: 13)
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)

        // Open Settings button
        let openSettingsButton = NSButton(title: "Open System Settings", target: self, action: #selector(openSystemSettings))
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.keyEquivalent = "\r" // Enter key
        openSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(openSettingsButton)

        // Close button
        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Message
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 15),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),

            // Buttons
            // FIX: with widths 160 and 100, centerX offsets of -60/+60 put
            // the two buttons' edges 10pt past each other (overlap).
            // -75/+75 leaves a clean ~20pt gap between them regardless of
            // the window's exact width.
            openSettingsButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 25),
            openSettingsButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: -75),
            openSettingsButton.widthAnchor.constraint(equalToConstant: 160),
            openSettingsButton.heightAnchor.constraint(equalToConstant: 32),

            closeButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 25),
            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 75),
            closeButton.widthAnchor.constraint(equalToConstant: 100),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            // Bottom spacing
            closeButton.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])
    }

    @objc private func openSystemSettings() {
        // Open System Settings to Accessibility preferences
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // Close the window after opening settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.closeWindow()
        }
    }

    @objc private func closeWindow() {
        AccessibilityPermissionWindowController.shared.closeWindow()
    }
}
