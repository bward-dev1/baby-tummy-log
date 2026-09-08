// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct HomeView: View {
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

            HStack(alignment: .top, spacing: 16) {
                SideRail(selection: $rail, onImportTapped: onImportTapped)

                VStack(spacing: 16) {
                    if let game = selected {
                        GameDetailPanel(game: game, onPlay: { onPlay(game) })
                    } else {
                        emptyStateHero
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                LibraryGrid(games: games, selected: $selected)
            }
            .padding(20)

            VStack {
                HStack {
                    Spacer()
                    Button("Change Theme", action: onChangeTheme)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(10)
                }
                Spacer()
            }
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

    private var emptyStateHero: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.4))
            Text("No game selected")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            Text("AetherEMU")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }
}
