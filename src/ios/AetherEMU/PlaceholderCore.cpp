// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

// Phase 0 placeholder translation unit.
//
// This file exists only so the `aetheremu-ios` CMake target (see
// CMakeLists.txt in this directory) has at least one compiled source --
// CMake rejects a library target declared with zero SOURCES. It
// intentionally contains no real logic yet. App.swift, also in this
// directory, is this app-shell's intended SwiftUI entry point, but Swift
// isn't compiled by this CMake target; a real Xcode app target wiring this
// static library and the Swift sources together is a later phase.

namespace AetherEMU {

// Placeholder anchor symbol. Remove once real translation units land here.
void PlaceholderAnchor() {}

} // namespace AetherEMU
