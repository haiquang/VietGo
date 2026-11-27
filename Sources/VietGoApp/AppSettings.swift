import Carbon
import Combine
import Foundation
import ServiceManagement
import VietGoEngine

public struct ToggleShortcut: Codable, Equatable, Sendable {
    public var keyCode: Int64?
    public var modifiersRaw: UInt64
    public var isModifierOnly: Bool

    public static let supportedModifierMask: CGEventFlags = [
        .maskControl,
        .maskAlternate,
        .maskShift,
        .maskCommand,
        .maskSecondaryFn
    ]

    public init(keyCode: Int64?, modifiers: CGEventFlags, isModifierOnly: Bool) {
        self.keyCode = keyCode
        self.modifiersRaw = modifiers.intersection(Self.supportedModifierMask).rawValue
        self.isModifierOnly = isModifierOnly
    }

    public var modifiers: CGEventFlags {
        CGEventFlags(rawValue: modifiersRaw)
    }

    public static let controlSpace = ToggleShortcut(
        keyCode: 49,
        modifiers: .maskControl,
        isModifierOnly: false
    )

    public static let optionZ = ToggleShortcut(
        keyCode: 6,
        modifiers: .maskAlternate,
        isModifierOnly: false
    )

    public static let commandShift = ToggleShortcut(
        keyCode: nil,
        modifiers: [.maskCommand, .maskShift],
        isModifierOnly: true
    )

    public static let controlShift = ToggleShortcut(
        keyCode: nil,
        modifiers: [.maskControl, .maskShift],
        isModifierOnly: true
    )

    public static let fnKey = ToggleShortcut(
        keyCode: nil,
        modifiers: .maskSecondaryFn,
        isModifierOnly: true
    )

    public var displayString: String {
        var parts: [String] = []
        let flags = modifiers
        if flags.contains(.maskSecondaryFn) { parts.append("Fn") }
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }

        if !isModifierOnly, let keyCode {
            parts.append(Self.keyName(for: keyCode))
        }
        return parts.joined(separator: " ")
    }

    private static func keyName(for keyCode: Int64) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Esc"
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1: return "S"
        case 17: return "T"
        case 32: return "U"
        case 9: return "V"
        case 13: return "W"
        case 7: return "X"
        case 16: return "Y"
        case 6: return "Z"
        default: return "Key(\(keyCode))"
        }
    }
}

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private enum Keys {
        static let isEnabled = "VietGo.isEnabled"
        static let inputMethod = "VietGo.inputMethod"
        static let toneStyle = "VietGo.toneStyle"
        static let autoRestoreEnglish = "VietGo.autoRestoreEnglish"
        static let autocompleteFix = "VietGo.autocompleteFix"
        static let standaloneW = "VietGo.standaloneW"
        static let bracketShortcuts = "VietGo.bracketShortcuts"
        static let launchAtLogin = "VietGo.launchAtLogin"
        static let toggleShortcut = "VietGo.toggleShortcut"
    }

    private let defaults = UserDefaults.standard

    @Published public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            onSettingsChanged?()
        }
    }

    @Published public var inputMethod: InputMethod {
        didSet {
            defaults.set(inputMethod.rawValue, forKey: Keys.inputMethod)
            onSettingsChanged?()
        }
    }

    @Published public var toneStyle: ToneStyle {
        didSet {
            defaults.set(toneStyle.rawValue, forKey: Keys.toneStyle)
            onSettingsChanged?()
        }
    }

    @Published public var autoRestoreEnglish: Bool {
        didSet {
            defaults.set(autoRestoreEnglish, forKey: Keys.autoRestoreEnglish)
            onSettingsChanged?()
        }
    }

    @Published public var autocompleteFix: Bool {
        didSet {
            defaults.set(autocompleteFix, forKey: Keys.autocompleteFix)
            onSettingsChanged?()
        }
    }

    @Published public var standaloneW: Bool {
        didSet {
            defaults.set(standaloneW, forKey: Keys.standaloneW)
            onSettingsChanged?()
        }
    }

    @Published public var bracketShortcuts: Bool {
        didSet {
            defaults.set(bracketShortcuts, forKey: Keys.bracketShortcuts)
            onSettingsChanged?()
        }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    @Published public var toggleShortcut: ToggleShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(toggleShortcut) {
                defaults.set(data, forKey: Keys.toggleShortcut)
            }
            onSettingsChanged?()
        }
    }

    public var onSettingsChanged: (() -> Void)?

    public var engineConfig: EngineConfig {
        EngineConfig(
            inputMethod: inputMethod,
            toneStyle: toneStyle,
            autoRestoreEnglish: autoRestoreEnglish,
            standaloneW: standaloneW,
            bracketShortcuts: bracketShortcuts
        )
    }

    private init() {
        self.isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true

        if let rawMethod = defaults.string(forKey: Keys.inputMethod),
           let parsedMethod = InputMethod(rawValue: rawMethod) {
            self.inputMethod = parsedMethod
        } else {
            self.inputMethod = .telex
        }

        if let rawTone = defaults.string(forKey: Keys.toneStyle),
           let parsedTone = ToneStyle(rawValue: rawTone) {
            self.toneStyle = parsedTone
        } else {
            self.toneStyle = .modern
        }

        self.autoRestoreEnglish = defaults.object(forKey: Keys.autoRestoreEnglish) as? Bool ?? true
        self.autocompleteFix = defaults.object(forKey: Keys.autocompleteFix) as? Bool ?? true
        self.standaloneW = defaults.object(forKey: Keys.standaloneW) as? Bool ?? true
        self.bracketShortcuts = defaults.object(forKey: Keys.bracketShortcuts) as? Bool ?? false

        if Bundle.main.bundlePath.hasSuffix(".app") {
            self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } else {
            self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        }

        if let data = defaults.data(forKey: Keys.toggleShortcut),
           let decoded = try? JSONDecoder().decode(ToggleShortcut.self, from: data) {
            self.toggleShortcut = decoded
        } else {
            self.toggleShortcut = .controlSpace
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently ignore when running unsigned or outside .app bundle
        }
    }
}
