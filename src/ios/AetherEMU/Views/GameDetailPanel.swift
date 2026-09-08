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
    var onRemove: () -> Void = {}

    @State private var tab: DetailTab = .info
    @State private var isConfirmingRemove = false

    private var fileSizeFormatted: String {
        let size = (try? FileManager.default.attributesOfItem(atPath: game.path.path)[.size] as? Int64) ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

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
                .buttonStyle(PressScaleButtonStyle())
            }

            HStack(spacing: 20) {
                ForEach(DetailTab.allCases, id: \.self) { candidate in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { tab = candidate }
                    } label: {
                        VStack(spacing: 4) {
                            Text(candidate.rawValue)
                                .font(.subheadline.weight(tab == candidate ? .bold : .regular))
                                .foregroundStyle(tab == candidate ? .white : .white.opacity(0.5))
                            Capsule()
                                .fill(.white)
                                .frame(height: 2)
                                .opacity(tab == candidate ? 1 : 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(.white.opacity(0.15))

            Group {
                switch tab {
                case .info:
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("File", value: game.path.lastPathComponent)
                        LabeledContent("Size", value: fileSizeFormatted)
                        Button(role: .destructive) {
                            isConfirmingRemove = true
                        } label: {
                            Label("Remove from Library", systemImage: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.top, 4)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                case .saveStates:
                    Text("No save states yet -- AetherEMU's core doesn't have save-state serialization implemented.")
                        .foregroundStyle(.white.opacity(0.5))
                case .mods:
                    Text("Mod support isn't wired up yet -- Eden's LayeredFS mod loader exists in the core, but there's no per-game mod folder picker on iOS yet.")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(.footnote)
            .transition(.opacity)
            .id(tab)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .confirmationDialog(
            "Remove \(game.title) from your library?", isPresented: $isConfirmingRemove, titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) {}
        }
    }
}
