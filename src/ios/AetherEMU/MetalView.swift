// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import QuartzCore
import UIKit

/// Hosts a bare CAMetalLayer and hands it to the C++ engine via AetherBridge. The
/// engine (video_core, via GraphicsContext_iOS -- see emu_window.h) owns the actual
/// MTLDevice/command queue and drives drawable presentation itself once rendering is
/// wired up; this view's only job is to exist and expose its layer. No CADisplayLink,
/// resize forwarding, or touch input is wired yet -- TODOs mirroring emu_window.h's.
final class MetalHostView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer {
        // Safe force-cast: `layerClass` above guarantees `layer` is a CAMetalLayer.
        layer as! CAMetalLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        AetherBridge.shared().attachMetalLayer(metalLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Match the layer's drawable size to the view's real pixel size on every
        // resize/rotation, otherwise CAMetalLayer defaults to a stale/point-scaled
        // size and the engine would render at the wrong resolution.
        metalLayer.drawableSize = CGSize(
            width: bounds.width * contentScaleFactor,
            height: bounds.height * contentScaleFactor
        )
        AetherBridge.shared().attachMetalLayer(metalLayer)
    }
}

struct MetalView: UIViewRepresentable {
    func makeUIView(context: Context) -> MetalHostView {
        MetalHostView()
    }

    func updateUIView(_ uiView: MetalHostView, context: Context) {}
}
