// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    // nil until the user picks one (ThemePickerView) -- entirely reshapes the home
    // screen once set, per-theme layouts in HomeView (Rail) vs. DockHomeView (Dock).
    @AppStorage("aetheremu.appTheme") private var storedTheme: String?

    // Owns the actual managed Games folder + persistence -- games/folders used to be
    // plain @State, reset to empty on every relaunch. See GameLibrary.swift.
    @StateObject private var library = GameLibrary()
    @State private var isPickingGame = false
    @State private var isRunning = false
    @State private var isLoadingGame = false
    @State private var lastError: String?
    // Shown once per cold launch (not persisted -- reappears every fresh launch, like the
    // reference lock screen), and the shared full-library sheet every theme's .library
    // icon opens (see onShowLibrary below).
    @State private var hasUnlocked = false
    @State private var isShowingLibrary = false

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
                        games: $library.games,
                        folders: $library.folders,
                        onPlay: loadGame,
                        onImportTapped: { isPickingGame = true },
                        onChangeTheme: { storedTheme = nil },
                        onShowLibrary: { isShowingLibrary = true }
                    )
                case .dock:
                    DockHomeView(
                        games: $library.games,
                        folders: $library.folders,
                        onPlay: loadGame,
                        onImportTapped: { isPickingGame = true },
                        onChangeTheme: { storedTheme = nil },
                        onShowLibrary: { isShowingLibrary = true }
                    )
                case .lavaWarm:
                    LavaLampHomeView(
                        palette: .warm,
                        games: $library.games,
                        onPlay: loadGame,
                        onImportTapped: { isPickingGame = true },
                        onChangeTheme: { storedTheme = nil },
                        onShowLibrary: { isShowingLibrary = true }
                    )
                case .lavaCool:
                    LavaLampHomeView(
                        palette: .cool,
                        games: $library.games,
                        onPlay: loadGame,
                        onImportTapped: { isPickingGame = true },
                        onChangeTheme: { storedTheme = nil },
                        onShowLibrary: { isShowingLibrary = true }
                    )
                case .lavaVerticalRed:
                    VerticalLavaLampHomeView(
                        palette: .verticalRed,
                        games: $library.games,
                        onPlay: loadGame,
                        onImportTapped: { isPickingGame = true },
                        onChangeTheme: { storedTheme = nil },
                        onShowLibrary: { isShowingLibrary = true }
                    )
                case .lavaVerticalBlue:
                    VerticalLavaLampHomeView(
                        palette: .verticalBlue,
                        games: $library.games,
                        onPlay: loadGame,
                        onImportTapped: { isPickingGame = true },
                        onChangeTheme: { storedTheme = nil },
                        onShowLibrary: { isShowingLibrary = true }
                    )
                case .lavaDark:
                    LavaLampHomeView(
                        palette: .dark,
                        games: $library.games,
                        onPlay: loadGame,
                        onImportTapped: { isPickingGame = true },
                        onChangeTheme: { storedTheme = nil },
                        onShowLibrary: { isShowingLibrary = true }
                    )
                case .lavaVerticalDark:
                    VerticalLavaLampHomeView(
                        palette: .dark,
                        games: $library.games,
                        onPlay: loadGame,
                        onImportTapped: { isPickingGame = true },
                        onChangeTheme: { storedTheme = nil },
                        onShowLibrary: { isShowingLibrary = true }
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: lastError)
            }

            if isLoadingGame {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.4)
                        Text("Loading…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
                .transition(.opacity)
            }

            if !hasUnlocked {
                LaunchLockView(onContinue: { hasUnlocked = true })
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLoadingGame)
        .animation(.easeInOut(duration: 0.3), value: theme)
        .fileImporter(isPresented: $isPickingGame, allowedContentTypes: Self.gameContentTypes) { result in
            switch result {
            case .success(let url):
                lastError = nil
                addAndSelect(url: url)
            case .failure(let error):
                lastError = error.localizedDescription
            }
        }
        .sheet(isPresented: $isShowingLibrary) {
            LibraryPageView(
                games: library.games,
                onSelect: { game in
                    isShowingLibrary = false
                    loadGame(game)
                },
                onDismiss: { isShowingLibrary = false }
            )
        }
    }

    private func addAndSelect(url: URL) {
        // Copies url into the app's own managed Games folder -- see GameLibrary's own
        // comment for why. The source picker result is already security-scoped-
        // accessible; importGame handles that grant itself.
        if library.importGame(from: url) == nil {
            lastError = "Couldn't import \(url.deletingPathExtension().lastPathComponent)."
        }
    }

    private func loadGame(_ game: Game) {
        // Unlike the original pick-in-place design, game.path now always points inside
        // this app's own sandbox (GameLibrary copies the file in at import time), so no
        // security-scoped access dance is needed here at all -- the long-standing "NSURL
        // bookmarks for re-open-without-repicking" TODO this used to carry is resolved by
        // construction, not worked around.
        lastError = nil
        isLoadingGame = true

        AetherBridge.shared().loadGame(atPath: game.path.path) { result in
            isLoadingGame = false
            if result == .success {
                library.markPlayed(game)
                withAnimation(.easeInOut(duration: 0.25)) {
                    isRunning = true
                }
                lastError = nil
            } else {
                lastError = "Failed to load \(game.title)."
            }
        }
    }
}

#Preview {
    ContentView()
}
