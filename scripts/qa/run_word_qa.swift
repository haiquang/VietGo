//
//  run_word_qa.swift
//  VietGo Real Microsoft Word (`com.microsoft.Word`) HID QA Suite
//
//  Opens a clean temporary .docx in Microsoft Word, drives real hardware CGEvent keystrokes
//  through VietGo's `.cghidEventTap` worker, and verifies long paragraphs, `ý`/`Ý`, special
//  characters, URLs, contractions, step-by-step Backspace, held Backspace autorepeat,
//  Option+Backspace, Forward Delete, and multi-paragraph VNI input.
//

import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Foundation

private let testEventMarker: Int64 = 0x574F_5244 // "WORD"
private let observerBypassMarker: Int64 = 0x5647_4F31 // Bypasses EventTapManager without resetting committedHistory
private let wordBundleID = "com.microsoft.Word"

enum KeyHand {
    case left
    case right
    case thumbOrEdit
}

struct KeySpec {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let hand: KeyHand
    let unicode: UniChar?
    let postSettleMs: Int
    let isAutorepeat: Bool

    init(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        hand: KeyHand,
        unicode: UniChar?,
        postSettleMs: Int,
        isAutorepeat: Bool = false
    ) {
        self.keyCode = keyCode
        self.flags = flags
        self.hand = hand
        self.unicode = unicode
        self.postSettleMs = postSettleMs
        self.isAutorepeat = isAutorepeat
    }
}

private func qwertySpec(for char: Character) -> KeySpec? {
    switch char {
    case "\u{E001}": // Left Arrow
        return KeySpec(keyCode: 123, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 25)
    case "\u{E002}": // Right Arrow
        return KeySpec(keyCode: 124, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 25)
    case "\u{E004}": // Option + Backspace
        return KeySpec(keyCode: 51, flags: .maskAlternate, hand: .thumbOrEdit, unicode: nil, postSettleMs: 60)
    case "\u{E008}": // Autorepeat Backspace
        return KeySpec(keyCode: 51, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 18, isAutorepeat: true)
    case "\u{E00B}": // Forward Delete
        return KeySpec(keyCode: 117, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 30)
    case "\u{08}":
        return KeySpec(keyCode: 51, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 12)
    case "\n", "\r":
        return KeySpec(keyCode: 36, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 25)
    case "\t":
        return KeySpec(keyCode: 48, flags: [], hand: .left, unicode: nil, postSettleMs: 30)
    case " ":
        return KeySpec(keyCode: 49, flags: [], hand: .thumbOrEdit, unicode: 0x0020, postSettleMs: 0)
    default:
        break
    }

    let shiftedSymbols: [Character: (CGKeyCode, KeyHand)] = [
        "!": (18, .left), "@": (19, .left), "#": (20, .left), "$": (21, .left), "%": (23, .left),
        "^": (22, .right), "&": (26, .right), "*": (28, .right), "(": (25, .right), ")": (29, .right),
        "_": (27, .right), "+": (24, .right), "{": (33, .right), "}": (30, .right), "|": (42, .right),
        ":": (41, .right), "\"": (39, .right), "<": (43, .right), ">": (47, .right), "?": (44, .right),
        "~": (50, .left)
    ]
    if let (kc, hand) = shiftedSymbols[char] {
        return KeySpec(keyCode: kc, flags: .maskShift, hand: hand, unicode: String(char).utf16.first, postSettleMs: 0)
    }

    let plainSymbols: [Character: (CGKeyCode, KeyHand)] = [
        "1": (18, .left), "2": (19, .left), "3": (20, .left), "4": (21, .left), "5": (23, .left),
        "6": (22, .right), "7": (26, .right), "8": (28, .right), "9": (25, .right), "0": (29, .right),
        "-": (27, .right), "=": (24, .right), "[": (33, .right), "]": (30, .right), "\\": (42, .right),
        ";": (41, .right), "'": (39, .right), ",": (43, .right), ".": (47, .right), "/": (44, .right),
        "`": (50, .left)
    ]
    if let (kc, hand) = plainSymbols[char] {
        return KeySpec(keyCode: kc, flags: [], hand: hand, unicode: String(char).utf16.first, postSettleMs: 0)
    }

    let isUpper = char.isUppercase
    let lower = Character(String(char).lowercased())
    let letterMap: [Character: (CGKeyCode, KeyHand)] = [
        "a": (0, .left), "s": (1, .left), "d": (2, .left), "f": (3, .left), "g": (5, .left),
        "q": (12, .left), "w": (13, .left), "e": (14, .left), "r": (15, .left), "t": (17, .left),
        "z": (6, .left), "x": (7, .left), "c": (8, .left), "v": (9, .left), "b": (11, .left),
        "h": (4, .right), "j": (38, .right), "k": (40, .right), "l": (37, .right),
        "y": (16, .right), "u": (32, .right), "i": (34, .right), "o": (31, .right), "p": (35, .right),
        "n": (45, .right), "m": (46, .right)
    ]
    if let (kc, hand) = letterMap[lower] {
        return KeySpec(
            keyCode: kc,
            flags: isUpper ? .maskShift : [],
            hand: hand,
            unicode: String(char).utf16.first,
            postSettleMs: 0
        )
    }
    return nil
}

struct SpeedProfile {
    let label: String
    let baseMs: Int
    let rolloverMs: Int
    let jitterMs: Int
}

struct StepDeleteProbe {
    let prefixToType: String
    let expectedFullText: String
    let deleteSteps: Int
    let protectedEnglishTokens: [String]
    let tailInput: String
}

struct WordQACase {
    let name: String
    let speed: SpeedProfile
    let input: String
    let expected: String
    let inputMethod: String
    let stepDeleteProbe: StepDeleteProbe?

    init(
        name: String,
        speed: SpeedProfile,
        input: String,
        expected: String,
        inputMethod: String = "telex",
        stepDeleteProbe: StepDeleteProbe? = nil
    ) {
        self.name = name
        self.speed = speed
        self.input = input
        self.expected = expected
        self.inputMethod = inputMethod
        self.stepDeleteProbe = stepDeleteProbe
    }
}

private final class IMEWorkerClient {
    private let process: Process
    private let stdinPipe = Pipe()
    private let stdoutHandle: FileHandle

    init(binaryPath: String) throws {
        process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--ime-worker"]
        let outPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = outPipe
        stdoutHandle = outPipe.fileHandleForReading
        try process.run()

        let ready = Self.readLine(from: stdoutHandle, timeoutSeconds: 5.0)
        guard ready == "READY" else {
            process.terminate()
            throw NSError(domain: "WordQA", code: 10, userInfo: [NSLocalizedDescriptionKey: "Worker did not print READY (got: \(ready ?? "nil"))"])
        }
    }

    func send(_ command: String) {
        if let data = (command + "\n").data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        _ = Self.readLine(from: stdoutHandle, timeoutSeconds: 3.0)
    }

    func stop() {
        if process.isRunning {
            if let data = "QUIT\n".data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            usleep(150_000)
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func readLine(from handle: FileHandle, timeoutSeconds: Double) -> String? {
        var buffer = Data()
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let chunk = handle.availableData
            if !chunk.isEmpty {
                buffer.append(chunk)
                if let str = String(data: buffer, encoding: .utf8),
                   let nl = str.firstIndex(of: "\n") {
                    return String(str[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            usleep(10_000)
        }
        return nil
    }
}

private func verifyWordHIDTapActive() -> (pid: pid_t, name: String)? {
    var count: UInt32 = 0
    CGGetEventTapList(0, nil, &count)
    var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
    CGGetEventTapList(count, &taps, &count)
    for tap in taps where tap.tapPoint == .cghidEventTap && tap.enabled {
        let app = NSRunningApplication(processIdentifier: tap.tappingProcess)
        let bundle = app?.bundleIdentifier ?? ""
        let exec = app?.executableURL?.lastPathComponent ?? ""
        if bundle == "org.vietgo.VietGo" || exec == "validate_fast_chat_e2e" {
            return (tap.tappingProcess, bundle.isEmpty ? exec : bundle)
        }
    }
    return nil
}

private func createMinimalEmptyDocx(at path: String) throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vietgo_docx_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("_rels"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("word"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """
    let rels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """
    let docXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p/>
        <w:sectPr/>
      </w:body>
    </w:document>
    """

    try contentTypes.write(to: dir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
    try rels.write(to: dir.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)
    try docXML.write(to: dir.appendingPathComponent("word/document.xml"), atomically: true, encoding: .utf8)

    try? FileManager.default.removeItem(atPath: path)
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = dir
    zip.arguments = ["-q", "-r", path, "[Content_Types].xml", "_rels", "word"]
    try zip.run()
    zip.waitUntilExit()
    if zip.terminationStatus != 0 {
        throw NSError(domain: "WordQA", code: 20, userInfo: [NSLocalizedDescriptionKey: "Failed to build empty .docx"])
    }
}

private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = [], unicode: UniChar? = nil, isAutorepeat: Bool = false, marker: Int64 = testEventMarker) {
    guard let src = CGEventSource(stateID: .privateState) else { return }
    let clearMask: CGEventFlags = [.maskShift, .maskCommand, .maskAlternate, .maskControl, .maskSecondaryFn]
    if let kd = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true) {
        kd.flags.subtract(clearMask)
        kd.flags.formUnion(flags)
        kd.setIntegerValueField(.keyboardEventAutorepeat, value: isAutorepeat ? 1 : 0)
        if let u = unicode {
            var arr: [UniChar] = [u]
            kd.keyboardSetUnicodeString(stringLength: 1, unicodeString: &arr)
        }
        kd.setIntegerValueField(.eventSourceUserData, value: marker)
        kd.post(tap: .cghidEventTap)
    }
    usleep(1200)
    if let ku = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
        ku.flags.subtract(clearMask)
        ku.flags.formUnion(flags)
        ku.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        if let u = unicode {
            var arr: [UniChar] = [u]
            ku.keyboardSetUnicodeString(stringLength: 1, unicodeString: &arr)
        }
        ku.setIntegerValueField(.eventSourceUserData, value: marker)
        ku.post(tap: .cghidEventTap)
    }
}

private func postHardwareSequence(_ input: String, speed: SpeedProfile, expectedPID: pid_t) throws -> Double {
    let start = CFAbsoluteTimeGetCurrent()
    var prevHand: KeyHand?
    var step = 0

    for ch in input {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != expectedPID {
            throw NSError(domain: "WordQA", code: 2, userInfo: [NSLocalizedDescriptionKey: "Lost Microsoft Word frontmost focus"])
        }
        guard let spec = qwertySpec(for: ch) else {
            throw NSError(domain: "WordQA", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unmapped char: \(ch)"])
        }

        if let prev = prevHand {
            let baseInterval = (prev != spec.hand) ? speed.rolloverMs : speed.baseMs
            let jitterOffset = (speed.jitterMs > 0 && step % 3 == 0) ? -min(baseInterval - 4, speed.jitterMs / 2) : (step % 2 == 0 ? speed.jitterMs : 0)
            let waitMs = max(5, baseInterval + jitterOffset)
            usleep(UInt32(waitMs * 1000))
        }
        prevHand = spec.hand
        step += 1

        postKey(spec.keyCode, flags: spec.flags, unicode: spec.unicode, isAutorepeat: spec.isAutorepeat)
        if spec.postSettleMs > 0 {
            usleep(UInt32(spec.postSettleMs * 1000))
        }
    }
    return (CFAbsoluteTimeGetCurrent() - start) * 1000.0
}

private func axStringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
          let val = ref else {
        return nil
    }
    return val as? String
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
          let arr = ref as? [AXUIElement] else {
        return []
    }
    return arr
}

private func findEditableWindowCenter(pid: pid_t) -> (point: CGPoint, title: String, hasSheet: Bool, sheetTitles: [String])? {
    let appEl = AXUIElementCreateApplication(pid)
    var winRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &winRef) == .success,
          let windows = winRef as? [AXUIElement],
          !windows.isEmpty else {
        return nil
    }

    var sheetTitles: [String] = []
    var primaryWindow: AXUIElement?
    for w in windows {
        let role = axStringAttribute(w, kAXRoleAttribute as String) ?? ""
        let subrole = axStringAttribute(w, kAXSubroleAttribute as String) ?? ""
        let title = axStringAttribute(w, kAXTitleAttribute as String) ?? ""
        for child in axChildren(w) {
            if axStringAttribute(child, kAXRoleAttribute as String) == (kAXSheetRole as String) {
                let sTitle = axStringAttribute(child, kAXTitleAttribute as String) ?? "AXSheet"
                sheetTitles.append(sTitle)
            }
        }
        if role == (kAXWindowRole as String) && subrole == (kAXStandardWindowSubrole as String) {
            if title.contains("vietgo_word_qa") || primaryWindow == nil {
                primaryWindow = w
            }
        }
    }

    guard let targetWin = primaryWindow ?? windows.first else { return nil }
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    var pos = CGPoint.zero
    var size = CGSize(width: 900, height: 700)
    if AXUIElementCopyAttributeValue(targetWin, kAXPositionAttribute as CFString, &posRef) == .success,
       let posVal = posRef {
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
    }
    if AXUIElementCopyAttributeValue(targetWin, kAXSizeAttribute as CFString, &sizeRef) == .success,
       let sizeVal = sizeRef {
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
    }

    let clickPt = CGPoint(x: pos.x + size.width * 0.50, y: pos.y + size.height * 0.55)
    let winTitle = axStringAttribute(targetWin, kAXTitleAttribute as String) ?? ""
    return (clickPt, winTitle, !sheetTitles.isEmpty, sheetTitles)
}

private func clickPoint(_ pt: CGPoint) {
    guard let src = CGEventSource(stateID: .privateState),
          let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left),
          let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left) else {
        return
    }
    down.post(tap: .cghidEventTap)
    usleep(20_000)
    up.post(tap: .cghidEventTap)
}

private func readWordAXTextPassively(expectedPID: pid_t) -> String? {
    let appEl = AXUIElementCreateApplication(expectedPID)
    var focusedRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
          let focused = focusedRef else {
        return nil
    }
    let focusedEl = focused as! AXUIElement
    if let axText = axStringAttribute(focusedEl, kAXValueAttribute as String) {
        var cleaned = axText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        while cleaned.hasSuffix("\n") {
            cleaned.removeLast()
        }
        return cleaned.precomposedStringWithCanonicalMapping
    }
    return nil
}

private func readWordDocumentText(expectedPID: pid_t) -> String {
    if let axText = readWordAXTextPassively(expectedPID: expectedPID), !axText.isEmpty {
        return axText
    }

    let pb = NSPasteboard.general
    let prevChangeCount = pb.changeCount
    pb.clearContents()
    pb.setString("__VIETGO_WORD_EMPTY__", forType: .string)
    let markerChange = pb.changeCount

    postKey(0, flags: .maskCommand, marker: observerBypassMarker) // Cmd+A (observer-only)
    usleep(90_000)
    postKey(8, flags: .maskCommand, marker: observerBypassMarker) // Cmd+C (observer-only)

    let deadline = Date().addingTimeInterval(0.6)
    while Date() < deadline && pb.changeCount == markerChange {
        usleep(15_000)
    }

    let raw = pb.string(forType: .string) ?? ""
    _ = prevChangeCount
    postKey(124, marker: observerBypassMarker) // Right arrow to deselect without resetting IME buffer
    usleep(50_000)

    if raw == "__VIETGO_WORD_EMPTY__" {
        return ""
    }
    // Trim only Word's trailing paragraph mark if added by Cmd+A
    var cleaned = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    while cleaned.hasSuffix("\n") {
        cleaned.removeLast()
    }
    return cleaned.precomposedStringWithCanonicalMapping
}

private func clearWordDocument() {
    postKey(0, flags: .maskCommand) // Cmd+A
    usleep(90_000)
    postKey(51) // Backspace
    usleep(120_000)
    postKey(51) // Extra Backspace if trailing empty formatting paragraph remained
    usleep(100_000)
}

@main
enum WordHostQAMain {
    static func main() {
        let args = CommandLine.arguments
        var workerBinaryPath: String?
        var jsonOutPath: String?

        var idx = 1
        while idx < args.count {
            switch args[idx] {
            case "--ime-worker-bin" where idx + 1 < args.count:
                workerBinaryPath = args[idx + 1]
                idx += 2
            case "--json-out" where idx + 1 < args.count:
                jsonOutPath = args[idx + 1]
                idx += 2
            default:
                idx += 1
            }
        }

        let pb = NSPasteboard.general
        let savedClipboard = pb.string(forType: .string)
        defer {
            if let savedClipboard {
                pb.clearContents()
                pb.setString(savedClipboard, forType: .string)
            }
        }

        var workerClient: IMEWorkerClient?
        if let workerBinaryPath {
            do {
                workerClient = try IMEWorkerClient(binaryPath: workerBinaryPath)
            } catch {
                fputs("ERROR: Failed to start IME worker: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        defer { workerClient?.stop() }

        var tapInfo = verifyWordHIDTapActive()
        if tapInfo == nil && workerClient != nil {
            let tapDeadline = Date().addingTimeInterval(3.0)
            while tapInfo == nil && Date() < tapDeadline {
                usleep(30_000)
                tapInfo = verifyWordHIDTapActive()
            }
        }
        guard let tapInfo else {
            fputs("ERROR: No active VietGo HID tap found in CGGetEventTapList!\n", stderr)
            exit(1)
        }
        print("Verified active HID tap: PID=\(tapInfo.pid) (\(tapInfo.name))")

        let docxPath = "/tmp/vietgo_word_qa.docx"
        do {
            try createMinimalEmptyDocx(at: docxPath)
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        let wordURL = URL(fileURLWithPath: "/Applications/Microsoft Word.app")
        let docURL = URL(fileURLWithPath: docxPath)
        let openSem = DispatchSemaphore(value: 0)
        var openedApp: NSRunningApplication?
        var openErr: Error?
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([docURL], withApplicationAt: wordURL, configuration: cfg) { app, err in
            openedApp = app
            openErr = err
            openSem.signal()
        }
        _ = openSem.wait(timeout: .now() + 20.0)
        if let openErr {
            fputs("ERROR: Failed to open Microsoft Word: \(openErr.localizedDescription)\n", stderr)
            exit(1)
        }

        guard let wordApp = openedApp ?? NSRunningApplication.runningApplications(withBundleIdentifier: wordBundleID).first else {
            fputs("ERROR: Microsoft Word is not running\n", stderr)
            exit(1)
        }
        let wordPID = wordApp.processIdentifier

        var winInfo: (point: CGPoint, title: String, hasSheet: Bool, sheetTitles: [String])?
        let winDeadline = Date().addingTimeInterval(20.0)
        while Date() < winDeadline {
            _ = wordApp.activate()
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == wordPID,
               let info = findEditableWindowCenter(pid: wordPID),
               info.title.contains("vietgo_word_qa") || info.title.contains("Document") {
                winInfo = info
                break
            }
            usleep(250_000)
        }

        guard let winInfo else {
            fputs("ERROR: Timed out waiting for editable Microsoft Word window\n", stderr)
            exit(1)
        }
        print("Opened Microsoft Word PID=\(wordPID), window=\"\(winInfo.title)\", sheets=\(winInfo.sheetTitles)")

        if winInfo.hasSheet {
            fputs("ERROR: Microsoft Word has a modal sheet blocking editing: \(winInfo.sheetTitles)\n", stderr)
            exit(2)
        }

        clickPoint(winInfo.point)
        usleep(450_000)
        // Dismiss any first-launch/tip popover if focus settled inside doc
        clearWordDocument()

        let wordFast = SpeedProfile(label: "Word Realistic (~110 WPM)", baseMs: 90, rolloverMs: 36, jitterMs: 12)
        let wordBurst = SpeedProfile(label: "Word Burst (~150 WPM)", baseMs: 62, rolloverMs: 22, jitterMs: 12)

        let cases: [WordQACase] = [
            WordQACase(
                name: "W_01_LongParagraph_MixedVietEnglish",
                speed: wordFast,
                input: "Hoom nay tooi kieemr tra booj gox VietGo trwcj tieeps trong Microsoft Word treen macOS: gox nhanh muowtj maf, giwx nguyeen window, refresh, defend, yess, less, boss, swiss, away, virus, was, worm vaf nhw, nhwng, thwr, chwx, ddwocj, trwongf, ngwoif, giwx, giwax, rwouj!",
                expected: "Hôm nay tôi kiểm tra bộ gõ VietGo trực tiếp trong Microsoft Word trên macOS: gõ nhanh mượt mà, giữ nguyên window, refresh, defend, yess, less, boss, swiss, away, virus, was, worm và như, nhưng, thử, chữ, được, trường, người, giữ, giữa, rượu!"
            ),
            WordQACase(
                name: "W_02_AcuteY_ToneSwitch_And_Backspace_InWord",
                speed: wordFast,
                input: "Ys kieens cuar quys khachs raats ddangs chus ys: quys\u{08}y, quysf, quyst, tuyf ys!",
                expected: "Ý kiến của quý khách rất đáng chú ý: quy, quỳ, quýt, tùy ý!"
            ),
            WordQACase(
                name: "W_03_SpecialCharacters_Symbols_URLs_Contractions",
                speed: wordFast,
                input: "Kys twj ddawcj bieetj: 98,5% ddatj #1 @vietgo (A+B=C) [Telex/VNI] {UTF-8} ~1.250.000dd; mail: qa_dev@vietgo.org, link: https://github.com/haiquang/VietGo?v=1.0.2&os=mac, path: ~/Works/VietGo, doesn't & won't looix!",
                expected: "Ký tự đặc biệt: 98,5% đạt #1 @vietgo (A+B=C) [Telex/VNI] {UTF-8} ~1.250.000đ; mail: qa_dev@vietgo.org, link: https://github.com/haiquang/VietGo?v=1.0.2&os=mac, path: ~/Works/VietGo, doesn\u{2019}t & won\u{2019}t lỗi!"
            ),
            WordQACase(
                name: "W_04_StepByStep_Backspace_65Chars_ZeroJump",
                speed: wordFast,
                input: "",
                expected: "Kiểm tra xóa từng ký tự trong Word: đã xóa sạch mượt mà!",
                stepDeleteProbe: StepDeleteProbe(
                    prefixToType: "Kieemr tra xoas twfng kys twj trong Word: window refresh defend yess away virus worm chus ys ddwocj giwx nguyeen!",
                    expectedFullText: "Kiểm tra xóa từng ký tự trong Word: window refresh defend yess away virus worm chú ý được giữ nguyên!",
                    deleteSteps: 65,
                    protectedEnglishTokens: ["window", "refresh", "defend", "yess", "away", "virus", "worm"],
                    tailInput: "ddax xoas sachj muowtj maf!"
                )
            ),
            WordQACase(
                name: "W_05_WordDelete_OptionBS_HoldRepeatBS_ForwardDelete",
                speed: wordBurst,
                input: "Tooi tests yess away\u{E008}\u{E008}\u{E008}\u{E008}worm\u{E004}dduowcj!\u{E001}\u{E00B}\u{E002} giwx nguyeen!",
                expected: "Tôi tests yess được giữ nguyên!"
            ),
            WordQACase(
                name: "W_06_MultiParagraph_Enter_Tab_And_VNI",
                speed: wordFast,
                input: "Do2ng 1: Go4 tie6ng1 Vie6t5 trong Word.\n\tDo2ng 2: Ho7p5 d9o6ng2 100% mu7o7t5 ma2!",
                expected: "Dòng 1: Gõ tiếng Việt trong Word.\n\tDòng 2: Hợp đồng 100% mượt mà!",
                inputMethod: "vni"
            )
        ]

        let suiteStart = CFAbsoluteTimeGetCurrent()
        var passedCount = 0
        var activeMethod = "telex"
        var jsonRecords: [[String: Any]] = []

        for item in cases {
            if let workerClient {
                if item.inputMethod != activeMethod {
                    workerClient.send("METHOD \(item.inputMethod)")
                    activeMethod = item.inputMethod
                } else {
                    workerClient.send("RESET")
                }
            }
            workerClient?.send("BUNDLE \(wordBundleID)")

            let caseStart = CFAbsoluteTimeGetCurrent()
            _ = wordApp.activate()
            clickPoint(winInfo.point)
            usleep(120_000)
            clearWordDocument()
            workerClient?.send("RESET")
            usleep(250_000)

            var burstMs = 0.0
            var burstError: Error?
            var stepProbeError: String?

            if let probe = item.stepDeleteProbe {
                do {
                    burstMs += try postHardwareSequence(probe.prefixToType, speed: item.speed, expectedPID: wordPID)
                    usleep(450_000)
                    let fullActual = readWordDocumentText(expectedPID: wordPID)
                    if fullActual != probe.expectedFullText {
                        stepProbeError = "Prefix mismatch: expected '\(probe.expectedFullText)' got '\(fullActual)'"
                    } else {
                        var protectedSuffixLengths: Set<Int> = []
                        for token in probe.protectedEnglishTokens {
                            if let range = fullActual.range(of: token) {
                                let start = fullActual.distance(from: fullActual.startIndex, to: range.lowerBound)
                                let end = fullActual.distance(from: fullActual.startIndex, to: range.upperBound)
                                for len in (start + 2)...end {
                                    protectedSuffixLengths.insert(len)
                                }
                            }
                        }

                        let axAvailable = (readWordAXTextPassively(expectedPID: wordPID) == fullActual)
                        if axAvailable {
                            var currentText = fullActual
                            for stepIdx in 1...probe.deleteSteps {
                                burstMs += try postHardwareSequence("\u{08}", speed: item.speed, expectedPID: wordPID)
                                usleep(55_000)
                                let nextText = readWordAXTextPassively(expectedPID: wordPID) ?? ""
                                if nextText.count != currentText.count - 1 {
                                    stepProbeError = "BS jump at step \(stepIdx): '\(currentText)' (\(currentText.count)) -> '\(nextText)' (\(nextText.count))"
                                    break
                                }
                                if protectedSuffixLengths.contains(currentText.count) && nextText != String(currentText.dropLast()) {
                                    stepProbeError = "English mutation at step \(stepIdx): '\(currentText)' -> '\(nextText)'"
                                    break
                                }
                                currentText = nextText
                            }
                        } else {
                            // Delete all 65 characters across 12 word-boundary checkpoints using real single Backspace presses,
                            // verifying Word's live document text after every deleted word (with committedHistory intact).
                            let wordBackspaceCounts = [7, 4, 5, 2, 4, 5, 6, 5, 5, 7, 8, 7]
                            var deletedSoFar = 0
                            for (cpIdx, count) in wordBackspaceCounts.enumerated() {
                                let bsString = String(repeating: "\u{08}", count: count)
                                burstMs += try postHardwareSequence(bsString, speed: item.speed, expectedPID: wordPID)
                                deletedSoFar += count
                                usleep(150_000)
                                let actualAfterWord = readWordDocumentText(expectedPID: wordPID)
                                let expectedAfterWord = String(fullActual.dropLast(deletedSoFar))
                                if actualAfterWord != expectedAfterWord {
                                    stepProbeError = "Checkpoint #\(cpIdx + 1) (deleted \(deletedSoFar)/\(probe.deleteSteps)) mismatch: expected '\(expectedAfterWord)' (\(expectedAfterWord.count)) got '\(actualAfterWord)' (\(actualAfterWord.count))"
                                    break
                                }
                            }
                        }

                        if stepProbeError == nil {
                            burstMs += try postHardwareSequence(probe.tailInput, speed: item.speed, expectedPID: wordPID)
                        }
                    }
                } catch {
                    burstError = error
                }
            } else {
                do {
                    burstMs = try postHardwareSequence(item.input, speed: item.speed, expectedPID: wordPID)
                } catch {
                    burstError = error
                }
            }

            usleep(450_000)
            let actual = readWordDocumentText(expectedPID: wordPID)
            let caseDurationMs = Int((CFAbsoluteTimeGetCurrent() - caseStart) * 1000.0)
            let totalChars = item.stepDeleteProbe.map { $0.prefixToType.count + $0.deleteSteps + $0.tailInput.count } ?? item.input.count
            let wpm = Int((Double(totalChars) / 5.0) / max(burstMs / 60_000.0, 0.001))
            let hasSentinelLeak = actual.contains("\u{202F}") || actual.contains("\u{2060}") || actual.contains("\u{0259}")
            let isNFC = (actual == actual.precomposedStringWithCanonicalMapping)
            let ok = (burstError == nil) && (stepProbeError == nil) && (actual == item.expected) && !hasSentinelLeak && isNFC
            let status = ok ? "PASS" : "FAIL"
            if ok { passedCount += 1 }

            let record: [String: Any] = [
                "name": item.name,
                "app": wordBundleID,
                "speed": item.speed.label,
                "wpm": wpm,
                "durationMs": caseDurationMs,
                "status": status,
                "actual": stepProbeError ?? actual,
                "expected": item.expected
            ]
            jsonRecords.append(record)

            print("\(status) \(item.name) [\(wordBundleID) | \(item.speed.label) | ~\(wpm) WPM | \(caseDurationMs)ms | nfc=\(isNFC)]")
            if !ok {
                print("  expected: \"\(item.expected)\"")
                print("  actual:   \"\(actual)\" (probeErr=\(stepProbeError ?? "none"), isNFC=\(isNFC), hasSentinelLeak=\(hasSentinelLeak), err=\(burstError?.localizedDescription ?? "none"))")
            }
        }

        // Clean document before exit so Word doesn't leave dirty prompt clutter, keeping Word open as requested
        clearWordDocument()
        if let workerClient, activeMethod != "telex" {
            workerClient.send("METHOD telex")
        }
        workerClient?.send("BUNDLE -")
        workerClient?.stop()

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - suiteStart) * 1000.0)
        let avgMs = totalMs / max(cases.count, 1)

        if let jsonOutPath {
            let outURL = URL(fileURLWithPath: jsonOutPath)
            try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload: [String: Any] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "targetBundle": wordBundleID,
                "windowTitle": winInfo.title,
                "totalCases": cases.count,
                "passedCases": passedCount,
                "totalDurationMs": totalMs,
                "avgDurationMs": avgMs,
                "results": jsonRecords
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: outURL)
            }
        }

        print("SUMMARY: \(passedCount)/\(cases.count) PASSED in \(totalMs)ms (avg \(avgMs)ms/case)")
        exit(passedCount == cases.count ? 0 : 1)
    }
}
