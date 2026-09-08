#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Xcode's HEADER_SEARCH_PATHS glob support only expands a trailing `/**` (whole-path
# recursive); it does NOT expand a `*` embedded inside one path segment, and in
# practice its recursive expansion of the CPM boost cache (a full boostorg/boost
# superproject checkout, ~150 sublibraries each with their own libs/<name>/include/
# directory) has repeatedly missed individual libraries' include/ subdirectories even
# though their parent library directory was found -- confirmed against real CI
# failures for both `boost/unordered/...` and `boost/throw_exception.hpp` in turn, both
# following the identical pattern (parent dir found, include/ child missing). Hardcoding
# one path at a time after each new CI failure doesn't scale (there could be many more
# transitive single-header libraries left), so this generates the complete, correct
# list with `find` instead, mirroring generate-link-flags.sh's existing
# find-then-response-file pattern for exactly the same underlying reason (CMake/CPM's
# own build already handles this correctly via Boost::headers; Xcode's app target needs
# an equivalent that doesn't rely on Xcode's own glob resolution).
#
# Usage: generate-boost-include-flags.sh <output-response-file>

set -euo pipefail

OUT_FILE="${1:?usage: generate-boost-include-flags.sh <output-response-file>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CPM_CACHE_DIR="$REPO_ROOT/.cache/cpm"

if [[ ! -d "$CPM_CACHE_DIR" ]]; then
    echo "generate-boost-include-flags.sh: no .cache/cpm directory at $CPM_CACHE_DIR --" >&2
    echo "run the CMake core build first (see .github/workflows/ios-configure.yml)." >&2
    exit 1
fi

: > "$OUT_FILE"
found_any=0

# Every libs/<name>/include directory in the boost superproject checkout, whatever its
# exact version -- find, unlike Xcode's HEADER_SEARCH_PATHS glob, has no trouble with
# this regardless of tree depth/size.
if [[ -d "$CPM_CACHE_DIR/boost" ]]; then
    while IFS= read -r -d '' dir; do
        printf -- '-I%q\n' "$dir" >> "$OUT_FILE"
        found_any=1
    done < <(find "$CPM_CACHE_DIR/boost" -type d -name include -print0)
fi

# boostorg/headers -- the flat "every top-level boost/*.hpp facade in one place" repo
# CMakeLists.txt falls back to for Boost::headers when CPM's regular boost package
# doesn't provide it (see its "really annoying" comment). Sweep the same way rather
# than assuming its exact internal layout.
if [[ -d "$CPM_CACHE_DIR/boost_headers" ]]; then
    printf -- '-I%q\n' "$CPM_CACHE_DIR/boost_headers" >> "$OUT_FILE"
    found_any=1
    while IFS= read -r -d '' dir; do
        printf -- '-I%q\n' "$dir" >> "$OUT_FILE"
        found_any=1
    done < <(find "$CPM_CACHE_DIR/boost_headers" -type d -name include -print0)
fi

if [[ "$found_any" -eq 0 ]]; then
    echo "generate-boost-include-flags.sh: found zero boost include directories under" >&2
    echo "$CPM_CACHE_DIR -- did the core build actually run/succeed before this step?" >&2
    exit 1
fi

echo "generate-boost-include-flags.sh: wrote $(wc -l < "$OUT_FILE") include flags to $OUT_FILE"
