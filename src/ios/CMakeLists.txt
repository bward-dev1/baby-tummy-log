# SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
# SPDX-License-Identifier: GPL-3.0-or-later

# SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
# SPDX-License-Identifier: GPL-3.0-or-later

# iOS app-shell bridge target.
#
# Unlike the Android jni target (which builds a JNI-facing SHARED library that gets
# dlopen()'d by the JVM), this is a STATIC library. There is no Xcode app target yet
# to embed a .framework in, and a static lib is what a future AetherEMU.xcodeproj/SwiftPM
# app target links directly -- no bundle Info.plist, no code-signing identity, and no
# dynamic-library-embedding step required just to get a CI `cmake --build` configure/build
# to succeed. If/when this needs to ship as an independently-versioned or dynamically
# loaded component (e.g. an app extension), it can be flipped to
# `add_library(yuzu-ios SHARED ...)` plus MACOSX_FRAMEWORK_* properties -- but that's a
# decision to make once there's an actual app target and device to validate it on.

add_library(yuzu-ios STATIC
    emu_window/emu_window.h
    emu_window/emu_window.mm
    native.h
    native.mm
)

target_link_libraries(yuzu-ios PRIVATE audio_core common core input_common frontend_common video_core)

# PLATFORM_LIBRARIES is populated by the top-level CMakeLists.txt's `if (IOS)` framework
# block (Metal, UIKit, CoreVideo, CoreMedia, Security, UniformTypeIdentifiers, Foundation).
# Reuse it instead of re-declaring find_library() calls here.
target_link_libraries(yuzu-ios PRIVATE ${PLATFORM_LIBRARIES})

target_compile_options(yuzu-ios PRIVATE -fobjc-arc)

set(CPACK_PACKAGE_EXECUTABLES ${CPACK_PACKAGE_EXECUTABLES} yuzu-ios)
