// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
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

    var body: some View {
        ZStack {
            if isRunning {
                MetalView()
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack {
                Spacer()
                if !isRunning {
                    VStack(spacing: 12) {
                        Text("AetherEMU")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Button("Load Game...") {
                            isPickingGame = true
                        }
                        .buttonStyle(.borderedProminent)
                        if let lastError {
                            Text(lastError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                Spacer()
            }
        }
        .fileImporter(isPresented: $isPickingGame, allowedContentTypes: Self.gameContentTypes) { result in
            switch result {
            case .success(let url):
                loadGame(at: url)
            case .failure(let error):
                lastError = error.localizedDescription
            }
        }
    }

    private func loadGame(at url: URL) {
        // NX game files live outside the app sandbox until picked, so a security-scoped
        // access grant is required before the C++ side can open the path -- see
        // AetherBridge.mm's TODO on filepath handling going through NSURL bookmarks for
        // the longer-term (re-open-without-repicking) story.
        guard url.startAccessingSecurityScopedResource() else {
            lastError = "Couldn't access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let result = AetherBridge.shared().loadGame(atPath: url.path)
        if result == .success {
            isRunning = true
            lastError = nil
        } else {
            lastError = "Failed to load game."
        }
    }
}

#Preview {
    ContentView()
}
