// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Shown once at cold launch, before theme selection/home -- our own equivalent of the
/// reference lock/launch screen, with AetherEMU's own wordmark and wording instead of
/// Nintendo's logo/text.
struct LaunchLockView: View {
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                VStack(spacing: 2) {
                    Text("AETHER")
                        .font(.headline.weight(.semibold))
                        .tracking(6)
                    Text("EMU")
                        .font(.system(size: 44, weight: .bold))
                }
                .foregroundStyle(.white)
                Spacer()

                Button(action: onContinue) {
                    Label("Tap to Continue", systemImage: "hand.tap.fill")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.15), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
    }
}
