//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MetalKit
import SignalRingRTC
import SignalServiceKit
import SignalUI
import WebRTC

class RemoteVideoView: UIView {
    private lazy var rtcMetalView = RTCMTLVideoView(frame: bounds)

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(rtcMetalView)
        rtcMetalView.autoPinEdgesToSuperviewEdges()
        // We want the rendered video to go edge-to-edge.
        rtcMetalView.layoutMargins = .zero
        // HACK: Although RTCMTLVideo view is positioned to the top edge of the screen
        // It's inner (private) MTKView is below the status bar.
        for subview in rtcMetalView.subviews {
            if subview is MTKView {
                subview.autoPinEdgesToSuperviewEdges()
            } else {
                owsFailDebug("New subviews added to MTLVideoView. Reconsider this hack.")
            }
        }

        applyDefaultRendererConfiguration()

        if Platform.isSimulator {
            backgroundColor = .blue.withAlphaComponent(0.4)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isScreenShare = false {
        didSet {
            if oldValue != isScreenShare {
                applyDefaultRendererConfigurationOnNextFrame = true
            }
        }
    }

    var isGroupCall = false {
        didSet {
            if oldValue != isGroupCall {
                applyDefaultRendererConfigurationOnNextFrame = true
            }
        }
    }

    var isFullScreen = false {
        didSet {
            if oldValue != isFullScreen {
                applyDefaultRendererConfigurationOnNextFrame = true
            }
        }
    }

    private var applyDefaultRendererConfigurationOnNextFrame = false

    private func applyDefaultRendererConfiguration() {
        if UIDevice.current.isIPad {
            rtcMetalView.videoContentMode = .scaleAspectFit
            rtcMetalView.rotationOverride = nil
        } else {
            rtcMetalView.videoContentMode = .scaleAspectFill
            rtcMetalView.rotationOverride = nil
        }
    }
}

extension RemoteVideoView: RTCVideoRenderer {

    func setSize(_ size: CGSize) {
        rtcMetalView.setSize(size)
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        rtcMetalView.renderFrame(frame)

        DispatchMainThreadSafe { [self] in
            if applyDefaultRendererConfigurationOnNextFrame {
                applyDefaultRendererConfigurationOnNextFrame = false
                applyDefaultRendererConfiguration()
            }

            guard let frame else { return }

            let isLandscape = bounds.width > bounds.height
            let remoteIsLandscape = frame.rotation == RTCVideoRotation._180 || frame.rotation == RTCVideoRotation._0
            let isSquarish = max(bounds.width, bounds.height) / min(bounds.width, bounds.height) <= 1.2

            // If we're both in the same orientation, let the video fill the screen.
            // Otherwise, fit the video to the screen size respecting the aspect ratio.
            if isLandscape == remoteIsLandscape || isSquarish, !isScreenShare {
                rtcMetalView.videoContentMode = .scaleAspectFill
            } else {
                rtcMetalView.videoContentMode = .scaleAspectFit
            }
        }
    }
}
