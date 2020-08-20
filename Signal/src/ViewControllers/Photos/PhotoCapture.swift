//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

protocol PhotoCaptureDelegate: AnyObject {

    // MARK: Still Photo

    func photoCaptureDidStartPhotoCapture(_ photoCapture: PhotoCapture)
    func photoCapture(_ photoCapture: PhotoCapture, didFinishProcessingAttachment attachment: SignalAttachment)
    func photoCapture(_ photoCapture: PhotoCapture, processingDidError error: Error)

    // MARK: Movie

    func photoCaptureDidBeginMovie(_ photoCapture: PhotoCapture)
    func photoCaptureDidCompleteMovie(_ photoCapture: PhotoCapture)
    func photoCaptureDidCancelMovie(_ photoCapture: PhotoCapture)

    // MARK: Utility

    func photoCapture(_ photoCapture: PhotoCapture, didChangeOrientation: AVCaptureVideoOrientation)
    func photoCaptureCanCaptureMoreItems(_ photoCapture: PhotoCapture) -> Bool
    func photoCaptureDidTryToCaptureTooMany(_ photoCapture: PhotoCapture)
    var zoomScaleReferenceHeight: CGFloat? { get }

    func beginCaptureButtonAnimation(_ duration: TimeInterval)
    func endCaptureButtonAnimation(_ duration: TimeInterval)

    func photoCapture(_ photoCapture: PhotoCapture, didCompleteFocusingAtPoint focusPoint: CGPoint)

}

@objc
class PhotoCapture: NSObject {

    weak var delegate: PhotoCaptureDelegate?

    // There can only ever be one `CapturePreviewView` per AVCaptureSession
    lazy private(set) var previewView = CapturePreviewView(session: session)

    private let sessionQueue = DispatchQueue(label: "PhotoCapture.sessionQueue")

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
    override init() {
        self.session = AVCaptureSession()
        self.captureOutput = CaptureOutput()
    }

    func didCompleteFocusing() {
        Logger.debug("")
        guard let currentCaptureInput = currentCaptureInput else {
            return
        }

        let focusPoint = currentCaptureInput.device.focusPointOfInterest

        DispatchQueue.main.async {
            self.delegate?.photoCapture(self, didCompleteFocusingAtPoint: focusPoint)
        }
    }

    // MARK: - Dependencies

    private var audioSession: OWSAudioSession {
        return Environment.shared.audioSession
    }

    private var audioDeviceInput: AVCaptureDeviceInput?

    // MARK: - Public

    public var flashMode: AVCaptureDevice.FlashMode {
        return captureOutput.flashMode
    }

    public let session: AVCaptureSession

    public func startAudioCapture() throws {
        assertIsOnSessionQueue()

        guard audioSession.startAudioActivity(recordingAudioActivity) else {
            throw PhotoCaptureError.assertionError(description: "unable to capture audio activity")
        }

        let audioDevice = AVCaptureDevice.default(for: .audio)
        // verify works without audio permissions
        let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
        if session.canAddInput(audioDeviceInput) {
            session.addInput(audioDeviceInput)
            self.audioDeviceInput = audioDeviceInput
        } else {
            owsFailDebug("Could not add audio device input to the session")
        }
    }

    public func stopAudioCapture() {
        assertIsOnSessionQueue()

        self.session.beginConfiguration()
        defer { self.session.commitConfiguration() }

        guard let audioDeviceInput = self.audioDeviceInput else {
            owsFailDebug("audioDevice was unexpectedly nil")
            return
        }
        session.removeInput(audioDeviceInput)
        self.audioDeviceInput = nil
        audioSession.endAudioActivity(recordingAudioActivity)
    }

    @objc
    public func orientationDidChange(notification: Notification) {
        AssertIsOnMainThread()
        guard let captureOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) else {
            return
        }

        sessionQueue.async {
            guard captureOrientation != self.captureOrientation else {
                return
            }
            self.captureOrientation = captureOrientation

            DispatchQueue.main.async {
                self.delegate?.photoCapture(self, didChangeOrientation: captureOrientation)
            }
        }
    }

    func updateVideoPreviewConnection(toOrientation orientation: AVCaptureVideoOrientation) {
        guard let videoConnection = previewView.previewLayer.connection else {
            Logger.info("previewView hasn't completed setup yet.")
            return
        }
        videoConnection.videoOrientation = orientation
    }

    public func startVideoCapture() -> Promise<Void> {
        AssertIsOnMainThread()
        guard !Platform.isSimulator else {
            // Trying to actually set up the capture session will fail on a simulator
            // since we don't have actual capture devices. But it's useful to be able
            // to mostly run the capture code on the simulator to work with layout.
            return Promise.value(())
        }

        // If the session is already running, no need to do anything.
        guard !self.session.isRunning else { return Promise.value(()) }

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(orientationDidChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: UIDevice.current)
        let initialCaptureOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) ?? .portrait

        return sessionQueue.async(.promise) { [weak self] in
            guard let self = self else { return }
            guard let delegate = self.delegate else { return }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            self.captureOrientation = initialCaptureOrientation
            self.session.sessionPreset = .high

            try self.updateCurrentInput(position: .back)

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
        }.done(on: sessionQueue) {
            self.session.startRunning()
        }
    }

    @discardableResult
    public func stopCapture() -> Guarantee<Void> {
        return sessionQueue.async(.promise) {
            self.session.stopRunning()
        }
    }

    public func assertIsOnSessionQueue() {
        assertOnQueue(sessionQueue)
    }

    public func switchCamera() -> Promise<Void> {
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
            break
        }
        desiredPosition = newPosition

        return sessionQueue.async(.promise) { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            try self.updateCurrentInput(position: newPosition)
        }
    }

    // This method should be called on the serial queue,
    // and between calls to session.beginConfiguration/commitConfiguration
    public func updateCurrentInput(position: AVCaptureDevice.Position) throws {
        assertIsOnSessionQueue()

        guard let device = captureOutput.videoDevice(position: position) else {
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

        resetFocusAndExposure()
    }

    public func switchFlashMode() -> Guarantee<Void> {
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

    public func focus(with focusMode: AVCaptureDevice.FocusMode,
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

    public func resetFocusAndExposure() {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }

    @objc
    private func subjectAreaDidChange(notification: NSNotification) {
        resetFocusAndExposure()
    }

    // MARK: - Zoom

    private let minimumZoom: CGFloat = 1.0
    private let maximumZoom: CGFloat = 3.0
    private var previousZoomFactor: CGFloat = 1.0

    public func updateZoom(alpha: CGFloat) {
        assert(alpha >= 0 && alpha <= 1)
        sessionQueue.async {
            guard let captureDevice = self.captureDevice else {
                owsFailDebug("captureDevice was unexpectedly nil")
                return
            }

            // we might want this to be non-linear
            let scale = CGFloatLerp(self.minimumZoom, self.maximumZoom, alpha)
            let zoomFactor = self.clampZoom(scale, device: captureDevice)
            self.updateZoom(factor: zoomFactor)
        }
    }

    public func updateZoom(scaleFromPreviousZoomFactor scale: CGFloat) {
        sessionQueue.async {
            guard let captureDevice = self.captureDevice else {
                owsFailDebug("captureDevice was unexpectedly nil")
                return
            }

            let zoomFactor = self.clampZoom(scale * self.previousZoomFactor, device: captureDevice)
            self.updateZoom(factor: zoomFactor)
        }
    }

    public func completeZoom(scaleFromPreviousZoomFactor scale: CGFloat) {
        sessionQueue.async {
            guard let captureDevice = self.captureDevice else {
                owsFailDebug("captureDevice was unexpectedly nil")
                return
            }

            let zoomFactor = self.clampZoom(scale * self.previousZoomFactor, device: captureDevice)

            Logger.debug("ended with scaleFactor: \(zoomFactor)")

            self.previousZoomFactor = zoomFactor
            self.updateZoom(factor: zoomFactor)
        }
    }

    private func updateZoom(factor: CGFloat) {
        assertIsOnSessionQueue()

        guard let captureDevice = self.captureDevice else {
            owsFailDebug("captureDevice was unexpectedly nil")
            return
        }

        do {
            try captureDevice.lockForConfiguration()
            captureDevice.videoZoomFactor = factor
            captureDevice.unlockForConfiguration()
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    private func clampZoom(_ factor: CGFloat, device: AVCaptureDevice) -> CGFloat {
        return min(factor.clamp(minimumZoom, maximumZoom), device.activeFormat.videoMaxZoomFactor)
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
        delegate.photoCaptureDidStartPhotoCapture(self)
        sessionQueue.async {
            self.captureOutput.takePhoto(delegate: self, captureRect: captureRect)
        }
    }

    // MARK: - Video

    private func beginMovieCapture() {
        AssertIsOnMainThread()
        Logger.verbose("")

        guard let delegate = delegate else { return }
        guard delegate.photoCaptureCanCaptureMoreItems(self) else {
            delegate.photoCaptureDidTryToCaptureTooMany(self)
            return
        }

        let aspectRatio = captureOutputAspectRatio
        sessionQueue.async(.promise) {
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            try self.startAudioCapture()
            return try self.captureOutput.beginMovie(delegate: self, aspectRatio: aspectRatio)
        }.done(on: captureOutput.movieRecordingQueue) { movieRecording in
            self.captureOutput.movieRecording = movieRecording
        }.done {
            self.setTorchMode(self.flashMode.toTorchMode)
            self.delegate?.photoCaptureDidBeginMovie(self)
        }.catch { error in
            self.delegate?.photoCapture(self, processingDidError: error)
        }
    }

    private func completeMovieCapture() {
        Logger.verbose("")
        BenchEventStart(title: "Movie Processing", eventId: "Movie Processing")
        captureOutput.movieRecordingQueue.async(.promise) {
            self.captureOutput.completeMovie(delegate: self)
            self.setTorchMode(.off)
        }.done(on: sessionQueue) {
            self.stopAudioCapture()
        }

        AssertIsOnMainThread()
        // immediately inform UI that capture is stopping
        delegate?.photoCaptureDidCompleteMovie(self)
    }

    private func cancelMovieCapture() {
        Logger.verbose("")
        AssertIsOnMainThread()
        sessionQueue.async {
            self.stopAudioCapture()
        }
        delegate?.photoCaptureDidCancelMovie(self)
    }

    private func setTorchMode(_ mode: AVCaptureDevice.TorchMode) {
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

extension PhotoCapture: CaptureButtonDelegate {
    func didTapCaptureButton(_ captureButton: CaptureButton) {
        takePhoto()
    }

    func didBeginLongPressCaptureButton(_ captureButton: CaptureButton) {
        beginMovieCapture()
    }

    func didCompleteLongPressCaptureButton(_ captureButton: CaptureButton) {
        completeMovieCapture()
    }

    func didCancelLongPressCaptureButton(_ captureButton: CaptureButton) {
        cancelMovieCapture()
    }

    func didPressStopCaptureButton(_ captureButton: CaptureButton) {
        completeMovieCapture()
    }

    var zoomScaleReferenceHeight: CGFloat? {
        return delegate?.zoomScaleReferenceHeight
    }

    func longPressCaptureButton(_ captureButton: CaptureButton, didUpdateZoomAlpha zoomAlpha: CGFloat) {
        updateZoom(alpha: zoomAlpha)
    }
}

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
            delegate.photoCapture(self, processingDidError: error)
        case .success(let photoData):
            let dataSource = DataSourceValue.dataSource(with: photoData, utiType: kUTTypeJPEG as String)

            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeJPEG as String, imageQuality: .medium)
            delegate.photoCapture(self, didFinishProcessingAttachment: attachment)
        }
    }

    // MARK: - Movie

    func captureOutputDidCapture(movieUrl: Swift.Result<URL, Error>) {
        Logger.verbose("")
        AssertIsOnMainThread()
        guard let delegate = delegate else { return }

        switch movieUrl {
        case .failure(let error):
            delegate.photoCapture(self, processingDidError: error)
        case .success(let movieUrl):
            guard let dataSource = try? DataSourcePath.dataSource(with: movieUrl, shouldDeleteOnDeallocation: true) else {
                delegate.photoCapture(self, processingDidError: PhotoCaptureError.captureFailed)
                return
            }
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeMPEG4 as String, imageQuality: .original)

            BenchEventComplete(eventId: "Movie Processing")
            delegate.photoCapture(self, didFinishProcessingAttachment: attachment)
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
    func captureOutputDidCapture(photoData: Swift.Result<Data, Error>)
    func captureOutputDidCapture(movieUrl: Swift.Result<URL, Error>)
    var captureOrientation: AVCaptureVideoOrientation { get }
    var captureOutputAspectRatio: CGFloat { get }
    var captureOutputPhotoRect: CGRect { get }
}

protocol ImageCaptureOutput: AnyObject {
    var avOutput: AVCaptureOutput { get }
    var flashMode: AVCaptureDevice.FlashMode { get set }
    func videoDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice?

    func takePhoto(delegate: CaptureOutputDelegate, captureRect: CGRect)
}

class CaptureOutput: NSObject {

    let imageOutput: ImageCaptureOutput

    let videoDataOutput: AVCaptureVideoDataOutput
    let audioDataOutput: AVCaptureAudioDataOutput

    let movieRecordingQueue = DispatchQueue(label: "CaptureOutput.movieRecordingQueue", qos: .userInitiated)
    var movieRecording: MovieRecording?

    // MARK: - Init

    override init() {
        imageOutput = PhotoCaptureOutputAdaptee()

        videoDataOutput = AVCaptureVideoDataOutput()
        audioDataOutput = AVCaptureAudioDataOutput()

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

    func videoDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return imageOutput.videoDevice(position: position)
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

    func beginMovie(delegate: CaptureOutputDelegate, aspectRatio: CGFloat) throws -> MovieRecording {
        delegate.assertIsOnSessionQueue()

        guard let videoConnection = videoDataOutput.connection(with: .video) else {
            throw OWSAssertionError("videoConnection was unexpectedly nil")
        }
        let videoOrientation = delegate.captureOrientation
        videoConnection.videoOrientation = videoOrientation

        assert(movieRecording == nil)
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
            AVVideoCodecKey: AVVideoCodecH264,
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

        let audioSettings: [String: Any]? =  self.audioDataOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) as? [String: Any]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        if audioSettings != nil {
            assetWriter.add(audioInput)
        } else {
            owsFailDebug("audioSettings was unexpectedly nil")
        }

        return MovieRecording(assetWriter: assetWriter, videoInput: videoInput, audioInput: audioInput)
    }

    func completeMovie(delegate: CaptureOutputDelegate) {
        firstly { () -> Promise<URL> in
            assertOnQueue(movieRecordingQueue)
            guard let movieRecording = self.movieRecording else {
                throw OWSAssertionError("movie recording was unexpectedly nil")
            }
            self.movieRecording = nil
            return movieRecording.finish()
        }.done { outputUrl in
            delegate.captureOutputDidCapture(movieUrl: .success(outputUrl))
        }.catch { error in
            delegate.captureOutputDidCapture(movieUrl: .failure(error))
        }
    }

    func cancelVideo(delegate: CaptureOutputDelegate) {
        delegate.assertIsOnSessionQueue()
        // There's currently no user-visible way to cancel, if so, we may need to do some cleanup here.
        owsFailDebug("video was unexpectedly canceled.")
    }
}

class MovieRecording {
    let assetWriter: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput

    enum State {
        case unstarted, recording, finished
    }
    private(set) var state: State = .unstarted

    init(assetWriter: AVAssetWriter, videoInput: AVAssetWriterInput, audioInput: AVAssetWriterInput) {
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
        Logger.verbose("")
        switch state {
        case .recording:
            state = .finished
            audioInput.markAsFinished()
            videoInput.markAsFinished()
            return Promise<URL> { resolver -> Void in
                self.assetWriter.finishWriting {
                    resolver.fulfill(self.assetWriter.outputURL)
                }
            }
        default:
            return Promise(error: OWSAssertionError("unexpected state: \(state)"))
        }
    }
}

extension CaptureOutput: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        assertOnQueue(movieRecordingQueue)

        guard let movieRecording = movieRecording else {
            // `movieRecording` is assigned async after the capture pipeline has been set up.
            // We'll drop a few frames before we're ready to start recording.
            return
        }

        do {
            if movieRecording.state == .unstarted {
                try movieRecording.start(sampleBuffer: sampleBuffer)
            }

            guard movieRecording.state == .recording else {
                assert(movieRecording.state == .finished)
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
                    if movieRecording.audioInput.isReadyForMoreMediaData {
                        movieRecording.audioInput.append(sampleBuffer)
                    } else {
                        Logger.verbose("audioInput was not ready for more data")
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

class PhotoCaptureOutputAdaptee: NSObject, ImageCaptureOutput {

    let photoOutput = AVCapturePhotoOutput()
    var avOutput: AVCaptureOutput {
        return photoOutput
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

    func videoDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // use dual camera where available
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
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
                    throw OWSAssertionError("photo data was unexpectely empty")
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

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .unknown:
            return nil
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        case .faceUp:
            return nil
        case .faceDown:
            return nil
        @unknown default:
            return nil
        }
    }

    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .unknown:
            return nil
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        @unknown default:
            return nil
        }
    }
}

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
