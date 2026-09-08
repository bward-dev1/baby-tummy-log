// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Shown on first launch (no theme chosen yet), and re-openable any time from either
/// theme's "Change Theme" button. Picking one entirely reshapes the home screen --
/// AppTheme is the single source of truth ContentView branches on.
struct ThemePickerView: View {
    var onSelect: (AppTheme) -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Choose your look")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("You can change this anytime.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        ForEach(AppTheme.allCases) { theme in
                            Button {
                                onSelect(theme)
                            } label: {
                                VStack(spacing: 14) {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(theme.previewGradient)
                                        .frame(width: 200, height: 130)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                                        )
                                    Text(theme.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(theme.summary)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                        .multilineTextAlignment(.center)
                                        .frame(width: 180)
                                }
                                .padding(16)
                                .glassCard()
                            }
                            .buttonStyle(PressScaleButtonStyle())
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .padding(32)
        }
    }
}

/// Simple press-feedback style: shrinks slightly while held, springs back on release.
/// Used on the theme tiles since choosing a theme is the very first interaction in the
/// app and deserves to feel responsive.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
