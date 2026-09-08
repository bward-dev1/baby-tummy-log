// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import QuartzCore
import UIKit

/// Hosts a bare CAMetalLayer and hands it to the C++ engine via AetherBridge. The
/// engine (video_core, via GraphicsContext_iOS -- see emu_window.h) owns the actual
/// MTLDevice/command queue and drives drawable presentation itself; this view's job is
/// to exist, expose its layer, and forward touch/resize events. Resize forwarding and
/// touch input (touchesBegan/Moved/Ended/Cancelled below) are both wired -- untested,
/// no local Xcode/iOS SDK/device/CI result exists yet. No CADisplayLink is used
/// deliberately: video_core's own GPU thread drives frame presentation, not the view.
final class MetalHostView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer {
        // Safe force-cast: `layerClass` above guarantees `layer` is a CAMetalLayer.
        layer as! CAMetalLayer
    }

    // TODO(ios): untested, no CI oracle available -- UITouch has no stable small int
    // id, so we assign one per touch and track it in this dictionary (UITouch is
    // Hashable/Equatable by identity, so this works as a key, but the whole path is
    // unverified without a device). Cleared on touchesEnded/Cancelled.
    private var touchIDs: [UITouch: Int] = [:]
    private var nextTouchID = 0

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
        if window == nil {
            // Leaving the view hierarchy -- this view (and its backing CAMetalLayer,
            // since layerClass makes it the sole owner) may deallocate after this.
            // AetherBridge's stored surface is a strong reference now, but detaching
            // explicitly avoids the engine holding onto a stale layer for a view that's
            // gone -- see AetherBridge.mm's AetherNativeSurface comment.
            AetherBridge.shared().detachMetalLayer()
        } else {
            // An adversarial review pass caught this: on a fresh attach, this fires
            // before layoutSubviews ever runs, so metalLayer.drawableSize is still
            // CGSize.zero (init only sets pixelFormat/framebufferOnly) -- OnSurfaceChanged
            // would read that zero size into m_window_width/m_window_height with no
            // guard. layoutSubviews always follows and re-attaches with the real size, so
            // this was self-correcting, but setting drawableSize here too (same formula
            // as layoutSubviews) avoids the transient zero-size window entirely.
            metalLayer.drawableSize = CGSize(
                width: bounds.width * contentScaleFactor,
                height: bounds.height * contentScaleFactor
            )
            AetherBridge.shared().attachMetalLayer(metalLayer)
        }
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

    // TODO(ios): untested, no CI oracle available. Coordinates are converted to the
    // CAMetalLayer's pixel space (points * contentScaleFactor) to match drawableSize
    // above -- this MUST match whatever EmuWindow_iOS::OnSurfaceChanged eventually sets
    // m_window_width/m_window_height (and therefore framebuffer_layout) to once that
    // TODO is filled in (currently a stub, see emu_window.mm), or MapToTouchScreen's
    // 0-1 normalization will divide by the wrong denominator and touches will land at
    // the wrong point on the emulated touchscreen.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        for touch in touches {
            let id = nextTouchID
            nextTouchID += 1
            touchIDs[touch] = id
            let p = touch.location(in: self)
            AetherBridge.shared().touchPressed(
                id, x: Float(p.x * contentScaleFactor), y: Float(p.y * contentScaleFactor))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        for touch in touches {
            guard let id = touchIDs[touch] else { continue }
            let p = touch.location(in: self)
            AetherBridge.shared().touchMoved(
                id, x: Float(p.x * contentScaleFactor), y: Float(p.y * contentScaleFactor))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        releaseTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // An adversarial review pass caught this forwarding into touchesEnded (which
        // calls super.touchesEnded), mislabeling a system-cancelled touch sequence as a
        // normal end to the UIResponder/gesture-recognizer chain -- call
        // super.touchesCancelled directly instead, sharing only the emulator-side
        // release logic (releaseTouches), same as Android's ACTION_CANCEL handling.
        super.touchesCancelled(touches, with: event)
        releaseTouches(touches)
    }

    private func releaseTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let id = touchIDs.removeValue(forKey: touch) else { continue }
            AetherBridge.shared().touchReleased(id)
        }
    }
}

struct MetalView: UIViewRepresentable {
    func makeUIView(context: Context) -> MetalHostView {
        MetalHostView()
    }

    func updateUIView(_ uiView: MetalHostView, context: Context) {}
}
