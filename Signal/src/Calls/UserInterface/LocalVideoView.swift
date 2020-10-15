//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class LocalVideoView: UIView {
    private let localVideoCapturePreview = RTCCameraPreviewView()

    var captureSession: AVCaptureSession? {
        set { localVideoCapturePreview.captureSession = newValue }
        get { localVideoCapturePreview.captureSession }
    }

    override var contentMode: UIView.ContentMode {
        didSet { localVideoCapturePreview.contentMode = contentMode }
    }

    override init(frame: CGRect) {
        super.init(frame: .zero)

        addSubview(localVideoCapturePreview)

        if Platform.isSimulator {
            backgroundColor = .green
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateLocalVideoOrientation),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var frame: CGRect {
        didSet { updateLocalVideoOrientation() }
    }

    @objc
    func updateLocalVideoOrientation() {
        defer { localVideoCapturePreview.frame = bounds }

        // iPad supports rotating this view controller directly,
        // so we don't need to do anything here.
        guard !UIDevice.current.isIPad else { return }

        // We lock this view to portrait only on phones, but the
        // local video capture will rotate with the device's
        // orientation (so the remote party will render your video
        // in the correct orientation). As such, we need to rotate
        // the local video preview layer so it *looks* like we're
        // also always capturing in portrait.

        switch UIDevice.current.orientation {
        case .portrait:
            localVideoCapturePreview.transform = .identity
        case .portraitUpsideDown:
            localVideoCapturePreview.transform = .init(rotationAngle: .pi)
        case .landscapeLeft:
            localVideoCapturePreview.transform = .init(rotationAngle: .halfPi)
        case .landscapeRight:
            localVideoCapturePreview.transform = .init(rotationAngle: .pi + .halfPi)
        case .faceUp, .faceDown, .unknown:
            break
        @unknown default:
            break
        }
    }
}

extension RTCCameraPreviewView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        return layer as? AVCaptureVideoPreviewLayer
    }

    open override var contentMode: UIView.ContentMode {
        set {
            guard let previewLayer = previewLayer else {
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
        get {
            guard let previewLayer = previewLayer else {
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
    }
}
