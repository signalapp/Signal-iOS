//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation
import PromiseKit
import Vision

@objc
protocol QRCodeScanDelegate: AnyObject {
    func qrCodeScanView(_ qrCodeScanViewController: QRCodeScanViewController,
                        didDetectQRCodeString value: String)
    func qrCodeScanView(_ qrCodeScanViewController: QRCodeScanViewController,
                        didDetectQRCodeData value: Data)
}

// MARK: -

@objc
class QRCodeScanViewController: OWSViewController {
    @objc
    weak var delegate: QRCodeScanDelegate?

    private var scanner: QRCodeScanner?

    deinit {
        stopScanning()
    }

    override var prefersStatusBarHidden: Bool {
        guard !OWSWindowManager.shared.hasCall else {
            return false
        }

        return true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

//    private var previewView: CapturePreviewView {
//        return scanner.previewView
//    }

    // MARK: - View Lifecycle

    @objc
    override func viewDidLoad() {
        AssertIsOnMainThread()

        super.viewDidLoad()

        view.backgroundColor = .ows_black

        addObservers()
    }

    public override func viewDidAppear(_ animated: Bool) {
        AssertIsOnMainThread()

        super.viewDidAppear(animated)

        tryToStartScanning()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        AssertIsOnMainThread()

        super.viewDidDisappear(animated)

        stopScanning()
    }

    // MARK: - Notifications

    private func addObservers() {
        AssertIsOnMainThread()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
    }

    @objc func didEnterBackground() {
        AssertIsOnMainThread()

        stopScanning()
    }

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        tryToStartScanning()
    }

    // MARK: - Scanning

    private func stopScanning() {
        scanner?.stopCapture().done {
            Logger.debug("stopCapture completed")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
        scanner = nil
    }

    private func tryToStartScanning() {
        AssertIsOnMainThread()

        guard nil == scanner else {
            return
        }

        self.ows_askForCameraPermissions { [weak self] granted in
            guard let self = self else { return }

            if granted {
                // Camera stops capturing when "sharing" while in capture mode.
                // Also, it's less obvious whats being "shared" at this point,
                // so just disable sharing when in capture mode.
                self.startScanning()
            } else {
                self.navigationController?.popViewController(animated: true)
            }
        }
    }

    private func startScanning() {
        AssertIsOnMainThread()

        guard nil == scanner else {
            return
        }

        view.removeAllSubviews()

        let scanner = QRCodeScanner(sampleBufferDelegate: self)
        self.scanner = scanner

        let previewView = scanner.previewView
        view.addSubview(previewView)
        previewView.autoPinEdgesToSuperviewEdges()

        let maskingView = OWSBezierPathView()
        maskingView.configureShapeLayerBlock = { (layer, bounds) in
            // Add a circular mask
            let path = UIBezierPath(rect: bounds)
            let margin = ScaleFromIPhone5To7Plus(8, 16)

            // Center the circle's bounding rectangle
            let circleDiameter = bounds.size.smallerAxis - margin * 2
            let circleSize = CGSize.square(circleDiameter)
            let circleRect = CGRect(origin: (bounds.size - circleSize).asPoint * 0.5,
                                    size: circleSize)
            let circlePath = UIBezierPath(roundedRect: circleRect,
                                          cornerRadius: circleDiameter / 2)
            path.append(circlePath)
            path.usesEvenOddFillRule = true

            layer.path = path.cgPath
            layer.fillRule = .evenOdd
            layer.fillColor = UIColor.gray.cgColor
            layer.opacity = 0.5
        }
        self.view.addSubview(maskingView)
        maskingView.autoPinEdgesToSuperviewEdges()

//    }
//
//    var hasCaptureStarted = false
//    private func setupPhotoCapture() {
//        photoCapture.delegate = self
//        captureButton.delegate = photoCapture

//        let captureReady = { [weak self] in
//            guard let self = self else { return }
//            self.hasCaptureStarted = true
//            BenchEventComplete(eventId: "Show-Camera")
//        }
//
//        // If the session is already running, we're good to go.
//        guard !photoCapture.session.isRunning else {
//            return captureReady()
//        }

        firstly {
            scanner.startVideoCapture()
        }.done {
            Logger.info("Ready.")
//            captureReady()
        }.catch { [weak self] error in
            owsFailDebug("Error: \(error)")
            guard let self = self else { return }
            self.showFailureUI(error: error)
        }
    }

    private func showFailureUI(error: Error) {
        Logger.error("error: \(error)")

        OWSActionSheets.showActionSheet(title: nil,
                                        message: error.localizedDescription,
                                        buttonTitle: CommonStrings.dismissButton,
                                        buttonAction: { [weak self] _ in self?.dismiss(animated: true) })
    }

    private lazy var detectQRCodeRequest: VNDetectBarcodesRequest = {
        let request = VNDetectBarcodesRequest { request, error in
            if let error = error {
                DispatchQueue.main.async { [weak self] in
                    self?.showFailureUI(error: error)
                }
                return
            }
            self.processClassification(request)
        }

        if VNDetectBarcodesRequest.supportedSymbologies.contains(.QR) {
            request.symbologies = [ .QR ]
        } else {
            owsFailDebug("Does not support .QR.")
        }

        return request
    }()

    private func processClassification(_ request: VNRequest) {
        func filterBarcodes() -> [VNBarcodeObservation] {
            guard let results = request.results else {
                return []
            }
            return results.compactMap {
                $0 as? VNBarcodeObservation
            }.filter { (barcode: VNBarcodeObservation) in
                barcode.symbology == .QR &&
                    barcode.confidence > 0.9
            }
        }
        let barcodes = filterBarcodes()
        guard !barcodes.isEmpty else {
            return
        }
        for barcode in barcodes {
            if let payloadStringValue = barcode.payloadStringValue {
                Logger.verbose("payloadStringValue: \(payloadStringValue)")
            }
            if let barcodeDescriptor = barcode.barcodeDescriptor {
                Logger.verbose("barcodeDescriptor: \(barcodeDescriptor)")
            }
        }
//
//
//
//        /**
//         @brief The string representation of the barcode's payload.  Depending on the symbology of the barcode and/or the payload data itself, a string representation of the payload may not be available.
//         */
//        open var payloadStringValue: String? { get }
//
//        DispatchQueue.main.async { [self] in
//            if captureSession.isRunning {
//                view.layer.sublayers?.removeSubrange(1...)
//
//                // 2
//                for barcode in barcodes {
//                    guard
//                        // TODO: Check for QR Code symbology and confidence score
//                        let potentialQRCode = barcode as? VNBarcodeObservation
//                    else { return }
//
//                    // 3
//                    showAlert(
//                        withTitle: potentialQRCode.symbology.rawValue,
//                        // TODO: Check the confidence score
//                        message: potentialQRCode.payloadStringValue ?? "" )
//                }
//            }
//        }
    }
}

// MARK: -

extension QRCodeScanViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            owsFailDebug("Missing pixelBuffer.")
            return
        }
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                        orientation: .right)
        do {
            try imageRequestHandler.perform([detectQRCodeRequest])
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }
}

// MARK: -

// extension QRCodeScanViewController: PhotoCaptureDelegate {
//
//    // MARK: - Photo
//
//    func photoCaptureDidStartPhotoCapture(_ photoCapture: PhotoCapture) {
//        let captureFeedbackView = UIView()
//        captureFeedbackView.backgroundColor = .black
//        view.insertSubview(captureFeedbackView, aboveSubview: previewView)
//        captureFeedbackView.autoPinEdgesToSuperviewEdges()
//
//        // Ensure the capture feedback is laid out before we remove it,
//        // depending on where we're coming from a layout pass might not
//        // trigger in 0.05 seconds otherwise.
//        view.setNeedsLayout()
//        view.layoutIfNeeded()
//
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
//            captureFeedbackView.removeFromSuperview()
//        }
//    }
//
//    func photoCapture(_ photoCapture: PhotoCapture, didFinishProcessingAttachment attachment: SignalAttachment) {
//        delegate?.photoCaptureViewController(self, didFinishProcessingAttachment: attachment)
//    }
//
//    func photoCapture(_ photoCapture: PhotoCapture, processingDidError error: Error) {
//        showFailureUI(error: error)
//    }
//
//    func photoCaptureCanCaptureMoreItems(_ photoCapture: PhotoCapture) -> Bool {
//        guard let delegate = delegate else { return false }
//        return delegate.photoCaptureViewControllerCanCaptureMoreItems(self)
//    }
//
//    func photoCaptureDidTryToCaptureTooMany(_ photoCapture: PhotoCapture) {
//        delegate?.photoCaptureViewControllerDidTryToCaptureTooMany(self)
//    }
//
//
//
//    //    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
//    //        super.viewWillTransition(to: size, with: coordinator)
//    //
//    //        if UIDevice.current.isIPad {
//    //            // Since we support iPad multitasking, we cannot *disable* rotation of our views.
//    //            // Rotating the preview layer is really distracting, so we fade out the preview layer
//    //            // while the rotation occurs.
//    //            self.previewView.alpha = 0
//    //            coordinator.animate(alongsideTransition: { _ in }) { _ in
//    //                UIView.animate(withDuration: 0.1) {
//    //                    self.previewView.alpha = 1
//    //                }
//    //            }
//    //        }
//    //    }
//    //
//    //    override func viewSafeAreaInsetsDidChange() {
//    //        super.viewSafeAreaInsetsDidChange()
//    //        if !UIDevice.current.isIPad {
//    //            // we pin to a constant rather than margin, because on notched devices the
//    //            // safeAreaInsets/margins change as the device rotates *EVEN THOUGH* the interface
//    //            // is locked to portrait.
//    //            // Only grab this once -- otherwise when we swipe to dismiss this is updated and the top bar jumps to having zero offset
//    //            if topBarOffset.constant == 0 {
//    //                topBarOffset.constant = max(view.safeAreaInsets.top, view.safeAreaInsets.left, view.safeAreaInsets.bottom)
//    //            }
//    //        }
//    //    }
//    //
//    //
// }

// MARK: -

enum QRCodeScanError: Error {
    case assertionError(description: String)
    case initializationFailed
    case captureFailed
}

// MARK: -

private class QRCodeScanner {

    //    weak var delegate: PhotoCaptureDelegate?

    lazy private(set) var previewView = QRCodeScanPreviewView(session: session)

    private let sessionQueue = DispatchQueue(label: "QRCodeScanner.sessionQueue")

    let session = AVCaptureSession()
    let output: QRCodeScanOutput

//    private var currentCaptureInput: AVCaptureDeviceInput?
//    private var captureDevice: AVCaptureDevice? {
//        return currentCaptureInput?.device
//    }
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

    required init(sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        output = QRCodeScanOutput(sampleBufferDelegate: sampleBufferDelegate)
    }

    // MARK: - Public

    //    public var flashMode: AVCaptureDevice.FlashMode {
    //        return captureOutput.flashMode
    //    }

    @objc
    private func orientationDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let captureOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) else {
            return
        }

        sessionQueue.async {
            guard captureOrientation != self.captureOrientation else {
                return
            }
            self.captureOrientation = captureOrientation

            //            DispatchQueue.main.async {
            //                self.delegate?.photoCapture(self, didChangeOrientation: captureOrientation)
            //            }
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
//            guard let delegate = self.delegate else { return }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            self.captureOrientation = initialCaptureOrientation
            // TODO:
            self.session.sessionPreset = .high

            try self.setCurrentInput(position: .back)

//            guard let photoOutput = self.output.photoOutput else {
//                owsFailDebug("Missing photoOutput.")
//                throw QRCodeScanError.initializationFailed
//            }
//
//            guard self.session.canAddOutput(photoOutput) else {
//                owsFailDebug("!canAddOutput(photoOutput).")
//                throw QRCodeScanError.initializationFailed
//            }
//            self.session.addOutput(photoOutput)

//            if let connection = photoOutput.connection(with: .video) {
//                if connection.isVideoStabilizationSupported {
//                    connection.preferredVideoStabilizationMode = .auto
//                }
//            }

            let videoDataOutput = self.output.videoDataOutput
            guard self.session.canAddOutput(videoDataOutput) else {
                owsFailDebug("!canAddOutput(videoDataOutput).")
                throw QRCodeScanError.initializationFailed
            }
            self.session.addOutput(videoDataOutput)
            guard let connection = videoDataOutput.connection(with: .video) else {
                owsFailDebug("Missing videoDataOutput.connection.")
                throw QRCodeScanError.initializationFailed
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
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

    //    public func switchCamera() -> Promise<Void> {
    //        AssertIsOnMainThread()
    //        let newPosition: AVCaptureDevice.Position
    //        switch desiredPosition {
    //        case .front:
    //            newPosition = .back
    //        case .back:
    //            newPosition = .front
    //        case .unspecified:
    //            newPosition = .front
    //        @unknown default:
    //            owsFailDebug("Unexpected enum value.")
    //            newPosition = .front
    //            break
    //        }
    //        desiredPosition = newPosition
    //
    //        return sessionQueue.async(.promise) { [weak self] in
    //            guard let self = self else { return }
    //
    //            self.session.beginConfiguration()
    //            defer { self.session.commitConfiguration() }
    //            try self.setCurrentInput(position: newPosition)
    //        }
    //    }

    // This method should be called on the serial queue,
    // and between calls to session.beginConfiguration/commitConfiguration
    public func setCurrentInput(position: AVCaptureDevice.Position) throws {
//        owsAssertDebug(currentCaptureInput == nil)
        assertIsOnSessionQueue()

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: position) else {
            throw QRCodeScanError.assertionError(description: "Missing videoDevice.")
        }

        try device.lockForConfiguration()

        // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
        // Call set(Focus/Exposure)Mode() to apply the new point of interest.
        let focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
        if device.isFocusModeSupported(focusMode) {
            device.focusMode = focusMode
        }

        let exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
        if device.isExposureModeSupported(exposureMode) {
            device.exposureMode = exposureMode
        }

        device.unlockForConfiguration()

        let newInput = try AVCaptureDeviceInput(device: device)

//        if let oldInput = self.currentCaptureInput {
//            session.removeInput(oldInput)
//        }
        session.addInput(newInput)
//        currentCaptureInput = newInput

//        resetFocusAndExposure()
    }
}

// MARK: -

private class QRCodeScanPreviewView: UIView {

    let previewLayer: AVCaptureVideoPreviewLayer

    override var bounds: CGRect {
        didSet {
            previewLayer.frame = bounds
        }
    }

    override var contentMode: UIView.ContentMode {
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

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: -

private class QRCodeScanOutput {

//    let imageOutput: ImageCaptureOutput

    let videoDataOutput = AVCaptureVideoDataOutput()

    //    let movieRecordingQueue = DispatchQueue(label: "CaptureOutput.movieRecordingQueue", qos: .userInitiated)
    //    var movieRecording: MovieRecording?

    // MARK: - Init

    required init(sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        videoDataOutput.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.setSampleBufferDelegate(
            sampleBufferDelegate,
            queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))

//        imageOutput = PhotoCaptureOutputAdaptee()

//        super.init()

//        videoDataOutput.setSampleBufferDelegate(self, queue: movieRecordingQueue)
    }

//    var photoOutput: AVCaptureOutput? {
//        return imageOutput.avOutput
//    }

//    var flashMode: AVCaptureDevice.FlashMode {
//        get {  imageOutput.flashMode }
//        set { imageOutput.flashMode = newValue }
//    }

//    func videoDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
//        return imageOutput.videoDevice(position: position)
//    }

//    func takePhoto(delegate: CaptureOutputDelegate, captureRect: CGRect) {
//        delegate.assertIsOnSessionQueue()
//
//        guard let photoOutput = photoOutput else {
//            owsFailDebug("photoOutput was unexpectedly nil")
//            return
//        }
//
//        guard let photoVideoConnection = photoOutput.connection(with: .video) else {
//            owsFailDebug("photoVideoConnection was unexpectedly nil")
//            return
//        }
//
//        ImpactHapticFeedback.impactOccured(style: .medium)
//
//        let videoOrientation = delegate.captureOrientation
//        photoVideoConnection.videoOrientation = videoOrientation
//        Logger.verbose("videoOrientation: \(videoOrientation), deviceOrientation: \(UIDevice.current.orientation)")
//
//        return imageOutput.takePhoto(delegate: delegate, captureRect: captureRect)
//    }

    //    // MARK: - Movie Output
    //
    //    func beginMovie(delegate: CaptureOutputDelegate, aspectRatio: CGFloat) throws -> MovieRecording {
    //        delegate.assertIsOnSessionQueue()
    //
    //        guard let videoConnection = videoDataOutput.connection(with: .video) else {
    //            throw OWSAssertionError("videoConnection was unexpectedly nil")
    //        }
    //        let videoOrientation = delegate.captureOrientation
    //        videoConnection.videoOrientation = videoOrientation
    //
    //        assert(movieRecording == nil)
    //        let outputURL = OWSFileSystem.temporaryFileUrl(fileExtension: "mp4")
    //        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    //
    //        guard let recommendedSettings = self.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4) else {
    //            throw OWSAssertionError("videoSettings was unexpectedly nil")
    //        }
    //        guard let capturedWidth: CGFloat = recommendedSettings[AVVideoWidthKey] as? CGFloat else {
    //            throw OWSAssertionError("capturedWidth was unexpectedly nil")
    //        }
    //        guard let capturedHeight: CGFloat = recommendedSettings[AVVideoHeightKey] as? CGFloat else {
    //            throw OWSAssertionError("capturedHeight was unexpectedly nil")
    //        }
    //        let capturedSize = CGSize(width: capturedWidth, height: capturedHeight)
    //
    //        // video specs from Signal-Android: 2Mbps video 192K audio, 720P 30 FPS
    //        let maxDimension: CGFloat = 1280 // 720p
    //
    //        let aspectSize = capturedSize.cropped(toAspectRatio: aspectRatio)
    //        let outputSize = aspectSize.scaledToFit(max: maxDimension)
    //
    //        // See AVVideoSettings.h
    //        let videoSettings: [String: Any] = [
    //            AVVideoWidthKey: outputSize.width,
    //            AVVideoHeightKey: outputSize.height,
    //            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
    //            AVVideoCodecKey: AVVideoCodecH264,
    //            AVVideoCompressionPropertiesKey: [
    //                AVVideoAverageBitRateKey: 2000000,
    //                AVVideoProfileLevelKey: AVVideoProfileLevelH264Baseline41,
    //                AVVideoMaxKeyFrameIntervalKey: 90
    //            ]
    //        ]
    //
    //        Logger.info("videoOrientation: \(videoOrientation), captured: \(capturedWidth)x\(capturedHeight), output: \(outputSize.width)x\(outputSize.height), aspectRatio: \(aspectRatio)")
    //
    //        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    //        videoInput.expectsMediaDataInRealTime = true
    //        assetWriter.add(videoInput)
    //
    //        let audioSettings: [String: Any]? =  self.audioDataOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) as? [String: Any]
    //        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
    //        audioInput.expectsMediaDataInRealTime = true
    //        if audioSettings != nil {
    //            assetWriter.add(audioInput)
    //        } else {
    //            owsFailDebug("audioSettings was unexpectedly nil")
    //        }
    //
    //        return MovieRecording(assetWriter: assetWriter, videoInput: videoInput, audioInput: audioInput)
    //    }
    //
    //    func completeMovie(delegate: CaptureOutputDelegate) {
    //        firstly { () -> Promise<URL> in
    //            assertOnQueue(movieRecordingQueue)
    //            guard let movieRecording = self.movieRecording else {
    //                throw OWSAssertionError("movie recording was unexpectedly nil")
    //            }
    //            self.movieRecording = nil
    //            return movieRecording.finish()
    //        }.done { outputUrl in
    //            delegate.captureOutputDidCapture(movieUrl: .success(outputUrl))
    //        }.catch { error in
    //            delegate.captureOutputDidCapture(movieUrl: .failure(error))
    //        }
    //    }
    //
    //    func cancelVideo(delegate: CaptureOutputDelegate) {
    //        delegate.assertIsOnSessionQueue()
    //        // There's currently no user-visible way to cancel, if so, we may need to do some cleanup here.
    //        owsFailDebug("video was unexpectedly canceled.")
    //    }
}
