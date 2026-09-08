#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The Xcode app target (src/ios/project.yml) links against the static libraries that
# `cmake --build build --config Release` already produced (core, video_core, audio_core,
# aetheremu-ios, plus every bundled CPM dependency -- boost, FFmpeg, MoltenVK, SDL3,
# ...) rather than recompiling ~1000 C++ files a second time inside Xcode's own build
# system, which has no story for providing those dependencies on its own (that's what
# CMake + CPM already solved). Same technique as cemu-ios-muffin's
# ci/generate-link-flags.sh.
#
# Static libs are listed by FULL PATH in a linker response file, not `-l<name>` +
# LIBRARY_SEARCH_PATHS -- the exact output directory for each target under CMake's
# Xcode generator hasn't been verified against a real completed build yet (no local
# Xcode/iOS SDK to test against), so this deliberately doesn't hardcode one.
#
# Usage: generate-link-flags.sh <output-response-file>

set -euo pipefail

OUT_FILE="${1:?usage: generate-link-flags.sh <output-response-file>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "generate-link-flags.sh: no build/ directory at $BUILD_DIR -- run the CMake" >&2
    echo "core build first (see .github/workflows/ios-configure.yml)." >&2
    exit 1
fi

: > "$OUT_FILE"
found_any=0
while IFS= read -r -d '' lib; do
    printf '%q\n' "$lib" >> "$OUT_FILE"
    found_any=1
done < <(find "$BUILD_DIR" -name '*.a' -not -path '*/CMakeFiles/*' -print0)

if [[ "$found_any" -eq 0 ]]; then
    echo "generate-link-flags.sh: found zero .a files under $BUILD_DIR -- did the core" >&2
    echo "build actually run/succeed before this step?" >&2
    exit 1
fi

echo "generate-link-flags.sh: wrote $(wc -l < "$OUT_FILE") library paths to $OUT_FILE"
