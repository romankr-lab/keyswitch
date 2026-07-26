import Cocoa

/// A small clickable control used in Settings to let the user re-record one
/// of the app's global hotkeys. Click it, press a key combo (must include at
/// least one modifier so we never register a global hotkey on a bare letter
/// key), and it reports the new keyCode/modifiers back via `onChange`.
class ShortcutRecorderView: NSView {

    var onChange: ((_ keyCode: UInt32, _ modifiers: NSEvent.ModifierFlags) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var keyCode: UInt32
    private var modifiers: NSEvent.ModifierFlags

    private var isRecording = false {
        didSet { updateAppearance() }
    }

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        // NOTE: this view is created with frame .zero and only gets its real
        // size afterwards, when the caller sets `.frame = ...`. An
        // autoresizingMask on the label would try to scale it proportionally
        // from that zero-sized starting frame, which produces a
        // degenerate/undefined result (effectively a 0-size or misplaced
        // label - the "blank field" bug). layout() below repositions the
        // label explicitly every time this view's own frame changes instead,
        // which has no such edge case.
        super.init(frame: .zero)

        // FIX: a custom NSView that returns true from acceptsFirstResponder
        // gets AppKit's default blue focus ring drawn around it as soon as
        // it becomes first responder - including automatically, right when
        // the window opens, before the user ever clicks it. That's the blue
        // border you saw on a field showing no "recording" state. We draw
        // our own recording-state border via the layer instead, so disable
        // the automatic one.
        focusRingType = .none

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.alignment = .center
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        label.frame = bounds
        addSubview(label)

        updateDisplay()
        updateAppearance()

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.frame = bounds
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func handleClick() {
        isRecording = true
        window?.makeFirstResponder(self)
        label.stringValue = "Press a key combo…"
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Require at least one modifier - otherwise every ordinary keystroke
        // in the app would get swallowed as "the new shortcut".
        let relevantModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !relevantModifiers.isEmpty else {
            NSSound.beep()
            return
        }

        keyCode = UInt32(event.keyCode)
        modifiers = relevantModifiers
        isRecording = false
        updateDisplay()
        onChange?(keyCode, modifiers)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateDisplay()
        return super.resignFirstResponder()
    }

    private func updateAppearance() {
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    private func updateDisplay() {
        label.stringValue = Self.displayString(keyCode: keyCode, modifiers: modifiers)
    }

    static func displayString(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += keyCodeToString(keyCode)
        return result
    }

    /// Covers the keys someone would realistically pick for a global hotkey
    /// (letters, digits) - anything outside this small table just shows its
    /// raw Carbon keyCode rather than pretending to know every key on every
    /// keyboard layout.
    private static func keyCodeToString(_ keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0"
        ]
        return map[keyCode] ?? "Key \(keyCode)"
    }
}
