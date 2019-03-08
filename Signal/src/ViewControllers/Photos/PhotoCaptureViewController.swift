//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation
import PromiseKit

@objc(OWSPhotoCaptureViewControllerDelegate)
protocol PhotoCaptureViewControllerDelegate: AnyObject {
    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController, didFinishProcessingAttachment attachment: SignalAttachment)
    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController)
}

enum PhotoCaptureError: Error {
    case assertionError(description: String)
    case initializationFailed
    case captureFailed
}

extension PhotoCaptureError: LocalizedError {
    var localizedDescription: String {
        switch self {
        case .initializationFailed:
            return NSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_INITIALIZE_CAMERA", comment: "alert title")
        case .captureFailed:
            return NSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_CAPTURE_IMAGE", comment: "alert title")
        case .assertionError:
            return NSLocalizedString("PHOTO_CAPTURE_GENERIC_ERROR", comment: "alert title, generic error preventing user from capturing a photo")
        }
    }
}

@objc(OWSPhotoCaptureViewController)
class PhotoCaptureViewController: OWSViewController {

    @objc
    weak var delegate: PhotoCaptureViewControllerDelegate?

    private var photoCapture: PhotoCapture!

    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        if let photoCapture = photoCapture {
            photoCapture.stopCapture().done {
                Logger.debug("stopCapture completed")
            }.retainUntilComplete()
        }
    }

    // MARK: - Overrides

    override func loadView() {
        self.view = UIView()
        self.view.backgroundColor = Theme.darkThemeBackgroundColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPhotoCapture()
        setupOrientationMonitoring()

        updateNavigationItems()
        updateFlashModeControl()
        updateIconOrientations(isAnimated: false)

        view.addGestureRecognizer(pinchZoomGesture)
        view.addGestureRecognizer(focusGesture)
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    // MARK -
    var isRecordingMovie: Bool = false
    let recordingTimerView = RecordingTimerView()

    func updateNavigationItems() {
        if isRecordingMovie {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItems = nil
            navigationItem.titleView = recordingTimerView
        } else {
            navigationItem.titleView = nil
            navigationItem.leftBarButtonItem = dismissControl.barButtonItem
            let fixedSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
            fixedSpace.width = 25
            navigationItem.rightBarButtonItems = [flashModeControl.barButtonItem, fixedSpace, switchCameraControl.barButtonItem]
        }
    }

    // HACK: Though we don't have an input accessory view, the VC we are presented above (ConversationVC) does.
    // If the app is backgrounded and then foregrounded, when OWSWindowManager calls mainWindow.makeKeyAndVisible
    // the ConversationVC's inputAccessoryView will appear *above* us unless we'd previously become first responder.
    override public var canBecomeFirstResponder: Bool {
        Logger.debug("")
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    // MARK: - Views

    let captureButton = CaptureButton()
    var previewView: CapturePreviewView!

    class PhotoControl {
        let button: OWSButton
        let barButtonItem: UIBarButtonItem

        init(imageName: String, block: @escaping () -> Void) {
            self.button = OWSButton(imageName: imageName, tintColor: .ows_white, block: block)
            button.autoPinToSquareAspectRatio()

            button.layer.shadowOffset = CGSize.zero
            button.layer.shadowOpacity = 0.35
            button.layer.shadowRadius = 4

            self.barButtonItem = UIBarButtonItem(customView: button)
        }

        func setImage(imageName: String) {
            button.setImage(imageName: imageName)
        }
    }
    private lazy var dismissControl: PhotoControl = {
        return PhotoControl(imageName: "ic_x_with_shadow") { [weak self] in
            self?.didTapClose()
        }
    }()

    private lazy var switchCameraControl: PhotoControl = {
        return PhotoControl(imageName: "ic_switch_camera") { [weak self] in
            self?.didTapSwitchCamera()
        }
    }()

    private lazy var flashModeControl: PhotoControl = {
        return PhotoControl(imageName: "ic_flash_mode_auto") { [weak self] in
            self?.didTapFlashMode()
        }
    }()

    lazy var pinchZoomGesture: UIPinchGestureRecognizer = {
        return UIPinchGestureRecognizer(target: self, action: #selector(didPinchZoom(pinchGesture:)))
    }()

    lazy var focusGesture: UITapGestureRecognizer = {
        return UITapGestureRecognizer(target: self, action: #selector(didTapFocusExpose(tapGesture:)))
    }()

    // MARK: - Events

    @objc
    func didTapClose() {
        self.delegate?.photoCaptureViewControllerDidCancel(self)
    }

    @objc
    func didTapSwitchCamera() {
        Logger.debug("")
        UIView.animate(withDuration: 0.5) {
            self.switchCameraControl.button.transform = self.switchCameraControl.button.transform.rotate(.pi)
        }
        photoCapture.switchCamera().catch { error in
            self.showFailureUI(error: error)
        }.retainUntilComplete()
    }

    @objc
    func didTapFlashMode() {
        Logger.debug("")
        photoCapture.switchFlashMode().done {
            self.updateFlashModeControl()
        }.retainUntilComplete()
    }

    @objc
    func didPinchZoom(pinchGesture: UIPinchGestureRecognizer) {
        switch pinchGesture.state {
        case .began: fallthrough
        case .changed:
            photoCapture.updateZoom(scaleFromPreviousZoomFactor: pinchGesture.scale)
        case .ended:
            photoCapture.completeZoom(scaleFromPreviousZoomFactor: pinchGesture.scale)
        default:
            break
        }
    }

    @objc
    func didTapFocusExpose(tapGesture: UITapGestureRecognizer) {
        let viewLocation = tapGesture.location(in: view)
        let devicePoint = previewView.previewLayer.captureDevicePointConverted(fromLayerPoint: viewLocation)
        photoCapture.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }

    @objc
    func didChangeDeviceOrientation(notification: Notification) {
        updateIconOrientations(isAnimated: true)
    }

    // MARK: -

    private func updateIconOrientations(isAnimated: Bool) {
        let currentOrientation = UIDevice.current.orientation
        Logger.verbose("currentOrientation: \(currentOrientation)")

        let transformFromOrientation: CGAffineTransform
        switch currentOrientation {
        case .portrait:
            transformFromOrientation = .identity
        case .portraitUpsideDown:
            transformFromOrientation = CGAffineTransform(rotationAngle: .pi)
        case .landscapeLeft:
            transformFromOrientation = CGAffineTransform(rotationAngle: .halfPi)
        case .landscapeRight:
            transformFromOrientation = CGAffineTransform(rotationAngle: -1 * .halfPi)
        case .faceUp, .faceDown, .unknown:
            // don't touch transform
            return
        }

        // Don't "unrotate" the switch camera icon if the front facing camera had been selected.
        let tranformFromCameraType: CGAffineTransform = photoCapture.desiredPosition == .front ? CGAffineTransform(rotationAngle: .pi) : .identity

        let updateOrientation = {
            self.flashModeControl.button.transform = transformFromOrientation
            self.switchCameraControl.button.transform   = transformFromOrientation.concatenating(tranformFromCameraType)
        }

        if isAnimated {
            UIView.animate(withDuration: 0.3, animations: updateOrientation)
        } else {
            updateOrientation()
        }
    }

    private func setupPhotoCapture() {
        photoCapture = PhotoCapture()
        photoCapture.delegate = self
        captureButton.delegate = photoCapture
        previewView = CapturePreviewView(session: photoCapture.session)

        photoCapture.startCapture().done { [weak self] in
            guard let self = self else { return }

            self.showCaptureUI()
        }.catch { [weak self] error in
            guard let self = self else { return }

            self.showFailureUI(error: error)
        }.retainUntilComplete()
    }

    private func setupOrientationMonitoring() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didChangeDeviceOrientation),
                                               name: .UIDeviceOrientationDidChange,
                                               object: UIDevice.current)
    }

    private func showCaptureUI() {
        Logger.debug("")
        view.addSubview(previewView)
        previewView.autoPinEdgesToSuperviewEdges()

        view.addSubview(captureButton)
        captureButton.autoHCenterInSuperview()
        let captureButtonDiameter: CGFloat = 80
        captureButton.autoSetDimensions(to: CGSize(width: captureButtonDiameter, height: captureButtonDiameter))
        captureButton.autoPinEdge(toSuperviewMargin: .bottom, withInset: 30)
    }

    private func showFailureUI(error: Error) {
        Logger.error("error: \(error)")

        OWSAlerts.showAlert(title: nil,
                            message: error.localizedDescription,
                            buttonTitle: CommonStrings.dismissButton,
                            buttonAction: { [weak self] _ in self?.dismiss(animated: true) })
    }

    private func updateFlashModeControl() {
        let imageName: String
        switch photoCapture.flashMode {
        case .auto:
            imageName = "ic_flash_mode_auto"
        case .on:
            imageName = "ic_flash_mode_on"
        case .off:
            imageName = "ic_flash_mode_off"
        }

        self.flashModeControl.setImage(imageName: imageName)
    }
}

extension PhotoCaptureViewController: PhotoCaptureDelegate {
    func photoCapture(_ photoCapture: PhotoCapture, didFinishProcessingAttachment attachment: SignalAttachment) {
        delegate?.photoCaptureViewController(self, didFinishProcessingAttachment: attachment)
    }

    func photoCapture(_ photoCapture: PhotoCapture, processingDidError error: Error) {
        showFailureUI(error: error)
    }

    func photoCaptureDidBeginVideo(_ photoCapture: PhotoCapture) {
        isRecordingMovie = true
        updateNavigationItems()
        recordingTimerView.startCounting()
    }

    func photoCaptureDidCompleteVideo(_ photoCapture: PhotoCapture) {
        // Stop counting, but keep visible
        recordingTimerView.stopCounting()
    }

    func photoCaptureDidCancelVideo(_ photoCapture: PhotoCapture) {
        owsFailDebug("If we ever allow this, we should test.")
        isRecordingMovie = false
        recordingTimerView.stopCounting()
        updateNavigationItems()
    }

    var zoomScaleReferenceHeight: CGFloat? {
        return view.bounds.height
    }
}

protocol PhotoCaptureDelegate: AnyObject {
    func photoCapture(_ photoCapture: PhotoCapture, didFinishProcessingAttachment attachment: SignalAttachment)
    func photoCapture(_ photoCapture: PhotoCapture, processingDidError error: Error)

    func photoCaptureDidBeginVideo(_ photoCapture: PhotoCapture)
    func photoCaptureDidCompleteVideo(_ photoCapture: PhotoCapture)
    func photoCaptureDidCancelVideo(_ photoCapture: PhotoCapture)
    var zoomScaleReferenceHeight: CGFloat? { get }
}

class PhotoCapture: NSObject {

    weak var delegate: PhotoCaptureDelegate?
    var flashMode: AVCaptureDevice.FlashMode {
        return captureOutput.flashMode
    }
    let session: AVCaptureSession

    private let sessionQueue = DispatchQueue(label: "PhotoCapture.sessionQueue")
    private var currentCaptureInput: AVCaptureDeviceInput?
    private let captureOutput: CaptureOutputAdapter
    var currentCaptureDevice: AVCaptureDevice? {
        return currentCaptureInput?.device
    }
    private(set) var desiredPosition: AVCaptureDevice.Position = .back

    override init() {
        self.session = AVCaptureSession()
        self.captureOutput = CaptureOutputAdapter()
    }

    func startCapture() -> Promise<Void> {
        return sessionQueue.async(.promise) { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()

            try self.updateCurrentInput(position: .back)

            let audioDevice = AVCaptureDevice.default(for: .audio)
            // verify works without audio permissions
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
            if self.session.canAddInput(audioDeviceInput) {
                self.session.addInput(audioDeviceInput)
            } else {
                owsFailDebug("Could not add audio device input to the session")
            }

            guard let photoOutput = self.captureOutput.photoOutput else {
                throw PhotoCaptureError.initializationFailed
            }

            // because it takes a moment to initialize outputs, we initially and immediately
            // add the photo output. If the user indicates they want to take video, we add
            // video output later.
            guard self.session.canAddOutput(photoOutput) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addOutput(photoOutput)

            self.session.commitConfiguration()

            self.session.startRunning()
        }
    }

    func stopCapture() -> Guarantee<Void> {
        return sessionQueue.async(.promise) {
            self.session.stopRunning()
        }
    }

    func switchCamera() -> Promise<Void> {
        let newPosition: AVCaptureDevice.Position
        switch desiredPosition {
        case .front:
            newPosition = .back
        case .back:
            newPosition = .front
        case .unspecified:
            newPosition = .front
        }
        desiredPosition = newPosition

        return sessionQueue.async(.promise) { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()
            try self.updateCurrentInput(position: newPosition)
            self.session.commitConfiguration()
        }
    }

    // This method should be called on the serial queue,
    // and between calls to session.beginConfiguration/commitConfiguration
    func updateCurrentInput(position: AVCaptureDevice.Position) throws {
        assertOnSessionQueue()

        guard let device = captureOutput.videoDevice(position: position) else {
            throw PhotoCaptureError.assertionError(description: description)
        }

        // TODO (avcam)
        // if let connection = self.movieFileOutput?.connection(with: .video) {
        //     if connection.isVideoStabilizationSupported {
        //         connection.preferredVideoStabilizationMode = .auto
        //     }
        // }

        let newInput = try AVCaptureDeviceInput(device: device)

        if let oldInput = self.currentCaptureInput {
            session.removeInput(oldInput)
            NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: oldInput.device)
        }
        session.addInput(newInput)
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: newInput.device)

        currentCaptureInput = newInput
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
            }
        }
    }

    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }

    func focus(with focusMode: AVCaptureDevice.FocusMode,
               exposureMode: AVCaptureDevice.ExposureMode,
               at devicePoint: CGPoint,
               monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            guard let device = self.currentCaptureDevice else {
                owsFailDebug("device was unexpectedly nil")
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

    // MARK: - Zoom

    let minimumZoom: CGFloat = 1.0
    let maximumZoom: CGFloat = 3.0
    var previousZoomFactor: CGFloat = 1.0

    func updateZoom(alpha: CGFloat) {
        assert(alpha >= 0 && alpha <= 1)
        sessionQueue.async {
            guard let currentCaptureDevice = self.currentCaptureDevice else {
                owsFailDebug("currentCaptureDevice was unexpectedly nil")
                return
            }

            // we might want this to be non-linear 
            let scale = CGFloatLerp(self.minimumZoom, self.maximumZoom, alpha)
            let zoomFactor = self.clampZoom(scale, device: currentCaptureDevice)
            self.updateZoom(factor: zoomFactor)
        }
    }

    func updateZoom(scaleFromPreviousZoomFactor scale: CGFloat) {
        sessionQueue.async {
            guard let currentCaptureDevice = self.currentCaptureDevice else {
                owsFailDebug("currentCaptureDevice was unexpectedly nil")
                return
            }

            let zoomFactor = self.clampZoom(scale * self.previousZoomFactor, device: currentCaptureDevice)
            self.updateZoom(factor: zoomFactor)
        }
    }

    func completeZoom(scaleFromPreviousZoomFactor scale: CGFloat) {
        sessionQueue.async {
            guard let currentCaptureDevice = self.currentCaptureDevice else {
                owsFailDebug("currentCaptureDevice was unexpectedly nil")
                return
            }

            let zoomFactor = self.clampZoom(scale * self.previousZoomFactor, device: currentCaptureDevice)

            Logger.debug("ended with scaleFactor: \(zoomFactor)")

            self.previousZoomFactor = zoomFactor
            self.updateZoom(factor: zoomFactor)
        }
    }

    func assertOnSessionQueue() {
        // TODO
    }

    private func updateZoom(factor: CGFloat) {
        assertOnSessionQueue()
        guard let currentCaptureDevice = self.currentCaptureDevice else {
            owsFailDebug("currentCaptureDevice was unexpectedly nil")
            return
        }

        do {
            try currentCaptureDevice.lockForConfiguration()
            currentCaptureDevice.videoZoomFactor = factor
            currentCaptureDevice.unlockForConfiguration()
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    private func clampZoom(_ factor: CGFloat, device: AVCaptureDevice) -> CGFloat {
        return min(factor.clamp(minimumZoom, maximumZoom), device.activeFormat.videoMaxZoomFactor)
    }
}

extension PhotoCapture: CaptureButtonDelegate {

    // MARK: - Photo

    func didTapCaptureButton(_ captureButton: CaptureButton) {
        Logger.verbose("")
        sessionQueue.async {
            self.captureOutput.takePhoto(delegate: self)
        }
    }

    // MARK: - Video

    func didBeginLongPressCaptureButton(_ captureButton: CaptureButton) {
        Logger.verbose("")
        sessionQueue.async {
            self.captureOutput.beginVideo(delegate: self)
        }

        AssertIsOnMainThread()
        delegate?.photoCaptureDidBeginVideo(self)
    }

    func didCompleteLongPressCaptureButton(_ captureButton: CaptureButton) {
        Logger.verbose("")
        sessionQueue.async {
            self.captureOutput.completeVideo(delegate: self)
        }
        AssertIsOnMainThread()
        delegate?.photoCaptureDidCompleteVideo(self)
    }

    func didCancelLongPressCaptureButton(_ captureButton: CaptureButton) {
        Logger.verbose("")
        AssertIsOnMainThread()
        delegate?.photoCaptureDidCancelVideo(self)
    }

    var zoomScaleReferenceHeight: CGFloat? {
        return delegate?.zoomScaleReferenceHeight
    }

    func longPressCaptureButton(_ captureButton: CaptureButton, didUpdateZoomAlpha zoomAlpha: CGFloat) {
        Logger.verbose("zoomAlpha: \(zoomAlpha)")
        updateZoom(alpha: zoomAlpha)
    }
}

extension PhotoCapture: CaptureOutputDelegate {

    // MARK: - Photo

    func captureOutputDidFinishProcessing(photoData: Data?, error: Error?) {
        if let error = error {
            delegate?.photoCapture(self, processingDidError: error)
            return
        }

        guard let photoData = photoData else {
            owsFailDebug("photoData was unexpectedly nil")
            delegate?.photoCapture(self, processingDidError: PhotoCaptureError.captureFailed)

            return
        }

        let dataSource = DataSourceValue.dataSource(with: photoData, utiType: kUTTypeJPEG as String)
        // TODO - avoid any image recompression.
        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeJPEG as String, imageQuality: .medium)
        delegate?.photoCapture(self, didFinishProcessingAttachment: attachment)
    }

    // MARK: - Movie

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Logger.verbose("")
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Logger.verbose("")
        if let error = error {
            delegate?.photoCapture(self, processingDidError: error)
            return
        }

        let dataSource = DataSourcePath.dataSource(with: outputFileURL, shouldDeleteOnDeallocation: true)
        // TODO - avoid any video recompression.
        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeMPEG4 as String)
        delegate?.photoCapture(self, didFinishProcessingAttachment: attachment)
    }
}

// MARK: - Capture Adapter

protocol CaptureOutputDelegate: AVCaptureFileOutputRecordingDelegate {
    var session: AVCaptureSession { get }
    func captureOutputDidFinishProcessing(photoData: Data?, error: Error?)
}

protocol ImageCaptureOutputAdaptee: AnyObject {
    var avOutput: AVCaptureOutput { get }
    var flashMode: AVCaptureDevice.FlashMode { get set }
    func videoDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice?

    func takePhoto(delegate: CaptureOutputDelegate)
}

class CaptureOutputAdapter {

    let imageCaptureOutputAdaptee: ImageCaptureOutputAdaptee

    init() {
        if #available(iOS 10.0, *) {
            imageCaptureOutputAdaptee = PhotoCaptureOutputAdaptee()
        } else {
            imageCaptureOutputAdaptee = StillImageCaptureOutputAdaptee()
        }
    }

    var photoOutput: AVCaptureOutput? {
        return imageCaptureOutputAdaptee.avOutput
    }

    var flashMode: AVCaptureDevice.FlashMode {
        get { return imageCaptureOutputAdaptee.flashMode }
        set { imageCaptureOutputAdaptee.flashMode = newValue }
    }

    func videoDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return imageCaptureOutputAdaptee.videoDevice(position: position)
    }

    func takePhoto(delegate: CaptureOutputDelegate) {
        // Adding photoOutput here is too late - there is noticeable delay
        // and the output is notably dark, as if the camera is still initializing
        //
        //        let session = delegate.session
        //        guard session.canAddOutput(avOutput) else {
        //            session.commitConfiguration()
        //            return
        //        }
        //        session.addOutput(avOutput)

        guard let photoOutput = photoOutput else {
            owsFailDebug("photoOutput was unexpectedly nil")
            return
        }

        guard let videoConnection = photoOutput.connection(with: .video) else {
            owsFailDebug("videoConnection was unexpectedly nil")
            return
        }

        if let videoOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) {
            videoConnection.videoOrientation = videoOrientation
        } // else do nothing for "faceUp" / "faceDown" orientations

        return imageCaptureOutputAdaptee.takePhoto(delegate: delegate)
    }

    // MARK: - Movie Output

    private var movieFileOutput: AVCaptureMovieFileOutput?

    var isRecordingVideo: Bool {
        return movieFileOutput != nil
    }

    func beginVideo(delegate: CaptureOutputDelegate) {
        // TODO?
        // updateVideoOrientation()

        let session = delegate.session

        let movieFileOutput = AVCaptureMovieFileOutput()

        if session.canAddOutput(movieFileOutput) {
            session.beginConfiguration()

            if let photoOutput = photoOutput {
                session.removeOutput(photoOutput)
                // TODO
                // self.photoOutput = nil
            } else {
                // This might happen if we allow the user to cancekl and restart video or something.
                owsFailDebug("photoOutput was unexpectedly nil")
            }

            session.addOutput(movieFileOutput)
            session.sessionPreset = .high
            if let connection = movieFileOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            session.commitConfiguration()

            self.movieFileOutput = movieFileOutput

            guard let videoConnection = movieFileOutput.connection(with: .video) else {
                owsFailDebug("movieFileOutputConnection was unexpectedly nil")
                return
            }

            if let videoOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) {
                videoConnection.videoOrientation = videoOrientation
            } // else do nothing for "faceUp" / "faceDown" orientations

            let outputFilePath = OWSFileSystem.temporaryFilePath(withFileExtension: "mp4")
            movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: delegate)
        }
    }

    func completeVideo(delegate: CaptureOutputDelegate) {
        guard let movieFileOutput = movieFileOutput else {
            owsFailDebug("movieFileOutput was unexpectedly nil")
            return
        }

        movieFileOutput.stopRecording()
    }

    func cancelVideo(delegate: CaptureOutputDelegate) {
        // TODO
    }
}

@available(iOS 10.0, *)
class PhotoCaptureOutputAdaptee: NSObject, ImageCaptureOutputAdaptee {

    let photoOutput = AVCapturePhotoOutput()
    var avOutput: AVCaptureOutput {
        return photoOutput
    }

    var flashMode: AVCaptureDevice.FlashMode = .auto

    override init() {
        photoOutput.isLivePhotoCaptureEnabled = false
        photoOutput.isHighResolutionCaptureEnabled = true
    }

    // FIXME: the DelegateWrapper needs to be retained until processing is complete.
    // this works, but we want to clean up the DelegateWrappers eventually.
    private var delegateWrappers: [DelegateWrapper] = []

    func takePhoto(delegate: CaptureOutputDelegate) {
        let settings = buildCaptureSettings()

        let delegateWrapper = DelegateWrapper(delegate: delegate)
        delegateWrappers.append(delegateWrapper)
        photoOutput.capturePhoto(with: settings, delegate: delegateWrapper)
    }

    func videoDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: -

    private func buildCaptureSettings() -> AVCapturePhotoSettings {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.flashMode = flashMode

        photoSettings.isAutoStillImageStabilizationEnabled =
            photoOutput.isStillImageStabilizationSupported

        return photoSettings
    }

    private class DelegateWrapper: NSObject, AVCapturePhotoCaptureDelegate {
        weak var delegate: CaptureOutputDelegate?
        init(delegate: CaptureOutputDelegate) {
            self.delegate = delegate
        }

        // The AVCapturePhotoOutput is available for iOS10, but not this particular delegate method.
        // We either need an equivalent delegate method for iOS10, or we could use the legacy adapter for iOS10.
        @available(iOS 11.0, *)
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            self.delegate?.captureOutputDidFinishProcessing(photoData: photo.fileDataRepresentation(), error: error)
        }
    }
}

class StillImageCaptureOutputAdaptee: ImageCaptureOutputAdaptee {
    var flashMode: AVCaptureDevice.FlashMode = .auto

    let stillImageOutput = AVCaptureStillImageOutput()
    var avOutput: AVCaptureOutput {
        return stillImageOutput
    }

    init() {
        stillImageOutput.isHighResolutionStillImageOutputEnabled = true
    }

    // MARK: -

    func takePhoto(delegate: CaptureOutputDelegate) {
        Logger.verbose("TODO")
    }

    func videoDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let captureDevices = AVCaptureDevice.devices()
        guard let device = (captureDevices.first { $0.hasMediaType(.video) && $0.position == position }) else {
            Logger.debug("unable to find desired position: \(position)")
            return captureDevices.first
        }

        return device
    }
}

// MARK: - Views

protocol CaptureButtonDelegate: AnyObject {
    // MARK: Photo
    func didTapCaptureButton(_ captureButton: CaptureButton)

    // MARK: Video
    func didBeginLongPressCaptureButton(_ captureButton: CaptureButton)
    func didCompleteLongPressCaptureButton(_ captureButton: CaptureButton)
    func didCancelLongPressCaptureButton(_ captureButton: CaptureButton)

    var zoomScaleReferenceHeight: CGFloat? { get }
    func longPressCaptureButton(_ captureButton: CaptureButton, didUpdateZoomAlpha zoomAlpha: CGFloat)
}

class CaptureButton: UIView {

    let innerButton = CircleView()

    var tapGesture: UITapGestureRecognizer!

    var longPressGesture: UILongPressGestureRecognizer!
    let longPressDuration = 0.5

    let zoomIndicator = CircleView()

    weak var delegate: CaptureButtonDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        innerButton.addGestureRecognizer(tapGesture)

        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(didLongPress))
        longPressGesture.minimumPressDuration = longPressDuration
        innerButton.addGestureRecognizer(longPressGesture)

        addSubview(innerButton)
        innerButton.backgroundColor = UIColor.ows_white.withAlphaComponent(0.33)
        innerButton.layer.shadowOffset = .zero
        innerButton.layer.shadowOpacity = 0.33
        innerButton.layer.shadowRadius = 2
        innerButton.autoPinEdgesToSuperviewEdges()

        zoomIndicator.isUserInteractionEnabled = false
        addSubview(zoomIndicator)
        zoomIndicator.layer.borderColor = UIColor.ows_white.cgColor
        zoomIndicator.layer.borderWidth = 1.5
        zoomIndicator.autoPin(toEdgesOf: innerButton)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Gestures

    @objc
    func didTap(_ gesture: UITapGestureRecognizer) {
        delegate?.didTapCaptureButton(self)
    }

    var initialTouchLocation: CGPoint?

    @objc
    func didLongPress(_ gesture: UILongPressGestureRecognizer) {
        Logger.verbose("")

        guard let gestureView = gesture.view else {
            owsFailDebug("gestureView was unexpectedly nil")
            return
        }

        switch gesture.state {
        case .possible: break
        case .began:
            initialTouchLocation = gesture.location(in: gesture.view)
            zoomIndicator.transform = .identity
            delegate?.didBeginLongPressCaptureButton(self)
        case .changed:
            guard let referenceHeight = delegate?.zoomScaleReferenceHeight else {
                owsFailDebug("referenceHeight was unexpectedly nil")
                return
            }

            guard referenceHeight > 0 else {
                owsFailDebug("referenceHeight was unexpectedly <= 0")
                return
            }

            guard let initialTouchLocation = initialTouchLocation else {
                owsFailDebug("initialTouchLocation was unexpectedly nil")
                return
            }

            let currentLocation = gesture.location(in: gestureView)
            let minDistanceBeforeActivatingZoom: CGFloat = 50
            let distance = initialTouchLocation.y - currentLocation.y - minDistanceBeforeActivatingZoom
            let distanceForFullZoom = referenceHeight / 3
            let ratio = distance / distanceForFullZoom

            let alpha = ratio.clamp(0, 1)

            Logger.verbose("distance: \(distance), alpha: \(alpha)")

            let transformScale = max(1 - alpha, 0.5)
            zoomIndicator.transform = CGAffineTransform(scaleX: transformScale, y: transformScale)
            zoomIndicator.superview?.layoutIfNeeded()

            delegate?.longPressCaptureButton(self, didUpdateZoomAlpha: alpha)
        case .ended:
            zoomIndicator.transform = .identity
            delegate?.didCompleteLongPressCaptureButton(self)
        case .cancelled, .failed:
            zoomIndicator.transform = .identity
            delegate?.didCancelLongPressCaptureButton(self)
        }
    }
}

class CapturePreviewView: UIView {

    let previewLayer: AVCaptureVideoPreviewLayer

    override var bounds: CGRect {
        didSet {
            previewLayer.frame = bounds
        }
    }

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        previewLayer.frame = bounds
        layer.addSublayer(previewLayer)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }

    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

class RecordingTimerView: UIView {

    private lazy var label: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_monospacedDigitFont(withSize: 17)
        label.textAlignment = .center
        label.textColor = UIColor.white
        label.layer.shadowOffset = CGSize.zero
        label.layer.shadowOpacity = 0.35
        label.layer.shadowRadius = 4

        return label
    }()

    private let icon: UIView = {
        let icon = CircleView()
        icon.layer.shadowOffset = CGSize.zero
        icon.layer.shadowOpacity = 0.35
        icon.layer.shadowRadius = 4

        return icon
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        icon.backgroundColor = .red
        icon.autoSetDimensions(to: CGSize(width: 6, height: 6))
        icon.alpha = 0

        let stackView = UIStackView(arrangedSubviews: [icon, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4

        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        updateView()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -
    var recordingStartTime: TimeInterval?

    func startCounting() {
        recordingStartTime = CACurrentMediaTime()
        timer = Timer.weakScheduledTimer(withTimeInterval: 0.1, target: self, selector: #selector(updateView), userInfo: nil, repeats: true)
        UIView.animate(withDuration: 0.8,
                       delay: 0,
                       options: [.autoreverse, .repeat],
                       animations: { self.icon.alpha = 1 })
    }

    func stopCounting() {
        timer?.invalidate()
        timer = nil
        icon.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.4) {
            self.icon.alpha = 0
        }
    }

    // MARK: -

    private var timer: Timer?

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")!

        return formatter
    }()

    // This method should only be called when the call state is "connected".
    var recordingDuration: TimeInterval {
        guard let recordingStartTime = recordingStartTime else {
            return 0
        }

        return CACurrentMediaTime() - recordingStartTime
    }

    @objc
    private func updateView() {
        let recordingDuration = self.recordingDuration
        Logger.verbose("recordingDuration: \(recordingDuration)")
        let durationDate = Date(timeIntervalSinceReferenceDate: recordingDuration)
        label.text = timeFormatter.string(from: durationDate)
    }
}
