import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var shortcut: ToggleShortcut
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var recordedModifierPeak: CGEventFlags = []
    @State private var keyPressedDuringRecord = false

    private let presets: [(String, ToggleShortcut)] = [
        ("⌃ Space", .controlSpace),
        ("⌥ Z", .optionZ),
        ("⌘ ⇧", .commandShift),
        ("⌃ ⇧", .controlShift),
        ("Fn", .fnKey)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Phím tắt chuyển Việt / Anh")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Text("Mặc định ⌃ Space. Nếu trùng phím tắt Input Source của macOS, hãy tắt trong System Settings → Keyboard.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if !isRecording {
                        VGKeycapGroup(shortcut: shortcut)
                    }

                    Button {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isRecording {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 7, height: 7)
                                Text("Nhấn tổ hợp phím… (Esc hủy)")
                                    .font(.system(size: 12, weight: .medium))
                            } else {
                                Text("Đổi phím tắt…")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isRecording ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.055))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .buttonStyle(.plain)

                    if shortcut != .controlSpace && !isRecording {
                        Button("Mặc định") {
                            stopRecording()
                            shortcut = .controlSpace
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Text("Mẫu nhanh:")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(presets, id: \.0) { label, preset in
                        let selected = (shortcut == preset)
                        Button {
                            stopRecording()
                            shortcut = preset
                        } label: {
                            Text(label)
                                .font(.system(size: 11, weight: selected ? .semibold : .medium, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .foregroundStyle(selected ? .white : .primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(selected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        recordedModifierPeak = []
        keyPressedDuringRecord = false
        EventTapManager.shared.isRecordingShortcut = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                keyPressedDuringRecord = true
                if event.keyCode == 53 { // Escape cancels
                    stopRecording()
                    return nil
                }

                let flags = cgModifiers(from: event.modifierFlags)
                guard !flags.isEmpty else {
                    return nil
                }

                shortcut = ToggleShortcut(
                    keyCode: Int64(event.keyCode),
                    modifiers: flags,
                    isModifierOnly: false
                )
                stopRecording()
                return nil
            }

            if event.type == .flagsChanged {
                let flags = cgModifiers(from: event.modifierFlags)
                if !flags.isEmpty {
                    recordedModifierPeak.formUnion(flags)
                } else if !keyPressedDuringRecord {
                    // Record modifier-only shortcut when 2+ modifiers or Fn were pressed and released
                    let count = modifierCount(recordedModifierPeak)
                    if count >= 2 || recordedModifierPeak == .maskSecondaryFn {
                        shortcut = ToggleShortcut(
                            keyCode: nil,
                            modifiers: recordedModifierPeak,
                            isModifierOnly: true
                        )
                        stopRecording()
                        return nil
                    }
                    recordedModifierPeak = []
                }
            }

            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        recordedModifierPeak = []
        keyPressedDuringRecord = false
        EventTapManager.shared.isRecordingShortcut = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func modifierCount(_ flags: CGEventFlags) -> Int {
        var count = 0
        if flags.contains(.maskControl) { count += 1 }
        if flags.contains(.maskAlternate) { count += 1 }
        if flags.contains(.maskShift) { count += 1 }
        if flags.contains(.maskCommand) { count += 1 }
        if flags.contains(.maskSecondaryFn) { count += 1 }
        return count
    }

    private func cgModifiers(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.function) { result.insert(.maskSecondaryFn) }
        return result
    }
}
