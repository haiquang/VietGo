import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Combine
import Foundation
import VietGoEngine

private let kVietGoEventMarker: Int64 = 0x5647_4F31

@MainActor
public final class EventTapManager: ObservableObject {
    public static let shared = EventTapManager()

    @Published public private(set) var isAccessibilityGranted: Bool = false
    @Published public private(set) var isTapRunning: Bool = false
    public var isRecordingShortcut: Bool = false
    public var onAccessibilityChanged: (() -> Void)?

    private var engine = VietInputEngine()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pollTimer: Timer?
    private var watchdogTimer: Timer?

    private let systemWideElement = AXUIElementCreateSystemWide()
    private let privateEventSource = CGEventSource(stateID: .privateState)
    private let axQueryQueue = DispatchQueue(label: "org.vietgo.VietGo.ax-query", qos: .userInitiated)
    private var pendingFocusRefreshWorkItem: DispatchWorkItem?
    private var focusGeneration: UInt64 = 0
    private var frontmostBundleID: String = ""
    private var cachedFocusedBundleID: String = ""
    private var cachedIsExplicitWebTextArea: Bool = false
    private var cachedIsCanvasNonTextInDesignApp: Bool = false
    private var isIncompatibleInputSource: Bool = false
    private var currentInputSourceID: String = ""
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var hasPromptedInCurrentProcess: Bool = false

    // Modifier-only shortcut tracking (supports sequential lift + hold-duration guard)
    private var pendingModifierOnlyMatch = false
    private var modifierMatchStartedAt: Date?
    private var keyPressedDuringModifierHold = false

    // Serialize physical events & synthetic injections at the HID/session boundary
    private let injectionSemaphore = DispatchSemaphore(value: 1)
    private var isHIDTapActive: Bool = false
    private var isSessionOnConsole: Bool = true
    private var mouseMonitor: Any?
    private static let strippedModifierFlags: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskAlphaShift, .maskSecondaryFn
    ]
    public var debugOverrideTargetBundleID: String?

    private let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaAir",
        "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS",
        "app.zen-browser.zen",
        "ai.perplexity.comet",
        "com.openai.atlas",
        "net.imput.helium",
        "com.coccoc.Coccoc"
    ]

    private let alwaysAutocompleteBundleIDs: Set<String> = [
        "com.apple.Spotlight",
        "com.raycast.macos",
        "com.runningwithcrayons.Alfred",
        "com.runningwithcrayons.Alfred-3",
        "com.apple.mail",
        "com.microsoft.Excel"
    ]

    private let microsoftOfficeBundleIDs: Set<String> = [
        "com.microsoft.Word",
        "com.microsoft.Powerpoint",
        "com.microsoft.Outlook",
        "com.microsoft.Excel"
    ]

    private let designCanvasBundleIDs: Set<String> = [
        "com.adobe.Photoshop",
        "com.adobe.illustrator",
        "com.seriflabs.affinitydesigner2",
        "com.seriflabs.affinityphoto2",
        "com.figma.Desktop"
    ]

    /// Terminal / PTY / TUI / IDE apps that benefit from paced Backspace -> Unicode delivery
    /// so raw PTY reads (e.g. Claude Code CLI, tmux, vim, Warp, Ghostty) do not drop characters.
    private let terminalAndPTYBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "com.google.antigravity",
        "com.vng.zalo",
        "dev.zed.Zed"
    ]

    private let navigationKeyCodes: Set<Int64> = [
        36,  // Return
        76,  // Keypad Enter
        48,  // Tab
        53,  // Escape
        117, // Forward Delete
        123, // Left Arrow
        124, // Right Arrow
        125, // Down Arrow
        126, // Up Arrow
        115, // Home
        119, // End
        116, // Page Up
        121  // Page Down
    ]

    private init() {
        AXUIElementSetMessagingTimeout(systemWideElement, 0.005)
        isSessionOnConsole = (CGSessionCopyCurrentDictionary() as? [String: Any])?[kCGSessionOnConsoleKey as String] as? Bool ?? true
        let initialBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        frontmostBundleID = initialBundle
        cachedFocusedBundleID = initialBundle
        engine.config = AppSettings.shared.engineConfig

        refreshInputSourceCompatibility()
        registerWorkspaceObservers()
    }

    public func updateEngineConfig(_ config: EngineConfig) {
        engine.config = config
    }

    private nonisolated static func runOnMainActor(_ block: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                block()
            }
        } else {
            Task { @MainActor in
                block()
            }
        }
    }

    private func registerWorkspaceObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        observers.append(wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let strongSelf = self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier ?? ""
            Self.runOnMainActor {
                guard !bundleID.isEmpty else { return }
                let didSwitchApp = (bundleID != strongSelf.frontmostBundleID)
                strongSelf.pendingFocusRefreshWorkItem?.cancel()
                strongSelf.pendingFocusRefreshWorkItem = nil
                strongSelf.focusGeneration &+= 1
                strongSelf.frontmostBundleID = bundleID
                strongSelf.cachedFocusedBundleID = bundleID
                if didSwitchApp {
                    strongSelf.cachedIsExplicitWebTextArea = false
                    strongSelf.cachedIsCanvasNonTextInDesignApp = false
                    strongSelf.engine.reset(clearHistory: true)
                }
                strongSelf.refreshFocusedBundleAsync()
            }
        })

        let wakeHandler: @Sendable (Notification) -> Void = { [weak self] _ in
            guard let strongSelf = self else { return }
            Self.runOnMainActor {
                strongSelf.handleSystemWakeOrSessionActive()
            }
        }
        observers.append(wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: wakeHandler))
        observers.append(wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: wakeHandler))
        observers.append(wsCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main, using: wakeHandler))

        observers.append(wsCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Self.runOnMainActor {
                strongSelf.isSessionOnConsole = false
                strongSelf.engine.reset(clearHistory: true)
            }
        })

        let distCenter = DistributedNotificationCenter.default()
        distributedObservers.append(distCenter.addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Self.runOnMainActor {
                let changed = strongSelf.refreshInputSourceCompatibility()
                if changed {
                    strongSelf.engine.reset(clearHistory: true)
                }
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Self.runOnMainActor {
                strongSelf.refreshAccessibilityAndStartIfPossible()
            }
        })
    }

    private func handleSystemWakeOrSessionActive() {
        isSessionOnConsole = (CGSessionCopyCurrentDictionary() as? [String: Any])?[kCGSessionOnConsoleKey as String] as? Bool ?? true
        engine.reset(clearHistory: true)
        pendingModifierOnlyMatch = false
        keyPressedDuringModifierHold = false
        refreshInputSourceCompatibility()

        if !checkAccessibility() {
            teardownTapOnly()
            startPollingForAccessibility()
            return
        }

        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            if !CGEvent.tapIsEnabled(tap: tap) {
                teardownTapOnly()
                setupEventTap()
            }
        } else {
            setupEventTap()
        }
    }

    @discardableResult
    private func refreshInputSourceCompatibility() -> Bool {
        guard let sourceRef = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            let changed = !currentInputSourceID.isEmpty || isIncompatibleInputSource
            currentInputSourceID = ""
            isIncompatibleInputSource = false
            return changed
        }

        var incompatible = false
        var sourceID = ""

        if let typeRef = TISGetInputSourceProperty(sourceRef, kTISPropertyInputSourceType) {
            let sourceType = Unmanaged<CFString>.fromOpaque(typeRef).takeUnretainedValue() as String
            if sourceType.localizedCaseInsensitiveContains("InputMethod") ||
               sourceType.localizedCaseInsensitiveContains("InputMode") {
                incompatible = true
            }
        }

        if let idRef = TISGetInputSourceProperty(sourceRef, kTISPropertyInputSourceID) {
            sourceID = Unmanaged<CFString>.fromOpaque(idRef).takeUnretainedValue() as String
            let blockedPatterns = [
                "Japanese", "Kotoeri", "SCIM", "TCIM", "Korean",
                "Vietnamese", "InputMethod", "com.apple.inputmethod"
            ]
            if blockedPatterns.contains(where: { sourceID.localizedCaseInsensitiveContains($0) }) {
                incompatible = true
            }
        }

        let changed = (!currentInputSourceID.isEmpty && sourceID != currentInputSourceID) ||
            (incompatible != isIncompatibleInputSource)
        currentInputSourceID = sourceID
        isIncompatibleInputSource = incompatible
        return changed
    }

    private func scheduleDelayedFocusRefresh(after delay: TimeInterval) {
        pendingFocusRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pendingFocusRefreshWorkItem = nil
                self.refreshFocusedBundleAsync()
            }
        }
        pendingFocusRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func refreshFocusedBundleAsync() {
        guard isAccessibilityGranted, AXIsProcessTrusted() else { return }
        focusGeneration &+= 1
        let generation = focusGeneration
        let element = systemWideElement
        let designApps = designCanvasBundleIDs
        let browsers = browserBundleIDs
        axQueryQueue.async { [weak self] in
            var focusedAppRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(
                element,
                kAXFocusedApplicationAttribute as CFString,
                &focusedAppRef
            )
            var resolvedBundle: String?
            if err == .success, let focusedAppRef {
                // swiftlint:disable:next force_cast
                let appElement = focusedAppRef as! AXUIElement
                var pid: pid_t = 0
                if AXUIElementGetPid(appElement, &pid) == .success, pid != 0 {
                    resolvedBundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                }
            }

            var isExplicitWebTextArea = false
            var isCanvasNonText = false
            if let bundle = resolvedBundle, browsers.contains(bundle) || designApps.contains(bundle) {
                var focusedUIRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focusedUIRef) == .success,
                   let focusedUIRef {
                    // swiftlint:disable:next force_cast
                    let uiElement = focusedUIRef as! AXUIElement
                    var roleRef: CFTypeRef?
                    var role = ""
                    if AXUIElementCopyAttributeValue(uiElement, kAXRoleAttribute as CFString, &roleRef) == .success,
                       let r = roleRef as? String {
                        role = r
                    }
                    if browsers.contains(bundle) {
                        // Chrome/browsers often expose degraded AX roles ("", "AXWindow", "AXUnknown", "AXGroup")
                        // for address bars, search inputs, and web fields. Only skip the empty-char prefix when AX
                        // explicitly confirms a multiline web editor (AXTextArea).
                        isExplicitWebTextArea = (role == "AXTextArea")
                    }
                    if designApps.contains(bundle) {
                        let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXWebArea"]
                        isCanvasNonText = !role.isEmpty && !editableRoles.contains(role)
                    }
                }
            }

            Task { @MainActor in
                guard let self, self.focusGeneration == generation else { return }
                if let resolvedBundle, !resolvedBundle.isEmpty {
                    self.cachedFocusedBundleID = resolvedBundle
                }
                self.cachedIsExplicitWebTextArea = isExplicitWebTextArea
                self.cachedIsCanvasNonTextInDesignApp = isCanvasNonText
            }
        }
    }

    public func start() {
        refreshAccessibilityAndStartIfPossible()
        if !isAccessibilityGranted {
            startPollingForAccessibility()
        }
        startWatchdogTimer()
    }

    public func stop() {
        pendingFocusRefreshWorkItem?.cancel()
        pendingFocusRefreshWorkItem = nil
        pollTimer?.invalidate()
        pollTimer = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        teardownTapOnly()
    }

    private func teardownTapOnly() {
        stopMouseMonitor()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        isHIDTapActive = false
        isTapRunning = false
    }

    private func startMouseMonitor() {
        stopMouseMonitor()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Self.runOnMainActor {
                if strongSelf.pendingModifierOnlyMatch {
                    strongSelf.keyPressedDuringModifierHold = true
                }
                strongSelf.engine.reset(clearHistory: true)
                strongSelf.scheduleDelayedFocusRefresh(after: 0.05)
            }
        }
    }

    private func stopMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    public func resetEngine() {
        engine.reset(clearHistory: true)
    }

    private func setAccessibilityGranted(_ granted: Bool) {
        if isAccessibilityGranted != granted {
            isAccessibilityGranted = granted
            onAccessibilityChanged?()
        }
    }

    @discardableResult
    public func checkAccessibility() -> Bool {
        let trusted = AXIsProcessTrusted()
        setAccessibilityGranted(trusted)
        return trusted
    }

    public func refreshNow() {
        refreshAccessibilityAndStartIfPossible()
    }

    public func refreshNowOrRelaunch() {
        refreshAccessibilityAndStartIfPossible()
        if !isAccessibilityGranted {
            relaunchApp()
        }
    }

    public func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-n", bundlePath]
        try? proc.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.terminate(nil)
        }
    }

    public func resetAndPromptAccessibility() {
        teardownTapOnly()
        setAccessibilityGranted(false)
        hasPromptedInCurrentProcess = false

        let bundleID = Bundle.main.bundleIdentifier ?? "org.vietgo.VietGo"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        proc.arguments = ["reset", "Accessibility", bundleID]
        try? proc.run()
        proc.waitUntilExit()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.promptAccessibility()
        }
    }

    public func promptAccessibility() {
        if AXIsProcessTrusted() {
            refreshAccessibilityAndStartIfPossible()
            return
        }
        startPollingForAccessibility()

        if !hasPromptedInCurrentProcess {
            hasPromptedInCurrentProcess = true
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        } else {
            openAccessibilitySettings()
        }
    }

    public func openAccessibilitySettings() {
        if AXIsProcessTrusted() {
            refreshAccessibilityAndStartIfPossible()
            return
        }
        startPollingForAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPollingForAccessibility() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibilityAndStartIfPossible()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func startWatchdogTimer() {
        guard watchdogTimer == nil else { return }
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let liveGranted = AXIsProcessTrusted()
                self.setAccessibilityGranted(liveGranted)
                if !liveGranted {
                    if self.isTapRunning {
                        self.teardownTapOnly()
                    }
                    self.startPollingForAccessibility()
                    return
                }
                if let tap = self.eventTap {
                    if !CGEvent.tapIsEnabled(tap: tap) {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                } else {
                    self.setupEventTap()
                }
            }
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func refreshAccessibilityAndStartIfPossible() {
        let trusted = AXIsProcessTrusted()
        if trusted {
            if !isTapRunning {
                setupEventTap()
            }
            if isTapRunning {
                pollTimer?.invalidate()
                pollTimer = nil
            }
        } else if isTapRunning {
            teardownTapOnly()
        }
        setAccessibilityGranted(trusted && isTapRunning)
    }

    private func setupEventTap() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            isTapRunning = false
            return
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleCGEvent(proxy: proxy, type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        )
        if tap != nil {
            isHIDTapActive = true
        } else {
            isHIDTapActive = false
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: callback,
                userInfo: refcon
            )
        }

        guard let tap else {
            isTapRunning = false
            isHIDTapActive = false
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.isTapRunning = true
        startMouseMonitor()
    }

    private func handleCGEvent(proxy: CGEventTapProxy?, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            engine.reset(clearHistory: true)
            let stillGranted = AXIsProcessTrusted()
            setAccessibilityGranted(stillGranted)
            if stillGranted, let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                teardownTapOnly()
                startPollingForAccessibility()
            }
            return Unmanaged.passUnretained(event)
        }

        // Ignore keystrokes belonging to another active console user (Fast User Switching)
        if !isSessionOnConsole {
            return Unmanaged.passUnretained(event)
        }

        // Never intercept our own synthetic events
        if event.getIntegerValueField(.eventSourceUserData) == kVietGoEventMarker {
            return Unmanaged.passUnretained(event)
        }

        // Ensure any prior replacement injection has finished entering the session stream
        injectionSemaphore.wait()
        injectionSemaphore.signal()

        let settings = AppSettings.shared
        let shortcut = settings.toggleShortcut

        if type == .flagsChanged {
            let activeControlOrCommand = event.flags.intersection([.maskControl, .maskCommand])
            if !activeControlOrCommand.isEmpty {
                engine.reset(clearHistory: true)
            }
            if !isRecordingShortcut && shortcut.isModifierOnly {
                handleModifierOnlyShortcutFlags(event.flags, shortcut: shortcut, settings: settings)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        if pendingModifierOnlyMatch {
            keyPressedDuringModifierHold = true
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let currentModifiers = event.flags.intersection(ToggleShortcut.supportedModifierMask)

        // Check Key + Modifier toggle shortcut
        if !isRecordingShortcut && !shortcut.isModifierOnly,
           let targetKeyCode = shortcut.keyCode,
           keyCode == targetKeyCode,
           currentModifiers == shortcut.modifiers {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat {
                settings.isEnabled.toggle()
                engine.reset(clearHistory: true)
            }
            return nil
        }

        // Trigger async focused-app refresh on Spotlight/Raycast shortcuts (Cmd/Opt+Space) or browser address-bar shortcuts (Cmd+L/T/K/F)
        if (keyCode == 49 && (currentModifiers.contains(.maskCommand) || currentModifiers.contains(.maskAlternate))) ||
            (currentModifiers.contains(.maskCommand) && (keyCode == 37 || keyCode == 17 || keyCode == 40 || keyCode == 3)) {
            scheduleDelayedFocusRefresh(after: 0.08)
        }

        // Bypass if disabled, incompatible Input Source, Secure Input, or design-app non-text canvas
        if !settings.isEnabled ||
            isIncompatibleInputSource ||
            cachedIsCanvasNonTextInDesignApp ||
            IsSecureEventInputEnabled() {
            engine.reset(clearHistory: true)
            return Unmanaged.passUnretained(event)
        }

        // Bypass command/control/option key combinations
        if currentModifiers.contains(.maskCommand) ||
            currentModifiers.contains(.maskControl) ||
            currentModifiers.contains(.maskAlternate) {
            engine.reset(clearHistory: true)
            return Unmanaged.passUnretained(event)
        }

        // Pass through key-repeat events cleanly except Backspace (51), which must stay synced with engine buffer
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 && keyCode != 51 {
            engine.reset(clearHistory: true)
            return Unmanaged.passUnretained(event)
        }

        // Handle Backspace (supports post-Space recovery & tone re-placement on coda deletion)
        if keyCode == 51 {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let targetBundle = activeTargetBundleID
            let decomposeAcuteY = requiresDecomposedAcuteY(targetBundle)
            let previousLast = decomposeAcuteY ? engine.lastDisplayedCharacter : nil
            let previousDisplayed = decomposeAcuteY ? Array(engine.currentWord) : nil

            switch engine.handleBackspace(allowToneReposition: !isRepeat) {
            case .passThrough:
                if decomposeAcuteY, let previousLast, isNonMacRomanLatin1Vowel(previousLast) {
                    injectReplacement(backspaceCount: 2, text: "", useAutocompleteFix: false, proxy: proxy)
                    return nil
                }
                return Unmanaged.passUnretained(event)
            case .replace(let backspaceCount, let text):
                let extraBS = decomposeAcuteY
                    ? (previousDisplayed?.suffix(backspaceCount).filter { isNonMacRomanLatin1Vowel($0) }.count ?? 0)
                    : 0
                injectReplacement(
                    backspaceCount: backspaceCount + extraBS,
                    text: text,
                    useAutocompleteFix: settings.autocompleteFix,
                    proxy: proxy
                )
                return nil
            }
        }

        // Reset on navigation or control keys
        if navigationKeyCodes.contains(keyCode) {
            engine.reset(clearHistory: true)
            return Unmanaged.passUnretained(event)
        }

        // Extract Unicode scalar(s) from the event
        var actualLength = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(
            maxStringLength: 4,
            actualStringLength: &actualLength,
            unicodeString: &buffer
        )

        guard actualLength == 1, let scalar = UnicodeScalar(buffer[0]) else {
            engine.reset(clearHistory: true)
            return Unmanaged.passUnretained(event)
        }

        let scalarValue = scalar.value
        if (scalarValue < 0x20 && scalarValue != 0x09 && scalarValue != 0x0A && scalarValue != 0x0D) ||
            scalarValue == 0x7F ||
            (scalarValue >= 0xF700 && scalarValue <= 0xF8FF) {
            engine.reset(clearHistory: true)
            return Unmanaged.passUnretained(event)
        }

        let char = Character(scalar)
        let decomposeAcuteY = requiresDecomposedAcuteY(activeTargetBundleID)
        let previousDisplayed = decomposeAcuteY ? Array(engine.currentWord) : nil

        switch engine.processKey(char) {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .replace(let backspaceCount, let text):
            let extraBS = decomposeAcuteY
                ? (previousDisplayed?.suffix(backspaceCount).filter { isNonMacRomanLatin1Vowel($0) }.count ?? 0)
                : 0
            injectReplacement(
                backspaceCount: backspaceCount + extraBS,
                text: text,
                useAutocompleteFix: settings.autocompleteFix,
                proxy: proxy
            )
            return nil
        }
    }

    private func handleModifierOnlyShortcutFlags(
        _ flags: CGEventFlags,
        shortcut: ToggleShortcut,
        settings: AppSettings
    ) {
        let active = flags.intersection(ToggleShortcut.supportedModifierMask)
        let target = shortcut.modifiers
        guard !target.isEmpty else { return }

        if active == target {
            pendingModifierOnlyMatch = true
            modifierMatchStartedAt = Date()
            keyPressedDuringModifierHold = false
            return
        }

        guard pendingModifierOnlyMatch else { return }

        // Trigger only when ALL modifiers are released cleanly without pressing any other key
        // and within 1.5s hold threshold (supports sequential lift of 2-modifier shortcuts like ⌘⇧).
        if active.isEmpty {
            let withinHoldLimit = modifierMatchStartedAt.map {
                let elapsed = Date().timeIntervalSince($0)
                return elapsed >= 0.025 && elapsed < 1.5
            } ?? false
            if !keyPressedDuringModifierHold && withinHoldLimit {
                settings.isEnabled.toggle()
                engine.reset(clearHistory: true)
            }
            pendingModifierOnlyMatch = false
            modifierMatchStartedAt = nil
            keyPressedDuringModifierHold = false
            return
        }

        // Only cancel if an unrelated modifier not in `target` was pressed
        if !target.isSuperset(of: active) {
            pendingModifierOnlyMatch = false
            modifierMatchStartedAt = nil
            keyPressedDuringModifierHold = false
        }
    }

    private var activeTargetBundleID: String {
        if let override = debugOverrideTargetBundleID, !override.isEmpty {
            return override
        }
        if !cachedFocusedBundleID.isEmpty {
            return cachedFocusedBundleID
        }
        if !frontmostBundleID.isEmpty {
            return frontmostBundleID
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }

    private func isTerminalOrPTYApp(_ bundleID: String) -> Bool {
        if terminalAndPTYBundleIDs.contains(bundleID) {
            return true
        }
        return bundleID.hasPrefix("com.jetbrains.")
    }

    private func requiresDecomposedAcuteY(_ bundleID: String) -> Bool {
        bundleID == "com.microsoft.Word" ||
            bundleID == "com.microsoft.Powerpoint" ||
            bundleID == "com.microsoft.Outlook"
    }

    private func isNonMacRomanLatin1Vowel(_ ch: Character) -> Bool {
        ch == "\u{00FD}" || ch == "\u{00DD}"
    }

    private func injectReplacement(
        backspaceCount: Int,
        text: String,
        useAutocompleteFix: Bool,
        proxy: CGEventTapProxy?
    ) {
        injectionSemaphore.wait()
        defer { injectionSemaphore.signal() }

        guard let source = privateEventSource ?? CGEventSource(stateID: .privateState) else { return }

        let targetBundle = activeTargetBundleID
        let isBrowser = browserBundleIDs.contains(targetBundle)
        let isSafari = (targetBundle == "com.apple.Safari" || targetBundle == "com.apple.SafariTechnologyPreview")
        let isMicrosoftOffice = microsoftOfficeBundleIDs.contains(targetBundle)
        let decomposeAcuteY = requiresDecomposedAcuteY(targetBundle)
        let applyAutocompleteFix = useAutocompleteFix &&
            backspaceCount > 0 &&
            (alwaysAutocompleteBundleIDs.contains(targetBundle) || (isBrowser && !cachedIsExplicitWebTextArea))
        let applyTerminalPacing = isTerminalOrPTYApp(targetBundle)
        let sendCharByChar = isSafari && !applyAutocompleteFix

        let backspaceStepDelay: UInt32 = (applyTerminalPacing || isMicrosoftOffice) ? 2000 : 1000
        let afterBackspaceWait: UInt32 = isMicrosoftOffice
            ? 5000
            : (applyTerminalPacing ? 4000 : (applyAutocompleteFix ? 2500 : 1500))
        let chunkStepDelay: UInt32 = (applyTerminalPacing || isMicrosoftOffice) ? 2000 : 1500
        let settleDelay: UInt32 = (applyTerminalPacing || isMicrosoftOffice) ? 3000 : 1000

        if applyAutocompleteFix {
            // Use U+0259 (Latin Small Letter Schwa, lowercaseLetter) rather than whitespace (U+202F, which triggers
            // macOS Inline Predictive Text acceptance such as `dep` -> `department`) or zero-width Format chars
            // (U+2060, which WebKit can swallow without inserting a deletable code unit), while still dismissing
            // browser omnibox inline autocomplete selections.
            postUnicodeChunk([0x0259], source: source, proxy: proxy)
            usleep(1000)
            postBackspaces(count: backspaceCount + 1, source: source, delayMicros: backspaceStepDelay, proxy: proxy)
            usleep(afterBackspaceWait)
        } else if backspaceCount > 0 {
            postBackspaces(count: backspaceCount, source: source, delayMicros: backspaceStepDelay, proxy: proxy)
            usleep(afterBackspaceWait)
        }

        if !text.isEmpty {
            postUnicodeText(
                text,
                source: source,
                decomposeAcuteY: decomposeAcuteY,
                chunkSize: sendCharByChar ? 1 : 20,
                chunkDelayMicros: chunkStepDelay,
                proxy: proxy
            )
        }
        usleep(settleDelay)
    }

    private func postSyntheticEvent(_ event: CGEvent, proxy: CGEventTapProxy?) {
        // Strip modifier bits while preserving system flags (e.g. NX_NONCOALESCEDMASK / 0x20000000)
        event.flags.subtract(Self.strippedModifierFlags)
        event.setIntegerValueField(.eventSourceUserData, value: kVietGoEventMarker)
        if let proxy {
            event.tapPostEvent(proxy)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func postBackspaces(count: Int, source: CGEventSource, delayMicros: UInt32, proxy: CGEventTapProxy?) {
        guard count > 0 else { return }
        for index in 0..<count {
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true) {
                postSyntheticEvent(down, proxy: proxy)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) {
                postSyntheticEvent(up, proxy: proxy)
            }
            if delayMicros > 0 && index + 1 < count {
                usleep(delayMicros)
            }
        }
    }

    private func postUnicodeText(
        _ text: String,
        source: CGEventSource,
        decomposeAcuteY: Bool,
        chunkSize: Int,
        chunkDelayMicros: UInt32,
        proxy: CGEventTapProxy?
    ) {
        let maxChunkUTF16 = max(1, chunkSize)
        var currentChunk: [UniChar] = []
        currentChunk.reserveCapacity(maxChunkUTF16)
        var didPostSegment = false

        func paceIfNeeded() {
            if didPostSegment && chunkDelayMicros > 0 {
                usleep(chunkDelayMicros)
            }
        }

        func flushChunk() {
            guard !currentChunk.isEmpty else { return }
            paceIfNeeded()
            postUnicodeChunk(currentChunk, source: source, proxy: proxy)
            didPostSegment = true
            currentChunk.removeAll(keepingCapacity: true)
        }

        for char in text {
            if char == "\n" || char == "\r" {
                flushChunk()
                paceIfNeeded()
                postSpecialKey(36, source: source, proxy: proxy)
                didPostSegment = true
                continue
            }
            if char == "\t" {
                flushChunk()
                paceIfNeeded()
                postSpecialKey(48, source: source, proxy: proxy)
                didPostSegment = true
                continue
            }

            let normalized = (decomposeAcuteY && isNonMacRomanLatin1Vowel(char))
                ? String(char).decomposedStringWithCanonicalMapping
                : String(char).precomposedStringWithCanonicalMapping
            let charUTF16 = Array(normalized.utf16)
            guard !charUTF16.isEmpty else { continue }

            if !currentChunk.isEmpty && currentChunk.count + charUTF16.count > maxChunkUTF16 {
                flushChunk()
            }
            currentChunk.append(contentsOf: charUTF16)
        }

        flushChunk()
    }

    private func postUnicodeChunk(_ utf16: [UniChar], source: CGEventSource, proxy: CGEventTapProxy?) {
        guard !utf16.isEmpty else { return }
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            postSyntheticEvent(down, proxy: proxy)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            postSyntheticEvent(up, proxy: proxy)
        }
    }

    private func postSpecialKey(_ keyCode: CGKeyCode, source: CGEventSource, proxy: CGEventTapProxy?) {
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            postSyntheticEvent(down, proxy: proxy)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            postSyntheticEvent(up, proxy: proxy)
        }
    }
}
