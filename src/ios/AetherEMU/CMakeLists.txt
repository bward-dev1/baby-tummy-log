# SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
# SPDX-License-Identifier: GPL-3.0-or-later

# SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
# SPDX-License-Identifier: GPL-3.0-or-later

# AetherEMU iOS app-shell (Phase 0 skeleton).
#
# This mirrors src/android/app/src/main/jni/CMakeLists.txt's role: build the
# C++ core as a library that an app target links against. Unlike the Android
# JNI target (a SHARED library dlopen()'d by the JVM), this is a STATIC
# library -- there is no Xcode app target yet to embed a shared
# library/framework in. Wiring an actual .xcodeproj/XCFramework that
# consumes this target plus App.swift is a later phase; see App.swift's
# header comment.
#
# Note: src/ios/CMakeLists.txt (target `yuzu-ios`) already exists as a
# separate, more advanced iOS app-shell attempt (Objective-C++ bridge:
# EmulationSession, EmuWindow_iOS) added in a prior pass under Eden's
# `yuzu-*` naming convention. This target is AetherEMU's own Phase 0
# skeleton per the project's own "aetheremu"/"aether" naming convention and
# does not replace or depend on `yuzu-ios` -- the two have not been
# reconciled yet. See PlaceholderCore.cpp for more on this.

add_library(aetheremu-ios STATIC
    PlaceholderCore.cpp
)

# Mirrors the android jni target's core-library link line, minus the
# Android-only libraries (jni, camera2ndk, jnigraphics, GLESv2, adrenotools,
# etc.) which don't apply on iOS.
target_link_libraries(aetheremu-ios PRIVATE audio_core common core input_common frontend_common video_core)
