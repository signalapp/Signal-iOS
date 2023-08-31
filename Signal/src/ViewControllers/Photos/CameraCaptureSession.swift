//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import CoreMotion
import CoreServices
import Foundation
import SignalCoreKit
import SignalMessaging
import SignalUI
import UIKit

enum PhotoCaptureError: Error {
    case assertionError(description: String)
    case initializationFailed
    case captureFailed
    case invalidVideo
    case videoTooLarge
}

extension PhotoCaptureError: LocalizedError, UserErrorDescriptionProvider {
    var localizedDescription: String {
        switch self {
        case .initializationFailed:
            return OWSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_INITIALIZE_CAMERA", comment: "alert title")
        case .captureFailed:
            return OWSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_CAPTURE_IMAGE", comment: "alert title")
        case .videoTooLarge:
            return OWSLocalizedString(
                "PHOTO_CAPTURE_VIDEO_SIZE_ERROR",
                comment: "alert title, generic error preventing user from capturing a video that is too long"
            )

        case .assertionError, .invalidVideo:
            return OWSLocalizedString("PHOTO_CAPTURE_GENERIC_ERROR", comment: "alert title, generic error preventing user from capturing a photo")
        }
    }
}

protocol CameraCaptureSessionDelegate: AnyObject {

    func cameraCaptureSessionDidStart(_ session: CameraCaptureSession)
    func cameraCaptureSession(_ session: CameraCaptureSession, didFinishProcessing attachment: SignalAttachment)
    func cameraCaptureSession(_ session: CameraCaptureSession, didFailWith error: Error)

    // MARK: Video

    func cameraCaptureSessionWillStartVideoRecording(_ session: CameraCaptureSession)
    func cameraCaptureSessionDidStartVideoRecording(_ session: CameraCaptureSession)
    func cameraCaptureSessionDidStopVideoRecording(_ session: CameraCaptureSession)
    func cameraCaptureSession(_ session: CameraCaptureSession, videoRecordingDurationChanged duration: TimeInterval)

    // MARK: Utility

    func cameraCaptureSession(_ session: CameraCaptureSession, didChangeOrientation: AVCaptureVideoOrientation)
    func cameraCaptureSession(_ session: CameraCaptureSession, didChangeZoomFactor: CGFloat, forCameraPosition: AVCaptureDevice.Position)
    func cameraCaptureSessionCanCaptureMoreItems(_ session: CameraCaptureSession) -> Bool
    func photoCaptureDidTryToCaptureTooMany(_ session: CameraCaptureSession)
    var zoomScaleReferenceDistance: CGFloat? { get }

    func beginCaptureButtonAnimation(_ duration: TimeInterval)
    func endCaptureButtonAnimation(_ duration: TimeInterval)

    func cameraCaptureSession(_ session: CameraCaptureSession, didFinishFocusingAt focusPoint: CGPoint)
}

// MARK: -

class CameraCaptureSession: NSObject {

    private weak var delegate: CameraCaptureSessionDelegate?

    // There can only ever be one `CapturePreviewView` per AVCaptureSession
    lazy var previewView = CapturePreviewView(session: avCaptureSession)

    let avCaptureSession = AVCaptureSession()
    private static let sessionQueue = DispatchQueue(label: "org.signal.capture.camera")
    private var sessionQueue: DispatchQueue { CameraCaptureSession.sessionQueue }

    // Separate session for capturing audio is necessary to eliminate
    // video stream stutter when audio connection is established.
    private let audioCaptureSession = AVCaptureSession()
    private var audioCaptureInput: AVCaptureDeviceInput?

    private var videoCaptureInput: AVCaptureDeviceInput?
    private var videoCaptureDevice: AVCaptureDevice? {
        return videoCaptureInput?.device
    }

    private let photoCapture = PhotoCapture()
    private let videoCapture = VideoCapture()

    init(delegate: CameraCaptureSessionDelegate) {
        self.delegate = delegate

        super.init()

        avCaptureSession.automaticallyConfiguresApplicationAudioSession = false
        avCaptureSession.usesApplicationAudioSession = true

        audioCaptureSession.automaticallyConfiguresApplicationAudioSession = false
        audioCaptureSession.usesApplicationAudioSession = true

        videoCapture.delegate = self
    }

    deinit {
        motionManager?.stopAccelerometerUpdates()
    }

    func prepare() -> Promise<Void> {
        AssertIsOnMainThread()
        guard !Platform.isSimulator else {
            // Trying to actually set up the capture session will fail on a simulator
            // since we don't have actual capture devices. But it's useful to be able
            // to mostly run the capture code on the simulator to work with layout.
            return Promise.value(())
        }

        // If the session is already running, no need to do anything.
        guard !avCaptureSession.isRunning else { return Promise.value(()) }

        let initialCaptureOrientation = beginObservingOrientationChanges()

        return sessionQueue.async(.promise) { [weak self] in
            guard let self else { return }

            self.avCaptureSession.beginConfiguration()
            defer { self.avCaptureSession.commitConfiguration() }

            self.captureOrientation = initialCaptureOrientation ?? self.captureOrientation
            self.avCaptureSession.sessionPreset = .high

            // 1. Reconfigure which camera to use.
            try self.reconfigureVideoCaptureInput()

            // 2. Add photo output (AVCapturePhotoOutput).
            let photoOutput = self.photoCapture.avCaptureOutput
            guard self.avCaptureSession.canAddOutput(photoOutput) else {
                owsFailDebug("Could not add AVCapturePhotoOutput.")
                throw PhotoCaptureError.initializationFailed
            }
            self.avCaptureSession.addOutput(photoOutput)
            // Do not set `preferredVideoStabilizationMode` - doing so causes
            // recording latency and results in last ~1.5 seconds of video not being written.

            // 3. Add outputs for video (AVCaptureVideoDataOutput and AVCaptureAudioDataOutput).
            let videoDataOutput = self.videoCapture.videoDataOutput
            guard self.avCaptureSession.canAddOutput(videoDataOutput) else {
                owsFailDebug("Could not add AVCaptureVideoDataOutput.")
                throw PhotoCaptureError.initializationFailed
            }
            self.avCaptureSession.addOutput(videoDataOutput)

            let audioDataOutput = self.videoCapture.audioDataOutput
            if self.audioCaptureSession.canAddOutput(audioDataOutput) {
                self.audioCaptureSession.addOutput(audioDataOutput)
            } else {
                owsFailDebug("Could not add AVCaptureAudioDataOutput.")
            }
        }
    }

    @discardableResult
    func stop() -> Guarantee<Void> {
        sessionQueue.async(.promise) { [avCaptureSession, audioCaptureSession] in
            avCaptureSession.stopRunning()
            audioCaptureSession.stopRunning()
        }
    }

    @discardableResult
    func resume() -> Guarantee<Void> {
        sessionQueue.async(.promise) { [avCaptureSession, audioCaptureSession] in
            avCaptureSession.startRunning()
            audioCaptureSession.startRunning()
        }
    }

    func assertIsOnSessionQueue() {
        assertOnQueue(sessionQueue)
    }

    // This method should be called on the serial queue, and between calls to session.beginConfiguration/commitConfiguration
    func reconfigureVideoCaptureInput() throws {
        assertIsOnSessionQueue()

        guard let device = defaultVideoCaptureDevice(forPosition: desiredPosition) else {
            throw PhotoCaptureError.assertionError(description: description)
        }

        let newInput = try AVCaptureDeviceInput(device: device)

        if let oldInput = videoCaptureInput {
            avCaptureSession.removeInput(oldInput)
            NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: oldInput.device)
        }
        avCaptureSession.addInput(newInput)
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: newInput.device)

        if let focusObservation {
            focusObservation.invalidate()
        }
        focusObservation = newInput.observe(
            \.device.isAdjustingFocus,
             options: [.old, .new]
        ) { [weak self] _, change in
            guard let self = self else { return }

            guard let oldValue = change.oldValue else {
                return
            }

            guard let newValue = change.newValue else {
                return
            }

            if oldValue == true && newValue == false {
                self.didCompleteFocusing()
            }
        }

        videoCaptureInput = newInput

        // Camera by default has zoom factor of 1, which would be UW camera on triple camera systems, but default camera in the UI is "wide".
        // Also it is necessary to reset camera to "1x" when switching between front and rear to match Camera app behavior.
        resetCameraZoomFactor(device)

        resetFocusAndExposure()
    }

    // MARK: - Flash

    var flashMode: AVCaptureDevice.FlashMode { photoCapture.flashMode }

    func toggleFlashMode() -> Guarantee<Void> {
        return sessionQueue.async(.promise) {
            switch self.photoCapture.flashMode {
            case .auto:
                Logger.debug("new flashMode: on")
                self.photoCapture.flashMode = .on
            case .on:
                Logger.debug("new flashMode: off")
                self.photoCapture.flashMode = .off
            case .off:
                Logger.debug("new flashMode: auto")
                self.photoCapture.flashMode = .auto
            @unknown default:
                owsFailDebug("unknown flashMode: \(self.photoCapture.flashMode)")
                self.photoCapture.flashMode = .auto
            }
        }
    }

    // MARK: - Focusing

    var focusObservation: NSKeyValueObservation?

    func focus(
        with focusMode: AVCaptureDevice.FocusMode,
        exposureMode: AVCaptureDevice.ExposureMode,
        at devicePoint: CGPoint,
        monitorSubjectAreaChange: Bool) {
            sessionQueue.async {
                Logger.debug("focusMode: \(focusMode), exposureMode: \(exposureMode), devicePoint: \(devicePoint), monitorSubjectAreaChange:\(monitorSubjectAreaChange)")
                guard let device = self.videoCaptureDevice else {
                    if !Platform.isSimulator {
                        owsFailDebug("device was unexpectedly nil")
                    }
                    return
                }
                do {
                    try device.lockForConfiguration()

                    // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                    // Call set(Focus/Exposure)Mode() to apply the new point of interest.
                    if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                        device.focusPointOfInterest = devicePoint
                        device.focusMode = focusMode
                    }

                    if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                        device.exposurePointOfInterest = devicePoint
                        device.exposureMode = exposureMode
                    }

                    device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                    device.unlockForConfiguration()
                } catch {
                    owsFailDebug("error: \(error)")
                }
            }
        }

    func resetFocusAndExposure() {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }

    func didCompleteFocusing() {
        Logger.debug("")
        guard let videoCaptureDevice else { return }

        let focusPoint = videoCaptureDevice.focusPointOfInterest
        DispatchQueue.main.async {
            self.delegate?.cameraCaptureSession(self, didFinishFocusingAt: focusPoint)
        }
    }

    @objc
    private func subjectAreaDidChange(notification: NSNotification) {
        resetFocusAndExposure()
    }

    // MARK: - Device Orientation

    private var _captureOrientation: AVCaptureVideoOrientation = .portrait
    var captureOrientation: AVCaptureVideoOrientation {
        get {
            assertIsOnSessionQueue()
            return _captureOrientation
        }
        set {
            assertIsOnSessionQueue()
            _captureOrientation = newValue
        }
    }

    private var motionManager: CMMotionManager?

    func updateVideoPreviewConnection(toOrientation orientation: AVCaptureVideoOrientation) {
        guard let videoConnection = previewView.previewLayer.connection else {
            Logger.info("previewView hasn't completed setup yet.")
            return
        }
        videoConnection.videoOrientation = orientation
    }

    // Outputs initial orientation.
    private func beginObservingOrientationChanges() -> AVCaptureVideoOrientation? {
        guard motionManager == nil else { return nil }

        let motionManager = CMMotionManager()
        motionManager.accelerometerUpdateInterval = 0.2
        motionManager.gyroUpdateInterval = 0.2
        self.motionManager = motionManager

        // Update the value immediately as the observation doesn't emit until it changes.
        let initialOrientation: AVCaptureVideoOrientation
        if let accelerometerOrientation = motionManager.accelerometerData?.acceleration.deviceOrientation {
            initialOrientation = accelerometerOrientation
        } else if let deviceOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) {
            initialOrientation = deviceOrientation
        } else {
            initialOrientation = .portrait
        }

        motionManager.startAccelerometerUpdates(
            to: OperationQueue.current!,
            withHandler: { [weak self] accelerometerData, error in
                if let orientation = accelerometerData?.acceleration.deviceOrientation {
                    self?.updateOrientation(orientation)
                } else if let error = error {
                    Logger.debug("Photo capture accelerometer error: \(error)")
                }
            }
        )

        return initialOrientation
    }

    private func updateOrientation(_ orientation: AVCaptureVideoOrientation) {
        sessionQueue.async {
            guard orientation != self.captureOrientation else {
                return
            }
            self.captureOrientation = orientation

            DispatchQueue.main.async {
                self.delegate?.cameraCaptureSession(self, didChangeOrientation: orientation)
            }
        }
    }

    // MARK: - Camera Device Information

    private lazy var availableRearVideoCaptureDeviceMap: [AVCaptureDevice.DeviceType: AVCaptureDevice] = {
        return CameraCaptureSession.availableVideoCaptureDevices(forPosition: .back)
    }()

    private lazy var availableFrontVideoCaptureDeviceMap: [AVCaptureDevice.DeviceType: AVCaptureDevice] = {
        return CameraCaptureSession.availableVideoCaptureDevices(forPosition: .front)
    }()

    private class func availableVideoCaptureDevices(forPosition position: AVCaptureDevice.Position) -> [AVCaptureDevice.DeviceType: AVCaptureDevice] {
        var queryDeviceTypes: [AVCaptureDevice.DeviceType] = [ .builtInWideAngleCamera, .builtInTelephotoCamera, .builtInDualCamera ]
        queryDeviceTypes.append(contentsOf: [ .builtInUltraWideCamera, .builtInDualWideCamera, .builtInTripleCamera ])
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: queryDeviceTypes, mediaType: .video, position: position)
        let deviceMap = session.devices.reduce(into: [AVCaptureDevice.DeviceType: AVCaptureDevice]()) { deviceMap, device in
            deviceMap[device.deviceType] = device
        }
        return deviceMap
    }

    private func availableVideoCaptureDeviceTypes(forPosition position: AVCaptureDevice.Position) -> [AVCaptureDevice.DeviceType] {
        switch position {
        case .front, .unspecified:
            return Array(availableFrontVideoCaptureDeviceMap.keys)

        case .back:
            return Array(availableRearVideoCaptureDeviceMap.keys)

        @unknown default:
            owsFailDebug("Unknown AVCaptureDevice.Position: [\(position)]")
            return []
        }
    }

    private func cameraSwitchOverZoomFactors(forPosition position: AVCaptureDevice.Position) -> [CGFloat] {
        let deviceMap = position == .front ? availableFrontVideoCaptureDeviceMap : availableRearVideoCaptureDeviceMap

        if let multiCameraDevice = deviceMap[.builtInTripleCamera] ?? deviceMap[.builtInDualWideCamera] ?? deviceMap[.builtInDualCamera] {
            return multiCameraDevice.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        }
        return []
    }

    // MARK: - Camera Selection

    // Order must be the same as it appears in the in-app camera UI.
    enum CameraType: Comparable {
        case ultraWide
        case wideAngle
        case telephoto
    }

    enum CameraSystem {
        case wide       // Single-camera devices.
        case dual       // W + T
        case dualWide   // UW + W
        case triple     // UW + W + T
    }

    private func availableCameras(forPosition position: AVCaptureDevice.Position) -> Set<CameraType> {
        let avTypes = availableVideoCaptureDeviceTypes(forPosition: position)
        var cameras: Set<CameraType> = []

        // AVCaptureDevice.DiscoverySession returns devices in an arbitrary order, explicit ordering is required
        if avTypes.contains(.builtInUltraWideCamera) {
            cameras.insert(.ultraWide)
        }

        if avTypes.contains(.builtInWideAngleCamera) {
            cameras.insert(.wideAngle)
        }

        if avTypes.contains(.builtInTelephotoCamera) {
            cameras.insert(.telephoto)
        }

        return cameras
    }

    private func defaultVideoCaptureDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        guard let devices: [AVCaptureDevice.DeviceType: AVCaptureDevice] = {
            switch position {
            case .front, .unspecified:
                return availableFrontVideoCaptureDeviceMap

            case .back:
                return availableRearVideoCaptureDeviceMap

            @unknown default:
                owsFailDebug("Unknown AVCaptureDevice.Position: [\(position)]")
                return nil
            }
        }() else { return nil }

        if let device = devices[.builtInTripleCamera] {
            return device
        }
        if let device = devices[.builtInDualWideCamera] {
            return device
        }
        return devices[.builtInDualCamera] ?? devices[.builtInWideAngleCamera]
    }

    private(set) var desiredPosition: AVCaptureDevice.Position = .back

    func switchCameraPosition() -> Promise<Void> {
        AssertIsOnMainThread()
        let newPosition: AVCaptureDevice.Position
        switch desiredPosition {
        case .front:
            newPosition = .back

        case .back, .unspecified:
            newPosition = .front

        @unknown default:
            owsFailDebug("Unexpected enum value.")
            newPosition = .front
        }
        desiredPosition = newPosition

        return sessionQueue.async(.promise) { [weak self] in
            guard let self = self else { return }

            self.avCaptureSession.beginConfiguration()
            defer { self.avCaptureSession.commitConfiguration() }
            try self.reconfigureVideoCaptureInput()
        }
    }

    func switchCamera(to camera: CameraType, at position: AVCaptureDevice.Position, animated: Bool) {
        AssertIsOnMainThread()

        owsAssertDebug(position == desiredPosition, "Attempt to select camera for incorrect position")

        let cameraZoomFactorMap = cameraZoomFactorMap(forPosition: position)
        guard let visibleZoomFactor = cameraZoomFactorMap[camera] else {
            owsFailDebug("Requested an unsupported device type")
            return
        }

        var zoomFactor = visibleZoomFactor / cameraZoomFactorMultiplier(forPosition: position)

        // Tap on 1x changes zoom to 2x if there's only one rear camera available.
        let availableCameras = availableCameras(forPosition: position)
        if availableCameras.count == 1, zoomFactor == videoCaptureDevice?.videoZoomFactor {
            zoomFactor *= 2
        }
        updateZoomFactor(zoomFactor, animated: animated)
    }

    // MARK: - Zoom

    private func minVisibleVideoZoom(forDevice device: AVCaptureDevice) -> CGFloat {
        if availableCameras(forPosition: device.position).contains(.ultraWide) {
            return 0.5
        }
        return 1
    }

    // 5x of the "zoom factor" of the camera with the longest focal length
    private func maximumZoomFactor(forDevice device: AVCaptureDevice) -> CGFloat {
        let devicePosition = device.position
        let cameraZoomFactorMap = cameraZoomFactorMap(forPosition: devicePosition)
        let maxVisibleZoomFactor = 5 * (cameraZoomFactorMap.values.max() ?? 1)
        return maxVisibleZoomFactor / cameraZoomFactorMultiplier(forPosition: devicePosition)
    }

    func cameraZoomFactorMap(forPosition position: AVCaptureDevice.Position) -> [CameraType: CGFloat] {
        let zoomFactors = cameraSwitchOverZoomFactors(forPosition: position)
        let avTypes = availableVideoCaptureDeviceTypes(forPosition: position)
        let cameraZoomFactorMultiplier = cameraZoomFactorMultiplier(forPosition: position)

        var cameraMap: [CameraType: CGFloat] = [:]
        if avTypes.contains(.builtInUltraWideCamera) {
            owsAssertDebug(cameraZoomFactorMultiplier != 1, "cameraZoomFactorMultiplier could not be 1 because there's UW camera available.")
            cameraMap[.ultraWide] = cameraZoomFactorMultiplier
        }
        if avTypes.contains(.builtInTelephotoCamera), let lastZoomFactor = zoomFactors.last {
            cameraMap[.telephoto] = cameraZoomFactorMultiplier * lastZoomFactor
        }
        if !Platform.isSimulator {
            owsAssertDebug(avTypes.contains(.builtInWideAngleCamera))
        }
        cameraMap[.wideAngle] = 1 // wide angle is the default camera used with 1x zoom.

        return cameraMap
    }

    // If device has an ultra-wide camera then API zoom factor of "1" means
    // full FOV of the ultra-wide camera which is "0.5" in the UI.
    private func cameraZoomFactorMultiplier(forPosition position: AVCaptureDevice.Position) -> CGFloat {
        if availableCameras(forPosition: position).contains(.ultraWide) {
            return 0.5
        }
        return 1
    }

    func changeVisibleZoomFactor(to visibleZoomFactor: CGFloat, animated: Bool) {
        let zoomFactor = visibleZoomFactor / cameraZoomFactorMultiplier(forPosition: desiredPosition)
        updateZoomFactor(zoomFactor, animated: animated)
    }

    private func updateZoomFactor(_ zoomFactor: CGFloat, animated: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let captureDevice = self.videoCaptureDevice else {
                owsFailDebug("captureDevice was unexpectedly nil")
                return
            }
            self.update(captureDevice: captureDevice, zoomFactor: zoomFactor, animated: animated)
        }
    }

    private func resetCameraZoomFactor(_ captureDevice: AVCaptureDevice) {
        assertIsOnSessionQueue()

        let devicePosition = captureDevice.position

        guard let defaultZoomFactor = cameraZoomFactorMap(forPosition: devicePosition)[.wideAngle] else {
            owsFailDebug("Requested an unsupported device type")
            return
        }

        let zoomFactor = defaultZoomFactor / cameraZoomFactorMultiplier(forPosition: devicePosition)
        update(captureDevice: captureDevice, zoomFactor: zoomFactor, animated: false)
    }

    private var initialSlideZoomFactor: CGFloat?

    func updateZoom(alpha: CGFloat) {
        owsAssertDebug(alpha >= 0 && alpha <= 1)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let captureDevice = self.videoCaptureDevice else {
                owsFailDebug("captureDevice was unexpectedly nil")
                return
            }

            let zoomFactor = CGFloatLerp(self.initialSlideZoomFactor!, self.maximumZoomFactor(forDevice: captureDevice), alpha)
            self.update(captureDevice: captureDevice, zoomFactor: zoomFactor)
        }
    }

    private var initialPinchZoomFactor: CGFloat = 1.0

    func beginPinchZoom() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let captureDevice = self.videoCaptureDevice else {
                owsFailDebug("captureDevice was unexpectedly nil")
                return
            }

            self.initialPinchZoomFactor = captureDevice.videoZoomFactor
            Logger.debug("began pinch zoom with factor: \(self.initialPinchZoomFactor)")
        }
    }

    func updatePinchZoom(withScale scale: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let captureDevice = self.videoCaptureDevice else {
                owsFailDebug("captureDevice was unexpectedly nil")
                return
            }

            let zoomFactor = scale * self.initialPinchZoomFactor
            self.update(captureDevice: captureDevice, zoomFactor: zoomFactor)
        }
    }

    func completePinchZoom(withScale scale: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let captureDevice = self.videoCaptureDevice else {
                owsFailDebug("captureDevice was unexpectedly nil")
                return
            }

            let zoomFactor = scale * self.initialPinchZoomFactor
            self.update(captureDevice: captureDevice, zoomFactor: zoomFactor)
            Logger.debug("ended pitch zoom with factor: \(zoomFactor)")
        }
    }

    private func update(captureDevice: AVCaptureDevice, zoomFactor: CGFloat, animated: Bool = false) {
        assertIsOnSessionQueue()

        do {
            try captureDevice.lockForConfiguration()

            let devicePosition = captureDevice.position
            let zoomFactorMultiplier = cameraZoomFactorMultiplier(forPosition: devicePosition)

            let minimumZoomFactor = minVisibleVideoZoom(forDevice: captureDevice) / zoomFactorMultiplier
            let clampedZoomFactor = min(zoomFactor.clamp(minimumZoomFactor, maximumZoomFactor(forDevice: captureDevice)), captureDevice.activeFormat.videoMaxZoomFactor)
            if animated {
                captureDevice.ramp(toVideoZoomFactor: clampedZoomFactor, withRate: 16)
            } else {
                captureDevice.videoZoomFactor = clampedZoomFactor
            }

            captureDevice.unlockForConfiguration()

            let visibleZoomFactor = clampedZoomFactor * zoomFactorMultiplier
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.cameraCaptureSession(self, didChangeZoomFactor: visibleZoomFactor, forCameraPosition: devicePosition)
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    // MARK: - Photo Capture

    private func takePhoto() {
        Logger.verbose("")
        AssertIsOnMainThread()

        guard let delegate else { return }

        guard delegate.cameraCaptureSessionCanCaptureMoreItems(self) else {
            delegate.photoCaptureDidTryToCaptureTooMany(self)
            return
        }

        ImpactHapticFeedback.impactOccurred(style: .medium)

        let previewLayer = previewView.previewLayer
        let captureRect = previewLayer.metadataOutputRectConverted(fromLayerRect: previewLayer.bounds)
        delegate.cameraCaptureSessionDidStart(self)
        sessionQueue.async {
            self.photoCapture.takePhoto(delegate: self, captureOrientation: self.captureOrientation, captureRect: captureRect)
        }
    }

    // MARK: - Video Capture

    private enum VideoRecordingState: Equatable {
        case ready
        case started
        case stopping
        case canceling
    }
    private var _videoRecordingState: VideoRecordingState = .ready
    private var videoRecordingState: VideoRecordingState {
        get {
            AssertIsOnMainThread()
            return _videoRecordingState
        }
        set {
            AssertIsOnMainThread()
            Logger.verbose("videoRecordingState: [\(_videoRecordingState)] -> [\(newValue)]")
            _videoRecordingState = newValue
        }
    }

    private func videoAspectRatio() -> CGFloat {
        AssertIsOnMainThread()
        let size = UIScreen.main.bounds.size
        let screenAspect: CGFloat
        if size.width == 0 || size.height == 0 {
            screenAspect = 0
        } else if size.width > size.height {
            screenAspect = size.height / size.width
        } else {
            screenAspect = size.width / size.height
        }
        return screenAspect.clamp(9/16, 3/4)
    }

    private func startVideoRecording() {
        AssertIsOnMainThread()
        Logger.verbose("")

        guard videoRecordingState == .ready else {
            owsFailBeta("Invalid recording state: \(videoRecordingState)")
            return
        }

        guard let delegate = delegate else { return }
        guard delegate.cameraCaptureSessionCanCaptureMoreItems(self) else {
            delegate.photoCaptureDidTryToCaptureTooMany(self)
            return
        }

        videoRecordingState = .started
        delegate.cameraCaptureSessionWillStartVideoRecording(self)

        let aspectRatio = videoAspectRatio()
        let videoCapture = videoCapture
        sessionQueue.async {
            self.setTorchMode(self.flashMode.toTorchMode)

            let audioCaptureStarted = self.startAudioCapture()
            let captureOrientation = self.captureOrientation

            do {
                try videoCapture.beginRecording(
                    captureOrientation: captureOrientation,
                    aspectRatio: aspectRatio,
                    includeAudio: audioCaptureStarted
                )
            } catch {
                DispatchQueue.main.async {
                    self.handleVideoCaptureError(error)
                }
                self.cleanUpAfterVideoRecording()
            }
        }
    }

    private func stopVideoRecording() {
        guard videoRecordingState == .started else {
            owsFailBeta("Invalid recording state: \(videoRecordingState)")
            return
        }

        Logger.verbose("")
        BenchEventStart(title: "Video Processing", eventId: "Video Processing")

        videoRecordingState = .stopping

        videoCapture.stopRecording()
    }

    private func cancelVideoRecording() {
        guard videoRecordingState == .started else {
            owsFailBeta("Invalid recording state: \(videoRecordingState)")
            return
        }

        Logger.verbose("")

        videoRecordingState = .canceling
        videoCapture.stopRecording()
    }

    private func handleVideoRecording(at outputUrl: URL) {
        AssertIsOnMainThread()

        guard let delegate else { return }

        // TODO: showing an error here feels bad; maybe break the
        // video up into segments like we do for stories. For now
        // this is better than the old behavior (fail silently).
        guard OWSMediaUtils.isVideoOfValidSize(path: outputUrl.path) else {
            return handleVideoCaptureError(PhotoCaptureError.videoTooLarge)
        }

        guard OWSMediaUtils.isValidVideo(path: outputUrl.path) else {
            return handleVideoCaptureError(PhotoCaptureError.invalidVideo)
        }
        guard let dataSource = try? DataSourcePath.dataSource(with: outputUrl, shouldDeleteOnDeallocation: true) else {
            return handleVideoCaptureError(PhotoCaptureError.captureFailed)
        }

        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeMPEG4 as String)
        BenchEventComplete(eventId: "Video Processing")
        delegate.cameraCaptureSession(self, didFinishProcessing: attachment)
    }

    private func handleVideoCaptureError(_ error: Error) {
        AssertIsOnMainThread()

        switch error {
        case PhotoCaptureError.invalidVideo, PhotoCaptureError.videoTooLarge:
            Logger.warn("Error: \(error)")
        default:
            owsFailDebug("Error: \(error)")
        }

        delegate?.cameraCaptureSession(self, didFailWith: error)
    }

    private func cleanUpAfterVideoRecording() {
        Logger.debug("")

        assertIsOnSessionQueue()

        setTorchMode(.off)
        stopAudioCapture()

        DispatchQueue.main.async {
            self.videoRecordingState = .ready
            self.delegate?.cameraCaptureSessionDidStopVideoRecording(self)
        }
    }

    private func setTorchMode(_ mode: AVCaptureDevice.TorchMode) {
        assertIsOnSessionQueue()

        guard let captureDevice = videoCaptureDevice, captureDevice.hasTorch, captureDevice.isTorchModeSupported(mode) else { return }
        do {
            try captureDevice.lockForConfiguration()
            captureDevice.torchMode = mode
            captureDevice.unlockForConfiguration()
        } catch {
            owsFailDebug("Error setting torchMode: \(error)")
        }
    }

    // MARK: - Audio Recording Stack

    private let recordingAudioActivity = AudioActivity(audioDescription: "VideoCapture", behavior: .playAndRecord)

    private func startAudioCapture() -> Bool {
        assertIsOnSessionQueue()

        // This check will fail if we do not have recording permissions.
        guard audioSession.startAudioActivity(recordingAudioActivity) else {
            Logger.warn("Unable to start recording audio activity!")
            return false
        }

        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            Logger.warn("Missing audio capture device!")
            return false
        }

        // NOTE: No need to call `beginConfiguration`/`commitConfiguration` when adding input.
        do {
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
            guard audioCaptureSession.canAddInput(audioDeviceInput) else {
                owsFailBeta("Could not add audio device input to the session")
                return false
            }
            audioCaptureSession.addInput(audioDeviceInput)
            self.audioCaptureInput = audioDeviceInput
        } catch let error {
            Logger.warn("Failed to create audioDeviceInput: \(error)")
            return false
        }

        return true
    }

    private func stopAudioCapture() {
        assertIsOnSessionQueue()

        guard let audioCaptureInput else {
            Logger.warn("audioCaptureInput was nil - recording permissions may have been disabled?")
            return
        }

        // NOTE: No need to call `beginConfiguration`/`commitConfiguration` when removing an input.
        audioCaptureSession.removeInput(audioCaptureInput)
        self.audioCaptureInput = nil

        audioSession.endAudioActivity(recordingAudioActivity)
    }
}

// MARK: -
extension CameraCaptureSession: VideoCaptureDelegate {

    fileprivate func videoCaptureDidStartRecording(_ videoCapture: VideoCapture) {
        AssertIsOnMainThread()
        delegate?.cameraCaptureSessionDidStartVideoRecording(self)
    }

    fileprivate func videoCaptureWillStopRecording(_ videoCapture: VideoCapture) {
        AssertIsOnMainThread()
        // Proper state might not be set if recording is stopped not by user.
        if videoRecordingState == .started {
            videoRecordingState = .stopping
        }
    }

    fileprivate func videoCapture(_ videoCapture: VideoCapture, didUpdateRecordingDuration duration: TimeInterval) {
        AssertIsOnMainThread()
        delegate?.cameraCaptureSession(self, videoRecordingDurationChanged: duration)
    }

    fileprivate func videoCapture(_ videoCapture: VideoCapture, didFinishWith result: Result<URL, Error>) {
        AssertIsOnMainThread()
        Logger.verbose("Video recording ended with result: \(result)")

        switch result {
        case .success(let outputURL):
            if videoRecordingState != .canceling {
                handleVideoRecording(at: outputURL)
            }

        case .failure(let error):
            handleVideoCaptureError(error)
        }

        sessionQueue.async {
            self.cleanUpAfterVideoRecording()
        }
    }
}

// MARK: -

extension CameraCaptureSession: PhotoCaptureDelegate {

    fileprivate func photoCaptureDidProduce(result: Result<Data, Error>) {
        Logger.verbose("")
        AssertIsOnMainThread()
        guard let delegate = delegate else { return }

        switch result {
        case .failure(let error):
            delegate.cameraCaptureSession(self, didFailWith: error)
        case .success(let photoData):
            let dataSource = DataSourceValue.dataSource(with: photoData, utiType: kUTTypeJPEG as String)

            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeJPEG as String)
            delegate.cameraCaptureSession(self, didFinishProcessing: attachment)
        }
    }
}

// MARK: -

class CapturePreviewView: UIView {

    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
        }
        return layer
    }

    override var contentMode: UIView.ContentMode {
        get {
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

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        previewLayer.session = session
        if Platform.isSimulator {
            // helpful for debugging layout on simulator which has no real capture device
            previewLayer.backgroundColor = UIColor.green.withAlphaComponent(0.4).cgColor
        }
        contentMode = .scaleAspectFill
    }

    @available(*, unavailable, message: "Use init(session:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: -

extension CameraCaptureSession: VolumeButtonObserver {

    func didPressVolumeButton(with identifier: VolumeButtons.Identifier) {
        delegate?.beginCaptureButtonAnimation(0.5)
    }

    func didReleaseVolumeButton(with identifier: VolumeButtons.Identifier) {
        delegate?.endCaptureButtonAnimation(0.2)
    }

    func didTapVolumeButton(with identifier: VolumeButtons.Identifier) {
        takePhoto()
    }

    func didBeginLongPressVolumeButton(with identifier: VolumeButtons.Identifier) {
        startVideoRecording()
    }

    func didCompleteLongPressVolumeButton(with identifier: VolumeButtons.Identifier) {
        stopVideoRecording()
    }

    func didCancelLongPressVolumeButton(with identifier: VolumeButtons.Identifier) {
        cancelVideoRecording()
    }
}

// MARK: -

extension CameraCaptureSession: CameraCaptureControlDelegate {

    func cameraCaptureControlDidRequestCapturePhoto(_ control: CameraCaptureControl) {
        takePhoto()
    }

    func cameraCaptureControlDidRequestStartVideoRecording(_ control: CameraCaptureControl) {
        if let videoCaptureDevice {
            initialSlideZoomFactor = videoCaptureDevice.videoZoomFactor
        }
        startVideoRecording()
    }

    func cameraCaptureControlDidRequestFinishVideoRecording(_ control: CameraCaptureControl) {
        stopVideoRecording()
    }

    func cameraCaptureControlDidRequestCancelVideoRecording(_ control: CameraCaptureControl) {
        cancelVideoRecording()
    }

    func didPressStopCaptureButton(_ control: CameraCaptureControl) {
        stopVideoRecording()
    }

    var zoomScaleReferenceDistance: CGFloat? {
        return delegate?.zoomScaleReferenceDistance
    }

    func cameraCaptureControl(_ control: CameraCaptureControl, didUpdateZoomLevel zoomLevel: CGFloat) {
        owsAssertDebug(initialSlideZoomFactor != nil, "initialSlideZoomFactor is not set")
        updateZoom(alpha: zoomLevel)
    }
}

// MARK: -

private protocol VideoCaptureDelegate: AnyObject {

    func videoCaptureDidStartRecording(_ videoCapture: VideoCapture)
    func videoCaptureWillStopRecording(_ videoCapture: VideoCapture)
    func videoCapture(_ videoCapture: VideoCapture, didUpdateRecordingDuration duration: TimeInterval)
    func videoCapture(_ videoCapture: VideoCapture, didFinishWith result: Result<URL, Error>)
}

private class VideoCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    let videoDataOutput = AVCaptureVideoDataOutput()
    let audioDataOutput = AVCaptureAudioDataOutput()

    private static let videoCaptureQueue = DispatchQueue(label: "org.signal.capture.video", qos: .userInteractive)
    private var videoCaptureQueue: DispatchQueue { VideoCapture.videoCaptureQueue }

    private static let audioCaptureQueue = DispatchQueue(label: "org.signal.capture.audio", qos: .userInteractive)
    private var audioCaptureQueue: DispatchQueue { VideoCapture.audioCaptureQueue }

    private let recordingQueue = DispatchQueue(label: "org.signal.capture.recording", qos: .userInteractive)

    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?

    private var isAssetWriterSessionStarted = false
    private var isAssetWriterAcceptingSampleBuffers = AtomicBool(false)
    private var needsFinishAssetWriterSession = false

    weak var delegate: VideoCaptureDelegate?

    private let videoSampleTimeLock = UnfairLock()
    private var timeOfFirstAppendedVideoSampleBuffer = CMTime.invalid
    private var timeOfLastAppendedVideoSampleBuffer = CMTime.invalid

    override init() {
        super.init()

        videoDataOutput.alwaysDiscardsLateVideoFrames = false
        videoDataOutput.setSampleBufferDelegate(self, queue: videoCaptureQueue)
        audioDataOutput.setSampleBufferDelegate(self, queue: audioCaptureQueue)
    }

    func beginRecording(
        captureOrientation: AVCaptureVideoOrientation,
        aspectRatio: CGFloat,
        includeAudio: Bool
    ) throws {
        Logger.verbose("")

        guard let videoConnection = videoDataOutput.connection(with: .video) else {
            throw OWSAssertionError("videoConnection was unexpectedly nil")
        }
        videoConnection.videoOrientation = captureOrientation

        let outputURL = OWSFileSystem.temporaryFileUrl(fileExtension: "mp4")
        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        guard var videoSettings = videoDataOutput.recommendedVideoSettings(
            forVideoCodecType: .h264,
            assetWriterOutputFileType: .mp4
        ) else {
            throw OWSAssertionError("videoSettings was unexpectedly nil")
        }
        guard
            let capturedWidth: CGFloat = videoSettings[AVVideoWidthKey] as? CGFloat,
            let capturedHeight: CGFloat = videoSettings[AVVideoHeightKey] as? CGFloat
        else {
            throw OWSAssertionError("video dimensions were unexpectedly nil")
        }
        let capturedSize = CGSize(width: capturedWidth, height: capturedHeight)
        let aspectSize = capturedSize.cropped(toAspectRatio: aspectRatio)
        let outputSize = aspectSize.scaledToFit(max: 1280) // 720p

        // video specs from Signal-Android: 2Mbps video 192K audio, 720P 30 FPS
        let customSettings: [String: Any] = [
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2000000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264Baseline41,
                AVVideoMaxKeyFrameIntervalKey: 90
            ]
        ]
        videoSettings.merge(customSettings) { $1 }

        guard assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw PhotoCaptureError.initializationFailed
        }

        Logger.info("videoOrientation: \(captureOrientation), captured: \(capturedWidth)x\(capturedHeight), output: \(outputSize.width)x\(outputSize.height), aspectRatio: \(aspectRatio)")

        let videoWriterInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings,
            sourceFormatHint: nil
        )
        videoWriterInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(videoWriterInput) else {
            throw PhotoCaptureError.initializationFailed
        }
        assetWriter.add(videoWriterInput)
        self.videoWriterInput = videoWriterInput

        if includeAudio {
            guard
                let audioSettings = audioDataOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4),
                assetWriter.canApply(outputSettings: audioSettings, forMediaType: .audio)
            else {
                throw PhotoCaptureError.initializationFailed
            }
            let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioWriterInput.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(audioWriterInput) else {
                throw PhotoCaptureError.initializationFailed
            }
            assetWriter.add(audioWriterInput)
            self.audioWriterInput = audioWriterInput
        } else {
            Logger.info("Not including audio.")
        }

        guard assetWriter.startWriting() else {
            throw PhotoCaptureError.initializationFailed
        }
        self.assetWriter = assetWriter

        isAssetWriterAcceptingSampleBuffers.set(true)
    }

    func stopRecording() {
        Logger.verbose("")
        AssertIsOnMainThread()

        // Make video recording at least 1 second long.
        let duration = durationOfCurrentRecording
        let recordedDurationSeconds: TimeInterval = duration.isValid ? duration.seconds : 0
        let timeExtension: TimeInterval = max(0, 1 - recordedDurationSeconds)
        recordingQueue.asyncAfter(deadline: .now() + timeExtension) {
            self.needsFinishAssetWriterSession = true
        }
    }

    var durationOfCurrentRecording: CMTime {
        videoSampleTimeLock.lock()
        let timeOfFirstAppendedVideoSampleBuffer = timeOfFirstAppendedVideoSampleBuffer
        let timeOfLastAppendedVideoSampleBuffer = timeOfLastAppendedVideoSampleBuffer
        videoSampleTimeLock.unlock()

        guard timeOfFirstAppendedVideoSampleBuffer.isValid, timeOfLastAppendedVideoSampleBuffer.isValid else {
            return .zero
        }
        return CMTimeSubtract(timeOfLastAppendedVideoSampleBuffer, timeOfFirstAppendedVideoSampleBuffer)
    }

    private func finishAssetWriterSession() {
        guard let assetWriter else {
            owsFailBeta("assetWriter is nil")
            return
        }

        isAssetWriterAcceptingSampleBuffers.set(false)

        videoSampleTimeLock.lock()
        let timeOfLastAppendedVideoSampleBuffer = timeOfLastAppendedVideoSampleBuffer
        videoSampleTimeLock.unlock()

        // Prevent assetWriter.startSession() from being called if for some reason it wasn't called yet.
        isAssetWriterSessionStarted = true

        if timeOfLastAppendedVideoSampleBuffer.isValid {
            assetWriter.endSession(atSourceTime: timeOfLastAppendedVideoSampleBuffer)
        } else {
            owsFailDebug("No timeOfLastAppendedVideoSampleBuffer")
        }

        assetWriter.finishWriting {
            self.recordingQueue.async {
                let result: Result<URL, Error>
                if assetWriter.status == .completed && assetWriter.error == nil {
                    result = .success(assetWriter.outputURL)
                } else {
                    result = .failure(PhotoCaptureError.invalidVideo)
                }
                DispatchQueue.main.async {
                    self.delegate?.videoCapture(self, didFinishWith: result)
                }

                self.cleanUp()
            }
        }
    }

    private func append(sampleBuffer: CMSampleBuffer, to assetWriterInput: AVAssetWriterInput) {
        guard let assetWriter else {
            owsFailBeta("assetWriter is nil")
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !isAssetWriterSessionStarted && assetWriterInput == videoWriterInput {
            assetWriter.startSession(atSourceTime: presentationTime)
            isAssetWriterSessionStarted = true
            DispatchQueue.main.async {
                self.delegate?.videoCaptureDidStartRecording(self)
            }
        }

        let acceptingSampleBuffers = isAssetWriterAcceptingSampleBuffers.get()
        guard acceptingSampleBuffers && isAssetWriterSessionStarted else {
            Logger.verbose("Not accepting sample buffers at the moment.")
            return
        }
        guard assetWriterInput.isReadyForMoreMediaData else {
            Logger.verbose("Input not ready for more media data")
            return
        }

        guard assetWriterInput.append(sampleBuffer) else {
            Logger.error("Input failed to append sample buffer.")
            needsFinishAssetWriterSession = true
            return
        }

        if assetWriterInput == videoWriterInput {
            videoSampleTimeLock.lock()
            timeOfLastAppendedVideoSampleBuffer = presentationTime
            if !timeOfFirstAppendedVideoSampleBuffer.isValid {
                timeOfFirstAppendedVideoSampleBuffer = presentationTime
            }
            videoSampleTimeLock.unlock()

            let recordingDuration = self.durationOfCurrentRecording.seconds
            DispatchQueue.main.async {
                self.delegate?.videoCapture(self, didUpdateRecordingDuration: recordingDuration)
            }
        }

        if needsFinishAssetWriterSession {
            DispatchQueue.main.async {
                self.delegate?.videoCaptureWillStopRecording(self)
            }
            finishAssetWriterSession()
            needsFinishAssetWriterSession = false
            return
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isAssetWriterAcceptingSampleBuffers.get() else {
            return
        }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            owsFailDebug("Failed to get format description")
            return
        }
        let mediaType = CMFormatDescriptionGetMediaType(formatDescription)

        recordingQueue.async {
            if mediaType == kCMMediaType_Video, let videoWriterInput = self.videoWriterInput {
                self.append(sampleBuffer: sampleBuffer, to: videoWriterInput)
            } else if mediaType == kCMMediaType_Audio, let audioWriterInput = self.audioWriterInput {
                self.append(sampleBuffer: sampleBuffer, to: audioWriterInput)
            } else {
                owsFailDebug("Unknown output for media type [\(mediaType)]")
                self.needsFinishAssetWriterSession = true
            }
        }
    }

    private func cleanUp() {
        assetWriter = nil
        videoWriterInput = nil
        audioWriterInput = nil
        isAssetWriterSessionStarted = false
        videoSampleTimeLock.lock()
        timeOfFirstAppendedVideoSampleBuffer = .invalid
        timeOfLastAppendedVideoSampleBuffer = .invalid
        videoSampleTimeLock.unlock()
    }
}

// MARK: -

private protocol PhotoCaptureDelegate: AnyObject {

    func photoCaptureDidProduce(result: Result<Data, Error>)
}

private class PhotoCapture: NSObject {

    let avCaptureOutput = AVCapturePhotoOutput()

    var flashMode: AVCaptureDevice.FlashMode = .off

    override init() {
        super.init()

        avCaptureOutput.isLivePhotoCaptureEnabled = false
        avCaptureOutput.isHighResolutionCaptureEnabled = true
    }

    private var photoProcessors: [Int64: PhotoProcessor] = [:]

    func takePhoto(delegate: PhotoCaptureDelegate, captureOrientation: AVCaptureVideoOrientation, captureRect: CGRect) {
        guard let avCaptureConnection = avCaptureOutput.connection(with: .video) else {
            owsFailBeta("photoVideoConnection was unexpectedly nil")
            return
        }

        avCaptureConnection.videoOrientation = captureOrientation
        Logger.verbose("photoOrientation: \(captureOrientation), deviceOrientation: \(UIDevice.current.orientation)")

        let photoSettings = AVCapturePhotoSettings()
        photoSettings.flashMode = flashMode
        photoSettings.isHighResolutionPhotoEnabled = true

        let photoProcessor = PhotoProcessor(delegate: delegate, captureRect: captureRect) { [weak self] in
            self?.photoProcessors[photoSettings.uniqueID] = nil
        }
        photoProcessors[photoSettings.uniqueID] = photoProcessor

        avCaptureOutput.capturePhoto(with: photoSettings, delegate: photoProcessor)
    }

    private class PhotoProcessor: NSObject, AVCapturePhotoCaptureDelegate {
        private weak var delegate: PhotoCaptureDelegate?
        private let captureRect: CGRect
        private let completion: () -> Void

        init(delegate: PhotoCaptureDelegate, captureRect: CGRect, completion: @escaping () -> Void) {
            self.delegate = delegate
            self.captureRect = captureRect
            self.completion = completion
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            defer { completion() }

            guard let delegate = delegate else { return }

            let result: Result<Data, Error>
            do {
                if let error {
                    throw error
                }
                guard let rawData = photo.fileDataRepresentation()  else {
                    throw OWSAssertionError("photo data was unexpectedly empty")
                }

                let resizedData = try crop(photoData: rawData, to: captureRect)
                result = .success(resizedData)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                delegate.photoCaptureDidProduce(result: result)
            }
        }

        private func crop(photoData: Data, to outputRect: CGRect) throws -> Data {
            guard
                let originalImage = UIImage(data: photoData),
                let cgImage = originalImage.cgImage
            else {
                throw OWSAssertionError("originalImage was unexpectedly nil")
            }

            guard outputRect.width > 0, outputRect.height > 0 else {
                throw OWSAssertionError("invalid outputRect: \(outputRect)")
            }

            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let cropRect = CGRect(x: outputRect.origin.x * width,
                                  y: outputRect.origin.y * height,
                                  width: outputRect.size.width * width,
                                  height: outputRect.size.height * height)
            let croppedCGImage = cgImage.cropping(to: cropRect)!
            let croppedUIImage = UIImage(cgImage: croppedCGImage, scale: 1, orientation: originalImage.imageOrientation)
            guard let croppedData = croppedUIImage.jpegData(compressionQuality: 0.9) else {
                throw OWSAssertionError("croppedData was unexpectedly nil")
            }
            return croppedData
        }
    }
}

// MARK: -

extension AVCaptureDevice.FocusMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .locked:
            return "FocusMode.locked"
        case .autoFocus:
            return "FocusMode.autoFocus"
        case .continuousAutoFocus:
            return "FocusMode.continuousAutoFocus"
        @unknown default:
            return "FocusMode.unknown"
        }
    }
}

// MARK: -

extension AVCaptureDevice.ExposureMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .locked:
            return "ExposureMode.locked"
        case .autoExpose:
            return "ExposureMode.autoExpose"
        case .continuousAutoExposure:
            return "ExposureMode.continuousAutoExposure"
        case .custom:
            return "ExposureMode.custom"
        @unknown default:
            return "ExposureMode.unknown"
        }
    }
}

// MARK: -

extension AVCaptureVideoOrientation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .portrait:
            return "AVCaptureVideoOrientation.portrait"
        case .portraitUpsideDown:
            return "AVCaptureVideoOrientation.portraitUpsideDown"
        case .landscapeRight:
            return "AVCaptureVideoOrientation.landscapeRight"
        case .landscapeLeft:
            return "AVCaptureVideoOrientation.landscapeLeft"
        @unknown default:
            return "AVCaptureVideoOrientation.unknownDefault"
        }
    }
}

// MARK: -

extension UIDeviceOrientation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "UIDeviceOrientation.unknown"
        case .portrait:
            return "UIDeviceOrientation.portrait"
        case .portraitUpsideDown:
            return "UIDeviceOrientation.portraitUpsideDown"
        case .landscapeLeft:
            return "UIDeviceOrientation.landscapeLeft"
        case .landscapeRight:
            return "UIDeviceOrientation.landscapeRight"
        case .faceUp:
            return "UIDeviceOrientation.faceUp"
        case .faceDown:
            return "UIDeviceOrientation.faceDown"
        @unknown default:
            return "UIDeviceOrientation.unknownDefault"
        }
    }
}

// MARK: -

extension UIInterfaceOrientation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "UIInterfaceOrientation.unknown"
        case .portrait:
            return "UIInterfaceOrientation.portrait"
        case .portraitUpsideDown:
            return "UIInterfaceOrientation.portraitUpsideDown"
        case .landscapeLeft:
            return "UIInterfaceOrientation.landscapeLeft"
        case .landscapeRight:
            return "UIInterfaceOrientation.landscapeRight"
        @unknown default:
            return "UIInterfaceOrientation.unknownDefault"
        }
    }
}

// MARK: -

extension UIImage.Orientation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .up:
            return "UIImageOrientation.up"
        case .down:
            return "UIImageOrientation.down"
        case .left:
            return "UIImageOrientation.left"
        case .right:
            return "UIImageOrientation.right"
        case .upMirrored:
            return "UIImageOrientation.upMirrored"
        case .downMirrored:
            return "UIImageOrientation.downMirrored"
        case .leftMirrored:
            return "UIImageOrientation.leftMirrored"
        case .rightMirrored:
            return "UIImageOrientation.rightMirrored"
        @unknown default:
            return "UIImageOrientation.unknownDefault"
        }
    }
}

// MARK: -

extension CGSize {
    func scaledToFit(max: CGFloat) -> CGSize {
        if width > height {
            if width > max {
                let scale = max / width
                return CGSize(width: max, height: height * scale)
            } else {
                return self
            }
        } else {
            if height > max {
                let scale = max / height
                return CGSize(width: width * scale, height: max)
            } else {
                return self
            }
        }
    }

    func cropped(toAspectRatio aspectRatio: CGFloat) -> CGSize {
        guard aspectRatio > 0, aspectRatio <= 1 else {
            owsFailDebug("invalid aspectRatio: \(aspectRatio)")
            return self
        }

        if width > height {
            return CGSize(width: width, height: width * aspectRatio)
        } else {
            return CGSize(width: height * aspectRatio, height: height)
        }
    }
}

// MARK: -

extension AVCaptureDevice.FlashMode {
    var toTorchMode: AVCaptureDevice.TorchMode {
        switch self {
        case .auto:
            return .auto
        case .on:
            return .on
        case .off:
            return .off
        @unknown default:
            owsFailDebug("Unhandled AVCaptureDevice.FlashMode type: \(self)")
            return .off
        }
    }
}

extension CMAcceleration {

    var deviceOrientation: AVCaptureVideoOrientation? {
        if x >= 0.75 {
            return .landscapeLeft
        } else if x <= -0.75 {
            return .landscapeRight
        } else if y <= -0.75 {
            return .portrait
        } else if y >= 0.75 {
            return .portraitUpsideDown
        } else {
            return nil
        }
    }
}
