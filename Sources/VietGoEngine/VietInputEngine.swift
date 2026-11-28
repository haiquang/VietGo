import Foundation

public struct VietInputEngine: Sendable {
    public var config: EngineConfig

    private struct CommittedWord {
        let rawKeys: [Character]
        let displayed: [Character]
        let separator: Character
        let hasContextLiteralLatch: Bool
        let isAutoRestoredWord: Bool
    }

    private var rawKeys: [Character] = []
    private var displayed: [Character] = []
    private var lastNonWordChar: Character?
    private var hasContextLiteralLatch: Bool = false
    private var isAutoRestoredWord: Bool = false
    private var prev2StreamChar: Character?
    private var prev1StreamChar: Character?
    private var urlLiteralDepth: Int = 0
    private var committedHistory: [CommittedWord] = []
    private let maxHistoryCount = 64

    public init(config: EngineConfig = EngineConfig()) {
        self.config = config
    }

    public var currentWord: String {
        String(displayed)
    }

    public var lastDisplayedCharacter: Character? {
        displayed.last
    }

    public func countTrailingDisplayed(maxCount: Int, where predicate: (Character) -> Bool) -> Int {
        guard maxCount > 0, !displayed.isEmpty else { return 0 }
        return displayed.suffix(maxCount).reduce(into: 0) { count, ch in
            if predicate(ch) {
                count += 1
            }
        }
    }

    public mutating func processKey(_ char: Character) -> EngineAction {
        if let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1 {
            let v = scalar.value
            if (v < 0x20 && v != 0x09 && v != 0x0A && v != 0x0D) ||
                v == 0x7F ||
                (v >= 0xF700 && v <= 0xF8FF) {
                reset(clearHistory: true)
                return .passThrough
            }
        }

        let isWordChar = VietnameseTables.isWordCharacter(
            char,
            inputMethod: config.inputMethod,
            hasActiveWord: !displayed.isEmpty,
            bracketShortcuts: config.bracketShortcuts
        )

        guard isWordChar else {
            // Check if finalizing an open consonant-initial `ă`/`â` word on Space/punctuation (`ddaxa `)
            var finalAction: EngineAction = .passThrough
            let committedContextLatch = hasContextLiteralLatch
            var committedAutoRestored = isAutoRestoredWord
            if !displayed.isEmpty && !hasContextLiteralLatch && !isAutoRestoredWord {
                let midWordResult = SyllableComposer.composeResult(
                    rawKeys: rawKeys,
                    config: config,
                    isFinalizingWord: false
                )
                let finalizedResult = SyllableComposer.composeResult(
                    rawKeys: rawKeys,
                    config: config,
                    isFinalizingWord: true
                )
                if config.autoRestoreEnglish && finalizedResult.characters != displayed {
                    var lcp = 0
                    let limit = min(displayed.count, finalizedResult.characters.count)
                    while lcp < limit && displayed[lcp] == finalizedResult.characters[lcp] {
                        lcp += 1
                    }
                    let bs = displayed.count - lcp
                    let replacement = String(finalizedResult.characters.dropFirst(lcp)) + String(char)
                    finalAction = .replace(
                        backspaceCount: bs,
                        text: replacement.precomposedStringWithCanonicalMapping
                    )
                    displayed = finalizedResult.characters
                }
                if finalizedResult.isEscaped ||
                    midWordResult.didAutoRestore ||
                    (finalizedResult.didAutoRestore && (SyllableComposer.isKnownEnglishToken(String(rawKeys)) || rawKeys.allSatisfy({ $0.isUppercase }))) {
                    committedAutoRestored = true
                }
            }

            // Save committed word (or empty separator) for post-Space Backspace recovery
            committedHistory.append(CommittedWord(
                rawKeys: rawKeys,
                displayed: displayed,
                separator: char,
                hasContextLiteralLatch: committedContextLatch,
                isAutoRestoredWord: committedAutoRestored
            ))
            if committedHistory.count > maxHistoryCount {
                committedHistory.removeFirst()
            }

            lastNonWordChar = char
            hasContextLiteralLatch = false
            isAutoRestoredWord = false
            rawKeys.removeAll(keepingCapacity: true)
            displayed.removeAll(keepingCapacity: true)

            let startsSchemeURL = (char == "/" && prev2StreamChar == ":" && prev1StreamChar == "/")
            let startsHomePath = (char == "/" && prev1StreamChar == "~" && (prev2StreamChar == nil || isURLTerminator(prev2StreamChar!)))
            if startsSchemeURL || startsHomePath {
                urlLiteralDepth = 1
            } else if urlLiteralDepth > 0 {
                if isURLTerminator(char) {
                    urlLiteralDepth = 0
                } else {
                    urlLiteralDepth += 1
                }
            }
            recordStreamChar(char)
            return finalAction
        }

        // Auto-restore English `-n't` contractions (`doesn't`, `isn't`, `won't`, `hasn't`, `didn't`)
        if displayed.isEmpty,
           config.autoRestoreEnglish,
           (char == "t" || char == "T"),
           let sep = lastNonWordChar,
           (sep == "'" || sep == "\u{2019}"),
           let prev = committedHistory.last,
           !prev.hasContextLiteralLatch,
           !prev.isAutoRestoredWord,
           prev.separator == sep,
           prev.displayed != prev.rawKeys,
           let lastRaw = prev.rawKeys.last,
           (lastRaw == "n" || lastRaw == "N") {
            let backspaceCount = prev.displayed.count + 1
            let replacement = (String(prev.rawKeys) + String(sep) + String(char)).precomposedStringWithCanonicalMapping
            committedHistory[committedHistory.count - 1] = CommittedWord(
                rawKeys: prev.rawKeys,
                displayed: prev.rawKeys,
                separator: sep,
                hasContextLiteralLatch: true,
                isAutoRestoredWord: prev.isAutoRestoredWord
            )
            hasContextLiteralLatch = true
            isAutoRestoredWord = false
            rawKeys = [char]
            displayed = [char]
            lastNonWordChar = nil
            recordStreamChar(char)
            return .replace(backspaceCount: backspaceCount, text: replacement)
        }

        // Keep entire URL (`*://...`) and home-path (`~/...`) segments literal until whitespace/delimiter
        if displayed.isEmpty, urlLiteralDepth > 0 {
            hasContextLiteralLatch = true
            isAutoRestoredWord = false
            urlLiteralDepth += 1
            rawKeys.append(char)
            displayed.append(char)
            lastNonWordChar = nil
            recordStreamChar(char)
            return .passThrough
        }

        // Prevent standalone `w` -> `ư` immediately after path/symbol separators (`~/was`, `foo/w`, `a.wav`, `https://www`)
        if displayed.isEmpty,
           config.inputMethod == .telex,
           config.standaloneW,
           (char == "w" || char == "W"),
           let prev = lastNonWordChar,
           isPathOrSymbolPrefix(prev) {
            hasContextLiteralLatch = true
            isAutoRestoredWord = false
            rawKeys.append(char)
            displayed.append(char)
            lastNonWordChar = nil
            recordStreamChar(char)
            return .passThrough
        }

        if urlLiteralDepth > 0 {
            urlLiteralDepth += 1
        }
        recordStreamChar(char)

        if hasContextLiteralLatch || isAutoRestoredWord {
            rawKeys.append(char)
            displayed.append(char)
            lastNonWordChar = nil
            return .passThrough
        }

        lastNonWordChar = nil
        let oldDisplayed = displayed
        rawKeys.append(char)

        let newDisplayed = SyllableComposer.compose(rawKeys: rawKeys, config: config)

        if newDisplayed.count == oldDisplayed.count + 1,
           Array(newDisplayed.dropLast()) == oldDisplayed,
           newDisplayed.last == char {
            displayed = newDisplayed
            return .passThrough
        }

        return makeReplaceAction(from: oldDisplayed, to: newDisplayed)
    }

    @discardableResult
    public mutating func handleBackspace(allowToneReposition: Bool = true) -> EngineAction {
        if urlLiteralDepth > 0 {
            urlLiteralDepth -= 1
        }
        prev2StreamChar = nil
        prev1StreamChar = nil

        if displayed.isEmpty {
            if let last = committedHistory.popLast() {
                rawKeys = last.rawKeys
                displayed = last.displayed
                hasContextLiteralLatch = last.hasContextLiteralLatch
                isAutoRestoredWord = last.isAutoRestoredWord
                lastNonWordChar = nil
            } else {
                rawKeys.removeAll(keepingCapacity: true)
                hasContextLiteralLatch = false
                isAutoRestoredWord = false
                lastNonWordChar = nil
            }
            return .passThrough
        }

        let oldDisplayed = displayed
        var afterBS = displayed
        afterBS.removeLast()

        if afterBS.isEmpty {
            rawKeys.removeAll(keepingCapacity: true)
            displayed.removeAll(keepingCapacity: true)
            hasContextLiteralLatch = false
            isAutoRestoredWord = false
            return .passThrough
        }

        if hasContextLiteralLatch {
            if !rawKeys.isEmpty {
                rawKeys.removeLast()
            }
            displayed = afterBS
            return .passThrough
        }

        if isAutoRestoredWord {
            let check = checkComposablePrefix(afterBS)
            if check.isComposable {
                isAutoRestoredWord = false
                rawKeys = check.canonicalRaw
            } else {
                rawKeys = afterBS
            }
            displayed = afterBS
            return .passThrough
        }

        let currentResult = SyllableComposer.composeResult(rawKeys: rawKeys, config: config)
        if currentResult.didAutoRestore && oldDisplayed == currentResult.characters {
            let droppedRaw = Array(rawKeys.dropLast())
            if allowToneReposition,
               rawKeys.count >= 2,
               droppedRaw == afterBS,
               !SyllableComposer.isKnownEnglishToken(String(oldDisplayed)),
               !SyllableComposer.isKnownEnglishToken(String(droppedRaw)) {
                let prevResult = SyllableComposer.composeResult(rawKeys: droppedRaw, config: config)
                if !prevResult.didAutoRestore && !prevResult.isEscaped && prevResult.characters != droppedRaw {
                    rawKeys = droppedRaw
                    return makeReplaceAction(from: oldDisplayed, to: prevResult.characters)
                }
            }
            let check = checkComposablePrefix(afterBS)
            if check.isComposable {
                isAutoRestoredWord = false
                rawKeys = check.canonicalRaw
            } else {
                isAutoRestoredWord = true
                rawKeys = afterBS
            }
            displayed = afterBS
            return .passThrough
        }

        if currentResult.isEscaped {
            let droppedRaw = Array(rawKeys.dropLast())
            if !droppedRaw.isEmpty && SyllableComposer.compose(rawKeys: droppedRaw, config: config) == afterBS {
                rawKeys = droppedRaw
            } else {
                let check = checkComposablePrefix(afterBS)
                if check.isComposable {
                    rawKeys = check.canonicalRaw
                } else {
                    isAutoRestoredWord = true
                    rawKeys = afterBS
                }
            }
            displayed = afterBS
            return .passThrough
        }

        let newRawKeys = VietnameseTables.canonicalRawKeys(
            fromDisplayed: afterBS,
            inputMethod: config.inputMethod
        )
        let recomposed = SyllableComposer.compose(rawKeys: newRawKeys, config: config)
        rawKeys = newRawKeys

        if recomposed == afterBS {
            displayed = recomposed
            return .passThrough
        }

        // Never let Backspace expand or contract character count (`tién` + BS -> `tié`, `refre` + BS -> `refr`),
        // never rewrite pure-ASCII prefixes, and never inject synthetic replacements while Backspace is held in autorepeat.
        if !allowToneReposition || recomposed.count != afterBS.count || afterBS.allSatisfy(\.isASCII) {
            displayed = afterBS
            return .passThrough
        }

        // Tone placement shifted after removing coda (e.g. `hoàn` + BS -> `hòa` instead of `hoà`)
        return makeReplaceAction(from: oldDisplayed, to: recomposed)
    }

    /// Re-synchronizes active buffer state to match visible text before selection on Backspace.
    public mutating func resyncToDisplayedWord(_ word: String) {
        urlLiteralDepth = 0
        prev2StreamChar = nil
        prev1StreamChar = nil
        lastNonWordChar = nil
        hasContextLiteralLatch = false

        let normalized = word.precomposedStringWithCanonicalMapping
        let chars = Array(normalized)
        guard !chars.isEmpty else {
            rawKeys.removeAll(keepingCapacity: true)
            displayed.removeAll(keepingCapacity: true)
            isAutoRestoredWord = false
            return
        }

        let check = checkComposablePrefix(chars)
        displayed = chars
        if check.isComposable {
            rawKeys = check.canonicalRaw
            isAutoRestoredWord = false
        } else {
            rawKeys = chars
            isAutoRestoredWord = true
        }
    }

    public mutating func reset(clearHistory: Bool = true) {
        rawKeys.removeAll(keepingCapacity: true)
        displayed.removeAll(keepingCapacity: true)
        lastNonWordChar = nil
        hasContextLiteralLatch = false
        isAutoRestoredWord = false
        prev2StreamChar = nil
        prev1StreamChar = nil
        urlLiteralDepth = 0
        if clearHistory {
            committedHistory.removeAll(keepingCapacity: true)
        }
    }

    private func checkComposablePrefix(_ chars: [Character]) -> (isComposable: Bool, canonicalRaw: [Character]) {
        let canonical = VietnameseTables.canonicalRawKeys(
            fromDisplayed: chars,
            inputMethod: config.inputMethod
        )
        let probe = SyllableComposer.composeResult(rawKeys: canonical, config: config)
        let ok = !probe.didAutoRestore && !probe.isEscaped && probe.characters == chars
        return (ok, canonical)
    }

    private mutating func makeReplaceAction(from oldDisplayed: [Character], to newDisplayed: [Character]) -> EngineAction {
        var lcp = 0
        let limit = min(oldDisplayed.count, newDisplayed.count)
        while lcp < limit && oldDisplayed[lcp] == newDisplayed[lcp] {
            lcp += 1
        }

        let backspaceCount = oldDisplayed.count - lcp
        let replacement = String(newDisplayed.dropFirst(lcp)).precomposedStringWithCanonicalMapping
        displayed = newDisplayed

        return .replace(backspaceCount: backspaceCount, text: replacement)
    }

    private func isPathOrSymbolPrefix(_ ch: Character) -> Bool {
        switch ch {
        case "/", "\\", "~", ".", "@", ":", "_", "-":
            return true
        default:
            return false
        }
    }

    private mutating func recordStreamChar(_ char: Character) {
        prev2StreamChar = prev1StreamChar
        prev1StreamChar = char
    }

    private func isURLTerminator(_ char: Character) -> Bool {
        if char.isWhitespace {
            return true
        }
        switch char {
        case "\"", "'", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}",
             "`", "<", ">", ",", ";":
            return true
        default:
            return false
        }
    }
}
