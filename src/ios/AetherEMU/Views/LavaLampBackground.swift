// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct LavaLampPalette {
    let base: LinearGradient
    let blobs: [Color]

    static let warm = LavaLampPalette(
        base: LinearGradient(
            colors: [Color(red: 0.93, green: 0.29, blue: 0.55), Color(red: 0.98, green: 0.55, blue: 0.25)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        blobs: [.white.opacity(0.35), .pink.opacity(0.4), .orange.opacity(0.35)]
    )

    static let cool = LavaLampPalette(
        base: LinearGradient(
            colors: [Color(red: 0.29, green: 0.55, blue: 0.93), Color(red: 0.25, green: 0.85, blue: 0.75)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        blobs: [.white.opacity(0.35), .mint.opacity(0.4), .indigo.opacity(0.3)]
    )

    // Three-stop diagonal (vs. warm/cool's two-stop) -- coral top-left, rose-pink
    // center, magenta/orange bottom corners.
    static let verticalRed = LavaLampPalette(
        base: LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.53, blue: 0.42),
                Color(red: 0.91, green: 0.36, blue: 0.58),
                Color(red: 0.76, green: 0.08, blue: 0.55),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        blobs: [.white.opacity(0.3), Color(red: 0.95, green: 0.62, blue: 0.35).opacity(0.4), .purple.opacity(0.35)]
    )

    // Three-stop diagonal -- periwinkle blue top, teal/green bottom-left, violet
    // bottom-right.
    static let verticalBlue = LavaLampPalette(
        base: LinearGradient(
            colors: [
                Color(red: 0.42, green: 0.55, blue: 0.93),
                Color(red: 0.38, green: 0.7, blue: 0.85),
                Color(red: 0.55, green: 0.42, blue: 0.91),
            ],
            startPoint: .top, endPoint: .bottomTrailing
        ),
        blobs: [.white.opacity(0.3), .teal.opacity(0.4), .indigo.opacity(0.35)]
    )
}

/// Soft, slowly-drifting translucent circles over a gradient -- the "lava lamp" look
/// from the reference screenshots. Purely decorative; positions are seeded once per
/// launch and animated with a slow repeating loop rather than driven by any real state.
struct LavaLampBackground: View {
    let palette: LavaLampPalette

    @State private var animate = false

    private struct Blob {
        let relativeX: CGFloat
        let relativeY: CGFloat
        let relativeSize: CGFloat
        let colorIndex: Int
    }

    private static let blobs: [Blob] = [
        Blob(relativeX: 0.85, relativeY: 0.08, relativeSize: 0.45, colorIndex: 0),
        Blob(relativeX: 0.05, relativeY: 0.75, relativeSize: 0.55, colorIndex: 1),
        Blob(relativeX: 0.75, relativeY: 0.85, relativeSize: 0.4, colorIndex: 2),
        Blob(relativeX: 0.15, relativeY: 0.15, relativeSize: 0.3, colorIndex: 1),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                palette.base

                ForEach(Array(Self.blobs.enumerated()), id: \.offset) { index, blob in
                    Circle()
                        .fill(palette.blobs[blob.colorIndex % palette.blobs.count])
                        .frame(width: proxy.size.width * blob.relativeSize)
                        .position(
                            x: proxy.size.width * blob.relativeX + (animate ? 20 : -20),
                            y: proxy.size.height * blob.relativeY + (animate ? -16 : 16)
                        )
                        .blur(radius: 40)
                        .animation(
                            .easeInOut(duration: Double(8 + index * 2)).repeatForever(autoreverses: true),
                            value: animate
                        )
                }
            }
            .onAppear { animate = true }
        }
        .ignoresSafeArea()
    }
}
