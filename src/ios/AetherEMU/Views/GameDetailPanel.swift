// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum DetailTab: String, CaseIterable {
    case info = "Info"
    case saveStates = "Save States"
    case mods = "Mods"
}

/// The hero panel for the currently-highlighted game. Its tab row (Info / Save States /
/// Mods) fills the same layout slot Option 2's reference design used for
/// Achievements/News/DLC -- swapped for what an emulator actually has to offer instead
/// of an online-service concept AetherEMU has no backend for.
struct GameDetailPanel: View {
    let game: Game
    var onPlay: () -> Void

    @State private var tab: DetailTab = .info

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    if let lastPlayed = game.lastPlayed {
                        Text("Last played \(lastPlayed.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    } else {
                        Text("Never played")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 20) {
                ForEach(DetailTab.allCases, id: \.self) { candidate in
                    Button {
                        tab = candidate
                    } label: {
                        Text(candidate.rawValue)
                            .font(.subheadline.weight(tab == candidate ? .bold : .regular))
                            .foregroundStyle(tab == candidate ? .white : .white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(.white.opacity(0.15))

            Group {
                switch tab {
                case .info:
                    LabeledContent("File", value: game.path.lastPathComponent)
                        .foregroundStyle(.white.opacity(0.8))
                case .saveStates:
                    Text("No save states yet.")
                        .foregroundStyle(.white.opacity(0.5))
                case .mods:
                    Text("Mod support isn't wired up yet.")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(.footnote)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
