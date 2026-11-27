import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Foundation
import VietGoEngine
import WebKit

private let testEventMarker: Int64 = 0x5445_5354 // "TEST"

enum KeyHand {
    case left
    case right
    case thumbOrEdit
}

struct KeySpec {
    let keyCode: CGKeyCode
    let shift: Bool
    let hand: KeyHand
    let unicode: UniChar?
}

private func qwertySpec(for char: Character) -> KeySpec? {
    if char == "\u{08}" {
        return KeySpec(keyCode: 51, shift: false, hand: .thumbOrEdit, unicode: nil)
    }
    if char == "\n" || char == "\r" {
        return KeySpec(keyCode: 36, shift: false, hand: .thumbOrEdit, unicode: nil)
    }
    if char == "\t" {
        return KeySpec(keyCode: 48, shift: false, hand: .left, unicode: nil)
    }
    if char == " " {
        return KeySpec(keyCode: 49, shift: false, hand: .thumbOrEdit, unicode: 0x0020)
    }

    let isUpper = char.isUppercase
    let lower = Character(String(char).lowercased())
    let utf16Unit = String(char).utf16.first

    let map: [Character: (CGKeyCode, KeyHand)] = [
        "a": (0, .left), "s": (1, .left), "d": (2, .left), "f": (3, .left), "g": (5, .left),
        "q": (12, .left), "w": (13, .left), "e": (14, .left), "r": (15, .left), "t": (17, .left),
        "z": (6, .left), "x": (7, .left), "c": (8, .left), "v": (9, .left), "b": (11, .left),
        "1": (18, .left), "2": (19, .left), "3": (20, .left), "4": (21, .left), "5": (23, .left),

        "h": (4, .right), "j": (38, .right), "k": (40, .right), "l": (37, .right),
        "y": (16, .right), "u": (32, .right), "i": (34, .right), "o": (31, .right), "p": (35, .right),
        "n": (45, .right), "m": (46, .right),
        "6": (22, .right), "7": (26, .right), "8": (28, .right), "9": (25, .right), "0": (29, .right),
        ",": (43, .right), ".": (47, .right), "/": (44, .right), ";": (41, .right), "'": (39, .right),
        "[": (33, .right), "]": (30, .right), "-": (27, .right), "=": (24, .right)
    ]

    if let (kc, hand) = map[lower] {
        return KeySpec(keyCode: kc, shift: isUpper, hand: hand, unicode: utf16Unit)
    }
    return nil
}

// MARK: - IME Worker Process Mode (--ime-worker)

@MainActor
final class IMEWorkerRunner {
    private static var readerThread: Thread?

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let settings = AppSettings.shared
        settings.isEnabled = true
        settings.inputMethod = .telex
        settings.toneStyle = .modern
        settings.autoRestoreEnglish = true
        settings.autocompleteFix = true
        settings.standaloneW = true
        settings.bracketShortcuts = false

        let tapManager = EventTapManager.shared
        tapManager.updateEngineConfig(settings.engineConfig)
        tapManager.start()

        guard tapManager.isTapRunning else {
            fputs("IME_WORKER_ERROR: Failed to start EventTapManager (isAccessibilityGranted=\(tapManager.isAccessibilityGranted))\n", stderr)
            exit(2)
        }

        print("READY")
        fflush(stdout)

        DispatchQueue.global(qos: .userInteractive).async {
            while let line = readLine(strippingNewline: true) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "QUIT" {
                    DispatchQueue.main.async {
                        EventTapManager.shared.stop()
                        exit(0)
                    }
                    break
                } else if trimmed == "RESET" {
                    DispatchQueue.main.sync {
                        EventTapManager.shared.resetEngine()
                        print("OK")
                        fflush(stdout)
                    }
                } else if trimmed.hasPrefix("BUNDLE ") {
                    let arg = String(trimmed.dropFirst("BUNDLE ".count))
                    DispatchQueue.main.sync {
                        EventTapManager.shared.debugOverrideTargetBundleID = (arg == "-" ? nil : arg)
                        EventTapManager.shared.resetEngine()
                        print("OK")
                        fflush(stdout)
                    }
                } else if trimmed.hasPrefix("METHOD ") {
                    let arg = String(trimmed.dropFirst("METHOD ".count)).lowercased()
                    DispatchQueue.main.sync {
                        let settings = AppSettings.shared
                        settings.inputMethod = (arg == "vni") ? .vni : .telex
                        EventTapManager.shared.updateEngineConfig(settings.engineConfig)
                        EventTapManager.shared.resetEngine()
                        print("OK")
                        fflush(stdout)
                    }
                }
            }
            // Exit immediately when parent closes stdin so no stray HID event tap remains active
            DispatchQueue.main.async {
                EventTapManager.shared.stop()
                exit(0)
            }
        }

        app.run()
        exit(0)
    }
}

// MARK: - E2E Orchestrator Mode

@MainActor
final class ValidatorCoordinator: NSObject, WKNavigationDelegate {
    let window: NSWindow
    let textView: NSTextView
    let webView: WKWebView
    private var webLoaded = false

    override init() {
        let contentRect = NSRect(x: 160, y: 160, width: 680, height: 460)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VietGo Fast-Chat E2E Validator"

        let root = NSView(frame: contentRect)
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 230, width: 648, height: 210))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 648, height: 210))
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        scroll.documentView = textView

        let webConfig = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 16, y: 16, width: 648, height: 200), configuration: webConfig)

        root.addSubview(scroll)
        root.addSubview(webView)
        window.contentView = root

        super.init()

        webView.navigationDelegate = self
        let html = """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"></head>
        <body style="margin:0;padding:8px;font-family:-apple-system,sans-serif;background:#ffffff;">
          <div id="editor" contenteditable="true" spellcheck="false" autocomplete="off" autocorrect="off" autocapitalize="off"
               style="width:100%;height:170px;border:1px solid #888;padding:8px;box-sizing:border-box;font-size:15px;outline:none;white-space:pre-wrap;"></div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webLoaded = true
    }

    func isWebReady() -> Bool {
        webLoaded
    }

    func focusTextViewAndClear() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        textView.string = ""
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        window.makeFirstResponder(textView)
    }

    func focusWebEditorAndClear() -> Bool {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(webView)

        let sem = DispatchSemaphore(value: 0)
        var ok = false
        webView.evaluateJavaScript("""
            (() => {
              const ed = document.getElementById('editor');
              if (!ed) return false;
              ed.textContent = '';
              ed.focus();
              return document.activeElement === ed;
            })()
        """) { result, _ in
            ok = (result as? Bool) ?? false
            sem.signal()
        }
        // Pump runloop until JS callback returns
        let deadline = Date().addingTimeInterval(2.0)
        while sem.wait(timeout: .now()) == .timedOut && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return ok
    }

    func readWebEditorText() -> String? {
        let sem = DispatchSemaphore(value: 0)
        var text: String?
        webView.evaluateJavaScript("document.getElementById('editor')?.textContent ?? ''") { result, _ in
            text = result as? String
            sem.signal()
        }
        // Pump runloop until JS callback returns
        let deadline = Date().addingTimeInterval(2.0)
        while sem.wait(timeout: .now()) == .timedOut && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return text
    }

    private var eventLog: [String] = []
    private var localMonitor: Any?

    func startEventCapture() {
        eventLog.removeAll()
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] ev in
                let chars = (ev.characters ?? "").map { ch -> String in
                    if ch == "\u{08}" || ch == "\u{7F}" { return "<BS>" }
                    if ch == "\r" || ch == "\n" { return "<RET>" }
                    return String(ch)
                }.joined()
                let t = String(format: "%.3f", ev.timestamp.truncatingRemainder(dividingBy: 100))
                self?.eventLog.append("[\(t) kc=\(ev.keyCode) '\(chars)']")
                return ev
            }
        }
    }

    func dumpEventCapture() -> String {
        eventLog.joined(separator: " ")
    }
}

final class IMEWorkerClient {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private var stdoutBuffer = Data()

    init(executablePath: String) throws {
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--ime-worker"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        try process.run()

        guard waitForLine(expected: "READY", timeoutSeconds: 5.0) else {
            terminate()
            throw NSError(domain: "E2E", code: 1, userInfo: [NSLocalizedDescriptionKey: "IME worker did not report READY"])
        }
    }

    func sendCommand(_ command: String) throws {
        guard let data = (command + "\n").data(using: .utf8) else { return }
        stdinPipe.fileHandleForWriting.write(data)
        guard waitForLine(expected: "OK", timeoutSeconds: 3.0) else {
            throw NSError(domain: "E2E", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timeout waiting OK for \(command)"])
        }
    }

    func terminate() {
        if process.isRunning {
            if let data = "QUIT\n".data(using: .utf8) {
                do {
                    try stdinPipe.fileHandleForWriting.write(contentsOf: data)
                } catch {}
            }
            usleep(50_000)
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func waitForLine(expected: String, timeoutSeconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let fd = stdoutPipe.fileHandleForReading.fileDescriptor
        while Date() < deadline {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, 50)
            if ready > 0 {
                let chunk = stdoutPipe.fileHandleForReading.availableData
                if !chunk.isEmpty {
                    stdoutBuffer.append(chunk)
                    if let str = String(data: stdoutBuffer, encoding: .utf8),
                       str.split(separator: "\n").contains(where: { String($0) == expected }) {
                        stdoutBuffer.removeAll()
                        return true
                    }
                }
            }
        }
        return false
    }
}

private func postHardwareBurst(_ input: String, baseMs: Int, rolloverMs: Int, targetPID: pid_t) throws -> Double {
    guard let privateSource = CGEventSource(stateID: .privateState) else {
        throw NSError(domain: "E2E", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create private CGEventSource"])
    }
    let clearMask: CGEventFlags = [.maskShift, .maskCommand, .maskAlternate, .maskControl, .maskSecondaryFn]

    let start = CFAbsoluteTimeGetCurrent()
    var prevHand: KeyHand?

    for ch in input {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID {
            throw NSError(domain: "E2E", code: 4, userInfo: [NSLocalizedDescriptionKey: "Aborted: target E2E window lost foreground focus"])
        }
        guard let spec = qwertySpec(for: ch) else {
            throw NSError(domain: "E2E", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unsupported char in E2E script: \(ch)"])
        }

        if let prev = prevHand {
            let intervalMs: Int
            if prev != spec.hand {
                intervalMs = rolloverMs
            } else {
                intervalMs = baseMs
            }
            usleep(UInt32(intervalMs * 1000))
        }
        prevHand = spec.hand

        let flags: CGEventFlags = spec.shift ? .maskShift : []
        if let kd = CGEvent(keyboardEventSource: privateSource, virtualKey: spec.keyCode, keyDown: true) {
            kd.flags.subtract(clearMask)
            kd.flags.formUnion(flags)
            if let u = spec.unicode {
                var arr: [UniChar] = [u]
                kd.keyboardSetUnicodeString(stringLength: 1, unicodeString: &arr)
            }
            kd.setIntegerValueField(.eventSourceUserData, value: testEventMarker)
            kd.post(tap: .cghidEventTap)
        }
        usleep(900)
        if let ku = CGEvent(keyboardEventSource: privateSource, virtualKey: spec.keyCode, keyDown: false) {
            ku.flags.subtract(clearMask)
            ku.flags.formUnion(flags)
            if let u = spec.unicode {
                var arr: [UniChar] = [u]
                ku.keyboardSetUnicodeString(stringLength: 1, unicodeString: &arr)
            }
            ku.setIntegerValueField(.eventSourceUserData, value: testEventMarker)
            ku.post(tap: .cghidEventTap)
        }
    }

    return (CFAbsoluteTimeGetCurrent() - start) * 1000.0
}

@MainActor
private func pumpRunLoop(for seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        while let event = NSApp.nextEvent(
            matching: .any,
            until: Date().addingTimeInterval(0.005),
            inMode: .default,
            dequeue: true
        ) {
            NSApp.sendEvent(event)
            if Date() >= deadline {
                break
            }
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
    }
}

struct Scenario {
    enum Target {
        case textView
        case webView
    }
    let name: String
    let bundleOverride: String?
    let target: Target
    let input: String
    let expected: String
    let baseMs: Int
    let rolloverMs: Int
    let normalizePrecomposed: Bool
}

@MainActor
func runOrchestrator() -> Int32 {
    guard AXIsProcessTrusted() else {
        fputs("ERROR: Accessibility permission (AXIsProcessTrusted) is required for E2E validation.\n", stderr)
        return 1
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.finishLaunching()

    let coordinator = ValidatorCoordinator()
    coordinator.window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    let selfPID = ProcessInfo.processInfo.processIdentifier
    let activationDeadline = Date().addingTimeInterval(4.0)
    while Date() < activationDeadline {
        pumpRunLoop(for: 0.05)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == selfPID &&
            coordinator.window.isKeyWindow &&
            coordinator.isWebReady() {
            break
        }
    }

    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == selfPID else {
        fputs("ERROR: Validator window failed to acquire frontmost focus.\n", stderr)
        return 1
    }

    let worker: IMEWorkerClient
    do {
        worker = try IMEWorkerClient(executablePath: CommandLine.arguments[0])
    } catch {
        fputs("ERROR: \(error.localizedDescription)\n", stderr)
        return 1
    }
    defer { worker.terminate() }

    let scenarios: [Scenario] = [
        Scenario(
            name: "A_NSTextView_FastChat_UserSentence_150WPM",
            bundleOverride: nil,
            target: .textView,
            input: "looix quas nhieeuf sau fix, ddanhs gias laij xem, banj thuwr validation nhuw mootj nguowif dungf chat nhanh ddi",
            expected: "lỗi quá nhiều sau fix, đánh giá lại xem, bạn thử validation như một người dùng chat nhanh đi",
            baseMs: 14,
            rolloverMs: 4,
            normalizePrecomposed: false
        ),
        Scenario(
            name: "B_NSTextView_ExtremeBurst_RegressionMatrix_220WPM",
            bundleOverride: nil,
            target: .textView,
            input: "lamf ddax cuar taij hanfh mowis URRL dessign ddasnh thuwr ddi \nmowis\nchafo tieengs\u{08}\u{08}p ",
            expected: "làm đã của tại hành mới URL design đánh thử đi \nmới\nchào tiếp ",
            baseMs: 8,
            rolloverMs: 3,
            normalizePrecomposed: false
        ),
        Scenario(
            name: "C_NSTextView_ChromeAutocompleteFix_U202F",
            bundleOverride: "com.google.Chrome",
            target: .textView,
            input: "aa ddi thuwr validation mowis lamf ddax ",
            expected: "â đi thử validation mới làm đã ",
            baseMs: 10,
            rolloverMs: 4,
            normalizePrecomposed: false
        ),
        Scenario(
            name: "D_NSTextView_MicrosoftWord_DecomposedAcuteY",
            bundleOverride: "com.microsoft.Word",
            target: .textView,
            input: "ys Ys kys ",
            expected: "ý Ý ký ",
            baseMs: 12,
            rolloverMs: 4,
            normalizePrecomposed: true
        ),
        Scenario(
            name: "E_WKWebView_ContentEditable_FastChat",
            bundleOverride: "com.google.antigravity",
            target: .webView,
            input: "ddanhs gias laij xem, banj thuwr validation nhuw mootj nguowif dungf chat nhanh ddi mowis",
            expected: "đánh giá lại xem, bạn thử validation như một người dùng chat nhanh đi mới",
            baseMs: 12,
            rolloverMs: 4,
            normalizePrecomposed: false
        ),
        Scenario(
            name: "F_WKWebView_ChromeAutocomplete_BurstChat",
            bundleOverride: "com.google.Chrome",
            target: .webView,
            input: "lamf ddax cuar taij hanfh mowis, thuwr validation nguowif dungf ddi ",
            expected: "làm đã của tại hành mới, thử validation người dùng đi ",
            baseMs: 10,
            rolloverMs: 3,
            normalizePrecomposed: false
        ),
        Scenario(
            name: "G_NSTextView_VSCodeTerminalPacing_FastChat",
            bundleOverride: "com.microsoft.VSCode",
            target: .textView,
            input: "mowis mootj nhieeuf nguowif dungf thuwr validation ddasnh ddi ",
            expected: "mới một nhiều người dùng thử validation đánh đi ",
            baseMs: 10,
            rolloverMs: 3,
            normalizePrecomposed: false
        )
    ]

    var allPassed = true

    for scenario in scenarios {
        do {
            try worker.sendCommand("BUNDLE \(scenario.bundleOverride ?? "-")")
        } catch {
            print("FAIL \(scenario.name): worker command error: \(error)")
            allPassed = false
            continue
        }

        switch scenario.target {
        case .textView:
            coordinator.focusTextViewAndClear()
        case .webView:
            let focused = coordinator.focusWebEditorAndClear()
            if !focused {
                print("FAIL \(scenario.name): could not focus #editor inside WKWebView")
                allPassed = false
                continue
            }
        }
        pumpRunLoop(for: 0.06)
        coordinator.startEventCapture()

        var elapsedMs = 0.0
        var burstError: Error?
        let doneSem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                elapsedMs = try postHardwareBurst(
                    scenario.input,
                    baseMs: scenario.baseMs,
                    rolloverMs: scenario.rolloverMs,
                    targetPID: selfPID
                )
            } catch {
                burstError = error
            }
            doneSem.signal()
        }

        while doneSem.wait(timeout: .now()) == .timedOut {
            pumpRunLoop(for: 0.005)
        }

        if let burstError {
            print("FAIL \(scenario.name): \(burstError.localizedDescription)")
            allPassed = false
            continue
        }

        // Let final AppKit / WebKit events drain completely
        pumpRunLoop(for: 0.16)

        let rawOutput: String
        switch scenario.target {
        case .textView:
            rawOutput = coordinator.textView.string
        case .webView:
            rawOutput = coordinator.readWebEditorText() ?? "<nil>"
        }

        let actual = scenario.normalizePrecomposed ? rawOutput.precomposedStringWithCanonicalMapping : rawOutput
        let expected = scenario.normalizePrecomposed ? scenario.expected.precomposedStringWithCanonicalMapping : scenario.expected
        let containsHiddenPrefix = actual.contains("\u{202F}")
        let wpm = (Double(scenario.input.count) / 5.0) / max(elapsedMs / 60_000.0, 0.001)

        if actual == expected && !containsHiddenPrefix {
            let msStr = String(format: "%.1f", elapsedMs)
            let wpmStr = String(format: "%.0f", wpm)
            print("PASS \(scenario.name) | keys=\(scenario.input.count) | time=\(msStr)ms | ~\(wpmStr) WPM | out=\"\(actual)\"")
        } else {
            allPassed = false
            print("FAIL \(scenario.name):")
            print("  input:    \"\(scenario.input)\"")
            print("  expected: \"\(expected)\"")
            print("  actual:   \"\(actual)\" (hasU202F=\(containsHiddenPrefix))")
            print("  events:   \(coordinator.dumpEventCapture())")
        }
    }

    return allPassed ? 0 : 1
}

@main
enum ValidatorMain {
    static func main() {
        if CommandLine.arguments.contains("--ime-worker") {
            MainActor.assumeIsolated {
                IMEWorkerRunner.run()
            }
        } else {
            let code = MainActor.assumeIsolated {
                runOrchestrator()
            }
            exit(code)
        }
    }
}
