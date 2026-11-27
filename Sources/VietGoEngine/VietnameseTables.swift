import Foundation

public struct VowelSpec: Hashable, Sendable {
    public let base: Character // Lowercase ASCII: a, e, i, o, u, y
    public let shape: VowelShape
    public let tone: Tone
    public let isUppercase: Bool

    public init(base: Character, shape: VowelShape = .none, tone: Tone = .none, isUppercase: Bool = false) {
        self.base = base
        self.shape = shape
        self.tone = tone
        self.isUppercase = isUppercase
    }
}

public enum VietnameseTables {
    private struct TableKey: Hashable {
        let base: Character
        let shape: VowelShape
        let tone: Tone
        let isUppercase: Bool
    }

    private static let rawRows: [(Character, VowelShape, [Character])] = [
        ("a", .none,       ["a", "\u{00E1}", "\u{00E0}", "\u{1EA3}", "\u{00E3}", "\u{1EA1}"]),
        ("a", .breve,      ["\u{0103}", "\u{1EAF}", "\u{1EB1}", "\u{1EB3}", "\u{1EB5}", "\u{1EB7}"]),
        ("a", .circumflex, ["\u{00E2}", "\u{1EA5}", "\u{1EA7}", "\u{1EA9}", "\u{1EAB}", "\u{1EAD}"]),
        ("e", .none,       ["e", "\u{00E9}", "\u{00E8}", "\u{1EBB}", "\u{1EBD}", "\u{1EB9}"]),
        ("e", .circumflex, ["\u{00EA}", "\u{1EBF}", "\u{1EC1}", "\u{1EC3}", "\u{1EC5}", "\u{1EC7}"]),
        ("i", .none,       ["i", "\u{00ED}", "\u{00EC}", "\u{1EC9}", "\u{0129}", "\u{1ECB}"]),
        ("o", .none,       ["o", "\u{00F3}", "\u{00F2}", "\u{1ECF}", "\u{00F5}", "\u{1ECD}"]),
        ("o", .circumflex, ["\u{00F4}", "\u{1ED1}", "\u{1ED3}", "\u{1ED5}", "\u{1ED7}", "\u{1ED9}"]),
        ("o", .horn,       ["\u{01A1}", "\u{1EDB}", "\u{1EDD}", "\u{1EDF}", "\u{1EE1}", "\u{1EE3}"]),
        ("u", .none,       ["u", "\u{00FA}", "\u{00F9}", "\u{1EE7}", "\u{0169}", "\u{1EE5}"]),
        ("u", .horn,       ["\u{01B0}", "\u{1EE9}", "\u{1EEB}", "\u{1EED}", "\u{1EEF}", "\u{1EF1}"]),
        ("y", .none,       ["y", "\u{00FD}", "\u{1EF3}", "\u{1EF7}", "\u{1EF9}", "\u{1EF5}"])
    ]

    private static let encodeMap: [TableKey: Character] = {
        var map: [TableKey: Character] = [:]
        for (base, shape, chars) in rawRows {
            for (toneIndex, lowerChar) in chars.enumerated() {
                let tone = Tone(rawValue: toneIndex) ?? .none
                map[TableKey(base: base, shape: shape, tone: tone, isUppercase: false)] = lowerChar
                let upperString = String(lowerChar).uppercased()
                if let upperChar = upperString.first {
                    map[TableKey(base: base, shape: shape, tone: tone, isUppercase: true)] = upperChar
                }
            }
        }
        return map
    }()

    private static let decodeMap: [Character: VowelSpec] = {
        var map: [Character: VowelSpec] = [:]
        for (key, ch) in encodeMap {
            map[ch] = VowelSpec(
                base: key.base,
                shape: key.shape,
                tone: key.tone,
                isUppercase: key.isUppercase
            )
        }
        return map
    }()

    public static func vowelCharacter(base: Character, shape: VowelShape, tone: Tone, isUppercase: Bool) -> Character {
        let lowerBase = Character(String(base).lowercased())
        if let ch = encodeMap[TableKey(base: lowerBase, shape: shape, tone: tone, isUppercase: isUppercase)] {
            return ch
        }
        if let ch = encodeMap[TableKey(base: lowerBase, shape: .none, tone: tone, isUppercase: isUppercase)] {
            return ch
        }
        return isUppercase ? Character(String(lowerBase).uppercased()) : lowerBase
    }

    public static func decodeVowel(_ char: Character) -> VowelSpec? {
        if let spec = decodeMap[char] {
            return spec
        }
        // Normalize decomposed NFD Unicode if encountered
        let nfc = String(char).precomposedStringWithCanonicalMapping
        if nfc.count == 1, let first = nfc.first {
            return decodeMap[first]
        }
        return nil
    }

    public static func isBaseVowel(_ char: Character) -> Bool {
        switch Character(String(char).lowercased()) {
        case "a", "e", "i", "o", "u", "y":
            return true
        default:
            return false
        }
    }

    public static func isVietnameseVowel(_ char: Character) -> Bool {
        decodeVowel(char) != nil
    }

    public static func isWordCharacter(
        _ char: Character,
        inputMethod: InputMethod,
        hasActiveWord: Bool,
        bracketShortcuts: Bool = false
    ) -> Bool {
        if char.isLetter {
            return true
        }
        if inputMethod == .telex && bracketShortcuts && (char == "[" || char == "]") {
            return true
        }
        if inputMethod == .vni && hasActiveWord, let ascii = char.asciiValue, ascii >= 48 && ascii <= 57 {
            return true
        }
        return false
    }

    /// Valid Vietnamese initial consonant clusters (lowercase, `đ` represented as `đ`).
    public static let validOnsets: Set<String> = [
        "", "b", "c", "ch", "d", "đ", "g", "gh", "gi",
        "h", "k", "kh", "kr", "l", "m", "n", "ng", "ngh", "nh",
        "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x"
    ]

    /// Valid Vietnamese final consonant clusters (lowercase).
    /// Includes `k` for official Vietnamese ethnic/place names such as `Đắk Lắk`, `Krông Búk`.
    public static let validCodas: Set<String> = [
        "", "c", "ch", "k", "m", "n", "ng", "nh", "p", "t"
    ]

    /// Valid Vietnamese vowel nuclei when NO coda is present (open syllables + intermediate forms).
    public static let validOpenNuclei: Set<String> = [
        // Single vowels (consonant-initial `ă`/`â` rejected without coda on word break; standalone `â`/`ă` stay valid)
        "a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
        // Finalized open diphthongs & triphthongs (intermediate `ie`, `ye`, `uo`, `ưo`, `uye` require a coda)
        "ai", "ao", "au", "ay", "âu", "ây",
        "eo", "êu",
        "ia", "iê", "iu",
        "oa", "oă", "oe", "oi", "ôi", "ơi", "oo",
        "ua", "uâ", "uê", "ui", "ưi", "uô", "uơ", "ưa", "ươ", "ưu", "uy",
        "ya", "yê",
        "iêu", "yêu",
        "oai", "oao", "oay", "oeo",
        "uây", "uôi", "ươi", "ươu", "uya", "uyê", "uyu",
        // Valid open intermediate triphthongs while typing
        "ieu", "yeu", "uoi", "uou", "uay"
    ]

    /// Valid Vietnamese vowel nuclei that CAN be followed by a coda (`c, ch, k, m, n, ng, nh, p, t`).
    /// Offglide diphthongs/triphthongs ending in semivowels (`ai, ay, ao, au, oi, ui, ia, ua, ưa, uôi, ươi...`)
    /// are excluded here so English words like `music`, `basic`, `coins`, `suits`, `vaixn`, `buaxn` auto-restore.
    public static let validClosedNuclei: Set<String> = [
        "a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
        "iê", "oa", "oă", "oe", "oo",
        "uâ", "uê", "uô", "ươ", "uy", "uyê", "yê",
        // Intermediate unmodified forms while typing end-of-word modifiers (`truongwf`, `vietej`, `tuyeen`)
        "ie", "ye", "uo", "ưo", "uye"
    ]

    /// Intermediate-only vowel nuclei valid while typing mid-word, but invalid once finalizing a word.
    public static let intermediateOnlyNuclei: Set<String> = [
        "ie", "ye", "uo", "ưo", "uye",
        "ieu", "yeu", "uoi", "uou", "uay"
    ]

    /// Safe English/code non-word exceptions whose Telex keystrokes happen to pass bare phonotactics
    /// without colliding with any real standard Vietnamese word.
    public static let englishNonWordExceptions: Set<String> = [
        "term", "more", "post", "data"
    ]

    /// Converts a displayed Vietnamese word back into canonical raw keystrokes (for Backspace resync).
    public static func canonicalRawKeys(fromDisplayed displayed: [Character], inputMethod: InputMethod) -> [Character] {
        var result: [Character] = []
        var activeTone: Tone = .none

        for ch in displayed {
            if ch == "đ" {
                result.append("d")
                result.append(inputMethod == .telex ? "d" : "9")
                continue
            }
            if ch == "Đ" {
                result.append("D")
                result.append(inputMethod == .telex ? "d" : "9")
                continue
            }
            if let spec = decodeVowel(ch) {
                let baseChar = spec.isUppercase ? Character(String(spec.base).uppercased()) : spec.base
                result.append(baseChar)
                switch spec.shape {
                case .none:
                    break
                case .circumflex:
                    if inputMethod == .telex {
                        result.append(spec.base)
                    } else {
                        result.append("6")
                    }
                case .breve:
                    result.append(inputMethod == .telex ? "w" : "8")
                case .horn:
                    result.append(inputMethod == .telex ? "w" : "7")
                }
                if spec.tone != .none {
                    activeTone = spec.tone
                }
            } else {
                result.append(ch)
            }
        }

        if activeTone != .none {
            switch inputMethod {
            case .telex:
                switch activeTone {
                case .none: break
                case .acute: result.append("s")
                case .grave: result.append("f")
                case .hook: result.append("r")
                case .tilde: result.append("x")
                case .dot: result.append("j")
                }
            case .vni:
                result.append(Character(String(activeTone.rawValue)))
            }
        }

        return result
    }
}
