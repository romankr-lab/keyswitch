import Cocoa

/// Transforms text between a Latin (US/ABC) keyboard layout and any of the
/// supported "same physical key positions as Cyrillic" layouts below, and
/// picks the right direction automatically based on the current/next
/// keyboard layout IDs reported by LayoutManager.
class LayoutTransformer {
    static let shared = LayoutTransformer()

    private init() {}

    /// Describes one non-Latin layout that can be auto-fixed. Only the
    /// Latin-key -> target-script lowercase letter needs to be written by
    /// hand; uppercase letter pairs and the reverse (target-script -> Latin)
    /// map are both derived automatically in forwardMap()/reverseMap()
    /// below, so adding a new language only means adding one entry here.
    private struct LayoutDefinition {
        /// Human-readable name, for logging only.
        let name: String
        /// The macOS input source ID must contain every string here...
        let idContains: [String]
        /// ...and none of the strings here. This rules out a *different*
        /// layout of the same language that does NOT share the Cyrillic
        /// physical-key principle — e.g. Bulgarian's default BDS-standard
        /// layout is its own bespoke arrangement, unlike Bulgarian-Phonetic,
        /// which does map to the same physical key positions.
        let idExcludes: [String]
        /// Lowercase Latin key character -> lowercase target-script character,
        /// plus any punctuation keys that also change (bracket/semicolon/
        /// comma/period/slash keys, which many of these layouts repurpose).
        let baseMap: [Character: Character]

        func matches(_ layoutID: String) -> Bool {
            for required in idContains where !layoutID.contains(required) { return false }
            for excluded in idExcludes where layoutID.contains(excluded) { return false }
            return true
        }
    }

    // MARK: - Supported non-Latin layouts
    //
    // Every layout below is physically laid out exactly like a US QWERTY
    // keyboard - same key positions, different character printed on each
    // key - which is what makes "read what was typed, re-map key-by-key"
    // possible at all. This does NOT work for layouts that physically
    // rearrange the keys themselves (French AZERTY, German QWERTZ) or for
    // IME/composition-based scripts (Chinese, Japanese, Korean, Thai,
    // Arabic, Devanagari), so those are intentionally out of scope.
    //
    // Mappings below were verified against Microsoft's published keyboard
    // layout tables (kbdlayout.info / KBDRU, KBDBLR, KBDBGPH, KBDYCC), which
    // document the same physical key -> character assignments macOS's
    // built-in layouts use for these languages.
    private let definitions: [LayoutDefinition] = [
        LayoutDefinition(
            name: "Ukrainian",
            idContains: ["Ukrainian"],
            idExcludes: [],
            baseMap: [
                "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
                "a": "ф", "s": "і", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л", "l": "д",
                "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
                "[": "х", "]": "ї", "\\": "є",
                "{": "Х", "}": "Ї", "|": "Є",
                ";": "ж", "'": "є",
                ":": "Ж", "\"": "Є",
                ",": "б", ".": "ю", "/": ".",
                "<": "Б", ">": "Ю", "?": ","
            ]
        ),
        LayoutDefinition(
            name: "Russian",
            idContains: ["Russian"],
            idExcludes: [],
            baseMap: [
                "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
                "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л", "l": "д",
                "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
                "[": "х", "]": "ъ",
                "{": "Х", "}": "Ъ",
                ";": "ж", "'": "э",
                ":": "Ж", "\"": "Э",
                ",": "б", ".": "ю", "/": ".",
                "<": "Б", ">": "Ю", "?": ","
            ]
        ),
        LayoutDefinition(
            name: "Belarusian",
            idContains: ["Belarusian"],
            idExcludes: [],
            baseMap: [
                "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "ў", "p": "з",
                "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л", "l": "д",
                "z": "я", "x": "ч", "c": "с", "v": "м", "b": "і", "n": "т", "m": "ь",
                "[": "х",
                "{": "Х",
                ";": "ж", "'": "э",
                ":": "Ж", "\"": "Э",
                ",": "б", ".": "ю", "/": ".",
                "<": "Б", ">": "Ю", "?": ","
            ]
        ),
        LayoutDefinition(
            name: "Bulgarian (Phonetic)",
            // NOTE: matches only the "Bulgarian-Phonetic" input source, not
            // plain "Bulgarian" (the default BDS-standard layout), which is
            // its own bespoke arrangement and would produce wrong text if
            // treated the same way.
            idContains: ["Bulgarian-Phonetic"],
            idExcludes: [],
            baseMap: [
                "q": "ч", "w": "ш", "e": "е", "r": "р", "t": "т", "y": "ъ", "u": "у", "i": "и", "o": "о", "p": "п",
                "a": "а", "s": "с", "d": "д", "f": "ф", "g": "г", "h": "х", "j": "й", "k": "к", "l": "л",
                "z": "з", "x": "ж", "c": "ц", "v": "в", "b": "б", "n": "н", "m": "м",
                "[": "я", "]": "щ", "\\": "ь"
            ]
        ),
        LayoutDefinition(
            name: "Serbian",
            // "Serbian (Latin)" is a separate input source that must NOT be
            // matched here - only the Cyrillic one shares the physical-key
            // principle we depend on.
            idContains: ["Serbian"],
            idExcludes: ["Latin"],
            baseMap: [
                "q": "љ", "w": "њ", "e": "е", "r": "р", "t": "т", "y": "з", "u": "у", "i": "и", "o": "о", "p": "п",
                "a": "а", "s": "с", "d": "д", "f": "ф", "g": "г", "h": "х", "j": "ј", "k": "к", "l": "л",
                "z": "ѕ", "x": "џ", "c": "ц", "v": "в", "b": "б", "n": "н", "m": "м",
                "[": "ш", "]": "ђ",
                ";": "ч", "'": "ћ"
            ]
        )
    ]

    private func definition(for layoutID: String) -> LayoutDefinition? {
        return definitions.first { $0.matches(layoutID) }
    }

    /// Builds the full (lowercase + uppercase) Latin -> target-script map
    /// for a definition, deriving the uppercase letter pairs automatically.
    private func forwardMap(for definition: LayoutDefinition) -> [Character: Character] {
        var map = definition.baseMap
        for (latin, target) in definition.baseMap where latin.isLetter {
            let upperLatin = Character(latin.uppercased())
            let upperTarget = Character(target.uppercased())
            map[upperLatin] = upperTarget
        }
        return map
    }

    /// Builds the reverse (target-script -> Latin) map from the forward one.
    private func reverseMap(for definition: LayoutDefinition) -> [Character: Character] {
        let forward = forwardMap(for: definition)
        var reverse: [Character: Character] = [:]
        for (latin, target) in forward {
            reverse[target] = latin
        }
        return reverse
    }

    // Cache built maps so we don't rebuild the dictionaries on every keystroke.
    private var mapCache: [String: [Character: Character]] = [:]

    /// Creates the character map to use when transforming from `fromLayout`
    /// to `toLayout` (both macOS input source IDs).
    private func createMap(from fromLayout: String, to toLayout: String) -> [Character: Character] {
        let cacheKey = "\(fromLayout)\u{2192}\(toLayout)"
        if let cached = mapCache[cacheKey] {
            return cached
        }

        var map: [Character: Character] = [:]

        let fromDefinition = definition(for: fromLayout)
        let toDefinition = definition(for: toLayout)

        if fromDefinition == nil, let to = toDefinition {
            // Latin -> script (e.g. text typed in "ABC" that should have been Ukrainian)
            map = forwardMap(for: to)
        } else if let from = fromDefinition, toDefinition == nil {
            // script -> Latin (e.g. text typed in Ukrainian that should have been Latin)
            map = reverseMap(for: from)
        }
        // If both or neither side matches a known non-Latin layout, there is
        // no supported transformation for this pair - leave the map empty
        // so transformText() below just returns the text unchanged instead
        // of guessing.

        mapCache[cacheKey] = map
        return map
    }

    /// Transforms text from one layout to another.
    func transformText(_ text: String, from fromLayout: String, to toLayout: String) -> String {
        let map = createMap(from: fromLayout, to: toLayout)
        return String(text.map { char in map[char] ?? char })
    }

    /// Transforms text using KeyboardLayout objects.
    func transformText(_ text: String, from fromLayout: KeyboardLayout, to toLayout: KeyboardLayout) -> String {
        return transformText(text, from: fromLayout.id, to: toLayout.id)
    }
}
