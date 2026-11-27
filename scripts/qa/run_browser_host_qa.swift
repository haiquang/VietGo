//
//  run_browser_host_qa.swift
//  VietGo Cumulative Real-Browser HID QA Suite
//
//  POLICY — APPEND-ONLY REGRESSION SUITE:
//  NEVER delete or weaken existing R3_* / R4_* cases when fixing new bugs or adding features.
//  Append new cases (`R5_XX_...`, `R6_XX_...`) to the end of `allCases` and re-run the full suite
//  via `bash scripts/qa/run_regression_qa.sh` to verify older fixes never regress.
//

import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Foundation
import WebKit

private let testEventMarker: Int64 = 0x5141_484F // "QAHO"

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
    // Control / Editing shortcuts represented via Private Use Area tokens
    switch char {
    case "\u{E001}": // Left Arrow
        return KeySpec(keyCode: 123, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 18)
    case "\u{E002}": // Right Arrow
        return KeySpec(keyCode: 124, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 18)
    case "\u{E003}": // Cmd + A
        return KeySpec(keyCode: 0, flags: .maskCommand, hand: .thumbOrEdit, unicode: nil, postSettleMs: 40)
    case "\u{E004}": // Option + Backspace
        return KeySpec(keyCode: 51, flags: .maskAlternate, hand: .thumbOrEdit, unicode: nil, postSettleMs: 40)
    case "\u{E006}": // Shift + Left Arrow
        return KeySpec(keyCode: 123, flags: .maskShift, hand: .thumbOrEdit, unicode: nil, postSettleMs: 22)
    case "\u{E007}": // Escape
        return KeySpec(keyCode: 53, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 40)
    case "\u{E008}": // Autorepeat Backspace
        return KeySpec(keyCode: 51, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 12, isAutorepeat: true)
    case "\u{E009}": // Autorepeat 'a'
        return KeySpec(keyCode: 0, flags: [], hand: .left, unicode: 0x0061, postSettleMs: 10, isAutorepeat: true)
    case "\u{E00A}": // Autorepeat 'i'
        return KeySpec(keyCode: 34, flags: [], hand: .right, unicode: 0x0069, postSettleMs: 10, isAutorepeat: true)
    case "\u{08}":
        return KeySpec(keyCode: 51, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 0)
    case "\n", "\r":
        return KeySpec(keyCode: 36, flags: [], hand: .thumbOrEdit, unicode: nil, postSettleMs: 0)
    case "\t":
        return KeySpec(keyCode: 48, flags: [], hand: .left, unicode: nil, postSettleMs: 50)
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

struct BrowserQACase {
    let name: String
    let selector: String
    let speed: SpeedProfile
    let input: String
    let expected: String
    let isChatSubmit: Bool
    let inputMethod: String
    let postFocusJS: String?
    let customReadoutJS: String?
    let domAssertionJS: String?
    let stepDeleteProbe: StepDeleteProbe?

    init(
        name: String,
        selector: String,
        speed: SpeedProfile,
        input: String,
        expected: String,
        isChatSubmit: Bool,
        inputMethod: String = "telex",
        postFocusJS: String? = nil,
        customReadoutJS: String? = nil,
        domAssertionJS: String? = nil,
        stepDeleteProbe: StepDeleteProbe? = nil
    ) {
        self.name = name
        self.selector = selector
        self.speed = speed
        self.input = input
        self.expected = expected
        self.isChatSubmit = isChatSubmit
        self.inputMethod = inputMethod
        self.postFocusJS = postFocusJS
        self.customReadoutJS = customReadoutJS
        self.domAssertionJS = domAssertionJS
        self.stepDeleteProbe = stepDeleteProbe
    }
}

@MainActor
final class BrowserHostCoordinator: NSObject, WKNavigationDelegate {
    let window: NSWindow
    let webView: WKWebView
    private var loaded = false

    override init() {
        let rect = NSRect(x: 120, y: 120, width: 960, height: 760)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BrowserHostQA (net.imput.helium) -> http://127.0.0.1:8765"

        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: rect, configuration: config)
        window.contentView = webView

        super.init()
        webView.navigationDelegate = self
        if let url = URL(string: "http://127.0.0.1:8765") {
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
    }

    func isLoaded() -> Bool { loaded }

    func evalJS(_ script: String) -> Any? {
        let sem = DispatchSemaphore(value: 0)
        var out: Any?
        webView.evaluateJavaScript(script) { res, _ in
            out = res
            sem.signal()
        }
        let deadline = Date().addingTimeInterval(3.0)
        while sem.wait(timeout: .now()) == .timedOut && Date() < deadline {
            pump(for: 0.005)
        }
        return out
    }

    func focusAndClickSelector(_ selector: String, postFocusJS: String? = nil) -> Bool {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(webView)

        _ = evalJS("window.qaResetAll()")
        pump(for: 0.05)

        let rectJSON = evalJS("""
            (() => {
              const el = document.querySelector(\(jsonString(selector)));
              if (!el) return null;
              el.scrollIntoView({ block: 'center' });
              const r = el.getBoundingClientRect();
              return { x: r.left + Math.min(40, r.width / 2), y: r.top + r.height / 2 };
            })()
        """) as? [String: Any]

        guard let xVal = rectJSON?["x"] as? Double,
              let yVal = rectJSON?["y"] as? Double,
              let primaryScreenHeight = NSScreen.screens.first?.frame.height else {
            return false
        }

        let viewPt = NSPoint(x: xVal, y: webView.bounds.height - yVal)
        let winPt = webView.convert(viewPt, to: nil)
        let screenPt = window.convertPoint(toScreen: winPt)
        let cgPt = CGPoint(x: screenPt.x, y: primaryScreenHeight - screenPt.y)

        if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: cgPt, mouseButton: .left),
           let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cgPt, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
            usleep(12_000)
            up.post(tap: .cghidEventTap)
        }
        pump(for: 0.12)

        if let postFocusJS {
            let ok = (evalJS(postFocusJS) as? Bool) ?? true
            pump(for: 0.04)
            return ok
        }

        let isFocused = (evalJS("""
            (() => {
              const el = document.querySelector(\(jsonString(selector)));
              if (!el) return false;
              el.focus();
              return document.activeElement === el;
            })()
        """) as? Bool) ?? false

        return isFocused
    }

    func readOutput(selector: String, isChatSubmit: Bool, customReadoutJS: String? = nil) -> String {
        if let customReadoutJS {
            return (evalJS(customReadoutJS) as? String) ?? ""
        }
        if isChatSubmit {
            let res = evalJS("""
                Array.from(document.querySelectorAll('#chat-messages .chat-bubble')).map(x => x.textContent).join(' | ')
            """) as? String
            return res ?? ""
        }
        let res = evalJS("""
            (() => {
              const el = document.querySelector(\(jsonString(selector)));
              if (!el) return '';
              if ('value' in el) return el.value;
              return el.textContent ?? '';
            })()
        """) as? String
        return res ?? ""
    }

    private func jsonString(_ str: String) -> String {
        guard let data = try? JSONEncoder().encode(str),
              let s = String(data: data, encoding: .utf8) else { return "\"\"" }
        return s
    }
}

@MainActor
private func pump(for seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        while let ev = NSApp.nextEvent(
            matching: .any,
            until: Date().addingTimeInterval(0.005),
            inMode: .default,
            dequeue: true
        ) {
            NSApp.sendEvent(ev)
            if Date() >= deadline { break }
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
    }
}

private func verifyAnyHIDTapActive() -> (pid: pid_t, name: String)? {
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

private func postHardwareSequence(_ input: String, speed: SpeedProfile, targetPID: pid_t) throws -> Double {
    guard let privateSource = CGEventSource(stateID: .privateState) else {
        throw NSError(domain: "QA", code: 1, userInfo: [NSLocalizedDescriptionKey: "No private CGEventSource"])
    }
    let clearMask: CGEventFlags = [.maskShift, .maskCommand, .maskAlternate, .maskControl, .maskSecondaryFn]
    let start = CFAbsoluteTimeGetCurrent()
    var prevHand: KeyHand?
    var step = 0

    for ch in input {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID {
            throw NSError(domain: "QA", code: 2, userInfo: [NSLocalizedDescriptionKey: "Lost frontmost focus"])
        }
        guard let spec = qwertySpec(for: ch) else {
            throw NSError(domain: "QA", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unmapped char: \(ch)"])
        }

        if let prev = prevHand {
            let baseInterval = (prev != spec.hand) ? speed.rolloverMs : speed.baseMs
            let jitterOffset = (speed.jitterMs > 0 && step % 3 == 0) ? -min(baseInterval - 3, speed.jitterMs / 2) : (step % 2 == 0 ? speed.jitterMs : 0)
            let waitMs = max(3, baseInterval + jitterOffset)
            usleep(UInt32(waitMs * 1000))
        }
        prevHand = spec.hand
        step += 1

        if let kd = CGEvent(keyboardEventSource: privateSource, virtualKey: spec.keyCode, keyDown: true) {
            kd.flags.subtract(clearMask)
            kd.flags.formUnion(spec.flags)
            kd.setIntegerValueField(.keyboardEventAutorepeat, value: spec.isAutorepeat ? 1 : 0)
            if let u = spec.unicode {
                var arr: [UniChar] = [u]
                kd.keyboardSetUnicodeString(stringLength: 1, unicodeString: &arr)
            }
            kd.setIntegerValueField(.eventSourceUserData, value: testEventMarker)
            kd.post(tap: .cghidEventTap)
        }
        usleep(1000)
        if let ku = CGEvent(keyboardEventSource: privateSource, virtualKey: spec.keyCode, keyDown: false) {
            ku.flags.subtract(clearMask)
            ku.flags.formUnion(spec.flags)
            ku.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            if let u = spec.unicode {
                var arr: [UniChar] = [u]
                ku.keyboardSetUnicodeString(stringLength: 1, unicodeString: &arr)
            }
            ku.setIntegerValueField(.eventSourceUserData, value: testEventMarker)
            ku.post(tap: .cghidEventTap)
        }
        if spec.postSettleMs > 0 {
            usleep(UInt32(spec.postSettleMs * 1000))
        }
    }
    return (CFAbsoluteTimeGetCurrent() - start) * 1000.0
}

private func postServerRequest(_ path: String, jsonObject: Any? = nil) {
    guard let url = URL(string: "http://127.0.0.1:8765" + path) else { return }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    if let jsonObject {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: jsonObject)
    }
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
    _ = sem.wait(timeout: .now() + 2.0)
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
            throw NSError(domain: "QA", code: 10, userInfo: [NSLocalizedDescriptionKey: "Worker did not print READY (got: \(ready ?? "nil"))"])
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

@main
@MainActor
enum BrowserHostQAMain {
    static func main() {
        UserDefaults.standard.register(defaults: ["ApplePressAndHoldEnabled": false])
        UserDefaults.standard.set(false, forKey: "ApplePressAndHoldEnabled")

        let args = CommandLine.arguments
        var workerBinaryPath: String?
        var filterTerm: String?
        var jsonOutPath: String?

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--ime-worker-bin" where i + 1 < args.count:
                workerBinaryPath = args[i + 1]
                i += 2
            case "--filter" where i + 1 < args.count:
                filterTerm = args[i + 1]
                i += 2
            case "--json-out" where i + 1 < args.count:
                jsonOutPath = args[i + 1]
                i += 2
            default:
                i += 1
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

        var tapInfo = verifyAnyHIDTapActive()
        if tapInfo == nil && workerClient != nil {
            let tapDeadline = Date().addingTimeInterval(3.0)
            while tapInfo == nil && Date() < tapDeadline {
                usleep(30_000)
                tapInfo = verifyAnyHIDTapActive()
            }
        }
        guard let tapInfo else {
            fputs("ERROR: No active VietGo HID tap found in CGGetEventTapList!\n", stderr)
            exit(1)
        }
        print("Verified active HID tap: PID=\(tapInfo.pid) (\(tapInfo.name))")

        postServerRequest("/api/clear")

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()

        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        app.mainMenu = mainMenu

        let coordinator = BrowserHostCoordinator()
        coordinator.window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        let selfPID = ProcessInfo.processInfo.processIdentifier
        let readyDeadline = Date().addingTimeInterval(6.0)
        while Date() < readyDeadline {
            pump(for: 0.05)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == selfPID &&
                coordinator.window.isKeyWindow &&
                coordinator.isLoaded() {
                break
            }
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == selfPID && coordinator.isLoaded() else {
            fputs("ERROR: BrowserHostQA failed to acquire focus or load http://127.0.0.1:8765\n", stderr)
            exit(1)
        }

        let fast140 = SpeedProfile(label: "Fast Chat (~140 WPM)", baseMs: 70, rolloverMs: 22, jitterMs: 8)
        let burst190 = SpeedProfile(label: "Burst Jitter (~190 WPM)", baseMs: 42, rolloverMs: 7, jitterMs: 18)
        let extreme250 = SpeedProfile(label: "Extreme Rollover (250+ WPM)", baseMs: 14, rolloverMs: 3, jitterMs: 0)

        let allCases: [BrowserQACase] = [
            // === Round 3 Cases (Preserved Regression Baseline) ===
            BrowserQACase(
                name: "R3_01_BackspaceMonotonicShrink_RepeatBS",
                selector: "#markdown-textarea",
                speed: fast140,
                input: "tiengs\u{08}\u{08}\u{08}\u{08}ieengs cuar nhaf hoanf\u{E008}\u{E008}\u{08}oanf mowis ",
                expected: "tiếng của nhà hoàn mới ",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R3_02_Contractions_MixedVietnamese",
                selector: "#rich-editor",
                speed: fast140,
                input: "It doesn't work, isn't it? Hoom nay won't fail vaf hasn't broken, ddasnh gias oorn!",
                expected: "It doesn't work, isn't it? Hôm nay won't fail và hasn't broken, đánh giá ổn!",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R3_03_URLsAndHomePaths_LiteralSegments",
                selector: "#omnibox-input",
                speed: fast140,
                input: "ddafs https://docs.google.com/forms tieeps ~/Works/test/forms anh/chij ",
                expected: "đá https://docs.google.com/forms tiếp ~/Works/test/forms anh/chị ",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R3_04_DegreeDecreeDefend_NoDeadResurrection",
                selector: "#markdown-textarea",
                speed: fast140,
                input: "degree decree defend defends depend world vaf depj duowngd ddeenf ddeens ",
                expected: "degree decree defend defends depend world và dẹp đương đền đến ",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R3_05_MultiFieldTabSwitch_MidWordReset",
                selector: "#form-field-1",
                speed: fast140,
                input: "hoaf\tbinhf ",
                expected: "hòa | bình ",
                isChatSubmit: false,
                customReadoutJS: "document.getElementById('form-field-1').value + ' | ' + document.getElementById('form-field-2').value",
                domAssertionJS: "document.activeElement && document.activeElement.id === 'form-field-2'"
            ),
            BrowserQACase(
                name: "R3_06_FormattedContentEditable_InlineTags",
                selector: "#formatted-editor",
                speed: fast140,
                input: "dduowcj kieemr tra ",
                expected: "[Bold] inline_code được kiểm tra ",
                isChatSubmit: false,
                postFocusJS: "window.qaFocusFormattedEnd()",
                domAssertionJS: "document.querySelectorAll('#formatted-editor b').length === 1 && document.querySelectorAll('#formatted-editor code').length === 1"
            ),
            BrowserQACase(
                name: "R3_07_MentionPopup_EscapeDismiss_Retype",
                selector: "#mention-popup-editor",
                speed: fast140,
                input: "tag @dev\u{E007} nguowif_dungf ddaau ",
                expected: "tag @dev người_dùng đâu ",
                isChatSubmit: false,
                domAssertionJS: "document.getElementById('mention-popup').style.display === 'none'"
            ),
            BrowserQACase(
                name: "R3_08_ChatEnterSubmit_MultiLine_Punctuation",
                selector: "#chat-input",
                speed: fast140,
                input: "Chafo banj, doesn't work af?\nTieeps tucj https://api.dev/test nhes!\n",
                expected: "Chào bạn, doesn't work à? | Tiếp tục https://api.dev/test nhé!",
                isChatSubmit: true
            ),
            BrowserQACase(
                name: "R3_09_MixedUnicodeNFC_ReactControlled_Burst",
                selector: "#react-controlled-input",
                speed: burst190,
                input: "dduowngf phoos Haf Nooij, QDD 12/NQ-CP vaf 98,5% nguowif dungf",
                expected: "đường phố Hà Nội, QĐ 12/NQ-CP và 98,5% người dùng",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R3_10_HoldKeyRepeat_NoModifierStuck",
                selector: "#markdown-textarea",
                speed: fast140,
                input: "chafo\u{E009}\u{E009} banj mowis ",
                expected: "chàoaa bạn mới ",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R3_11_ExtremeRollover250WPM_VietnameseProse",
                selector: "#rich-editor",
                speed: extreme250,
                input: "Ngheej thuaatj lafm vieecj hieeuj quar cuar nguowif Vieetj taij Ddaf Nawngx ",
                expected: "Nghệ thuật làm việc hiệu quả của người Việt tại Đà Nẵng ",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R3_12_VNI_Alphanumeric_MixedMethod",
                selector: "#markdown-textarea",
                speed: fast140,
                input: "VNI: tie6ng1 Vie6t5 d9u7o7c5 100% tre6n Chrome2 v2.0, doesn't break",
                expected: "VNI: tiếng Việt được 100% trên Chrome2 v2.0, doesn't break",
                isChatSubmit: false,
                inputMethod: "vni"
            ),

            // === Round 4 Cases (Paragraph Backspace, English Disambiguation, `w -> ư`) ===
            BrowserQACase(
                name: "R4_01_LongParagraph_StepByStepBackspace_ZeroJump",
                selector: "#markdown-textarea",
                speed: fast140,
                input: "",
                expected: "Hôm nay tôi kiểm tra bộ gõ VietGo trên Safari & Chrome: đã xóa từng từ mượt mà!",
                isChatSubmit: false,
                stepDeleteProbe: StepDeleteProbe(
                    prefixToType: "Hoom nay tooi kieemr tra booj gox VietGo treen browser: window refresh defend texts work virus away less boss yess was worm ddwocj giwx nguyeen maf khoong bij nhayr chuwx!",
                    expectedFullText: "Hôm nay tôi kiểm tra bộ gõ VietGo trên browser: window refresh defend texts work virus away less boss yess was worm được giữ nguyên mà không bị nhảy chữ!",
                    deleteSteps: 114,
                    protectedEnglishTokens: ["browser:", "window", "refresh", "defend", "texts", "work", "virus", "away", "less", "boss", "yess", "was", "worm"],
                    tailInput: "Safari & Chrome: ddax xoas twfng twf muowtj maf!"
                )
            ),
            BrowserQACase(
                name: "R4_02_RichEditor_HoldRepeatBS_And_OptionWordDelete",
                selector: "#rich-editor",
                speed: fast140,
                input: "Tooi gox thwr away\u{E008}\u{E008}\u{E008}\u{E008}less\u{E004}yess worm ddwocj giwx nguyen!\u{08}!",
                expected: "Tôi gõ thử yess worm được giữ nguyen!",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R4_03_YesYessYesss_And_FinalGeminates",
                selector: "#markdown-textarea",
                speed: fast140,
                input: "yes yess yesss less mess boss loss pass miss kiss mass guess chess swiss tariff buff purr vaf ass hass gass buss hiss thiss losse dessign ",
                expected: "yes yess yesss less mess boss loss pass miss kiss mass guess chess swiss tariff buff purr và as has gas bus his this lose design ",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R4_04_EnglishToneSwitch_And_AwayCircumflex",
                selector: "#rich-editor",
                speed: fast140,
                input: "away awake aware award virus terms turns burns horns surf turf dwarf been canhj nhaf hoafn thanhf ",
                expected: "away awake aware award virus terms turns burns horns surf turf dwarf bên cạnh nhà hoàn thành ",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R4_05_InitialW_English_Vs_VietnameseShorthandW",
                selector: "#markdown-textarea",
                speed: fast140,
                input: "was war wax won woo wow worm worn wrong write nhwng thwr chwx chwa ddwngf ddwocj trwongf ngwoif giwx giwax rwouj hwou bwoms camr own cow how ",
                expected: "was war wax won woo wow worm worn wrong write nhưng thử chữ chưa đừng được trường người giữ giữa rượu hươu bướm cảm ơn cơ hơ ",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R4_06_OmniboxAutocomplete_NoSentinelLeak",
                selector: "#omnibox-input",
                speed: fast140,
                input: "ddang tests yess away virus worm was ddwocj https://github.com/haiquang/VietGo ",
                expected: "đang tests yess away virus worm was được https://github.com/haiquang/VietGo ",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R4_07_ReactControlledInput_BackspaceWordByWord",
                selector: "#react-controlled-input",
                speed: burst190,
                input: "Window refresh defend dduowcj\u{08}\u{08}\u{08}\u{08}\u{08}\u{08}\u{08}\u{08}\u{08}\u{08}\u{08}yess vaf chwx ",
                expected: "Window refresh yess và chữ ",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R4_08_ChatMultiTurn_BurstRollover",
                selector: "#chat-input",
                speed: burst190,
                input: "Chafo banj, yess hay away vaf virus ddeefu oorn!\nNhwng nhwngx twf ddwocj nhw giwx nguyeen, doesn't break!\n",
                expected: "Chào bạn, yess hay away và virus đều ổn! | Nhưng những từ được như giữ nguyên, doesn't break!",
                isChatSubmit: true
            ),

            // === Round 5 Cases (Zero-Thrash & Free-Order `điều` + Post-Space Recovery) ===
            BrowserQACase(
                name: "R5_01_Dieu_AllOrders_ExtremeRollover250WPM",
                selector: "#rich-editor",
                speed: extreme250,
                input: "ddieeuf ddieuef ddieufe ddiefeu ddifeeu dieeufd Ddieeuf nhiefeu tieseng viejet truofwng dduojwc ",
                expected: "điều điều điều điều điều điều Điều nhiều tiếng việt trường được ",
                isChatSubmit: false
            ),
            BrowserQACase(
                name: "R5_02_Dieu_Omnibox_PostSpaceRecovery_And_Backspace",
                selector: "#omnibox-input",
                speed: fast140,
                input: "mootj ddieeuf quan trongj, ddieu \u{08}ef hay ddieuf \u{08}e vaf dies lies yess ",
                expected: "một điều quan trọng, điều hay điều và dies lies yess ",
                isChatSubmit: false
            )
            // APPEND NEW ROUND CASES (`R6_XX_...`) BELOW THIS LINE
        ]

        let cases: [BrowserQACase]
        if let filterTerm, !filterTerm.isEmpty {
            cases = allCases.filter { $0.name.localizedCaseInsensitiveContains(filterTerm) }
        } else {
            cases = allCases
        }

        guard !cases.isEmpty else {
            fputs("ERROR: No QA cases matched filter '\(filterTerm ?? "")'\n", stderr)
            exit(1)
        }

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

            let caseStart = CFAbsoluteTimeGetCurrent()
            guard coordinator.focusAndClickSelector(item.selector, postFocusJS: item.postFocusJS) else {
                print("FAIL \(item.name) (\(item.selector)): failed to focus/click")
                continue
            }
            pump(for: 0.50)

            var burstMs = 0.0
            var burstError: Error?
            var stepProbeError: String?

            if let probe = item.stepDeleteProbe {
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .userInteractive).async {
                    do {
                        burstMs += try postHardwareSequence(probe.prefixToType, speed: item.speed, targetPID: selfPID)
                    } catch {
                        burstError = error
                    }
                    sem.signal()
                }
                while sem.wait(timeout: .now()) == .timedOut {
                    pump(for: 0.005)
                }
                pump(for: 0.35)

                let fullActual = coordinator.readOutput(selector: item.selector, isChatSubmit: false)
                    .precomposedStringWithCanonicalMapping
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

                    var currentText = fullActual
                    for stepIdx in 1...probe.deleteSteps {
                        let bsSem = DispatchSemaphore(value: 0)
                        DispatchQueue.global(qos: .userInteractive).async {
                            do {
                                burstMs += try postHardwareSequence("\u{08}", speed: item.speed, targetPID: selfPID)
                            } catch {
                                burstError = error
                            }
                            bsSem.signal()
                        }
                        while bsSem.wait(timeout: .now()) == .timedOut {
                            pump(for: 0.004)
                        }
                        pump(for: 0.022)
                        let nextText = coordinator.readOutput(selector: item.selector, isChatSubmit: false)
                            .precomposedStringWithCanonicalMapping
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

                    if stepProbeError == nil && burstError == nil {
                        let tailSem = DispatchSemaphore(value: 0)
                        DispatchQueue.global(qos: .userInteractive).async {
                            do {
                                burstMs += try postHardwareSequence(probe.tailInput, speed: item.speed, targetPID: selfPID)
                            } catch {
                                burstError = error
                            }
                            tailSem.signal()
                        }
                        while tailSem.wait(timeout: .now()) == .timedOut {
                            pump(for: 0.005)
                        }
                    }
                }
            } else {
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .userInteractive).async {
                    do {
                        burstMs = try postHardwareSequence(item.input, speed: item.speed, targetPID: selfPID)
                    } catch {
                        burstError = error
                    }
                    sem.signal()
                }
                while sem.wait(timeout: .now()) == .timedOut {
                    pump(for: 0.005)
                }
            }

            pump(for: 0.40)

            let caseDurationMs = Int((CFAbsoluteTimeGetCurrent() - caseStart) * 1000.0)
            let actual = coordinator.readOutput(
                selector: item.selector,
                isChatSubmit: item.isChatSubmit,
                customReadoutJS: item.customReadoutJS
            ).precomposedStringWithCanonicalMapping
            let domOk: Bool
            if let domAssertionJS = item.domAssertionJS {
                domOk = (coordinator.evalJS(domAssertionJS) as? Bool) ?? false
            } else {
                domOk = true
            }
            let totalChars = item.stepDeleteProbe.map { $0.prefixToType.count + $0.deleteSteps + $0.tailInput.count } ?? item.input.count
            let wpm = Int((Double(totalChars) / 5.0) / max(burstMs / 60_000.0, 0.001))
            let hasSentinelLeak = actual.contains("\u{202F}") || actual.contains("\u{2060}") || actual.contains("\u{0259}")
            let isNFC = (actual == actual.precomposedStringWithCanonicalMapping)
            let ok = (burstError == nil) && (stepProbeError == nil) && (actual == item.expected) && domOk && !hasSentinelLeak && isNFC
            let status = ok ? "PASS" : "FAIL"
            if ok { passedCount += 1 }

            let record: [String: Any] = [
                "name": item.name,
                "selector": item.selector,
                "speed": item.speed.label,
                "wpm": wpm,
                "durationMs": caseDurationMs,
                "status": status,
                "actual": stepProbeError ?? actual,
                "expected": item.expected
            ]
            jsonRecords.append(record)
            postServerRequest("/api/results", jsonObject: record)

            print("\(status) \(item.name) [\(item.selector) | \(item.speed.label) | ~\(wpm) WPM | \(caseDurationMs)ms | dom=\(domOk) nfc=\(isNFC)]")
            if !ok {
                print("  expected: \"\(item.expected)\"")
                print("  actual:   \"\(actual)\" (probeErr=\(stepProbeError ?? "none"), domOk=\(domOk), isNFC=\(isNFC), hasSentinelLeak=\(hasSentinelLeak), err=\(burstError?.localizedDescription ?? "none"))")
            }
        }

        if let workerClient, activeMethod != "telex" {
            workerClient.send("METHOD telex")
        }
        workerClient?.stop()

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - suiteStart) * 1000.0)
        let avgMs = totalMs / max(cases.count, 1)
        let selfAuditPassed = avgMs >= 500

        if let jsonOutPath {
            let outURL = URL(fileURLWithPath: jsonOutPath)
            try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload: [String: Any] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "totalCases": cases.count,
                "passedCases": passedCount,
                "totalDurationMs": totalMs,
                "avgDurationMs": avgMs,
                "selfAuditPassed": selfAuditPassed,
                "results": jsonRecords
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: outURL)
            }
        }

        print("SUMMARY: \(passedCount)/\(cases.count) PASSED in \(totalMs)ms (avg \(avgMs)ms/case)")
        if !selfAuditPassed {
            fputs("SELF_AUDIT_FAIL: avgDurationMs=\(avgMs)ms < 500ms/case minimum browser QA budget.\n", stderr)
            exit(2)
        }
        exit(passedCount == cases.count ? 0 : 1)
    }
}
