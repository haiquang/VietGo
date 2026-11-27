import SwiftUI
import VietGoEngine

struct SettingsView: View {
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case input
        case smart
        case shortcuts
        case sandbox

        var id: String { rawValue }

        var title: String {
            switch self {
            case .input: return "Bộ gõ"
            case .smart: return "Thông minh"
            case .shortcuts: return "Phím tắt"
            case .sandbox: return "Gõ thử"
            }
        }

        var symbol: String {
            switch self {
            case .input: return "keyboard"
            case .smart: return "wand.and.stars"
            case .shortcuts: return "command"
            case .sandbox: return "character.cursor.ibeam"
            }
        }
    }

    private let quickSamples: [(raw: String, expected: String, text: String)] = [
        ("tieengs vieetj", "tiếng việt", "tiếng việt "),
        ("truongwf hocj", "trường học", "trường học "),
        ("hoaf", "hòa", "hòa "),
        ("URRL", "URL", "URL "),
        ("dessign", "design", "design "),
        ("ys", "ý", "ý ")
    ]

    private let restoredTokens = ["window", "URL", "design", "refresh", "string", "password"]

    @ObservedObject var settings: AppSettings
    @ObservedObject var tapManager: EventTapManager

    @State private var selectedTab: SettingsTab = .input
    @State private var playgroundText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if !tapManager.isAccessibilityGranted {
                accessibilityBanner
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }

            tabBar
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedTab {
                    case .input:
                        inputTabContent
                    case .smart:
                        smartTabContent
                    case .shortcuts:
                        shortcutsTabContent
                    case .sandbox:
                        sandboxTabContent
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 620, height: 520)
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Button {
                settings.isEnabled.toggle()
                tapManager.resetEngine()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(settings.isEnabled ? Color.accentColor : Color.primary.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Text(settings.isEnabled ? "V" : "E")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(settings.isEnabled ? .white : .secondary)
                }
                .animation(.spring(response: 0.24, dampingFraction: 0.82), value: settings.isEnabled)
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(settings.isEnabled ? "Tiếng Việt đang bật" : "Đang ở chế độ Tiếng Anh")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text("\(settings.inputMethod.displayName) • \(settings.toneStyle == .modern ? "Dấu mới" : "Dấu cũ")")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)

                    VGKeycapGroup(shortcut: settings.toggleShortcut, compact: true)
                }
            }

            Spacer(minLength: 8)

            Button {
                selectedTab = .shortcuts
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: tapManager.isAccessibilityGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text(tapManager.isAccessibilityGranted ? "Đã cấp quyền" : "Cần cấp quyền")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(tapManager.isAccessibilityGranted ? Color.green : Color.orange)
                .background(
                    Capsule(style: .continuous)
                        .fill((tapManager.isAccessibilityGranted ? Color.green : Color.orange).opacity(0.13))
                )
                .contentShape(Capsule(style: .continuous))
            }
            .contentShape(Capsule(style: .continuous))
            .buttonStyle(.plain)

            Toggle("", isOn: $settings.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private var accessibilityBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cần cấp quyền Trợ năng (Accessibility)")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Bật VietGo trong Privacy & Security để nhận phím và bỏ dấu không gạch chân. Nếu macOS hiện hộp thoại \"Device Control and Data Access\", hãy bấm \"Open System Settings\" ngay trên hộp thoại đó.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Button("Làm mới quyền") {
                        tapManager.resetAndPromptAccessibility()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Mở Cài đặt") {
                        tapManager.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Cấp quyền") {
                        tapManager.promptAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                let active = (selectedTab == tab)
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(active ? .primary : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(active ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                            .shadow(color: active ? Color.black.opacity(0.08) : .clear, radius: 1.5, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(active ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 0.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }

    private var inputTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VGMethodOptionCard(
                    method: .telex,
                    subtitle: "Bỏ dấu bằng phím chữ cái (s, f, r, x, j, w).",
                    example: "tieengs vieetj → tiếng việt",
                    isSelected: settings.inputMethod == .telex
                ) {
                    settings.inputMethod = .telex
                }

                VGMethodOptionCard(
                    method: .vni,
                    subtitle: "Bỏ dấu bằng phím số (1–5 thanh, 6–8 mũ/râu).",
                    example: "tie61ng vie65t → tiếng việt",
                    isSelected: settings.inputMethod == .vni
                ) {
                    settings.inputMethod = .vni
                }
            }

            VGSurfaceCard {
                VGSettingRow(
                    title: "Quy tắc đặt dấu",
                    subtitle: "Áp dụng cho các vần oa, oe, uy không có âm cuối."
                ) {
                    Picker("", selection: $settings.toneStyle) {
                        ForEach(ToneStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 225)
                }

                Divider()
                    .padding(.leading, 14)

                VGSettingRow(
                    title: "Gõ w đơn thành ư",
                    subtitle: "Nhấn w ngay sau phụ âm đầu (nhw → như, wf → ừ).",
                    badgeText: settings.inputMethod == .telex ? nil : "Chỉ Telex",
                    onRowTap: {
                        if settings.inputMethod == .telex {
                            settings.standaloneW.toggle()
                        }
                    }
                ) {
                    Toggle("", isOn: $settings.standaloneW)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .opacity(settings.inputMethod == .telex ? 1 : 0.45)
                .disabled(settings.inputMethod != .telex)

                Divider()
                    .padding(.leading, 14)

                VGSettingRow(
                    title: "Gõ tắt [ → ơ, ] → ư trong Telex",
                    subtitle: "Nhập nhanh nguyên âm ơ và ư bằng phím ngoặc vuông.",
                    badgeText: settings.inputMethod == .telex ? nil : "Chỉ Telex",
                    onRowTap: {
                        if settings.inputMethod == .telex {
                            settings.bracketShortcuts.toggle()
                        }
                    }
                ) {
                    Toggle("", isOn: $settings.bracketShortcuts)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .opacity(settings.inputMethod == .telex ? 1 : 0.45)
                .disabled(settings.inputMethod != .telex)
            }
        }
    }

    private var smartTabContent: some View {
        VGSurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                VGSettingRow(
                    title: "Tự động khôi phục từ tiếng Anh & code",
                    subtitle: "Tự trả về nguyên bản khi chuỗi phím không khớp âm tiết Việt hoặc khớp từ vựng tiếng Anh hợp lệ.",
                    systemImage: "text.badge.checkmark",
                    onRowTap: {
                        settings.autoRestoreEnglish.toggle()
                    }
                ) {
                    Toggle("", isOn: $settings.autoRestoreEnglish)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack(spacing: 6) {
                    ForEach(restoredTokens, id: \.self) { token in
                        Text(token)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(0.055))
                            )
                    }
                    Spacer()
                }
                .padding(.leading, 52)
                .padding(.trailing, 14)
                .padding(.bottom, 12)

                Divider()
                    .padding(.leading, 14)

                VGSettingRow(
                    title: "Chống lỗi lặp / nuốt chữ trên trình duyệt & Launcher",
                    subtitle: "Tương thích inline autocomplete trên Chrome, Safari, Arc, Dia, Comet, ChatGPT Atlas, Spotlight, Raycast và Microsoft Office.",
                    systemImage: "sparkles.rectangle.stack",
                    onRowTap: {
                        settings.autocompleteFix.toggle()
                    }
                ) {
                    Toggle("", isOn: $settings.autocompleteFix)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var shortcutsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VGSurfaceCard {
                ShortcutRecorderView(shortcut: $settings.toggleShortcut)
            }

            VGSurfaceCard {
                VGSettingRow(
                    title: "Khởi động cùng macOS",
                    subtitle: "Tự mở VietGo ẩn trên thanh menu ngay khi đăng nhập.",
                    systemImage: "power",
                    onRowTap: {
                        settings.launchAtLogin.toggle()
                    }
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()
                    .padding(.leading, 14)

                VGSettingRow(
                    title: "Quyền Trợ năng (Accessibility)",
                    subtitle: tapManager.isAccessibilityGranted
                        ? "Đã cấp quyền — Bộ gõ đang hoạt động ổn định."
                        : "Chưa cấp quyền — Bấm Làm mới quyền rồi bật lại VietGo trong System Settings.",
                    systemImage: "hand.raised"
                ) {
                    HStack(spacing: 6) {
                        Button("Làm mới quyền") {
                            tapManager.resetAndPromptAccessibility()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Mở Cài đặt") {
                            tapManager.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var sandboxTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(settings.isEnabled ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(
                        settings.isEnabled
                            ? "Đang hoạt động: Tiếng Việt (\(settings.inputMethod.displayName))"
                            : "Đang tạm tắt — Chế độ Tiếng Anh (E)"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if !playgroundText.isEmpty {
                    Button("Xóa nội dung") {
                        playgroundText = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $playgroundText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(10)

                if playgroundText.isEmpty {
                    Text("Gõ thử tiếng Việt, từ tiếng Anh hoặc các trường hợp đặc biệt tại đây…")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )

            VGSurfaceCard {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Chạm mẫu để chèn nhanh kết quả kiểm tra")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(quickSamples, id: \.raw) { sample in
                            Button {
                                playgroundText += sample.text
                            } label: {
                                HStack(spacing: 4) {
                                    Text(sample.raw)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text("→ \(sample.expected)")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.05))
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(13)
            }
        }
    }
}
