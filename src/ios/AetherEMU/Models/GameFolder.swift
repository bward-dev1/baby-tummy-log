// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A user-created grouping of games. AetherEMU has no metadata service to auto-sort
/// games into genres/categories -- these are plain user-organized folders, not curated
/// "Cozy/Chill"-style shelves (there's no data backing a claim like that).
struct GameFolder: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var gameIDs: [UUID]

    init(name: String, gameIDs: [UUID] = []) {
        self.id = UUID()
        self.name = name
        self.gameIDs = gameIDs
    }

    func games(in library: [Game]) -> [Game] {
        library.filter { gameIDs.contains($0.id) }
    }
}
