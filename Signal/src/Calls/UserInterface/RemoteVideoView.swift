//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MetalKit
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

            // In certain cases, rotate the video so it's always right side up in landscape.
            // We only allow portrait orientation in the calling views on iPhone so we don't
            // get this for free.
            let shouldOverrideRotation: Bool
            if UIDevice.current.isIPad || !isFullScreen {
                // iPad allows all orientations so we can skip this.
                // Non-full-screen views are part of a portrait-locked UI (e.g. the group call grid)
                // and rotating the video without rotating the UI would look weird.
                shouldOverrideRotation = false
            } else if isGroupCall {
                // For speaker view in a group call, keep screenshares right-side up.
                shouldOverrideRotation = isScreenShare
            } else {
                // For a 1:1 call, always keep video right-side up.
                shouldOverrideRotation = true
            }

            let isLandscape: Bool
            if shouldOverrideRotation {
                switch UIDevice.current.orientation {
                case .portrait, .portraitUpsideDown:
                    // We don't have to do anything, the renderer will automatically
                    // make sure it's right-side-up.
                    isLandscape = false
                    rtcMetalView.rotationOverride = nil

                case .landscapeLeft:
                    isLandscape = true
                    switch frame.rotation {
                        // Portrait upside-down
                    case ._270:
                        rtcMetalView.rotationOverride = NSNumber(value: RTCVideoRotation._0.rawValue)

                        // Portrait
                    case ._90:
                        rtcMetalView.rotationOverride = NSNumber(value: RTCVideoRotation._180.rawValue)

                        // Landscape right
                    case ._180:
                        rtcMetalView.rotationOverride = NSNumber(value: RTCVideoRotation._270.rawValue)

                        // Landscape left
                    case ._0:
                        rtcMetalView.rotationOverride = NSNumber(value: RTCVideoRotation._90.rawValue)
                    @unknown default:
                        owsFailBeta("unknown frame.rotation: \(frame.rotation)")
                    }

                case .landscapeRight:
                    isLandscape = true
                    switch frame.rotation {
                        // Portrait upside-down
                    case ._270:
                        rtcMetalView.rotationOverride = NSNumber(value: RTCVideoRotation._180.rawValue)

                        // Portrait
                    case ._90:
                        rtcMetalView.rotationOverride = NSNumber(value: RTCVideoRotation._0.rawValue)

                        // Landscape right
                    case ._180:
                        rtcMetalView.rotationOverride = NSNumber(value: RTCVideoRotation._90.rawValue)

                        // Landscape left
                    case ._0:
                        rtcMetalView.rotationOverride = NSNumber(value: RTCVideoRotation._270.rawValue)
                    @unknown default:
                        owsFailBeta("unknown frame.rotation: \(frame.rotation)")
                    }

                default:
                    // Do nothing if we're face down, up, etc.
                    // Assume we're already set up for the correct orientation.
                    isLandscape = false
                }
            } else {
                rtcMetalView.rotationOverride = nil
                isLandscape = bounds.width > bounds.height
            }

            let remoteIsLandscape = frame.rotation == RTCVideoRotation._180 || frame.rotation == RTCVideoRotation._0
            let isSquarish = max(bounds.width, bounds.height) / min(bounds.width, bounds.height) <= 1.2

            // If we're both in the same orientation, let the video fill the screen.
            // Otherwise, fit the video to the screen size respecting the aspect ratio.
            if (isLandscape == remoteIsLandscape || isSquarish) && !isScreenShare {
                rtcMetalView.videoContentMode = .scaleAspectFill
            } else {
                rtcMetalView.videoContentMode = .scaleAspectFit
            }
        }
    }
}
