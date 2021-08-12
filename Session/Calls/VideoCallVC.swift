import UIKit
import AVFoundation
import WebRTC

final class VideoCallVC : UIViewController {
    private var localVideoView: UIView!
    private var remoteVideoView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpViewHierarchy()
        CameraManager.shared.delegate = self
    }
        
    private func setUpViewHierarchy() {
        // Create video views
        #if arch(arm64)
            // Use Metal
            let localRenderer = RTCMTLVideoView(frame: self.localVideoView.frame)
            localRenderer.contentMode = .scaleAspectFill
            let remoteRenderer = RTCMTLVideoView(frame: self.remoteVideoView.frame)
            remoteRenderer.contentMode = .scaleAspectFill
        #else
            // Use OpenGLES
            let localRenderer = RTCEAGLVideoView(frame: self.localVideoView.frame)
            let remoteRenderer = RTCEAGLVideoView(frame: self.remoteVideoView.frame)
        #endif
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ localVideoView, remoteVideoView ])
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        stackView.alignment = .fill
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.pin(to: view)
        // Attach video views
        CallManager.shared.attachLocalRenderer(localRenderer)
        CallManager.shared.attachRemoteRenderer(remoteRenderer)
        localVideoView.addSubview(localRenderer)
        localRenderer.translatesAutoresizingMaskIntoConstraints = false
        localRenderer.pin(to: localVideoView)
        remoteVideoView.addSubview(remoteRenderer)
        remoteRenderer.translatesAutoresizingMaskIntoConstraints = false
        remoteRenderer.pin(to: remoteVideoView)
    }
}

// MARK: Camera
extension VideoCallVC : CameraCaptureDelegate {
    
    func captureVideoOutput(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let rtcpixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timeStampNs = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000000000)
        let videoFrame = RTCVideoFrame(buffer: rtcpixelBuffer, rotation: RTCVideoRotation._0, timeStampNs: timeStampNs)
        CallManager.shared.handleLocalFrameCaptured(videoFrame)
    }
}
