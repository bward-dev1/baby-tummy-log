// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Owns the app's actual managed game folder (Application Support/Games) and persists
/// the library across launches -- previously `games`/`folders` were plain `@State` in
/// ContentView, reset to empty on every relaunch, and every load re-required picking the
/// file fresh via a security-scoped bookmark that was never actually saved anywhere.
///
/// Importing a game now COPIES it into this app-owned folder. That's a deliberate
/// tradeoff (doubles disk usage vs. referencing the original file in place) in exchange
/// for something that actually works reliably: once copied, the file lives inside our
/// own sandbox, so no security-scoped access is needed ever again, and the library
/// survives relaunch without re-picking anything.
@MainActor
final class GameLibrary: ObservableObject {
    // didSet-based autosave rather than each mutator remembering to call save() --
    // `folders` in particular is also mutated directly through a SwiftUI Binding by
    // DockHomeView's folder-creation/drag-to-folder UI, not just through the convenience
    // methods below; a manual save()-on-every-mutator approach would silently miss those
    // direct-binding writes and never persist folder changes made that way.
    @Published var games: [Game] = [] { didSet { save() } }
    @Published var folders: [GameFolder] = [] { didSet { save() } }

    private let gamesDirectory: URL
    private let manifestURL: URL
    // load() and the initial property values above both fire didSet -- guard against
    // writing an empty manifest over a real one before load() has actually run once.
    private var isLoaded = false

    struct Manifest: Codable {
        var games: [Game]
        var folders: [GameFolder]
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        gamesDirectory = support.appendingPathComponent("Games", isDirectory: true)
        manifestURL = support.appendingPathComponent("library.json")
        try? FileManager.default.createDirectory(at: gamesDirectory, withIntermediateDirectories: true)
        load()
        isLoaded = true
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return
        }
        // Drop any entry whose backing file went missing (e.g. the user deleted the app's
        // data via Settings > General > iPhone Storage without going through this UI) --
        // showing a game that can never load is worse than silently dropping it.
        games = manifest.games.filter { FileManager.default.fileExists(atPath: $0.path.path) }
        folders = manifest.folders
    }

    private func save() {
        guard isLoaded else { return }
        let manifest = Manifest(games: games, folders: folders)
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    /// Copies `sourceURL` (already security-scoped-accessible, e.g. from a
    /// UIDocumentPickerViewController result) into the managed Games folder and adds it
    /// to the library. Returns the new Game on success.
    @discardableResult
    func importGame(from sourceURL: URL) -> Game? {
        let needsAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if needsAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        let title = sourceURL.deletingPathExtension().lastPathComponent
        let destination = gamesDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceURL.pathExtension)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            return nil
        }

        let game = Game(title: title, path: destination)
        games.append(game)
        return game
    }

    func removeGame(_ game: Game) {
        try? FileManager.default.removeItem(at: game.path)
        games.removeAll { $0.id == game.id }
        for index in folders.indices {
            folders[index].gameIDs.removeAll { $0 == game.id }
        }
    }

    func markPlayed(_ game: Game) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index].lastPlayed = Date()
    }

    func addFolder(named name: String) {
        folders.append(GameFolder(name: name))
    }

    func addGame(_ game: Game, to folder: GameFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        if !folders[index].gameIDs.contains(game.id) {
            folders[index].gameIDs.append(game.id)
        }
    }

    func removeGame(_ game: Game, from folder: GameFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index].gameIDs.removeAll { $0 == game.id }
    }
}
