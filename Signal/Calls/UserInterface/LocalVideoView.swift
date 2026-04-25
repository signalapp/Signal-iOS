//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import SignalRingRTC
import SignalServiceKit
public import WebRTC

class LocalVideoView: UIView {
    private let localVideoCapturePreview = RTCCameraPreviewView()

    var captureSession: AVCaptureSession? {
        get { localVideoCapturePreview.captureSession }
        set { localVideoCapturePreview.captureSession = newValue }
    }

    override var contentMode: UIView.ContentMode {
        didSet { localVideoCapturePreview.contentMode = contentMode }
    }

    init() {
        super.init(frame: .zero)

        addSubview(localVideoCapturePreview)

        if Platform.isSimulator {
            backgroundColor = .brown
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateLocalVideoOrientation),
            name: UIDevice.orientationDidChangeNotification,
            object: nil,
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var frame: CGRect {
        didSet {
            updateLocalVideoOrientation()
        }
    }

    @objc
    private func updateLocalVideoOrientation() {
        localVideoCapturePreview.frame = bounds
    }
}

extension RTCCameraPreviewView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        return layer as? AVCaptureVideoPreviewLayer
    }

    override open var contentMode: UIView.ContentMode {
        get {
            guard let previewLayer else {
                owsFailDebug("missing preview layer")
                return .scaleToFill
            }

            switch previewLayer.videoGravity {
            case .resizeAspectFill:
                return .scaleAspectFill
            case .resizeAspect:
                return .scaleAspectFit
            case .resize:
                return .scaleToFill
            default:
                owsFailDebug("Unexpected contentMode")
                return .scaleToFill
            }
        }
        set {
            guard let previewLayer else {
                return owsFailDebug("missing preview layer")
            }

            switch newValue {
            case .scaleAspectFill:
                previewLayer.videoGravity = .resizeAspectFill
            case .scaleAspectFit:
                previewLayer.videoGravity = .resizeAspect
            case .scaleToFill:
                previewLayer.videoGravity = .resize
            default:
                owsFailDebug("Unexpected contentMode")
            }
        }
    }
}
