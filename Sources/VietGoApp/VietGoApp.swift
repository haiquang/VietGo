import AppKit
import SwiftUI
import VietGoEngine

@main
struct VietGoMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    private let settings = AppSettings.shared
    private let tapManager = EventTapManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        settings.onSettingsChanged = { [weak self] in
            guard let self else { return }
            self.tapManager.updateEngineConfig(self.settings.engineConfig)
            self.updateStatusItemAppearance()
            self.rebuildMenu()
        }
        tapManager.onAccessibilityChanged = { [weak self] in
            self?.rebuildMenu()
        }

        tapManager.start()
        updateStatusItemAppearance()
        rebuildMenu()

        if !tapManager.isAccessibilityGranted {
            openSettingsWindow()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            SyllableComposer.warmUpSpellChecker()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tapManager.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemAppearance()
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.image = makeStatusBarIcon(isVietnamese: settings.isEnabled)
        button.imagePosition = .imageOnly
        button.toolTip = settings.isEnabled
            ? "VietGo — Tiếng Việt (\(settings.inputMethod.displayName))"
            : "VietGo — Tiếng Anh"
    }

    private func makeStatusBarIcon(isVietnamese: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let cgContext = NSGraphicsContext.current?.cgContext else { return false }

            if isVietnamese {
                let pillRect = rect.insetBy(dx: 1, dy: 1)
                let path = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)
                NSColor.black.setFill()
                path.fill()

                let glyph = "V" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10.5, weight: .bold),
                    .foregroundColor: NSColor.black
                ]
                let textSize = glyph.size(withAttributes: attrs)
                let textOrigin = NSPoint(
                    x: (rect.width - textSize.width) * 0.5,
                    y: (rect.height - textSize.height) * 0.5
                )

                cgContext.saveGState()
                cgContext.setBlendMode(.destinationOut)
                glyph.draw(at: textOrigin, withAttributes: attrs)
                cgContext.restoreGState()
            } else {
                let pillRect = rect.insetBy(dx: 1.5, dy: 1.5)
                let path = NSBezierPath(roundedRect: pillRect, xRadius: 3.5, yRadius: 3.5)
                path.lineWidth = 1.35
                NSColor.black.setStroke()
                path.stroke()

                let glyph = "E" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor.black
                ]
                let textSize = glyph.size(withAttributes: attrs)
                let textOrigin = NSPoint(
                    x: (rect.width - textSize.width) * 0.5,
                    y: (rect.height - textSize.height) * 0.5
                )
                glyph.draw(at: textOrigin, withAttributes: attrs)
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggleTitle = settings.isEnabled
            ? "Chế độ Tiếng Việt (V) — Đang bật"
            : "Chế độ Tiếng Anh (E) — Nhấn để bật Việt"
        let toggleItem = NSMenuItem(
            title: "\(toggleTitle)   [\(settings.toggleShortcut.displayString)]",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Input method items
        let methodHeader = NSMenuItem(title: "Kiểu gõ", action: nil, keyEquivalent: "")
        methodHeader.isEnabled = false
        menu.addItem(methodHeader)

        for method in InputMethod.allCases {
            let item = NSMenuItem(
                title: method.displayName,
                action: #selector(selectInputMethod(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = method.rawValue
            item.state = (settings.inputMethod == method) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Tone style items
        let toneHeader = NSMenuItem(title: "Quy tắc đặt dấu", action: nil, keyEquivalent: "")
        toneHeader.isEnabled = false
        menu.addItem(toneHeader)

        for style in ToneStyle.allCases {
            let item = NSMenuItem(
                title: style.displayName,
                action: #selector(selectToneStyle(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = style.rawValue
            item.state = (settings.toneStyle == style) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        if !tapManager.isAccessibilityGranted {
            let axItem = NSMenuItem(
                title: "⚠ Cấp quyền Trợ năng (Accessibility)…",
                action: #selector(requestAccessibility),
                keyEquivalent: ""
            )
            axItem.target = self
            menu.addItem(axItem)
        }

        let settingsItem = NSMenuItem(
            title: "Mở Cài đặt & Gõ thử…",
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionItem = NSMenuItem(title: "VietGo v\(appVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quitItem = NSMenuItem(
            title: "Thoát VietGo",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        tapManager.resetEngine()
    }

    @objc private func selectInputMethod(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let method = InputMethod(rawValue: raw) else { return }
        settings.inputMethod = method
        tapManager.resetEngine()
    }

    @objc private func selectToneStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = ToneStyle(rawValue: raw) else { return }
        settings.toneStyle = style
        tapManager.resetEngine()
    }

    @objc private func requestAccessibility() {
        tapManager.promptAccessibility()
    }

    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            let rootView = SettingsView(settings: settings, tapManager: tapManager)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "VietGo — Bộ gõ Tiếng Việt"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 620, height: 520))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
