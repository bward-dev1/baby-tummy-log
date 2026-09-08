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

                HStack(spacing: 24) {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            onSelect(theme)
                        } label: {
                            VStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(theme.previewGradient)
                                    .frame(width: 220, height: 140)
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
                                    .frame(width: 200)
                            }
                            .padding(16)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(32)
        }
    }
}
