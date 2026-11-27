import AppKit
import SwiftUI
import VietGoEngine

struct VGSurfaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct VGSettingRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let badgeText: String?
    let systemImage: String?
    let onRowTap: (() -> Void)?
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        badgeText: String? = nil,
        systemImage: String? = nil,
        onRowTap: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badgeText = badgeText
        self.systemImage = systemImage
        self.onRowTap = onRowTap
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if let onRowTap {
                labelArea
                    .padding(.leading, 14)
                    .padding(.trailing, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onRowTap)
            } else {
                labelArea
                    .padding(.leading, 14)
                    .padding(.trailing, 14)
                    .padding(.vertical, 11)
            }

            trailing
                .padding(.trailing, 14)
                .padding(.vertical, 11)
        }
    }

    private var labelArea: some View {
        HStack(alignment: .center, spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    if let badgeText {
                        Text(badgeText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VGKeycap: View {
    let label: String
    var compact: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, compact ? 5.5 : 7.5)
            .frame(minWidth: compact ? 20 : 25, minHeight: compact ? 19 : 23)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.08), radius: 0.5, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1.5)
                    .padding(.horizontal, 1)
            }
    }
}

struct VGKeycapGroup: View {
    let shortcut: ToggleShortcut
    var compact: Bool = false

    private var parts: [String] {
        shortcut.displayString.split(separator: " ").map(String.init)
    }

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                VGKeycap(label: part, compact: compact)
            }
        }
    }
}

struct VGMethodOptionCard: View {
    let method: InputMethod
    let subtitle: String
    let example: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(method.displayName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.22), lineWidth: 1.5)
                            .frame(width: 17, height: 17)
                        if isSelected {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 17, height: 17)
                            Image(systemName: "checkmark")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }

                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Text(example)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.055))
                    )
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .buttonStyle(.plain)
    }
}
