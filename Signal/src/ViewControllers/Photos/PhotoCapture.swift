//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import CoreServices
import Foundation
import SignalCoreKit
import UIKit

enum PhotoCaptureError: Error {
    case assertionError(description: String)
    case initializationFailed
    case captureFailed
    case invalidVideo
}

extension PhotoCaptureError: LocalizedError, UserErrorDescriptionProvider {
    var localizedDescription: String {
        switch self {
        case .initializationFailed:
            return NSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_INITIALIZE_CAMERA", comment: "alert title")
        case .captureFailed:
            return NSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_CAPTURE_IMAGE", comment: "alert title")
        case .assertionError, .invalidVideo:
            return NSLocalizedString("PHOTO_CAPTURE_GENERIC_ERROR", comment: "alert title, generic error preventing user from capturing a photo")
        }
    }
}

protocol PhotoCaptureDelegate: AnyObject {

    // MARK: Still Photo

    func photoCaptureDidStart(_ photoCapture: PhotoCapture)
    func photoCapture(_ photoCapture: PhotoCapture, didFinishProcessing attachment: SignalAttachment)
    func photoCapture(_ photoCapture: PhotoCapture, didFailProcessing error: Error)

    // MARK: Video

    func photoCaptureWillBeginRecording(_ photoCapture: PhotoCapture)
    func photoCaptureDidBeginRecording(_ photoCapture: PhotoCapture)
    func photoCaptureDidFinishRecording(_ photoCapture: PhotoCapture)
    func photoCaptureDidCancelRecording(_ photoCapture: PhotoCapture)

    // MARK: Utility

    func photoCapture(_ photoCapture: PhotoCapture, didChangeOrientation: AVCaptureVideoOrientation)
    func photoCapture(_ photoCapture: PhotoCapture, didChangeVideoZoomFactor: CGFloat, forCameraPosition: AVCaptureDevice.Position)
    func photoCaptureCanCaptureMoreItems(_ photoCapture: PhotoCapture) -> Bool
    func photoCaptureDidTryToCaptureTooMany(_ photoCapture: PhotoCapture)
    var zoomScaleReferenceDistance: CGFloat? { get }

    func beginCaptureButtonAnimation(_ duration: TimeInterval)
    func endCaptureButtonAnimation(_ duration: TimeInterval)

    func photoCapture(_ photoCapture: PhotoCapture, didCompleteFocusing focusPoint: CGPoint)
}

// MARK: -

class PhotoCapture: NSObject {

    weak var delegate: PhotoCaptureDelegate?

    // There can only ever be one `CapturePreviewView` per AVCaptureSession
    lazy private(set) var previewView = CapturePreviewView(session: session)

    fileprivate static let sessionQueue = DispatchQueue(label: "PhotoCapture.sessionQueue")
    private var sessionQueue: DispatchQueue { PhotoCapture.sessionQueue }

    private var currentCaptureInput: AVCaptureDeviceInput?
    private let captureOutput: CaptureOutput
    private var captureDevice: AVCaptureDevice? {
        return currentCaptureInput?.device
    }
    private(set) var desiredPosition: AVCaptureDevice.Position = .back

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

    private let recordingAudioActivity = AudioActivity(audioDescription: "PhotoCapture", behavior: .playAndRecord)

    var focusObservation: NSKeyValueObservation?
    var deviceOrientationObserver: AnyObject?

    override init() {
        self.session = AVCaptureSession()
        self.captureOutput = CaptureOutput(session: session)
    }

    deinit {
        if let deviceOrientationObserver = deviceOrientationObserver {
            NotificationCenter.default.removeObserver(deviceOrientationObserver)
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    func didCompleteFocusing() {
        Logger.debug("")
        guard let currentCaptureInput = currentCaptureInput else {
            return
        }

        let focusPoint = currentCaptureInput.device.focusPointOfInterest

        DispatchQueue.main.async {
            self.delegate?.photoCapture(self, didCompleteFocusing: focusPoint)
        }
    }

    private var audioDeviceInput: AVCaptureDeviceInput?

    // MARK: - Public

    var flashMode: AVCaptureDevice.FlashMode {
        return captureOutput.flashMode
    }

    let session: AVCaptureSession

    func startAudioCapture() -> Bool {
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

        do {
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)

            guard session.canAddInput(audioDeviceInput) else {
                owsFailDebug("Could not add audio device input to the session")
                return false
            }

            session.addInput(audioDeviceInput)
            self.audioDeviceInput = audioDeviceInput
        } catch let error {
            Logger.warn("Failed to create audioDeviceInput: \(error)")
            return false
        }

        return true
    }

    func stopAudioCapture() {
        assertIsOnSessionQueue()

        self.session.beginConfiguration()
        defer { self.session.commitConfiguration() }

        guard let audioDeviceInput = self.audioDeviceInput else {
            Logger.warn("audioDeviceInput was nil - recording permissions may have been disabled?")
            return
        }

        session.removeInput(audioDeviceInput)
        self.audioDeviceInput = nil
        audioSession.endAudioActivity(recordingAudioActivity)
    }

    func updateVideoPreviewConnection(toOrientation orientation: AVCaptureVideoOrientation) {
        guard let videoConnection = previewView.previewLayer.connection else {
            Logger.info("previewView hasn't completed setup yet.")
            return
        }
        videoConnection.videoOrientation = orientation
    }

    func prepareVideoCapture() -> Promise<Void> {
        AssertIsOnMainThread()
        guard !Platform.isSimulator else {
            // Trying to actually set up the capture session will fail on a simulator
            // since we don't have actual capture devices. But it's useful to be able
            // to mostly run the capture code on the simulator to work with layout.
            return Promise.value(())
        }

        // If the session is already running, no need to do anything.
        guard !self.session.isRunning else { return Promise.value(()) }

        owsAssertDebug(deviceOrientationObserver == nil)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        deviceOrientationObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                                                           object: UIDevice.current,
                                                                           queue: nil) { [weak self] _ in
            guard let self = self,
                  let captureOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) else {
                return
            }

            self.sessionQueue.async {
                guard captureOrientation != self.captureOrientation else {
                    return
                }
                self.captureOrientation = captureOrientation

                DispatchQueue.main.async {
                    self.delegate?.photoCapture(self, didChangeOrientation: captureOrientation)
                }
            }
        }

        let initialCaptureOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) ?? .portrait

        return sessionQueue.async(.promise) { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            self.captureOrientation = initialCaptureOrientation
            self.session.sessionPreset = .high

            try self.reconfigureCaptureInput()

            guard let photoOutput = self.captureOutput.photoOutput else {
                owsFailDebug("Missing photoOutput.")
                throw PhotoCaptureError.initializationFailed
            }

            guard self.session.canAddOutput(photoOutput) else {
                owsFailDebug("!canAddOutput(photoOutput).")
                throw PhotoCaptureError.initializationFailed
            }
            self.session.addOutput(photoOutput)

            if let connection = photoOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }

            let videoDataOutput = self.captureOutput.videoDataOutput
            guard self.session.canAddOutput(videoDataOutput) else {
                owsFailDebug("!canAddOutput(videoDataOutput).")
                throw PhotoCaptureError.initializationFailed
            }
            self.session.addOutput(videoDataOutput)
            guard let connection = videoDataOutput.connection(with: .video) else {
                owsFailDebug("Missing videoDataOutput.connection.")
                throw PhotoCaptureError.initializationFailed
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }

            let audioDataOutput = self.captureOutput.audioDataOutput
            if self.session.canAddOutput(audioDataOutput) {
                self.session.addOutput(audioDataOutput)
            } else {
                owsFailDebug("couldn't add audioDataOutput")
            }
        }
    }

    @discardableResult
    func stopCapture() -> Guarantee<Void> {
        sessionQueue.async(.promise) { [session] in
            session.stopRunning()
        }
    }

    @discardableResult
    func resumeCapture() -> Guarantee<Void> {
        sessionQueue.async(.promise) { [session] in
            session.startRunning()
        }
    }

    func assertIsOnSessionQueue() {
        assertOnQueue(sessionQueue)
    }

    func switchCameraPosition() -> Promise<Void> {
        AssertIsOnMainThread()
        let newPosition: AVCaptureDevice.Position
        switch desiredPosition {
        case .front:
            newPosition = .back
        case .back:
            newPosition = .front
        case .unspecified:
            newPosition = .front
        @unknown default:
            owsFailDebug("Unexpected enum value.")
            newPosition = .front
        }
        desiredPosition = newPosition

        return sessionQueue.async(.promise) { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            try self.reconfigureCaptureInput()
        }
    }

    // This method should be called on the serial queue, and between calls to session.beginConfiguration/commitConfiguration
    func reconfigureCaptureInput() throws {
        assertIsOnSessionQueue()

        let avCaptureDevicePosition = desiredPosition
        let avCaptureDeviceType = avCaptureDeviceType(forCameraSystem: bestAvailableCameraSystem(forPosition: avCaptureDevicePosition))

        guard let device = captureOutput.videoDevice(for: avCaptureDeviceType, position: avCaptureDevicePosition) else {
            throw PhotoCaptureError.assertionError(description: description)
        }

        let newInput = try AVCaptureDeviceInput(device: device)

        if let oldInput = self.currentCaptureInput {
            session.removeInput(oldInput)
            NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: oldInput.device)
        }
        session.addInput(newInput)
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: newInput.device)

        if let focusObservation = focusObservation {
            focusObservation.invalidate()
        }
        self.focusObservation = newInput.observe(\.device.isAdjustingFocus,
                                                  options: [.old, .new]) { [weak self] _, change in
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

        currentCaptureInput = newInput

        // Camera by default has zoom factor of 1, which would be UW camera on triple camera systems, but default camera in the UI is "wide".
        // Also it is necessary to reset camera to "1x" when switching between front and rear to match Camera app behavior.
        resetCameraZoomFactor(device)

        resetFocusAndExposure()
    }

    func switchFlashMode() -> Guarantee<Void> {
        return sessionQueue.async(.promise) {
            switch self.captureOutput.flashMode {
            case .auto:
                Logger.debug("new flashMode: on")
                self.captureOutput.flashMode = .on
            case .on:
                Logger.debug("new flashMode: off")
                self.captureOutput.flashMode = .off
            case .off:
                Logger.debug("new flashMode: auto")
                self.captureOutput.flashMode = .auto
            @unknown default:
                owsFailDebug("unknown flashMode: \(self.captureOutput.flashMode)")
                self.captureOutput.flashMode = .auto
            }
        }
    }

    func focus(with focusMode: AVCaptureDevice.FocusMode,
               exposureMode: AVCaptureDevice.ExposureMode,
               at devicePoint: CGPoint,
               monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            Logger.debug("focusMode: \(focusMode), exposureMode: \(exposureMode), devicePoint: \(devicePoint), monitorSubjectAreaChange:\(monitorSubjectAreaChange)")
            guard let device = self.captureDevice else {
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

    @objc
    private func subjectAreaDidChange(notification: NSNotification) {
        resetFocusAndExposure()
    }

    // MARK: - Rear Camera Selection

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

    private func availableCameras(forPosition position: AVCaptureDevice.Position) -> [CameraType] {
        let avTypes = captureOutput.imageOutput.availableDeviceTypes(forPosition: position)
        var cameras: [CameraType] = []

        // AVCaptureDevice.DiscoverySession returns devices in an arbitrary order, explicit ordering is required
        if #available(iOS 13, *), avTypes.contains(.builtInUltraWideCamera) {
            cameras.append(.ultraWide)
        }

        if avTypes.contains(.builtInWideAngleCamera) {
            cameras.append(.wideAngle)
        }

        if avTypes.contains(.builtInTelephotoCamera) {
            cameras.append(.telephoto)
        }

        return cameras
    }

    private func bestAvailableCameraSystem(forPosition position: AVCaptureDevice.Position) -> CameraSystem {
        let avTypes = captureOutput.imageOutput.availableDeviceTypes(forPosition: position)

        // No iOS 12 device can have a triple camera system.
        if #available(iOS 13, *) {
            if avTypes.contains(.builtInTripleCamera) {
                return .triple
            }
            if avTypes.contains(.builtInDualWideCamera) {
                return .dualWide
            }
        }
        if avTypes.contains(.builtInDualCamera) {
            return .dual
        }
        return .wide
    }

    private func avCaptureDeviceType(forCameraSystem cameraSystem: CameraSystem) -> AVCaptureDevice.DeviceType {
        switch cameraSystem {
        case .wide:
            return .builtInWideAngleCamera

        case .dual:
            return .builtInDualCamera

        case .dualWide:
            if #available(iOS 13, *) {
                return .builtInDualWideCamera
            }
            fallthrough

        case .triple:
            if #available(iOS 13, *) {
                return .builtInTripleCamera
            }
            fallthrough

        default:
            owsFailDebug("Unsupported camera system.")
            return .builtInWideAngleCamera
        }
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
        let zoomFactors = captureOutput.imageOutput.cameraSwitchOverZoomFactors(forPosition: position)
        let avTypes = captureOutput.imageOutput.availableDeviceTypes(forPosition: position)
        let cameraZoomFactorMultiplier = cameraZoomFactorMultiplier(forPosition: position)

        var cameraMap: [CameraType: CGFloat] = [:]
        if #available(iOS 13, *), avTypes.contains(.builtInUltraWideCamera) {
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
        if availableCameras.count == 1, let currentZoomFactor = captureDevice?.videoZoomFactor, currentZoomFactor == zoomFactor {
            zoomFactor *= 2
        }
        updateZoomFactor(zoomFactor, animated: animated)
    }

    func changeVisibleZoomFactor(to visibleZoomFactor: CGFloat, animated: Bool) {
        let zoomFactor = visibleZoomFactor / cameraZoomFactorMultiplier(forPosition: desiredPosition)
        updateZoomFactor(zoomFactor, animated: animated)
    }

    private func updateZoomFactor(_ zoomFactor: CGFloat, animated: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let captureDevice = self.captureDevice else {
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
            guard let self = self else { return }
            guard let captureDevice = self.captureDevice else {
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
            guard let self = self else { return }
            guard let captureDevice = self.captureDevice else {
                owsFailDebug("captureDevice was unexpectedly nil")
                return
            }

            self.initialPinchZoomFactor = captureDevice.videoZoomFactor
            Logger.debug("began pinch zoom with factor: \(self.initialPinchZoomFactor)")
        }
    }

    func updatePinchZoom(withScale scale: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let captureDevice = self.captureDevice else {
                owsFailDebug("captureDevice was unexpectedly nil")
                return
            }

            let zoomFactor = scale * self.initialPinchZoomFactor
            self.update(captureDevice: captureDevice, zoomFactor: zoomFactor)
        }
    }

    func completePinchZoom(withScale scale: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let captureDevice = self.captureDevice else {
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
                self.delegate?.photoCapture(self, didChangeVideoZoomFactor: visibleZoomFactor, forCameraPosition: devicePosition)
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    // MARK: - Photo

    private func takePhoto() {
        Logger.verbose("")
        AssertIsOnMainThread()

        guard let delegate = delegate else { return }
        guard delegate.photoCaptureCanCaptureMoreItems(self) else {
            delegate.photoCaptureDidTryToCaptureTooMany(self)
            return
        }

        let captureRect = captureOutputPhotoRect
        delegate.photoCaptureDidStart(self)
        sessionQueue.async {
            self.captureOutput.takePhoto(delegate: self, captureRect: captureRect)
        }
    }

    // MARK: - Video

    private enum VideoRecordingState: Equatable {
        case stopped
        case starting
        case recording
        case stopping
    }
    private var _videoRecordingState: VideoRecordingState = .stopped
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

    private func beginMovieCapture() {
        AssertIsOnMainThread()
        Logger.verbose("")

        guard let delegate = delegate else { return }
        guard delegate.photoCaptureCanCaptureMoreItems(self) else {
            delegate.photoCaptureDidTryToCaptureTooMany(self)
            return
        }

        owsAssertDebug(videoRecordingState == .stopped)

        let aspectRatio = captureOutputAspectRatio
        firstly(on: captureOutput.movieRecordingQueue) { () -> Promise<Void> in
            let movieRecordingBox = self.captureOutput.newMovieRecordingBox()
            return firstly(on: self.sessionQueue) {
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }

                self.setTorchMode(self.flashMode.toTorchMode)

                let audioCaptureStartedSuccessfully = self.startAudioCapture()
                return try self.captureOutput.beginMovie(
                    delegate: self,
                    aspectRatio: aspectRatio,
                    includeAudio: audioCaptureStartedSuccessfully
                )
            }.done(on: self.captureOutput.movieRecordingQueue) { movieRecording in
                movieRecordingBox.set(movieRecording)
            }.done {
                // Makes sure that user hasn't stopped recording while recording was being started.
                guard self.videoRecordingState == .starting else {
                    throw PhotoCaptureError.invalidVideo
                }

                self.videoRecordingState = .recording
                self.delegate?.photoCaptureDidBeginRecording(self)
            }
        }.catch { error in
            self.handleMovieCaptureError(error)
        }

        videoRecordingState = .starting
        delegate.photoCaptureWillBeginRecording(self)
    }

    private func completeMovieCapture() {
        // User has stopped recording before the it has actually started.
        // Treat this as canceled recording.
        if videoRecordingState == .starting {
            cancelMovieCapture()
            return
        }

        Logger.verbose("")
        BenchEventStart(title: "Movie Processing", eventId: "Movie Processing")

        owsAssertDebug(videoRecordingState == .recording)
        videoRecordingState = .stopping

        firstly(on: captureOutput.movieRecordingQueue) {
            self.captureOutput.completeMovie(delegate: self)
        }.done(on: .main) {
            AssertIsOnMainThread()

            guard self.videoRecordingState == .stopping else {
                throw PhotoCaptureError.invalidVideo
            }

            self.sessionQueue.async {
                self.setTorchMode(.off)
                self.stopAudioCapture()
            }

            // Inform UI that capture is stopping.
            self.videoRecordingState = .stopped
            self.delegate?.photoCaptureDidFinishRecording(self)
        }.catch { error in
            self.handleMovieCaptureError(error)
        }
    }

    private func handleMovieCaptureError(_ error: Error) {
        AssertIsOnMainThread()
        if case PhotoCaptureError.invalidVideo = error {
            Logger.warn("Error: \(error)")
        } else {
            owsFailDebug("Error: \(error)")
        }
        self.sessionQueue.async {
            self.setTorchMode(.off)
            self.stopAudioCapture()
        }
        self.videoRecordingState = .stopped
        self.delegate?.photoCapture(self, didFailProcessing: error)
    }

    private func cancelMovieCapture() {
        Logger.verbose("")
        AssertIsOnMainThread()

        videoRecordingState = .stopping

        firstly(on: captureOutput.movieRecordingQueue) {
            self.captureOutput.cancelVideo(delegate: self)
        }.done(on: .main) {
            AssertIsOnMainThread()

            self.sessionQueue.async {
                self.setTorchMode(.off)
                self.stopAudioCapture()
            }

            self.videoRecordingState = .stopped
            self.delegate?.photoCaptureDidCancelRecording(self)
        }.catch { error in
            self.handleMovieCaptureError(error)
        }
    }

    private func setTorchMode(_ mode: AVCaptureDevice.TorchMode) {
        assertIsOnSessionQueue()

        guard let captureDevice = captureDevice, captureDevice.hasTorch, captureDevice.isTorchModeSupported(mode) else { return }
        do {
            try captureDevice.lockForConfiguration()
            captureDevice.torchMode = mode
            captureDevice.unlockForConfiguration()
        } catch {
            owsFailDebug("Error setting torchMode: \(error)")
        }
    }
}

// MARK: -

class CapturePreviewView: UIView {

    let previewLayer: AVCaptureVideoPreviewLayer

    override var bounds: CGRect {
        didSet {
            previewLayer.frame = bounds
        }
    }

    override var frame: CGRect {
        didSet {
            previewLayer.frame = bounds
        }
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
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        if Platform.isSimulator {
            // helpful for debugging layout on simulator which has no real capture device
            previewLayer.backgroundColor = UIColor.green.withAlphaComponent(0.4).cgColor
        }
        super.init(frame: .zero)
        self.contentMode = .scaleAspectFill
        previewLayer.frame = bounds
        layer.addSublayer(previewLayer)
    }

    @available(*, unavailable, message: "Use init(session:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: -

extension PhotoCapture: VolumeButtonObserver {

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
        beginMovieCapture()
    }

    func didCompleteLongPressVolumeButton(with identifier: VolumeButtons.Identifier) {
        completeMovieCapture()
    }

    func didCancelLongPressVolumeButton(with identifier: VolumeButtons.Identifier) {
        cancelMovieCapture()
    }
}

// MARK: -

extension PhotoCapture: CameraCaptureControlDelegate {

    func cameraCaptureControlDidRequestCapturePhoto(_ control: CameraCaptureControl) {
        takePhoto()
    }

    func cameraCaptureControlDidRequestStartVideoRecording(_ control: CameraCaptureControl) {
        if let captureDevice = captureDevice {
            self.initialSlideZoomFactor = captureDevice.videoZoomFactor
        }
        beginMovieCapture()
    }

    func cameraCaptureControlDidRequestFinishVideoRecording(_ control: CameraCaptureControl) {
        completeMovieCapture()
    }

    func cameraCaptureControlDidRequestCancelVideoRecording(_ control: CameraCaptureControl) {
        cancelMovieCapture()
    }

    func didPressStopCaptureButton(_ control: CameraCaptureControl) {
        completeMovieCapture()
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

extension PhotoCapture: CaptureOutputDelegate {

    var captureOutputAspectRatio: CGFloat {
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

    var captureOutputPhotoRect: CGRect {
        AssertIsOnMainThread()
        return previewView.previewLayer.metadataOutputRectConverted(fromLayerRect: previewView.previewLayer.bounds)
    }

    // MARK: - Photo

    func captureOutputDidCapture(photoData: Swift.Result<Data, Error>) {
        Logger.verbose("")
        AssertIsOnMainThread()
        guard let delegate = delegate else { return }

        switch photoData {
        case .failure(let error):
            delegate.photoCapture(self, didFailProcessing: error)
        case .success(let photoData):
            let dataSource = DataSourceValue.dataSource(with: photoData, utiType: kUTTypeJPEG as String)

            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeJPEG as String)
            delegate.photoCapture(self, didFinishProcessing: attachment)
        }
    }

    // MARK: - Movie

    func captureOutputDidCapture(movieUrl: Swift.Result<URL, Error>) {
        Logger.verbose("")
        AssertIsOnMainThread()
        guard let delegate = delegate else { return }

        switch movieUrl {
        case .failure(let error):
            self.handleMovieCaptureError(error)
        case .success(let movieUrl):
            guard OWSMediaUtils.isValidVideo(path: movieUrl.path) else {
                self.handleMovieCaptureError(PhotoCaptureError.invalidVideo)
                return
            }
            guard let dataSource = try? DataSourcePath.dataSource(with: movieUrl, shouldDeleteOnDeallocation: true) else {
                self.handleMovieCaptureError(PhotoCaptureError.captureFailed)
                return
            }
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeMPEG4 as String)

            BenchEventComplete(eventId: "Movie Processing")
            delegate.photoCapture(self, didFinishProcessing: attachment)
        }
    }

    /// The AVCaptureFileOutput can return an error even though recording succeeds.
    /// I can't find useful documentation on this, but Apple's example AVCam app silently
    /// discards these errors, so we do the same.
    /// These spurious errors can be reproduced 1/3 of the time when making a series of short videos.
    private func didSucceedDespiteError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard let successfullyFinished = nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool else {
            return false
        }

        return successfullyFinished
    }
}

// MARK: - Capture Adapter

protocol CaptureOutputDelegate: AnyObject {
    var session: AVCaptureSession { get }
    func assertIsOnSessionQueue()
    func stopCapture() -> Guarantee<Void>
    func captureOutputDidCapture(photoData: Swift.Result<Data, Error>)
    func captureOutputDidCapture(movieUrl: Swift.Result<URL, Error>)
    var captureOrientation: AVCaptureVideoOrientation { get }
    var captureOutputAspectRatio: CGFloat { get }
    var captureOutputPhotoRect: CGRect { get }
}

// MARK: -

protocol ImageCaptureOutput: AnyObject {
    func availableDeviceTypes(forPosition position: AVCaptureDevice.Position) -> [AVCaptureDevice.DeviceType]
    func cameraSwitchOverZoomFactors(forPosition position: AVCaptureDevice.Position) -> [CGFloat]
    var avOutput: AVCaptureOutput { get }
    var flashMode: AVCaptureDevice.FlashMode { get set }
    func videoDevice(for deviceType: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position) -> AVCaptureDevice?
    func takePhoto(delegate: CaptureOutputDelegate, captureRect: CGRect)
}

// MARK: -

class CaptureOutput: NSObject {

    let session: AVCaptureSession
    let imageOutput: ImageCaptureOutput

    let videoDataOutput: AVCaptureVideoDataOutput
    let audioDataOutput: AVCaptureAudioDataOutput

    static let movieRecordingQueue = DispatchQueue(label: "CaptureOutput.movieRecordingQueue", qos: .userInitiated)
    var movieRecordingQueue: DispatchQueue { CaptureOutput.movieRecordingQueue }

    // A user might cancel movie recording before recording has
    // begun (e.g. an instance of MovieRecording has been created),
    // with a very short long press gesture.
    // We handle that case by marking that recording as aborted
    // before it exists using this box.
    struct MovieRecordingBox {

        private let invalidated = AtomicBool(false)
        private let movieRecording = AtomicOptional<MovieRecording>(nil)

        func set(_ value: MovieRecording) {
            movieRecording.set(value)
        }

        @discardableResult
        func invalidate() -> MovieRecording? {
            let value = self.value
            invalidated.set(true)
            return value
        }

        var value: MovieRecording? {
            guard !invalidated.get() else {
                return nil
            }
            return movieRecording.get()
        }
    }
    private let _movieRecordingBox = AtomicOptional<MovieRecordingBox>(nil)
    var currentMovieRecording: MovieRecording? {
        _movieRecordingBox.get()?.value
    }
    @discardableResult
    func clearMovieRecording() -> MovieRecording? {
        let box = _movieRecordingBox.swap(nil)
        return box?.invalidate()
    }
    func newMovieRecordingBox() -> MovieRecordingBox {
        let newBox = MovieRecordingBox()
        let oldBox = _movieRecordingBox.swap(newBox)
        oldBox?.invalidate()
        return newBox
    }

    // MARK: - Init

    init(session: AVCaptureSession) {
        imageOutput = PhotoCaptureOutputAdaptee()

        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = false
        audioDataOutput = AVCaptureAudioDataOutput()

        self.session = session
        super.init()

        videoDataOutput.setSampleBufferDelegate(self, queue: movieRecordingQueue)
        audioDataOutput.setSampleBufferDelegate(self, queue: movieRecordingQueue)
    }

    var photoOutput: AVCaptureOutput? {
        return imageOutput.avOutput
    }

    var flashMode: AVCaptureDevice.FlashMode {
        get { return imageOutput.flashMode }
        set { imageOutput.flashMode = newValue }
    }

    func videoDevice(for deviceType: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return imageOutput.videoDevice(for: deviceType, position: position)
    }

    func takePhoto(delegate: CaptureOutputDelegate, captureRect: CGRect) {
        delegate.assertIsOnSessionQueue()

        guard let photoOutput = photoOutput else {
            owsFailDebug("photoOutput was unexpectedly nil")
            return
        }

        guard let photoVideoConnection = photoOutput.connection(with: .video) else {
            owsFailDebug("photoVideoConnection was unexpectedly nil")
            return
        }

        ImpactHapticFeedback.impactOccured(style: .medium)

        let videoOrientation = delegate.captureOrientation
        photoVideoConnection.videoOrientation = videoOrientation
        Logger.verbose("videoOrientation: \(videoOrientation), deviceOrientation: \(UIDevice.current.orientation)")

        return imageOutput.takePhoto(delegate: delegate, captureRect: captureRect)
    }

    // MARK: - Movie Output

    func beginMovie(
        delegate: CaptureOutputDelegate,
        aspectRatio: CGFloat,
        includeAudio: Bool
    ) throws -> MovieRecording {
        Logger.verbose("")

        delegate.assertIsOnSessionQueue()

        guard let videoConnection = videoDataOutput.connection(with: .video) else {
            throw OWSAssertionError("videoConnection was unexpectedly nil")
        }
        let videoOrientation = delegate.captureOrientation
        videoConnection.videoOrientation = videoOrientation

        owsAssertDebug(currentMovieRecording == nil)
        let outputURL = OWSFileSystem.temporaryFileUrl(fileExtension: "mp4")
        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        guard let recommendedSettings = self.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4) else {
            throw OWSAssertionError("videoSettings was unexpectedly nil")
        }
        guard let capturedWidth: CGFloat = recommendedSettings[AVVideoWidthKey] as? CGFloat else {
            throw OWSAssertionError("capturedWidth was unexpectedly nil")
        }
        guard let capturedHeight: CGFloat = recommendedSettings[AVVideoHeightKey] as? CGFloat else {
            throw OWSAssertionError("capturedHeight was unexpectedly nil")
        }
        let capturedSize = CGSize(width: capturedWidth, height: capturedHeight)

        // video specs from Signal-Android: 2Mbps video 192K audio, 720P 30 FPS
        let maxDimension: CGFloat = 1280 // 720p

        let aspectSize = capturedSize.cropped(toAspectRatio: aspectRatio)
        let outputSize = aspectSize.scaledToFit(max: maxDimension)

        // See AVVideoSettings.h
        let videoSettings: [String: Any] = [
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2000000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264Baseline41,
                AVVideoMaxKeyFrameIntervalKey: 90
            ]
        ]

        Logger.info("videoOrientation: \(videoOrientation), captured: \(capturedWidth)x\(capturedHeight), output: \(outputSize.width)x\(outputSize.height), aspectRatio: \(aspectRatio)")

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        assetWriter.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if includeAudio {
            if let audioSettings = self.audioDataOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) {
                audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioInput!.expectsMediaDataInRealTime = true
                assetWriter.add(audioInput!)
            } else {
                owsFailDebug("audioSettings was unexpectedly nil!")
            }
        } else {
            Logger.info("Not including audio.")
        }

        return MovieRecording(assetWriter: assetWriter, videoInput: videoInput, audioInput: audioInput)
    }

    func completeMovie(delegate: CaptureOutputDelegate) {
        Logger.verbose("")

        assertOnQueue(movieRecordingQueue)

        firstly {
            delegate.stopCapture()
        }.then(on: CaptureOutput.movieRecordingQueue) { [weak self] _ -> Promise<URL> in
            assertOnQueue(CaptureOutput.movieRecordingQueue)
            guard let movieRecording = self?.clearMovieRecording() else {
                // If the user cancels a video before recording begins,
                // the instance of MovieRecording might not be set yet.
                // clearMovieRecording() will ensure that race does not
                // cause problems.
                Logger.warn("Movie recording is nil.")
                throw PhotoCaptureError.invalidVideo
            }
            return movieRecording.finish()
        }.done { outputUrl in
            delegate.captureOutputDidCapture(movieUrl: .success(outputUrl))
        }.catch { error in
            delegate.captureOutputDidCapture(movieUrl: .failure(error))
        }
    }

    func cancelVideo(delegate: CaptureOutputDelegate) {
        assertOnQueue(movieRecordingQueue)

        self.clearMovieRecording()
    }
}

// MARK: -

class MovieRecording {

    let assetWriter: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput?

    enum State {
        case unstarted, recording, finished
    }
    private(set) var state: State = .unstarted

    init(assetWriter: AVAssetWriter, videoInput: AVAssetWriterInput, audioInput: AVAssetWriterInput?) {
        self.assetWriter = assetWriter
        self.videoInput = videoInput
        self.audioInput = audioInput
    }

    func start(sampleBuffer: CMSampleBuffer) throws {
        Logger.verbose("")
        switch state {
        case .unstarted:
            state = .recording
            guard assetWriter.startWriting() else {
                throw OWSAssertionError("startWriting() was unexpectedly false")
            }
            assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        default:
            throw OWSAssertionError("unexpected state: \(state)")
        }
    }

    func finish() -> Promise<URL> {
        assertOnQueue(CaptureOutput.movieRecordingQueue)

        Logger.verbose("")
        switch state {
        case .recording:
            state = .finished
            audioInput?.markAsFinished()
            videoInput.markAsFinished()
            return Promise<URL> { future -> Void in
                let assetWriter = self.assetWriter
                assetWriter.finishWriting {
                    if assetWriter.status == .completed,
                       assetWriter.error == nil {
                        future.resolve(self.assetWriter.outputURL)
                    } else {
                        // If the user cancels a video right after recording
                        // begins, recording is expected to fail.
                        future.reject(PhotoCaptureError.invalidVideo)
                    }
                }
            }
        default:
            Logger.warn("Unexpected state: \(state)")
            return Promise(error: PhotoCaptureError.invalidVideo)
        }
    }
}

// MARK: -

extension CaptureOutput: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        assertOnQueue(movieRecordingQueue)

        guard let movieRecording = currentMovieRecording else {
            // `movieRecording` is assigned async after the capture pipeline has been set up.
            // We'll drop a few frames before we're ready to start recording.
            return
        }

        do {
            if movieRecording.state == .unstarted {
                try movieRecording.start(sampleBuffer: sampleBuffer)
            }

            guard movieRecording.state == .recording else {
                owsAssertDebug(movieRecording.state == .finished)
                Logger.verbose("ignoring samples since recording has finished.")
                return
            }

            if output == self.videoDataOutput {
                movieRecordingQueue.async {
                    if movieRecording.videoInput.isReadyForMoreMediaData {
                        movieRecording.videoInput.append(sampleBuffer)
                    } else {
                        Logger.verbose("videoInput was not ready for more data")
                    }
                }
            } else if output == self.audioDataOutput {
                movieRecordingQueue.async {
                    if
                        let audioInput = movieRecording.audioInput,
                        audioInput.isReadyForMoreMediaData
                    {
                        audioInput.append(sampleBuffer)
                    } else {
                        Logger.verbose("audioInput was not present or ready for more data")
                    }
                }
            } else {
                owsFailDebug("unknown output: \(output)")
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        Logger.error("dropped sampleBuffer from connection: \(connection)")
    }
}

// MARK: -

class PhotoCaptureOutputAdaptee: NSObject, ImageCaptureOutput {

    let photoOutput = AVCapturePhotoOutput()
    var avOutput: AVCaptureOutput {
        return photoOutput
    }

    private lazy var availableRearDeviceMap: [AVCaptureDevice.DeviceType: AVCaptureDevice] = {
        return availableDevices(forPosition: .back)
    }()

    private lazy var availableFrontDeviceMap: [AVCaptureDevice.DeviceType: AVCaptureDevice] = {
        return availableDevices(forPosition: .front)
    }()

    func availableDeviceTypes(forPosition position: AVCaptureDevice.Position) -> [AVCaptureDevice.DeviceType] {
        switch position {
        case .front, .unspecified:
            return Array(availableFrontDeviceMap.keys)

        case .back:
            return Array(availableRearDeviceMap.keys)

        @unknown default:
            owsFailDebug("Unknown AVCaptureDevice.Position: [\(position)]")
            return []
        }
    }

    func cameraSwitchOverZoomFactors(forPosition position: AVCaptureDevice.Position) -> [CGFloat] {
        let deviceMap = position == .front ? availableFrontDeviceMap : availableRearDeviceMap

        guard #available(iOS 13, *) else {
            // No iOS 12 device can have triple camera system.
            if deviceMap[.builtInDualCamera] != nil {
                return UIDevice.current.isPlusSizePhone ? [ 2.5 ] : [ 2 ]
            }
            return []
        }

        if let multiCameraDevice = deviceMap[.builtInTripleCamera] ?? deviceMap[.builtInDualWideCamera] ?? deviceMap[.builtInDualCamera] {
            return multiCameraDevice.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        }
        return []
    }

    var flashMode: AVCaptureDevice.FlashMode = .off

    override init() {
        photoOutput.isLivePhotoCaptureEnabled = false
        photoOutput.isHighResolutionCaptureEnabled = true
    }

    private var photoProcessors: [Int64: PhotoProcessor] = [:]

    func takePhoto(delegate: CaptureOutputDelegate, captureRect: CGRect) {
        delegate.assertIsOnSessionQueue()

        let settings = buildCaptureSettings()

        let photoProcessor = PhotoProcessor(delegate: delegate, captureRect: captureRect, completion: { [weak self] in
            self?.photoProcessors[settings.uniqueID] = nil
        })
        photoProcessors[settings.uniqueID] = photoProcessor
        photoOutput.capturePhoto(with: settings, delegate: photoProcessor)
    }

    func videoDevice(for deviceType: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        switch position {
        case .back:
            return availableRearDeviceMap[deviceType]
        case .front:
            return availableFrontDeviceMap[deviceType]
        default:
            owsFailDebug("Requested invalid camera position")
            return nil
        }
    }

    // MARK: -

    private func buildCaptureSettings() -> AVCapturePhotoSettings {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.flashMode = flashMode
        photoSettings.isHighResolutionPhotoEnabled = true

        photoSettings.isAutoStillImageStabilizationEnabled =
        photoOutput.isStillImageStabilizationSupported

        return photoSettings
    }

    private func availableDevices(forPosition position: AVCaptureDevice.Position) -> [AVCaptureDevice.DeviceType: AVCaptureDevice] {
        var queryDeviceTypes: [AVCaptureDevice.DeviceType] = [ .builtInWideAngleCamera, .builtInTelephotoCamera, .builtInDualCamera ]
        if #available(iOS 13, *) {
            queryDeviceTypes.append(contentsOf: [ .builtInUltraWideCamera, .builtInDualWideCamera, .builtInTripleCamera ])
        }
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: queryDeviceTypes, mediaType: .video, position: position)
        let deviceMap = session.devices.reduce(into: [AVCaptureDevice.DeviceType: AVCaptureDevice]()) { deviceMap, device in
            deviceMap[device.deviceType] = device
        }
        return deviceMap
    }

    private class PhotoProcessor: NSObject, AVCapturePhotoCaptureDelegate {
        weak var delegate: CaptureOutputDelegate?
        let captureRect: CGRect
        let completion: () -> Void

        init(delegate: CaptureOutputDelegate, captureRect: CGRect, completion: @escaping () -> Void) {
            self.delegate = delegate
            self.captureRect = captureRect
            self.completion = completion
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            defer { completion() }

            guard let delegate = delegate else { return }

            let result: Swift.Result<Data, Error>
            do {
                if let error = error {
                    throw error
                }
                guard let rawData = photo.fileDataRepresentation()  else {
                    throw OWSAssertionError("photo data was unexpectedly empty")
                }

                let resizedData = try crop(photoData: rawData, toOutputRect: captureRect)
                result = .success(resizedData)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                delegate.captureOutputDidCapture(photoData: result)
            }
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

// MARK: -

private func crop(photoData: Data, toOutputRect outputRect: CGRect) throws -> Data {
    guard let originalImage = UIImage(data: photoData) else {
        throw OWSAssertionError("originalImage was unexpectedly nil")
    }

    guard outputRect.width > 0, outputRect.height > 0 else {
        throw OWSAssertionError("invalid outputRect: \(outputRect)")
    }

    var cgImage = originalImage.cgImage!
    let width = CGFloat(cgImage.width)
    let height = CGFloat(cgImage.height)
    let cropRect = CGRect(x: outputRect.origin.x * width,
                          y: outputRect.origin.y * height,
                          width: outputRect.size.width * width,
                          height: outputRect.size.height * height)

    cgImage = cgImage.cropping(to: cropRect)!
    let croppedUIImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: originalImage.imageOrientation)
    guard let croppedData = croppedUIImage.jpegData(compressionQuality: 0.9) else {
        throw OWSAssertionError("croppedData was unexpectedly nil")
    }
    return croppedData
}
