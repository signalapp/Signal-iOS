import Foundation
import AVFoundation

@objc
protocol CameraCaptureDelegate : AnyObject {
    
    func captureVideoOutput(sampleBuffer: CMSampleBuffer)
}

final class CameraManager : NSObject {
    private let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let dataOutputQueue = DispatchQueue(label: "CameraManager.dataOutputQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    private var isCapturing = false
    weak var delegate: CameraCaptureDelegate?
    
    private lazy var videoCaptureDevice: AVCaptureDevice? = {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }()
    
    static let shared = CameraManager()
    
    private override init() { }
    
    func prepare() {
        captureSession.sessionPreset = .low
        if let videoCaptureDevice = videoCaptureDevice,
            let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice), captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [ kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA) ]
            videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
            videoDataOutput.connection(with: .video)?.videoOrientation = .portrait
            videoDataOutput.connection(with: .video)?.automaticallyAdjustsVideoMirroring = false
            videoDataOutput.connection(with: .video)?.isVideoMirrored = true
        } else {
            SNLog("Couldn't add video data output to capture session.")
            captureSession.commitConfiguration()
        }
    }
    
    func start() {
        guard !isCapturing else { return }
        isCapturing = true
        #if arch(arm64)
        captureSession.startRunning()
        #endif
    }
    
    func stop() {
        guard isCapturing else { return }
        isCapturing = false
        #if arch(arm64)
        captureSession.stopRunning()
        #endif
    }
}

extension CameraManager : AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard connection == videoDataOutput.connection(with: .video) else { return }
        delegate?.captureVideoOutput(sampleBuffer: sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) { }
}
