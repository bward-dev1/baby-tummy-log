// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The "Dock" theme: a full-width horizontal carousel with a floating bottom dock,
/// in the spirit of the bottom-dock reference concept -- but with its own wording
/// throughout (no "View All"/"Folders" header text, no A/X button-hint glyphs) rather
/// than reproducing that concept's on-screen text verbatim, since that one leans much
/// closer to a literal recreation of Nintendo's own system menu than the Rail theme
/// does.
struct DockHomeView: View {
    @Binding var games: [Game]
    var onPlay: (Game) -> Void
    var onImportTapped: () -> Void
    var onChangeTheme: () -> Void

    @State private var rail: RailSection = .library
    @State private var selected: Game?

    var body: some View {
        ZStack {
            (selected?.accentGradient ?? Theme.backgroundGradient)
                .opacity(0.5)
                .background(Theme.backgroundGradient)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: selected)

            VStack(spacing: 16) {
                HStack {
                    Text("AetherEMU")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Change Theme", action: onChangeTheme)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Your Library")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(games.count) games")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    if games.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.4))
                            Text("Import a game to get started")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(games) { game in
                                    Button {
                                        selected = game
                                    } label: {
                                        VStack {
                                            GameTile(game: game, isSelected: selected?.id == game.id)
                                                .overlay(alignment: .topLeading) {
                                                    if selected?.id == game.id {
                                                        Text("Now Viewing")
                                                            .font(.caption2.bold())
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 3)
                                                            .background(.white, in: Capsule())
                                                            .foregroundStyle(.black)
                                                            .padding(8)
                                                    }
                                                }
                                        }
                                        .frame(width: 160)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if let game = selected {
                        Divider().overlay(.white.opacity(0.15))
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.title)
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                                Text(game.path.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            Button {
                                onPlay(game)
                            } label: {
                                Label("Open", systemImage: "play.fill")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(.white, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .glassCard()

                Spacer()

                DockBar(selection: $rail, onImportTapped: onImportTapped)
            }
            .padding(20)
        }
        .onChange(of: games) { newValue in
            if selected == nil {
                selected = newValue.first
            }
        }
        .onAppear {
            if selected == nil {
                selected = games.first
            }
        }
    }
}
