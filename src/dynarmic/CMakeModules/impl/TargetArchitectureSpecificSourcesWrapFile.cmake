# SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
# SPDX-License-Identifier: GPL-3.0-or-later

# NOTE(ios): Do NOT uppercase `arch` here. DetectArchitecture.cmake (externals/cmake-modules/)
# always defines ARCHITECTURE_<arch> in the exact case CMAKE_OSX_ARCHITECTURES/the ARCH
# parameter uses (lowercase: ARCHITECTURE_arm64, ARCHITECTURE_x86_64, ...), both in its
# CMAKE_OSX_ARCHITECTURES multiarch branch and its single-arch detect_architecture_symbols()
# path. Uppercasing here (as this file previously did) checks for ARCHITECTURE_ARM64, which
# is never defined anywhere -- every architecture-specific source silently compiled down to
# an empty translation unit as a result. A real CI link failure caught this: every public
# method of Dynarmic::A64::Jit/A32::Jit/ExclusiveMonitor undefined, because backend/arm64/*.cpp
# (all wrapped by this script) had never actually contained any code in a multiarch build
# (CMAKE_OSX_ARCHITECTURES set, i.e. every Apple-platform build using this generator).
file(READ "${input_file}" f_contents)
file(WRITE "${output_file}" "#if defined(ARCHITECTURE_${arch})\n${f_contents}\n#endif\n")
