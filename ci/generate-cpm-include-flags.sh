#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Xcode's HEADER_SEARCH_PATHS glob support only expands a trailing `/**` (whole-path
# recursive); it does NOT expand a `*` embedded inside one path segment, and in
# practice its recursive expansion of large vendored trees under .cache/cpm (CPM's
# SOURCE_DIR for every dependency -- CPMUtil.cmake's AddPackage flow passes one
# explicitly, so packages never land under the default <binary_dir>/_deps/<name>-src
# path, confirmed by reading that CMake logic, not guessed) has repeatedly missed
# individual libraries' include/ subdirectories even though their parent directory was
# found. First seen against boost/unordered/... and boost/throw_exception.hpp (same
# pattern each time: a hand-glob for just the boost tree kept finding one library's
# parent dir but not its include/ child), then against fmt (fmt/ranges.h not found at
# all -- HEADER_SEARCH_PATHS had never included fmt's cache dir in the first place,
# since it isn't a boost sublibrary). Rather than keep hardcoding one CPM package's
# include path at a time as each new one surfaces in CI, this sweeps the ENTIRE
# .cache/cpm tree once for every directory literally named "include" (covering boost,
# fmt, zstd, SPIRV-Headers, and anything else force-bundled for iOS per
# CMakeLists.txt's `if (IOS)` block) and writes a response file -- mirroring
# generate-link-flags.sh's existing find-then-response-file pattern for exactly the
# same underlying reason: CMake/CPM's own build already handles this correctly via each
# package's INTERFACE include directories; Xcode's app target needs an equivalent that
# doesn't rely on Xcode's own glob resolution, which `find` has no trouble with
# regardless of tree depth/size.
#
# Usage: generate-cpm-include-flags.sh <output-response-file>

set -euo pipefail

OUT_FILE="${1:?usage: generate-cpm-include-flags.sh <output-response-file>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CPM_CACHE_DIR="$REPO_ROOT/.cache/cpm"

if [[ ! -d "$CPM_CACHE_DIR" ]]; then
    echo "generate-cpm-include-flags.sh: no .cache/cpm directory at $CPM_CACHE_DIR --" >&2
    echo "run the CMake core build first (see .github/workflows/ios-configure.yml)." >&2
    exit 1
fi

: > "$OUT_FILE"
found_any=0

while IFS= read -r -d '' dir; do
    printf -- '-I%q\n' "$dir" >> "$OUT_FILE"
    found_any=1
done < <(find "$CPM_CACHE_DIR" -type d -name include -print0)

# boostorg/headers (CMakeLists.txt's fallback for when Boost::headers isn't available
# via the regular boost package, see its "really annoying" comment) is a flat "every
# top-level boost/*.hpp facade in one place" repo -- its own root, not an include/
# subdirectory under it, is the actual header root.
if [[ -d "$CPM_CACHE_DIR/boost_headers" ]]; then
    printf -- '-I%q\n' "$CPM_CACHE_DIR/boost_headers" >> "$OUT_FILE"
    found_any=1
fi

if [[ "$found_any" -eq 0 ]]; then
    echo "generate-cpm-include-flags.sh: found zero include directories under" >&2
    echo "$CPM_CACHE_DIR -- did the core build actually run/succeed before this step?" >&2
    exit 1
fi

echo "generate-cpm-include-flags.sh: wrote $(wc -l < "$OUT_FILE") include flags to $OUT_FILE"
