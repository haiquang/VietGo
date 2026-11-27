import Foundation

public enum InputMethod: String, CaseIterable, Codable, Sendable {
    case telex
    case vni

    public var displayName: String {
        switch self {
        case .telex:
            return "Telex"
        case .vni:
            return "VNI"
        }
    }
}

public enum ToneStyle: String, CaseIterable, Codable, Sendable {
    /// Đặt dấu mới: hòa, khỏe, thủy, tùy (oa, oe, uy không âm cuối -> dấu ở nguyên âm đầu)
    case modern
    /// Đặt dấu cũ: hoà, khoẻ, thuỷ, tuỳ (oa, oe, uy không âm cuối -> dấu ở nguyên âm sau)
    case traditional

    public var displayName: String {
        switch self {
        case .modern:
            return "Dấu mới (hòa, khỏe, thủy)"
        case .traditional:
            return "Dấu cũ (hoà, khoẻ, thuỷ)"
        }
    }
}

public enum Tone: Int, CaseIterable, Sendable {
    case none = 0
    case acute = 1  // Sắc
    case grave = 2  // Huyền
    case hook = 3   // Hỏi
    case tilde = 4  // Ngã
    case dot = 5    // Nặng
}

public enum VowelShape: Equatable, Sendable {
    case none
    case circumflex // â, ê, ô
    case breve      // ă
    case horn       // ơ, ư
}

public struct EngineConfig: Equatable, Codable, Sendable {
    public var inputMethod: InputMethod
    public var toneStyle: ToneStyle
    public var autoRestoreEnglish: Bool
    public var standaloneW: Bool
    public var bracketShortcuts: Bool

    public init(
        inputMethod: InputMethod = .telex,
        toneStyle: ToneStyle = .modern,
        autoRestoreEnglish: Bool = true,
        standaloneW: Bool = true,
        bracketShortcuts: Bool = false
    ) {
        self.inputMethod = inputMethod
        self.toneStyle = toneStyle
        self.autoRestoreEnglish = autoRestoreEnglish
        self.standaloneW = standaloneW
        self.bracketShortcuts = bracketShortcuts
    }
}

public enum EngineAction: Equatable, Sendable {
    case passThrough
    case replace(backspaceCount: Int, text: String)
}
