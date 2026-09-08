// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    // nil until the user picks one (ThemePickerView) -- entirely reshapes the home
    // screen once set, per-theme layouts in HomeView (Rail) vs. DockHomeView (Dock).
    @AppStorage("aetheremu.appTheme") private var storedTheme: String?

    @State private var games: [Game] = []
    @State private var folders: [GameFolder] = []
    @State private var isPickingGame = false
    @State private var isRunning = false
    @State private var lastError: String?

    // NX game images. AetherBridge doesn't validate extensions today (see
    // AetherBridge.mm's TODO on InitializeEmulation) -- this list only limits what the
    // document picker itself will show/accept.
    private static let gameContentTypes: [UTType] = [
        UTType(filenameExtension: "nsp"),
        UTType(filenameExtension: "xci"),
        UTType(filenameExtension: "nca"),
    ].compactMap { $0 }

    private var theme: AppTheme? {
        storedTheme.flatMap(AppTheme.init(rawValue:))
    }

    var body: some View {
        ZStack {
            if isRunning {
                MetalView()
                    .ignoresSafeArea()
                    .overlay(alignment: .topTrailing) {
                        Button {
                            AetherBridge.shared().pause()
                            isRunning = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.7))
                                .padding()
                        }
                    }
            } else if let theme {
                switch theme {
                case .rail:
                    HomeView(
                        games: $games,
                        folders: $folders,
                        onPlay: loadGame,
                        onImportTapped: { isPickingGame = true },
                        onChangeTheme: { storedTheme = nil }
                    )
                case .dock:
                    DockHomeView(
                        games: $games,
                        folders: $folders,
                        onPlay: loadGame,
                        onImportTapped: { isPickingGame = true },
                        onChangeTheme: { storedTheme = nil }
                    )
                }
            } else {
                ThemePickerView(onSelect: { storedTheme = $0.rawValue })
            }

            if let lastError {
                VStack {
                    Spacer()
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 24)
                }
            }
        }
        .fileImporter(isPresented: $isPickingGame, allowedContentTypes: Self.gameContentTypes) { result in
            switch result {
            case .success(let url):
                addAndSelect(url: url)
            case .failure(let error):
                lastError = error.localizedDescription
            }
        }
    }

    private func addAndSelect(url: URL) {
        let game = Game(title: url.deletingPathExtension().lastPathComponent, path: url)
        games.append(game)
    }

    private func loadGame(_ game: Game) {
        // NX game files live outside the app sandbox until picked, so a security-scoped
        // access grant is required before the C++ side can open the path -- see
        // AetherBridge.mm's TODO on filepath handling going through NSURL bookmarks for
        // the longer-term (re-open-without-repicking) story.
        guard game.path.startAccessingSecurityScopedResource() else {
            lastError = "Couldn't access \(game.title)."
            return
        }
        defer { game.path.stopAccessingSecurityScopedResource() }

        let result = AetherBridge.shared().loadGame(atPath: game.path.path)
        if result == .success {
            isRunning = true
            lastError = nil
        } else {
            lastError = "Failed to load \(game.title)."
        }
    }
}

#Preview {
    ContentView()
}
