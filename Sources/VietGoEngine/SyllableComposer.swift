import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum SyllableComposer {
    private struct VowelSlot {
        let base: Character // lowercase ASCII: a, e, i, o, u, y
        var shape: VowelShape
        let isUppercase: Bool
        var explicitShape: Bool
    }

    private enum LastAction: Equatable {
        case none
        case strokeD(trigger: Character)
        case vowelShape(index: Int, shape: VowelShape, trigger: Character)
        case tone(Tone, trigger: Character)
        case standaloneW(trigger: Character)
        case standaloneBracket(trigger: Character)
    }

    private enum EscapeOrigin: Equatable {
        case explicitEscape
        case telexToneConsonant(triggerLower: Character)
    }

    public struct ComposeResult: Equatable, Sendable {
        public let characters: [Character]
        public let isEscaped: Bool
        public let didAutoRestore: Bool

        public init(characters: [Character], isEscaped: Bool, didAutoRestore: Bool = false) {
            self.characters = characters
            self.isEscaped = isEscaped
            self.didAutoRestore = didAutoRestore
        }
    }

    public static func compose(
        rawKeys: [Character],
        config: EngineConfig,
        isFinalizingWord: Bool = false
    ) -> [Character] {
        composeResult(rawKeys: rawKeys, config: config, isFinalizingWord: isFinalizingWord).characters
    }

    public static func composeResult(
        rawKeys: [Character],
        config: EngineConfig,
        isFinalizingWord: Bool = false
    ) -> ComposeResult {
        guard !rawKeys.isEmpty else {
            return ComposeResult(characters: [], isEscaped: false)
        }

        var onsetChars: [Character] = []
        var hasStrokeD = false
        var hadLongDistanceDStroke = false
        var hadToneSwitch = false
        var hadInitialStandaloneW = false
        var vowels: [VowelSlot] = []
        var codaChars: [Character] = []
        var tone: Tone = .none
        var lastAction: LastAction = .none

        var escapeOrigin: EscapeOrigin?
        var escapedDisplay: [Character] = []
        var escapedBaseLength = 0
        var escapedHasPostTrailingContent = false
        var escapedExtraTriggerRepeats = 0
        var telexToneEscapeHadValidVietnamese = true
        var ooEscapeRawIndex: Int?
        var currentRawIndex = 0

        // Track whether the word already failed structure before the end
        var structuralFailure = false

        func unconsumedRawKeys() -> [Character] {
            guard let skipIdx = ooEscapeRawIndex, skipIdx >= 0, skipIdx < rawKeys.count else {
                return rawKeys
            }
            var trimmed = rawKeys
            trimmed.remove(at: skipIdx)
            return trimmed
        }

        func strokeInitialD(triggerChar: Character) -> Bool {
            guard !hasStrokeD else { return false }
            if onsetChars.count == 1 {
                let ch = onsetChars[0]
                if ch == "d" {
                    onsetChars[0] = "đ"
                    hasStrokeD = true
                    lastAction = .strokeD(trigger: triggerChar)
                    return true
                } else if ch == "D" {
                    onsetChars[0] = "Đ"
                    hasStrokeD = true
                    lastAction = .strokeD(trigger: triggerChar)
                    return true
                }
            } else if vowels.isEmpty && codaChars.isEmpty,
                      let last = onsetChars.last,
                      (last == "D" || (last == "d" && onsetChars.allSatisfy { $0.isUppercase || $0 == "d" })) {
                // Support uppercase abbreviations like SĐT, QĐ, NĐ
                onsetChars[onsetChars.count - 1] = last.isUppercase ? "Đ" : "đ"
                hasStrokeD = true
                lastAction = .strokeD(trigger: triggerChar)
                return true
            }
            return false
        }

        func undoStrokeInitialD(with firstTrigger: Character) {
            if let idx = onsetChars.lastIndex(where: { $0 == "đ" || $0 == "Đ" }) {
                onsetChars[idx] = (onsetChars[idx] == "Đ") ? "D" : "d"
            }
            hasStrokeD = false
            escapeOrigin = .explicitEscape
            escapedDisplay = renderCurrent(
                onsetChars: onsetChars,
                vowels: vowels,
                codaChars: codaChars,
                tone: tone,
                toneStyle: config.toneStyle
            )
            escapedDisplay.append(firstTrigger)
        }

        func promoteQuOrGiIfNeeded() {
            // `q` + `u` followed by another vowel -> `qu` becomes onset
            if onsetChars.count == 1,
               (onsetChars[0] == "q" || onsetChars[0] == "Q"),
               vowels.count == 1,
               vowels[0].base == "u",
               vowels[0].shape == .none {
                let uChar: Character = vowels[0].isUppercase ? "U" : "u"
                onsetChars.append(uChar)
                vowels.removeAll()
                return
            }
            // `g` + `i` followed by another vowel -> `gi` becomes onset
            if onsetChars.count == 1,
               (onsetChars[0] == "g" || onsetChars[0] == "G"),
               vowels.count == 1,
               vowels[0].base == "i",
               vowels[0].shape == .none {
                let iChar: Character = vowels[0].isUppercase ? "I" : "i"
                onsetChars.append(iChar)
                vowels.removeAll()
            }
        }

        func applyShape(_ targetShape: VowelShape, toBase targetBases: Set<Character>, triggerChar: Character) -> Bool {
            // Never resurrect or shape-escape a syllable whose coda/tone combination is already phonotactically invalid (`decree`),
            // while allowing unshaped intermediate nuclei (`ie`, `ye`, `uo`, `ưo`, `uye`, `ua`) to receive their vowel shape (`ddiefeu -> điều`, `tieseng -> tiếng`).
            if config.autoRestoreEnglish && (tone != .none || !codaChars.isEmpty) {
                let preShapeNucleus = String(vowels.map {
                    VietnameseTables.vowelCharacter(base: $0.base, shape: $0.shape, tone: .none, isUppercase: false)
                })
                let isPreShapeIntermediate = VietnameseTables.intermediateOnlyNuclei.contains(preShapeNucleus) || preShapeNucleus == "ua"
                if isPreShapeIntermediate {
                    let onsetLower = String(onsetChars).lowercased()
                    let codaLower = String(codaChars).lowercased()
                    if !VietnameseTables.validOnsets.contains(onsetLower) || !VietnameseTables.validCodas.contains(codaLower) {
                        return false
                    }
                    if (codaLower == "c" || codaLower == "ch" || codaLower == "k" || codaLower == "p" || codaLower == "t") &&
                        (tone == .grave || tone == .hook || tone == .tilde) {
                        return false
                    }
                } else if !isPhonotacticallyValid(
                    onsetChars: onsetChars,
                    vowels: vowels,
                    codaChars: codaChars,
                    tone: tone,
                    rawKeys: Array(rawKeys.prefix(currentRawIndex)),
                    inputMethod: config.inputMethod,
                    isFinalizingWord: false,
                    hadLongDistanceDStroke: hadLongDistanceDStroke,
                    hadToneSwitch: hadToneSwitch,
                    hadInitialStandaloneW: hadInitialStandaloneW
                ) {
                    return false
                }
            }

            // Handle `uo` / `uô` -> `ươ` compound horn (`w` in Telex or `7` in VNI)
            if targetShape == .horn {
                if let uIdx = vowels.lastIndex(where: { $0.base == "u" }),
                   let oIdx = vowels.lastIndex(where: { $0.base == "o" }),
                   uIdx + 1 == oIdx {
                    // Check if user just horned o (adjacent double-tap escape)
                    if case .vowelShape(let idx, .horn, let firstTrigger) = lastAction, idx == oIdx {
                        vowels[oIdx].shape = .none
                        vowels[oIdx].explicitShape = false
                        if !vowels[uIdx].explicitShape {
                            vowels[uIdx].shape = .none
                        }
                        escapeOrigin = .explicitEscape
                        escapedDisplay = renderCurrent(
                            onsetChars: onsetChars,
                            vowels: vowels,
                            codaChars: codaChars,
                            tone: tone,
                            toneStyle: config.toneStyle
                        )
                        escapedDisplay.append(firstTrigger)
                        return true
                    }

                    // If `u` was horned explicitly earlier (`truwow`) and `o` was not yet explicitly horned, horn `o`
                    if vowels[uIdx].shape == .horn && (vowels[oIdx].shape != .horn || !vowels[oIdx].explicitShape) {
                        vowels[oIdx].shape = .horn
                        vowels[oIdx].explicitShape = true
                        lastAction = .vowelShape(index: oIdx, shape: .horn, trigger: triggerChar)
                        return true
                    }

                    // Convert `uo` or `uô` (`truoonw` -> `trươn`) to `ươ` (or `uơ` for open `h`/`th`/`kh`)
                    if vowels[uIdx].shape == .none && vowels[oIdx].shape != .horn {
                        vowels[oIdx].shape = .horn
                        vowels[oIdx].explicitShape = true
                        let onsetLower = String(onsetChars).lowercased()
                        let hasFollowUp = !codaChars.isEmpty || vowels.count > oIdx + 1
                        if hasFollowUp || (onsetLower != "h" && onsetLower != "th" && onsetLower != "kh") {
                            vowels[uIdx].shape = .horn
                        }
                        lastAction = .vowelShape(index: oIdx, shape: .horn, trigger: triggerChar)
                        return true
                    }
                }

                // Handle `uu` + `w`/`7` -> `ưu` (target the FIRST `u`, never `uư`!)
                if vowels.count >= 2 {
                    for i in 0..<(vowels.count - 1) {
                        if vowels[i].base == "u" && vowels[i + 1].base == "u" {
                            if case .vowelShape(let lastIdx, .horn, let firstTrigger) = lastAction, lastIdx == i {
                                vowels[i].shape = .none
                                vowels[i].explicitShape = false
                                escapeOrigin = .explicitEscape
                                escapedDisplay = renderCurrent(
                                    onsetChars: onsetChars,
                                    vowels: vowels,
                                    codaChars: codaChars,
                                    tone: tone,
                                    toneStyle: config.toneStyle
                                )
                                escapedDisplay.append(firstTrigger)
                                return true
                            }
                            if vowels[i].shape == .none {
                                vowels[i].shape = .horn
                                vowels[i].explicitShape = true
                                lastAction = .vowelShape(index: i, shape: .horn, trigger: triggerChar)
                                return true
                            }
                            return false
                        }
                    }
                }
            }

            // General single vowel shape lookup (prefer last matching vowel in nucleus)
            guard let idx = vowels.lastIndex(where: { targetBases.contains($0.base) }) else {
                return false
            }

            // Guard against invalid circumflex combinations in Telex/VNI
            if targetShape == .circumflex {
                let targetBase = vowels[idx].base
                if config.inputMethod == .telex && targetBase == "a" && vowels[idx].shape == .breve && vowels[idx].explicitShape {
                    return false
                }
                if targetBase == "a", idx > 0 {
                    let prev = vowels[idx - 1]
                    // `ưâ`, `iâ`, `oâ`, `eâ`, `yâ`, `aâ` do not exist in Vietnamese (only plain `u` + `â` in `uân`, `uất`)
                    if prev.base != "u" || prev.shape != .none {
                        return false
                    }
                }
                if targetBase == "e", idx > 0 {
                    let prevBase = vowels[idx - 1].base
                    // `ê` can only follow `i`, `u`, `y` (`iê`, `uê`, `yê`, `uyê`)
                    if prevBase != "i" && prevBase != "u" && prevBase != "y" {
                        return false
                    }
                }
                if targetBase == "o", vowels.count >= 2 {
                    let bases = String(vowels.map { $0.base })
                    // `oao`, `oeo` must not circumflex `o` into `ôa`, `ôe`
                    if bases == "oa" || bases == "oe" || bases == "oao" || bases == "oeo" {
                        return false
                    }
                }
            }

            // Adjacent double-tap escape on the exact same vowel shape
            if case .vowelShape(let lastIdx, let lastShape, let firstTrigger) = lastAction,
               lastIdx == idx,
               lastShape == targetShape,
               vowels[idx].shape == targetShape {
                vowels[idx].shape = .none
                vowels[idx].explicitShape = false

                // Double `o` + `o` -> allow `oo` + coda + tone (`voọc`, `soóc`, `thoòng`, `xoong`)
                if vowels[idx].base == "o" && targetShape == .circumflex && config.inputMethod == .telex && ooEscapeRawIndex == nil {
                    let extraO = VowelSlot(
                        base: "o",
                        shape: .none,
                        isUppercase: firstTrigger.isUppercase,
                        explicitShape: false
                    )
                    vowels.insert(extraO, at: idx + 1)
                    ooEscapeRawIndex = currentRawIndex
                    lastAction = .none
                    return true
                }

                escapeOrigin = .explicitEscape
                escapedDisplay = renderCurrent(
                    onsetChars: onsetChars,
                    vowels: vowels,
                    codaChars: codaChars,
                    tone: tone,
                    toneStyle: config.toneStyle
                )
                escapedDisplay.append(firstTrigger)
                return true
            }

            if vowels[idx].shape == targetShape {
                // Non-adjacent repeat of same shape modifier -> fail/restore English
                return false
            }

            vowels[idx].shape = targetShape
            vowels[idx].explicitShape = true
            lastAction = .vowelShape(index: idx, shape: targetShape, trigger: triggerChar)
            return true
        }

        func applyTone(_ newTone: Tone, triggerChar: Character) -> Bool {
            guard !vowels.isEmpty else { return false }

            if newTone != .none,
               case .tone(let prevTone, let firstTrigger) = lastAction,
               prevTone == newTone {
                // Record whether the first tone tap produced a phonotactically valid Vietnamese syllable (`ass` -> `á`),
                // vs an unrendered invalid prefix (`yes` -> `yes`, where double-tapping `s` means literal `yess`).
                if config.autoRestoreEnglish {
                    telexToneEscapeHadValidVietnamese = isPhonotacticallyValid(
                        onsetChars: onsetChars,
                        vowels: vowels,
                        codaChars: codaChars,
                        tone: tone,
                        rawKeys: Array(rawKeys.prefix(currentRawIndex)),
                        inputMethod: config.inputMethod,
                        isFinalizingWord: false,
                        hadLongDistanceDStroke: hadLongDistanceDStroke,
                        hadToneSwitch: hadToneSwitch,
                        hadInitialStandaloneW: hadInitialStandaloneW
                    )
                } else {
                    telexToneEscapeHadValidVietnamese = true
                }
                // Adjacent double-tap tone escape (e.g. `ass` -> `as`, `a11` -> `a1`)
                tone = .none
                if config.inputMethod == .telex {
                    escapeOrigin = .telexToneConsonant(triggerLower: Character(String(triggerChar).lowercased()))
                } else {
                    escapeOrigin = .explicitEscape
                }
                escapedDisplay = renderCurrent(
                    onsetChars: onsetChars,
                    vowels: vowels,
                    codaChars: codaChars,
                    tone: tone,
                    toneStyle: config.toneStyle
                )
                escapedDisplay.append(firstTrigger)
                escapedBaseLength = escapedDisplay.count
                return true
            }

            // Never resurrect a syllable that has already failed phonotactics into an English word
            if tone != .none && config.autoRestoreEnglish && !isPhonotacticallyValid(
                onsetChars: onsetChars,
                vowels: vowels,
                codaChars: codaChars,
                tone: tone,
                rawKeys: Array(rawKeys.prefix(currentRawIndex)),
                inputMethod: config.inputMethod,
                isFinalizingWord: false,
                hadLongDistanceDStroke: hadLongDistanceDStroke,
                hadToneSwitch: hadToneSwitch,
                hadInitialStandaloneW: hadInitialStandaloneW
            ) {
                return false
            }

            if newTone == .none {
                if tone != .none {
                    tone = .none
                    hadToneSwitch = false
                    lastAction = .none
                    return true
                }
                return false
            }

            if tone == newTone {
                // Non-adjacent duplicate tone key (e.g. `tests`, `hosts`, `lists`)
                return false
            }

            if tone != .none && newTone != .none && tone != newTone {
                hadToneSwitch = true
            }
            tone = newTone
            lastAction = .tone(newTone, trigger: triggerChar)
            return true
        }

        for (rawIdx, rawChar) in rawKeys.enumerated() {
            currentRawIndex = rawIdx

            if let origin = escapeOrigin {
                if case .telexToneConsonant(let triggerLower) = origin {
                    let lowerChar = Character(String(rawChar).lowercased())
                    if lowerChar == triggerLower && !escapedHasPostTrailingContent {
                        escapedExtraTriggerRepeats += 1
                    } else {
                        escapedHasPostTrailingContent = true
                    }
                }
                escapedDisplay.append(rawChar)
                continue
            }

            if structuralFailure {
                break
            }

            if config.autoRestoreEnglish && rawIdx >= 48 && escapeOrigin == nil {
                return ComposeResult(characters: rawKeys, isEscaped: false, didAutoRestore: true)
            }

            let lower = Character(String(rawChar).lowercased())
            let isUpper = rawChar.isUppercase

            switch config.inputMethod {
            case .telex:
                // Optional Telex `[` -> `ơ` and `]` -> `ư`
                if config.bracketShortcuts && (rawChar == "[" || rawChar == "]") {
                    if case .standaloneBracket(let firstBracket) = lastAction,
                       firstBracket == rawChar,
                       !vowels.isEmpty {
                        vowels.removeLast()
                        escapeOrigin = .explicitEscape
                        escapedDisplay = renderCurrent(
                            onsetChars: onsetChars,
                            vowels: vowels,
                            codaChars: codaChars,
                            tone: tone,
                            toneStyle: config.toneStyle
                        )
                        escapedDisplay.append(firstBracket)
                        continue
                    }
                    if vowels.isEmpty && codaChars.isEmpty {
                        if config.autoRestoreEnglish && !onsetChars.isEmpty {
                            let onsetLower = String(onsetChars).lowercased()
                            if onsetLower == "q" || !VietnameseTables.validOnsets.contains(onsetLower) {
                                structuralFailure = true
                                break
                            }
                        }
                        let targetBase: Character = (rawChar == "[") ? "o" : "u"
                        vowels.append(VowelSlot(base: targetBase, shape: .horn, isUppercase: false, explicitShape: true))
                        lastAction = .standaloneBracket(trigger: rawChar)
                        continue
                    }
                    if rawChar == "[" {
                        if applyShape(.horn, toBase: ["o"], triggerChar: rawChar) {
                            continue
                        }
                    } else if rawChar == "]" {
                        if applyShape(.horn, toBase: ["u"], triggerChar: rawChar) {
                            continue
                        }
                    }
                }

                // 1. Check `d` -> `đ` (or adjacent escape `ddd` -> `dd`)
                if lower == "d" {
                    if case .strokeD(let firstTrigger) = lastAction {
                        undoStrokeInitialD(with: firstTrigger)
                        continue
                    }
                    let wasLongDistanceD = !vowels.isEmpty
                    if strokeInitialD(triggerChar: rawChar) {
                        if wasLongDistanceD {
                            hadLongDistanceDStroke = true
                        }
                        continue
                    }
                }

                // 2. Check tone keys (`s, f, r, x, j, z`) when vowels exist
                if let telexTone = telexTone(for: lower), !vowels.isEmpty {
                    if applyTone(telexTone, triggerChar: rawChar) {
                        continue
                    }
                }

                // 3. Check `w` (breve on `a`, horn on `o`/`u`, or standalone `ư`)
                if lower == "w" {
                    if case .standaloneW(let firstW) = lastAction,
                       !vowels.isEmpty,
                       vowels[vowels.count - 1].base == "u",
                       vowels[vowels.count - 1].shape == .horn {
                        vowels.removeLast()
                        escapeOrigin = .explicitEscape
                        escapedDisplay = renderCurrent(
                            onsetChars: onsetChars,
                            vowels: vowels,
                            codaChars: codaChars,
                            tone: tone,
                            toneStyle: config.toneStyle
                        )
                        escapedDisplay.append(firstW)
                        continue
                    }

                    // Promote `gi` + `w` -> `giư` (`giw`, `giwx`, `giwax`, `giwowngf`)
                    if config.standaloneW,
                       onsetChars.count == 1,
                       (onsetChars[0] == "g" || onsetChars[0] == "G"),
                       vowels.count == 1,
                       vowels[0].base == "i",
                       vowels[0].shape == .none,
                       codaChars.isEmpty {
                        let iChar: Character = vowels[0].isUppercase ? "I" : "i"
                        onsetChars.append(iChar)
                        vowels[0] = VowelSlot(base: "u", shape: .horn, isUppercase: isUpper, explicitShape: true)
                        lastAction = .standaloneW(trigger: rawChar)
                        continue
                    }

                    let hasOA = vowels.count >= 2 &&
                        vowels.contains(where: { $0.base == "o" }) &&
                        vowels.contains(where: { $0.base == "a" })
                    let hasUorO = vowels.contains { $0.base == "u" || $0.base == "o" }
                    let hasA = vowels.contains { $0.base == "a" }

                    // For `oă` (`thoắng`, `hoặc`, `xoăn`), apply `.breve` to `a` instead of horning `o`
                    if hasOA, applyShape(.breve, toBase: ["a"], triggerChar: rawChar) {
                        continue
                    }
                    if hasUorO, applyShape(.horn, toBase: ["u", "o"], triggerChar: rawChar) {
                        continue
                    }
                    if hasA, applyShape(.breve, toBase: ["a"], triggerChar: rawChar) {
                        continue
                    }
                    if config.standaloneW && vowels.isEmpty && codaChars.isEmpty {
                        if config.autoRestoreEnglish && !onsetChars.isEmpty {
                            let onsetLower = String(onsetChars).lowercased()
                            if onsetLower == "q" || !VietnameseTables.validOnsets.contains(onsetLower) {
                                structuralFailure = true
                                break
                            }
                        }
                        if onsetChars.isEmpty {
                            hadInitialStandaloneW = true
                        }
                        vowels.append(VowelSlot(base: "u", shape: .horn, isUppercase: isUpper, explicitShape: true))
                        lastAction = .standaloneW(trigger: rawChar)
                        continue
                    }
                    structuralFailure = true
                    break
                }

                // 4. Check circumflex triggers (`a`->`â`, `e`->`ê`, `o`->`ô`)
                if lower == "a" || lower == "e" || lower == "o" {
                    // Convert `ươ` + `o` -> `uô` (`cuowoi` -> `cuôi`, `truwongo` -> `truông`, `truowo` -> `truô`)
                    if lower == "o",
                       let uIdx = vowels.firstIndex(where: { $0.base == "u" }),
                       uIdx + 1 < vowels.count,
                       vowels[uIdx + 1].base == "o",
                       vowels[uIdx + 1].shape == .horn {
                        vowels[uIdx].shape = .none
                        vowels[uIdx].explicitShape = false
                        vowels[uIdx + 1].shape = .circumflex
                        vowels[uIdx + 1].explicitShape = true
                        lastAction = .vowelShape(index: uIdx + 1, shape: .circumflex, trigger: rawChar)
                        continue
                    }

                    if vowels.contains(where: { $0.base == lower }) {
                        if applyShape(.circumflex, toBase: [lower], triggerChar: rawChar) {
                            continue
                        }
                    }
                }

            case .vni:
                if lower == "9" {
                    if case .strokeD(let firstTrigger) = lastAction {
                        undoStrokeInitialD(with: firstTrigger)
                        continue
                    }
                    if strokeInitialD(triggerChar: rawChar) {
                        continue
                    }
                    structuralFailure = true
                    break
                }

                if let vniTone = vniTone(for: lower) {
                    if applyTone(vniTone, triggerChar: rawChar) {
                        continue
                    }
                    structuralFailure = true
                    break
                }

                if lower == "6" {
                    if applyShape(.circumflex, toBase: ["a", "e", "o"], triggerChar: rawChar) {
                        continue
                    }
                    structuralFailure = true
                    break
                }

                if lower == "7" {
                    if applyShape(.horn, toBase: ["u", "o"], triggerChar: rawChar) {
                        continue
                    }
                    structuralFailure = true
                    break
                }

                if lower == "8" {
                    if applyShape(.breve, toBase: ["a"], triggerChar: rawChar) {
                        continue
                    }
                    structuralFailure = true
                    break
                }
            }

            // 5. Literal letter processing (supports precomposed Vietnamese vowels like `Ư`, `è` too)
            if let decoded = VietnameseTables.decodeVowel(rawChar) {
                if !codaChars.isEmpty {
                    structuralFailure = true
                    break
                }

                promoteQuOrGiIfNeeded()

                if config.autoRestoreEnglish {
                    let onsetLower = String(onsetChars).lowercased()
                    let isQuWaiting = (onsetLower == "q" && vowels.isEmpty && decoded.base == "u" && decoded.shape == .none)
                    if !isQuWaiting && !VietnameseTables.validOnsets.contains(onsetLower) {
                        structuralFailure = true
                        break
                    }
                }

                vowels.append(VowelSlot(
                    base: decoded.base,
                    shape: decoded.shape,
                    isUppercase: decoded.isUppercase,
                    explicitShape: decoded.shape != .none
                ))
                if decoded.tone != .none {
                    tone = decoded.tone
                }

                // If `u` was horned earlier (`ư`) and `o` follows immediately (`uwo`), auto-horn `o` -> `ơ`
                if let uIdx = vowels.firstIndex(where: { $0.base == "u" && $0.shape == .horn }),
                   uIdx + 1 < vowels.count,
                   vowels[uIdx + 1].base == "o",
                   vowels[uIdx + 1].shape == .none {
                    vowels[uIdx + 1].shape = .horn
                }
                // If `u` + `ơ` has a 3rd vowel (`hươu`, `rượu`), auto-horn `u` -> `ư`
                if vowels.count >= 3,
                   let uIdx = vowels.firstIndex(where: { $0.base == "u" && $0.shape == .none }),
                   uIdx + 1 < vowels.count,
                   vowels[uIdx + 1].base == "o",
                   vowels[uIdx + 1].shape == .horn {
                    vowels[uIdx].shape = .horn
                }
                lastAction = .none
            } else {
                // Consonant (treat precomposed `đ`/`Đ` as onset consonant too)
                if vowels.isEmpty {
                    onsetChars.append(rawChar)
                    if rawChar == "đ" || rawChar == "Đ" {
                        hasStrokeD = true
                    }
                } else {
                    codaChars.append(rawChar)
                    if config.autoRestoreEnglish {
                        let codaLower = String(codaChars).lowercased()
                        if !VietnameseTables.validCodas.contains(codaLower) {
                            structuralFailure = true
                            break
                        }
                    }
                    // Upgrade `uơ` -> `ươ` if a coda is added (`huơ` + `n` + `g` -> `hương`)
                    if let uIdx = vowels.firstIndex(where: { $0.base == "u" && $0.shape == .none }),
                       uIdx + 1 < vowels.count,
                       vowels[uIdx + 1].base == "o",
                       vowels[uIdx + 1].shape == .horn {
                        vowels[uIdx].shape = .horn
                    }
                }
                lastAction = .none
            }
        }

        if structuralFailure {
            return ComposeResult(characters: unconsumedRawKeys(), isEscaped: ooEscapeRawIndex != nil, didAutoRestore: true)
        }

        if let origin = escapeOrigin {
            switch origin {
            case .explicitEscape:
                return ComposeResult(characters: escapedDisplay, isEscaped: true)
            case .telexToneConsonant:
                let unconsumed = unconsumedRawKeys()
                // Geminate English tone consonants (`password`, `message`, `coffee`, `error`, `traffic`, `less`, `mess`, `boss`, `swiss`, `tariff`)
                // restore raw keys when lexical disambiguation prefers the double-consonant form over the single-consonant escaped form.
                if config.autoRestoreEnglish {
                    if !telexToneEscapeHadValidVietnamese && !escapedHasPostTrailingContent {
                        return ComposeResult(characters: unconsumed, isEscaped: true, didAutoRestore: true)
                    }
                    if escapedExtraTriggerRepeats == 0 {
                        if escapedHasPostTrailingContent {
                            if shouldRestoreGeminateToneWord(
                                escaped: escapedDisplay,
                                raw: unconsumed,
                                escapedBaseLength: escapedBaseLength
                            ) {
                                return ComposeResult(characters: unconsumed, isEscaped: true, didAutoRestore: true)
                            }
                        } else if unconsumed.count >= 4 {
                            let escapedHasNonASCII = escapedDisplay.contains { !$0.isASCII }
                            let rawValid = isValidEnglishWord(String(unconsumed), allowProperNounFallback: escapedHasNonASCII)
                            if rawValid && (escapedHasNonASCII || !isValidEnglishWord(String(escapedDisplay))) {
                                return ComposeResult(characters: unconsumed, isEscaped: true, didAutoRestore: true)
                            }
                        }
                    }
                }
                return ComposeResult(characters: escapedDisplay, isEscaped: true)
            }
        }

        if config.autoRestoreEnglish {
            if !isPhonotacticallyValid(
                onsetChars: onsetChars,
                vowels: vowels,
                codaChars: codaChars,
                tone: tone,
                rawKeys: rawKeys,
                inputMethod: config.inputMethod,
                isFinalizingWord: isFinalizingWord,
                hadLongDistanceDStroke: hadLongDistanceDStroke,
                hadToneSwitch: hadToneSwitch,
                hadInitialStandaloneW: hadInitialStandaloneW
            ) {
                return ComposeResult(characters: unconsumedRawKeys(), isEscaped: ooEscapeRawIndex != nil, didAutoRestore: true)
            }
        }

        return ComposeResult(
            characters: renderCurrent(
                onsetChars: onsetChars,
                vowels: vowels,
                codaChars: codaChars,
                tone: tone,
                toneStyle: config.toneStyle
            ),
            isEscaped: ooEscapeRawIndex != nil
        )
    }

    private static let spellCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1024
        return cache
    }()

    private static func splitIdentifierSubwords(_ word: String) -> [String]? {
        let chars = Array(word)
        guard !chars.isEmpty else { return nil }
        for ch in chars where !ch.isLetter {
            return nil
        }

        // Treat plural acronyms like `URLs`, `URRLs`, `APIs` as a single lowercased token
        if chars.count >= 3,
           chars.last == "s",
           chars.dropLast().allSatisfy({ $0.isUppercase }) {
            return [word.lowercased()]
        }

        var subwords: [String] = []
        var current: [Character] = [chars[0]]
        for i in 1..<chars.count {
            let prev = chars[i - 1]
            let cur = chars[i]
            let lowerToUpper = prev.isLowercase && cur.isUppercase
            let acronymToWord = (i + 1 < chars.count) && prev.isUppercase && cur.isUppercase && chars[i + 1].isLowercase
            if lowerToUpper || acronymToWord {
                subwords.append(String(current).lowercased())
                current = [cur]
            } else {
                current.append(cur)
            }
        }
        subwords.append(String(current).lowercased())
        return subwords
    }

    public static func warmUpSpellChecker() {
        #if canImport(AppKit)
        let check = {
            _ = NSSpellChecker.shared.checkSpelling(
                of: "hello",
                startingAt: 0,
                language: "en_US",
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )
        }
        if Thread.isMainThread {
            check()
        } else {
            DispatchQueue.main.async(execute: check)
        }
        #endif
    }

    internal static func isKnownEnglishToken(_ word: String) -> Bool {
        isValidEnglishWord(word)
    }

    private static func isValidEnglishWord(_ word: String, allowProperNounFallback: Bool = false) -> Bool {
        guard word.count >= 3,
              let subwords = splitIdentifierSubwords(word) else {
            return false
        }

        let cacheKey = "\(subwords.joined(separator: "|"))#\(allowProperNounFallback ? 1 : 0)" as NSString
        if let cached = spellCache.object(forKey: cacheKey) {
            return cached.boolValue
        }

        var valid = true
        for sub in subwords {
            if sub.count < 2 {
                valid = false
                break
            }
            // Reject 4+ char hex-like tokens (`affc`, `deff`, `effa`) that NSSpellChecker treats as hex literals
            if sub.count >= 4 && sub != "cafe" && sub.allSatisfy({ "abcdef".contains($0) }) {
                valid = false
                break
            }
            // Reject 3-letter loan/abbreviation false positives so `less`, `loss`, `pass`, `miss` restore cleanly
            if sub == "les" || sub == "los" || sub == "pas" || sub == "mis" {
                valid = false
                break
            }
            #if canImport(AppKit)
            let checkBlock: () -> NSRange = {
                let r = NSSpellChecker.shared.checkSpelling(
                    of: sub,
                    startingAt: 0,
                    language: "en_US",
                    wrap: false,
                    inSpellDocumentWithTag: 0,
                    wordCount: nil
                )
                if r.location != NSNotFound && allowProperNounFallback, let first = sub.first {
                    let capitalized = String(first).uppercased() + sub.dropFirst()
                    return NSSpellChecker.shared.checkSpelling(
                        of: capitalized,
                        startingAt: 0,
                        language: "en_US",
                        wrap: false,
                        inSpellDocumentWithTag: 0,
                        wordCount: nil
                    )
                }
                return r
            }
            let range = Thread.isMainThread ? checkBlock() : DispatchQueue.main.sync(execute: checkBlock)
            if range.location != NSNotFound {
                valid = false
                break
            }
            #else
            valid = false
            break
            #endif
        }

        spellCache.setObject(NSNumber(value: valid), forKey: cacheKey)
        return valid
    }

    private static func shouldRestoreGeminateToneWord(
        escaped: [Character],
        raw: [Character],
        escapedBaseLength: Int
    ) -> Bool {
        let totalTrailing = escaped.count - escapedBaseLength
        guard totalTrailing > 0, totalTrailing <= 24, raw.count >= totalTrailing else { return false }
        let rawBaseLength = raw.count - totalTrailing

        var latchedRaw = false
        for trailing in 1...totalTrailing {
            let escWord = String(escaped.prefix(escapedBaseLength + trailing))
            let rawWord = String(raw.prefix(rawBaseLength + trailing))
            let escValid = isValidEnglishWord(escWord)
            let rawValid = isValidEnglishWord(rawWord)

            // Never corrupt a lexically valid escaped word into a double-consonant collision (`URL`/`URRL`, `chars`/`charrs`)
            if escValid {
                latchedRaw = false
            } else if rawValid {
                latchedRaw = true
            }
        }
        return latchedRaw
    }

    private static func telexTone(for lower: Character) -> Tone? {
        switch lower {
        case "s": return .acute
        case "f": return .grave
        case "r": return .hook
        case "x": return .tilde
        case "j": return .dot
        case "z": return Tone.none
        default: return nil
        }
    }

    private static func vniTone(for lower: Character) -> Tone? {
        switch lower {
        case "1": return .acute
        case "2": return .grave
        case "3": return .hook
        case "4": return .tilde
        case "5": return .dot
        case "0": return Tone.none
        default: return nil
        }
    }

    private static func isPhonotacticallyValid(
        onsetChars: [Character],
        vowels: [VowelSlot],
        codaChars: [Character],
        tone: Tone,
        rawKeys: [Character],
        inputMethod: InputMethod,
        isFinalizingWord: Bool,
        hadLongDistanceDStroke: Bool = false,
        hadToneSwitch: Bool = false,
        hadInitialStandaloneW: Bool = false
    ) -> Bool {
        let onsetLower = String(onsetChars).lowercased()
        let codaLower = String(codaChars).lowercased()

        // Allow uppercase abbreviations containing `Đ` (`SĐT`, `QĐ`, `NĐ`, `ĐL`, `ĐN`)
        if vowels.isEmpty && codaChars.isEmpty && tone == .none && onsetChars.contains(where: { $0 == "Đ" }) &&
            onsetChars.allSatisfy({ $0.isUppercase }) {
            return true
        }

        // Allow incomplete `"q"` only if there is no vowel/coda/tone yet, or `"q"` + `"u"` (with no coda/tone/shape)
        if onsetLower == "q" {
            if vowels.isEmpty && codaChars.isEmpty && tone == .none {
                return true
            }
            if vowels.count == 1 && vowels[0].base == "u" && vowels[0].shape == .none && codaChars.isEmpty && tone == .none {
                return true
            }
            return false
        }

        guard VietnameseTables.validOnsets.contains(onsetLower) else {
            return false
        }

        guard VietnameseTables.validCodas.contains(codaLower) else {
            return false
        }

        if vowels.isEmpty {
            return codaChars.isEmpty && tone == .none
        }

        let nucleusString = String(vowels.map {
            VietnameseTables.vowelCharacter(base: $0.base, shape: $0.shape, tone: .none, isUppercase: false)
        })

        // Reject unresolved intermediate vowel nuclei when finalizing a word (`lieus `, `cuois `, `tuyetj `, `ddien `)
        if isFinalizingWord && VietnameseTables.intermediateOnlyNuclei.contains(nucleusString) {
            return false
        }

        // Reject English `wr-` + vowel cluster when `standaloneW` turns `w` into `ư` (`wrong`, `write`)
        if inputMethod == .telex && onsetChars.isEmpty && vowels.count >= 2 &&
            String(rawKeys).lowercased().hasPrefix("wr") {
            return false
        }

        // Validate closed vs open vowel nuclei strictly
        if codaChars.isEmpty {
            let hasExplicitVietMark = onsetLower == "đ" || vowels.contains(where: { $0.shape != .none })
            let isValidOpen = VietnameseTables.validOpenNuclei.contains(nucleusString) ||
                (!isFinalizingWord && hasExplicitVietMark && VietnameseTables.intermediateOnlyNuclei.contains(nucleusString)) ||
                (inputMethod == .vni && tone != .none && isElongatedValidOpenNucleus(vowels: vowels))
            guard isValidOpen else {
                return false
            }
            // Consonant-initial open `ă`/`â` cannot end a valid Vietnamese word (`ddaxa `, `law `, `saw `, `NASA `);
            // standalone letters `â`, `ă` (e.g. `` `â` ``, `â `, `` `ă` ``, `ă `) remain valid except `aws`/`AWS` and interleaved `asa`/`ara`.
            if isFinalizingWord && (nucleusString == "ă" || nucleusString == "â") {
                if !onsetChars.isEmpty {
                    return false
                }
                let rawLower = String(rawKeys).lowercased()
                if nucleusString == "ă" && rawLower == "aws" {
                    return false
                }
                if nucleusString == "â" && tone != .none && !rawLower.hasPrefix("aa") && !rawLower.hasPrefix("a6") {
                    return false
                }
            }
        } else {
            guard VietnameseTables.validClosedNuclei.contains(nucleusString) else {
                return false
            }
            // `oo` only allows `c` or `ng` coda (`xoong, boong, voọc, soóc, thoòng`)
            if nucleusString == "oo" && codaLower != "c" && codaLower != "ng" {
                return false
            }
            // `k` coda only allowed in ethnic/loanwords like `Đắk`, `Lắk`, `Búk` (`ă` or `u`)
            if codaLower == "k" && nucleusString != "ă" && nucleusString != "u" {
                return false
            }
        }

        // Orthographic onset-vowel restrictions
        if let first = vowels.first {
            let isFrontVowel = (first.base == "e" || first.base == "i" || first.base == "y")
            if onsetLower == "c" && isFrontVowel {
                return false
            }
            if onsetLower == "k" && !isFrontVowel {
                return false
            }
            if (onsetLower == "ngh" || onsetLower == "gh") && (first.base != "e" && first.base != "i") {
                return false
            }
            if onsetLower == "ng" && (first.base == "e" || first.base == "i") {
                return false
            }
            if onsetLower == "g" && first.base == "e" {
                return false
            }
            if onsetLower == "gi" && first.base == "i" {
                return false
            }
            if onsetLower == "qu" && (first.base == "u" || nucleusString == "êu") {
                return false
            }
            if onsetLower == "kr" && first.base != "o" {
                return false
            }
        }

        // Stop codas (`c, ch, k, p, t`) cannot carry huyền (.grave), hỏi (.hook), or ngã (.tilde)
        if codaLower == "c" || codaLower == "ch" || codaLower == "k" || codaLower == "p" || codaLower == "t" {
            if tone == .grave || tone == .hook || tone == .tilde {
                return false
            }
        }

        // Check safe English non-word exception list (`term`, `more`, `post`, `data`)
        let rawLower = String(rawKeys).lowercased()
        if VietnameseTables.englishNonWordExceptions.contains(rawLower) {
            return false
        }

        // Guard against long-distance `d...d` stroke on valid 5+ char English words (`defend`, `defends`, etc.)
        if hadLongDistanceDStroke && rawKeys.count >= 5 && isValidEnglishWord(rawLower) {
            return false
        }

        // Guard against tone-switch overwrite on valid 4+ char English words (`virus`, `terms`, `turns`, `surf`, `turf`, `dwarf`)
        if inputMethod == .telex && hadToneSwitch && rawKeys.count >= 4 && isValidEnglishWord(rawLower) {
            return false
        }

        // Guard against word-initial standalone `w` -> `ư` on valid 3+ char English words (`was`, `war`, `wax`, `won`, `woo`, `wow`, `worm`, `worn`)
        if inputMethod == .telex && hadInitialStandaloneW && rawKeys.count >= 3 && isValidEnglishWord(rawLower) {
            return false
        }

        return true
    }

    private static func isElongatedValidOpenNucleus(vowels: [VowelSlot]) -> Bool {
        guard vowels.count >= 2, let last = vowels.last, last.shape == .none else {
            return false
        }
        var collapsed = vowels
        while collapsed.count >= 2,
              let tail = collapsed.last,
              tail.shape == .none,
              collapsed[collapsed.count - 2].shape == .none,
              collapsed[collapsed.count - 2].base == tail.base {
            collapsed.removeLast()
        }
        guard collapsed.count < vowels.count else { return false }
        let collapsedString = String(collapsed.map {
            VietnameseTables.vowelCharacter(base: $0.base, shape: $0.shape, tone: .none, isUppercase: false)
        })
        return VietnameseTables.validOpenNuclei.contains(collapsedString)
    }

    private static func toneTargetIndex(vowels: [VowelSlot], hasCoda: Bool, toneStyle: ToneStyle) -> Int {
        guard vowels.count > 1 else { return 0 }

        // 1. Any vowel with `ơ` (`o` + `.horn`), circumflex (`â, ê, ô`), or breve (`ă`)
        if let idx = vowels.lastIndex(where: {
            $0.shape == .circumflex || $0.shape == .breve || ($0.base == "o" && $0.shape == .horn)
        }) {
            return idx
        }

        // 2. Any vowel with `ư` (`u` + `.horn`) when no `ơ` is present (`ưa, ưi, ưu`)
        if let idx = vowels.lastIndex(where: { $0.base == "u" && $0.shape == .horn }) {
            return idx
        }

        // Collapse trailing elongated identical unshaped vowels when length >= 3 (e.g. `iaaa` -> `ia`, `oaii` -> `oai`),
        // while preserving 2-vowel `oo` (`voọc`, `soóc`, `thoòng`) so `hasCoda` places tone on the 2nd `o`.
        var effectiveCount = vowels.count
        while effectiveCount > 2,
              vowels[effectiveCount - 1].shape == .none,
              vowels[effectiveCount - 2].shape == .none,
              vowels[effectiveCount - 1].base == vowels[effectiveCount - 2].base {
            effectiveCount -= 1
        }
        let baseVowels = Array(vowels.prefix(effectiveCount))
        guard baseVowels.count > 1 else { return 0 }

        // 3. Triphthongs (all plain vowels) -> middle vowel
        if baseVowels.count >= 3 {
            return 1
        }

        // 4. Two plain vowels
        if hasCoda {
            return 1
        }

        let pair = String([baseVowels[0].base, baseVowels[1].base])
        if pair == "oa" || pair == "oe" || pair == "uy" {
            return toneStyle == .modern ? 0 : 1
        }

        return 0
    }

    private static func renderCurrent(
        onsetChars: [Character],
        vowels: [VowelSlot],
        codaChars: [Character],
        tone: Tone,
        toneStyle: ToneStyle
    ) -> [Character] {
        var result: [Character] = onsetChars

        let toneIdx = vowels.isEmpty
            ? -1
            : toneTargetIndex(vowels: vowels, hasCoda: !codaChars.isEmpty, toneStyle: toneStyle)

        for (index, slot) in vowels.enumerated() {
            let slotTone: Tone = (index == toneIdx) ? tone : .none
            let ch = VietnameseTables.vowelCharacter(
                base: slot.base,
                shape: slot.shape,
                tone: slotTone,
                isUppercase: slot.isUppercase
            )
            result.append(ch)
        }

        result.append(contentsOf: codaChars)
        return result
    }
}
