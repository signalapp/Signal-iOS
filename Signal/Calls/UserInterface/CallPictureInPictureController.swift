//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVKit
@preconcurrency import AVFoundation
import CoreMotion
import SignalServiceKit
import UIKit
import WebRTC

@preconcurrency @MainActor
class CallPictureInPictureController: NSObject {

    private var pipController: AVPictureInPictureController?
    private var pipVideoCallViewController: AVPictureInPictureVideoCallViewController?

    private var sampleBufferView: SampleBufferDisplayView?
    private var frameRenderer: PiPFrameRenderer?
    private weak var currentRemoteVideoTrack: RTCVideoTrack?

    private var localSampleBufferView: SampleBufferDisplayView?
    private var localCaptureOutput: AVCaptureVideoDataOutput?
    private var localCaptureDelegate: LocalCaptureOutputDelegate?
    private weak var attachedCaptureSession: AVCaptureSession?
    private var motionManager: CMMotionManager?

    private(set) var isPictureInPictureActive: Bool = false
    var onRestoreUserInterface: (() -> Void)?
    var onPictureInPictureDidStop: (() -> Void)?
    private weak var sourceView: UIView?

    // MARK: - Configuration

    func configure(sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            Logger.warn("PiP is not supported on this device.")
            return
        }

        pipController = nil
        pipVideoCallViewController = nil
        self.sourceView = sourceView

        let callVC = AVPictureInPictureVideoCallViewController()
        callVC.preferredContentSize = CGSize(width: 1080, height: 1920)

        // Using layerClass = AVSampleBufferDisplayLayer makes the layer the
        // view's backing layer. A standalone layer added via addSublayer does
        // NOT render in the out-of-process PiP window.
        let sbView = SampleBufferDisplayView()
        sbView.sampleBufferLayer.videoGravity = .resizeAspect
        callVC.view.addSubview(sbView)
        sbView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sbView.leadingAnchor.constraint(equalTo: callVC.view.leadingAnchor),
            sbView.trailingAnchor.constraint(equalTo: callVC.view.trailingAnchor),
            sbView.topAnchor.constraint(equalTo: callVC.view.topAnchor),
            sbView.bottomAnchor.constraint(equalTo: callVC.view.bottomAnchor),
        ])
        self.sampleBufferView = sbView

        let localView = SampleBufferDisplayView()
        localView.sampleBufferLayer.videoGravity = .resizeAspectFill
        localView.layer.cornerRadius = 6
        localView.clipsToBounds = true
        localView.layer.borderWidth = 1
        localView.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        callVC.view.addSubview(localView)
        localView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            localView.widthAnchor.constraint(equalTo: callVC.view.widthAnchor, multiplier: 0.28),
            localView.heightAnchor.constraint(equalTo: localView.widthAnchor, multiplier: 16.0 / 9.0),
            localView.trailingAnchor.constraint(equalTo: callVC.view.trailingAnchor, constant: -6),
            localView.bottomAnchor.constraint(equalTo: callVC.view.bottomAnchor, constant: -6),
        ])
        self.localSampleBufferView = localView
        self.pipVideoCallViewController = callVC

        let pipContentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: callVC
        )

        let controller = AVPictureInPictureController(contentSource: pipContentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = controller

        let renderer = PiPFrameRenderer(sampleBufferLayer: sbView.sampleBufferLayer)
        renderer.onVideoSizeChanged = { [weak callVC] size in
            callVC?.preferredContentSize = size
        }
        frameRenderer = renderer
    }

    // MARK: - Local Video

    func attachLocalCaptureSession(_ session: AVCaptureSession) {
        detachLocalCaptureSession()
        guard let localLayer = localSampleBufferView?.sampleBufferLayer else { return }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let delegate = LocalCaptureOutputDelegate(sampleBufferLayer: localLayer)
        output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "org.signal.pip.localvideo"))

        session.beginConfiguration()
        if session.canAddOutput(output) {
            session.addOutput(output)
            self.localCaptureOutput = output
            self.localCaptureDelegate = delegate
            self.attachedCaptureSession = session
        }
        session.commitConfiguration()

        // CMMotionManager tracks orientation via accelerometer — works on
        // background queues and while the app is backgrounded during PiP.
        // Same threshold-based approach used in CameraCaptureSession.swift.
        let manager = CMMotionManager()
        manager.accelerometerUpdateInterval = 0.2
        manager.startAccelerometerUpdates(to: OperationQueue()) { [weak delegate] data, _ in
            guard let accel = data?.acceleration, let delegate else { return }
            let orientation: CGImagePropertyOrientation
            if accel.x >= 0.75 {
                orientation = .upMirrored
            } else if accel.x <= -0.75 {
                orientation = .downMirrored
            } else if accel.y <= -0.75 {
                orientation = .leftMirrored
            } else if accel.y >= 0.75 {
                orientation = .rightMirrored
            } else {
                return
            }
            delegate.currentOrientation = orientation
        }
        self.motionManager = manager
    }

    private func detachLocalCaptureSession() {
        if let output = localCaptureOutput, let session = attachedCaptureSession {
            session.beginConfiguration()
            session.removeOutput(output)
            session.commitConfiguration()
        }
        motionManager?.stopAccelerometerUpdates()
        motionManager = nil
        localCaptureOutput = nil
        localCaptureDelegate = nil
        attachedCaptureSession = nil
    }

    // MARK: - Camera Multitasking

    func enableMultitaskingCameraAccess(for captureSession: AVCaptureSession) {
        if #available(iOS 16.0, *) {
            if captureSession.isMultitaskingCameraAccessSupported {
                captureSession.isMultitaskingCameraAccessEnabled = true
            }
        }
    }

    // MARK: - Video Track Management

    func attachRemoteVideoTrack(_ track: RTCVideoTrack?) {
        if let oldTrack = currentRemoteVideoTrack, let renderer = frameRenderer {
            oldTrack.remove(renderer)
        }
        currentRemoteVideoTrack = track

        if let track = track, let renderer = frameRenderer {
            track.add(renderer)
        }
    }

    // MARK: - PiP Lifecycle

    func startPictureInPicture() {
        guard let pipController = pipController else { return }
        guard !pipController.isPictureInPictureActive else { return }
        pipController.startPictureInPicture()
    }

    func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }

    func tearDown() {
        stopPictureInPicture()
        attachRemoteVideoTrack(nil)
        detachLocalCaptureSession()
        frameRenderer = nil
        sampleBufferView = nil
        localSampleBufferView = nil
        pipController = nil
        pipVideoCallViewController = nil
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension CallPictureInPictureController: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        MainActor.assumeIsolated {
            self.isPictureInPictureActive = true
            AppEnvironment.shared.callService?.isPictureInPictureActive = true
            AppEnvironment.shared.callService?.updateIsVideoEnabled()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        MainActor.assumeIsolated {
            Logger.info("PiP did start")
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {}

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        MainActor.assumeIsolated {
            self.isPictureInPictureActive = false
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            self.onPictureInPictureDidStop?()
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated {
            self.onRestoreUserInterface?()
            completionHandler(true)
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        MainActor.assumeIsolated {
            Logger.error("PiP failed to start: \(error)")
            self.isPictureInPictureActive = false
            AppEnvironment.shared.callService?.isPictureInPictureActive = false
            AppEnvironment.shared.callService?.updateIsVideoEnabled()
        }
    }
}

// MARK: - SampleBufferDisplayView

/// A UIView whose backing layer IS an AVSampleBufferDisplayLayer.
/// Using `layerClass` is required for the layer to render in the
/// out-of-process PiP window.
private class SampleBufferDisplayView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var sampleBufferLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }
}

// MARK: - PiPFrameRenderer

private class PiPFrameRenderer: NSObject, RTCVideoRenderer {

    private let sampleBufferLayer: AVSampleBufferDisplayLayer
    private var frameCounter: Int = 0
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    var onVideoSizeChanged: ((CGSize) -> Void)?
    private var lastOutputSize: CGSize = .zero

    init(sampleBufferLayer: AVSampleBufferDisplayLayer) {
        self.sampleBufferLayer = sampleBufferLayer
        super.init()
    }

    // Intentionally empty — PiP window size is managed via preferredContentSize.
    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame = frame else { return }
        guard var pixelBuffer = extractPixelBuffer(from: frame) else { return }

        let orientation = Self.ciImageOrientation(for: frame.rotation)
        if orientation != .up {
            if let rotated = rotatePixelBuffer(pixelBuffer, orientation: orientation) {
                pixelBuffer = rotated
            }
        }

        frameCounter += 1

        guard let sampleBuffer = Self.createImmediateDisplaySampleBuffer(
            from: pixelBuffer,
            presentationTime: CMTime(value: Int64(frameCounter), timescale: 30)
        ) else {
            return
        }

        let outputSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                height: CVPixelBufferGetHeight(pixelBuffer))
        let sizeChanged = outputSize != lastOutputSize && outputSize.width > 0 && outputSize.height > 0
        if sizeChanged { lastOutputSize = outputSize }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if sizeChanged { self.onVideoSizeChanged?(outputSize) }
            Self.safeEnqueue(sampleBuffer, on: self.sampleBufferLayer)
        }
    }

    // MARK: - Rotation

    private static func ciImageOrientation(for rotation: RTCVideoRotation) -> CGImagePropertyOrientation {
        switch rotation {
        case ._0:   return .up
        case ._90:  return .right
        case ._180: return .down
        case ._270: return .left
        @unknown default: return .up
        }
    }

    private func rotatePixelBuffer(_ source: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: source).oriented(orientation)
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        guard let output = Self.createIOSurfacePixelBuffer(width: width, height: height, format: kCVPixelFormatType_32BGRA) else { return nil }
        ciContext.render(ciImage, to: output)
        return output
    }

    // MARK: - Pixel Buffer Extraction

    private func extractPixelBuffer(from frame: RTCVideoFrame) -> CVPixelBuffer? {
        if let cvPixelBufferWrapper = frame.buffer as? RTCCVPixelBuffer {
            return ensureIOSurfaceBacked(cvPixelBufferWrapper.pixelBuffer)
        }
        return convertI420ToNV12(frame.buffer.toI420())
    }

    /// AVSampleBufferDisplayLayer silently drops non-IOSurface-backed buffers.
    private func ensureIOSurfaceBacked(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        if CVPixelBufferGetIOSurface(pixelBuffer) != nil { return pixelBuffer }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard let dest = Self.createIOSurfacePixelBuffer(width: width, height: height, format: format) else { return pixelBuffer }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(dest, [])
        let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        if planeCount > 0 {
            for plane in 0..<planeCount {
                if let src = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane),
                   let dst = CVPixelBufferGetBaseAddressOfPlane(dest, plane) {
                    let srcStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
                    let dstStride = CVPixelBufferGetBytesPerRowOfPlane(dest, plane)
                    let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
                    for row in 0..<h {
                        memcpy(dst.advanced(by: row * dstStride), src.advanced(by: row * srcStride), min(srcStride, dstStride))
                    }
                }
            }
        } else if let src = CVPixelBufferGetBaseAddress(pixelBuffer),
                  let dst = CVPixelBufferGetBaseAddress(dest) {
            let srcStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let dstStride = CVPixelBufferGetBytesPerRow(dest)
            for row in 0..<height {
                memcpy(dst.advanced(by: row * dstStride), src.advanced(by: row * srcStride), min(srcStride, dstStride))
            }
        }
        CVPixelBufferUnlockBaseAddress(dest, [])
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        return dest
    }

    private func convertI420ToNV12(_ i420Buffer: any RTCI420BufferProtocol) -> CVPixelBuffer? {
        let width = Int(i420Buffer.width)
        let height = Int(i420Buffer.height)
        guard let outputBuffer = Self.createIOSurfacePixelBuffer(width: width, height: height, format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) else { return nil }

        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputBuffer, []) }

        if let yDest = CVPixelBufferGetBaseAddressOfPlane(outputBuffer, 0) {
            let yDestStride = CVPixelBufferGetBytesPerRowOfPlane(outputBuffer, 0)
            let ySrcStride = Int(i420Buffer.strideY)
            for row in 0..<height {
                memcpy(yDest.advanced(by: row * yDestStride), i420Buffer.dataY.advanced(by: row * ySrcStride), min(yDestStride, ySrcStride))
            }
        }

        if let uvDest = CVPixelBufferGetBaseAddressOfPlane(outputBuffer, 1) {
            let uvDestStride = CVPixelBufferGetBytesPerRowOfPlane(outputBuffer, 1)
            let chromaHeight = height / 2
            let chromaWidth = width / 2
            for row in 0..<chromaHeight {
                let uvDestRow = uvDest.advanced(by: row * uvDestStride)
                let uSrcRow = i420Buffer.dataU.advanced(by: row * Int(i420Buffer.strideU))
                let vSrcRow = i420Buffer.dataV.advanced(by: row * Int(i420Buffer.strideV))
                for col in 0..<chromaWidth {
                    uvDestRow.storeBytes(of: uSrcRow[col], toByteOffset: col * 2, as: UInt8.self)
                    uvDestRow.storeBytes(of: vSrcRow[col], toByteOffset: col * 2 + 1, as: UInt8.self)
                }
            }
        }
        return outputBuffer
    }

    // MARK: - Shared Helpers

    static func createIOSurfacePixelBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attrs as CFDictionary, &pixelBuffer)
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }

    static func createImmediateDisplaySampleBuffer(from pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription) == noErr,
              let formatDesc = formatDescription else { return nil }

        var timingInfo = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: formatDesc, sampleTiming: &timingInfo, sampleBufferOut: &sampleBuffer) == noErr,
              let sampleBuffer else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? [NSMutableDictionary],
           let dict = attachments.first {
            dict[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sampleBuffer
    }

    static func safeEnqueue(_ buffer: CMSampleBuffer, on layer: AVSampleBufferDisplayLayer) {
        if layer.status == .failed { layer.flush() }
        layer.enqueue(buffer)
    }
}

// MARK: - LocalCaptureOutputDelegate

/// Rotates local camera frames based on device orientation (set by CMMotionManager)
/// and enqueues them into the local camera inset's AVSampleBufferDisplayLayer.
private class LocalCaptureOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let sampleBufferLayer: AVSampleBufferDisplayLayer
    private var frameCount: Int64 = 0
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Written from CMMotionManager's OperationQueue, read from capture queue.
    // Benign race on ARM64 — CGImagePropertyOrientation is a single-word enum.
    var currentOrientation: CGImagePropertyOrientation = .leftMirrored

    init(sampleBufferLayer: AVSampleBufferDisplayLayer) {
        self.sampleBufferLayer = sampleBufferLayer
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: sourceBuffer).oriented(currentOrientation)
        let w = Int(ciImage.extent.width)
        let h = Int(ciImage.extent.height)
        guard let pixelBuffer = PiPFrameRenderer.createIOSurfacePixelBuffer(width: w, height: h, format: kCVPixelFormatType_32BGRA) else { return }
        ciContext.render(ciImage, to: pixelBuffer)

        frameCount += 1
        guard let newSampleBuffer = PiPFrameRenderer.createImmediateDisplaySampleBuffer(
            from: pixelBuffer,
            presentationTime: CMTime(value: frameCount, timescale: 30)
        ) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            PiPFrameRenderer.safeEnqueue(newSampleBuffer, on: self.sampleBufferLayer)
        }
    }
}
