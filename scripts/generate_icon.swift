#!/usr/bin/env swift

import AppKit
import Foundation
import SwiftUI

struct GeometricVPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let leftTop = CGPoint(x: rect.minX, y: rect.minY)
        let bottomTip = CGPoint(x: rect.midX, y: rect.maxY)
        let rightTop = CGPoint(x: rect.maxX, y: rect.minY)
        path.move(to: leftTop)
        path.addLine(to: bottomTip)
        path.addLine(to: rightTop)
        return path
    }
}

struct CircumflexPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct AcutePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

struct VietGoAppIconView: View {
    let isSmallSize: Bool

    var body: some View {
        ZStack {
            // 1. Outer Chassis (824x824 squircle inside 1024x1024 Apple HIG canvas)
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x252834),
                            Color(hex: 0x13141C),
                            Color(hex: 0x090A0F)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.36), radius: 24, x: 0, y: 14)
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 186, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0.06),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2.5
                        )
                )

            // 2. Recessed Switch Well + Warm Vermilion Under-Glow
            ZStack {
                RoundedRectangle(cornerRadius: 156, style: .continuous)
                    .fill(Color(hex: 0x07080C))
                    .frame(width: 748, height: 748)
                    .overlay(
                        RoundedRectangle(cornerRadius: 156, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.85),
                                        Color.white.opacity(0.09)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 2
                            )
                    )

                // Backlight glow under the sculpted keycap
                RoundedRectangle(cornerRadius: 142, style: .continuous)
                    .fill(Color(hex: 0xFF5238).opacity(0.45))
                    .frame(width: 684, height: 684)
                    .offset(y: 16)
                    .blur(radius: 26)
            }
            .frame(width: 748, height: 748)
            .clipShape(RoundedRectangle(cornerRadius: 156, style: .continuous))

            // 3. 3D Sculpted Lacquer Keycap Skirt
            RoundedRectangle(cornerRadius: 140, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0xF14C3C), location: 0.0),
                            .init(color: Color(hex: 0xCA2129), location: 0.35),
                            .init(color: Color(hex: 0x9C121B), location: 0.78),
                            .init(color: Color(hex: 0x6F0A12), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 692, height: 692)
                .offset(y: 8)
                .shadow(color: .black.opacity(0.62), radius: 14, x: 0, y: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 140, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0xFFB5A6).opacity(0.55),
                                    Color.white.opacity(0.08),
                                    Color.black.opacity(0.45)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .offset(y: 8)
                )

            // 4. Concave Spherical Keycap Dish
            ZStack {
                RoundedRectangle(cornerRadius: 114, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(hex: 0xB31721), location: 0.0),
                                .init(color: Color(hex: 0xD72729), location: 0.52),
                                .init(color: Color(hex: 0xF34D3C), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 604, height: 572)

                // Subtle radial bowl highlight in center-lower dish
                RadialGradient(
                    colors: [
                        Color(hex: 0xFF7B63).opacity(0.24),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.68),
                    startRadius: 20,
                    endRadius: 310
                )
                .frame(width: 604, height: 572)
                .clipShape(RoundedRectangle(cornerRadius: 114, style: .continuous))

                // Inner dish bevel rim
                RoundedRectangle(cornerRadius: 114, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x62080E).opacity(0.42),
                                Color.white.opacity(0.06),
                                Color(hex: 0xFFC2B5).opacity(0.42)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: 604, height: 572)

                // 5. Tactile Homing Bar (hidden at <= 32px for crisp tiny icons)
                if !isSmallSize {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0x8F0F18).opacity(0.55),
                                    Color(hex: 0xFFAE9E).opacity(0.48)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 72, height: 8)
                        .offset(y: 222)
                }

                // 6. Hero Center Glyph: Pearl-Ivory "V" + Champagne-Gold Vietnamese Crown (ˆ + ´)
                ZStack {
                    // Champagne-Gold Circumflex (ˆ)
                    CircumflexPath()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0xFFF7CE),
                                    Color(hex: 0xFFD166),
                                    Color(hex: 0xF09E18)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(
                                lineWidth: isSmallSize ? 32 : 26,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .frame(width: 104, height: 42)
                        .offset(x: -16, y: -124)
                        .shadow(color: Color(hex: 0xFFD166).opacity(0.28), radius: 10, x: 0, y: 0)
                        .shadow(color: Color(hex: 0x4A060A).opacity(0.55), radius: 7, x: 0, y: 4)

                    // Champagne-Gold Acute Accent (´) — clear air gap from circumflex
                    AcutePath()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0xFFF9DB),
                                    Color(hex: 0xFFD166),
                                    Color(hex: 0xEE9814)
                                ],
                                startPoint: .topTrailing,
                                endPoint: .bottomLeading
                            ),
                            style: StrokeStyle(
                                lineWidth: isSmallSize ? 28 : 23,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .frame(width: 40, height: 52)
                        .offset(x: 78, y: -156)
                        .shadow(color: Color(hex: 0xFFD166).opacity(0.28), radius: 10, x: 0, y: 0)
                        .shadow(color: Color(hex: 0x4A060A).opacity(0.55), radius: 7, x: 0, y: 4)

                    // Pearl-Ivory Geometric "V"
                    GeometricVPath()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color(hex: 0xFFF7EB),
                                    Color(hex: 0xF9DEC2)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(
                                lineWidth: isSmallSize ? 52 : 44,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .frame(width: 220, height: 198)
                        .offset(y: 38)
                        .shadow(color: Color(hex: 0x450509).opacity(0.55), radius: 10, x: 0, y: 7)
                }
                .offset(y: 12)
            }
            .offset(y: -24)
        }
        .frame(width: 1024, height: 1024)
        .background(Color.clear)
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

@MainActor
func renderPNG(pixelSize: Int, to url: URL) throws {
    let view = VietGoAppIconView(isSmallSize: pixelSize <= 32)
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: 1024, height: 1024)
    renderer.scale = CGFloat(pixelSize) / 1024.0
    renderer.isOpaque = false

    guard let cgImage = renderer.cgImage else {
        throw NSError(domain: "VietGoIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render CGImage"])
    }

    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "VietGoIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try pngData.write(to: url)
}

enum GenerateIconCLI {
    @MainActor
    static func run() throws {
        let fm = FileManager.default
        let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let rootDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
        let resourcesDir = rootDir.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

        let tempIconset = fm.temporaryDirectory.appendingPathComponent("VietGo_\(UUID().uuidString).iconset", isDirectory: true)
        try fm.createDirectory(at: tempIconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempIconset) }

        let entries: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        for (filename, size) in entries {
            try renderPNG(pixelSize: size, to: tempIconset.appendingPathComponent(filename))
        }

        let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
        if fm.fileExists(atPath: icnsURL.path) {
            try fm.removeItem(at: icnsURL)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        proc.arguments = ["-c", "icns", tempIconset.path, "-o", icnsURL.path]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw NSError(domain: "VietGoIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "iconutil failed with status \(proc.terminationStatus)"])
        }

        // Export preview PNGs if requested via --preview-dir
        if let previewIdx = CommandLine.arguments.firstIndex(of: "--preview-dir"),
           previewIdx + 1 < CommandLine.arguments.count {
            let previewDir = URL(fileURLWithPath: CommandLine.arguments[previewIdx + 1], isDirectory: true)
            try fm.createDirectory(at: previewDir, withIntermediateDirectories: true)
            try renderPNG(pixelSize: 1024, to: previewDir.appendingPathComponent("vietgo_app_icon_1024.png"))
            try renderPNG(pixelSize: 64, to: previewDir.appendingPathComponent("vietgo_app_icon_64.png"))
        }

        print("Generated \(icnsURL.path)")
    }
}

try MainActor.assumeIsolated {
    try GenerateIconCLI.run()
}
