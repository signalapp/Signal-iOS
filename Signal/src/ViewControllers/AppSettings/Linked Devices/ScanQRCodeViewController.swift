//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation
import PromiseKit
import Vision

@objc
protocol QRCodeScanDelegate: AnyObject {
    // Should return true IFF the qrCode was accepted.
    func qrCodeScanViewScanned(_ qrCodeScanViewController: QRCodeScanViewController,
                               qrCodeData value: Data,
                               qrCodeString value: String?) -> Bool

    func qrCodeScanViewDismiss(_ qrCodeScanViewController: QRCodeScanViewController)
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

    @objc
    public func tryToStartScanning() {
        AssertIsOnMainThread()

        guard nil == scanner else {
            return
        }

        self.ows_askForCameraPermissions { [weak self] granted in
            guard let self = self else { return }

            if granted {
                self.startScanning()
            } else {
                self.delegate?.qrCodeScanViewDismiss(self)
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

        firstly {
            scanner.startVideoCapture()
        }.done {
            Logger.info("Ready.")
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
                                        buttonAction: { [weak self] _ in
                                            guard let self = self else { return }
                                            self.delegate?.qrCodeScanViewDismiss(self)
                                        })
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
                guard barcode.symbology == .QR else {
                    owsFailDebug("Invalid symbology.")
                    return false
                }
                guard nil != barcode.barcodeDescriptor as? CIQRCodeDescriptor else {
                    owsFailDebug("Invalid barcodeDescriptor.")
                    return false
                }
                guard barcode.confidence > 0.9 else {
                    // Require high confidence.
                    return false
                }
                return true
            }
        }
        let barcodes = filterBarcodes().sorted { (left, right) in
            // If multiple bardcodes found, prefer barcode with higher confidence.
            left.confidence > right.confidence
        }
        guard !barcodes.isEmpty else {
            return
        }
        Logger.verbose("---")
        for barcode in barcodes {
            Logger.verbose("barcode.confidence: \(barcode.confidence)")
            if let payloadStringValue = barcode.payloadStringValue {
                Logger.verbose("payloadStringValue: \(payloadStringValue)")
            }
            if let barcodeDescriptor = barcode.barcodeDescriptor as? CIQRCodeDescriptor {
                Logger.verbose("errorCorrectedPayload: \(barcodeDescriptor.errorCorrectedPayload.base64EncodedString()), symbolVersion: \(barcodeDescriptor.symbolVersion)")
            }
            if let barcodeDescriptor = barcode.barcodeDescriptor {
                Logger.verbose("barcodeDescriptor: \(barcodeDescriptor)")
            }
        }
        if false,
           let barcode = barcodes.first,
//        if let barcode = barcodes.first,
           let barcodeDescriptor = barcode.barcodeDescriptor as? CIQRCodeDescriptor {
            Logger.info("Scanned QR Code.")

            let qrCodeData = barcodeDescriptor.errorCorrectedPayload
            let qrCodeString = barcode.payloadStringValue

            Logger.verbose("----- qrCodeData: \(qrCodeData.count), \(qrCodeData.hexadecimalString)")
            Logger.verbose("----- qrCodeString: \(qrCodeString?.count), \(qrCodeString)")

            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let delegate = self.delegate else {
                    return
                }

                let accepted = delegate.qrCodeScanViewScanned(self, qrCodeData: qrCodeData, qrCodeString: qrCodeString)
                if accepted {
                    self.stopScanning()

                    // Vibrate
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        }
    }
}

// MARK: -

private enum QRCodeError: Error {
    case invalidCodewords
    case unknownMode
    case unsupportedConfiguration
    case invalidLength
}

// MARK: -

// fileprivate class QRCodeBitParser {
//    private let codewords: Data
//
//    private var codewordIndex: UInt = 0
//    private var consumedCodewordBitCount: UInt = 0
//    private var availableBitsAtCurrentCodeword: UInt {
//        guard codewordIndex < codewords.count else {
//            return 0
//        }
//        owsAssertDebug(consumedCodewordBitCount <= 8)
//        return 8 - consumedCodewordBitCount
//    }
//    // Does not include the current codeword.
//    private var remainingCodewordCount: UInt {
//        let processedCodewords = codewordIndex + 1
//        guard codewords.count >= processedCodewords else {
//            return 0
//        }
//        return UInt(codewords.count) - processedCodewords
//    }
//    private var availableBitsTotal: UInt {
//        availableBitsAtCurrentCodeword + (remainingCodewordCount * 8)
//    }
//
//    required init(codewords: Data) {
//        self.codewords = codewords
//    }
//
//    private struct Bits {
//        let bits: UInt
//        let count: UInt
//    }
//
//    private func readBits(count: UInt) throws -> Bits {
//        var bitsToReadCount = count
//        var bits: UInt = 0
//        while bitsToReadCount > 0 {
//            let availableBitsAtCurrentCodeword = self.availableBitsAtCurrentCodeword
//            guard availableBitsAtCurrentCodeword > 0 else {
//                throw QRCodeError.invalidCodewords
//            }
//            if availableBitsAtCurrentCodeword > bitsToReadCount {
//
//            }
//        }
//    }
// }

// MARK: -

// This isn't an efficient way to parse the codewords, but
// correctness matters and perf doesn't, since QR code payloads
// are inherently small.
public class QRCodePayload {
    let version: Int
    let mode: Mode
    let bytes: [UInt8]

    var data: Data {
        Data(bytes)
    }
    var asString: String? {
        String(data: data, encoding: .utf8)
    }

    init(version: Int, mode: Mode, bytes: [UInt8]) {
        self.version = version
        self.mode = mode
        self.bytes = bytes
    }

    public enum Mode: UInt {
        case numeric = 1
        case alphaNumeric = 2
        case bytes = 4
        case kanji = 8
    }
//    // CIQRCodeDescriptor codewords (mode + character count + data + terminator + padding)
//    public static var byteEncodingMode: UInt {  mode.bytes.rawValue }

    public static func parse(codewords: Data,
                             qrCodeVersion version: Int,
                             ignoreUnknownMode: Bool = false) -> QRCodePayload? {
        // QR Code Standard
        // ISO/IEC 18004:2015
        // https://www.iso.org/standard/62021.html
        //
        //
        do {
            let bitstream = QRCodeBitStream(codewords: codewords)

            let modeLength: UInt = 4
            let modeBits = try bitstream.readUInt8(bitCount: modeLength)
            guard let mode = Mode(rawValue: UInt(modeBits)) else {
                if ignoreUnknownMode {
                    owsAssertDebug(CurrentAppContext().isRunningTests)
                    Logger.error("Invalid mode: \(modeBits)")
                    return nil
                } else {
                    owsFailDebug("Invalid mode: \(modeBits)")
                }
                throw QRCodeError.unknownMode
            }
            // TODO: We currently only support .byte mode.
            guard mode == .bytes else {
                Logger.warn("Unsupported mode: \(mode)")
                throw QRCodeError.unsupportedConfiguration
            }

            let characterCountLength = try characterCountIndicatorLengthBits(version: version,
                                                                             mode: mode)
            let characterCount = try bitstream.readUInt32(bitCount: characterCountLength)
            guard characterCount > 0 else {
                Logger.error("Invalid length: \(characterCount)")
                throw QRCodeError.invalidLength
            }
            // TODO: We currently only support .byte mode.
            var bytes = [UInt8]()
            for _ in 0..<characterCount {
                let byte = try bitstream.readUInt8(bitCount: 8)
                bytes.append(byte)
            }
            // TODO:
            return QRCodePayload(version: version, mode: mode, bytes: bytes)
        } catch {
//            if ignoreUnknownMode,
//               let error = error as? QRCodeError,
//               case .unknownMode = error {
//                owsAssertDebug(CurrentAppContext().isRunningTests)
//                Logger.error("Error: \(error)")
//            } else {
            owsFailDebug("Error: \(error)")
//            }
            return nil
        }
    }

    private static func characterCountIndicatorLengthBits(version: Int,
                                                          mode: Mode) throws -> UInt {
        if version >= 1, version <= 9 {
            switch mode {
            case .numeric:
                return 10
            case .alphaNumeric:
                return 9
            case .bytes:
                return 8
            case .kanji:
                return 8
            }
        } else if version >= 10, version <= 26 {
            switch mode {
            case .numeric:
                return 12
            case .alphaNumeric:
                return 11
            case .bytes:
                return 16
            case .kanji:
                return 10
            }
        } else if version >= 27, version <= 40 {
            switch mode {
            case .numeric:
                return 14
            case .alphaNumeric:
                return 13
            case .bytes:
                return 16
            case .kanji:
                return 12
            }
        }
        throw QRCodeError.unsupportedConfiguration
    }
}

// MARK: -

// This isn't an efficient way to parse the codewords, but
// correctness matters and perf doesn't, since QR code payloads
// are inherently small.
private class QRCodeBitStream {
    private var bits: [UInt8]

    required init(codewords: Data) {
        var bits = [UInt8]()
        for codeword in codewords {
            var codeword: UInt8 = codeword
            var codewordBits = [UInt8]()
            for _ in 0..<8 {
                let bit = codeword & 1
                codeword = codeword >> 1
                codewordBits.append(UInt8(bit))
            }
            owsAssertDebug(codeword == 0)
            // We reverse; we want to stream bits in "most significant-to-least-significant"
            // order.
            bits.append(contentsOf: codewordBits.reversed())
        }
        self.bits = bits
    }

    private func readBit() throws -> UInt8 {
        guard !bits.isEmpty else {
            throw QRCodeError.invalidCodewords
        }
        return bits.removeFirst()
    }

    fileprivate func readUInt8(bitCount: UInt) throws -> UInt8 {
        owsAssertDebug(bitCount > 0)
        owsAssertDebug(bitCount <= 8)

        return UInt8(try readUInt32(bitCount: bitCount))
    }

    fileprivate func readUInt32(bitCount: UInt) throws -> UInt32 {
        owsAssertDebug(bitCount > 0)
        owsAssertDebug(bitCount <= 32)

        var result: UInt32 = 0
        for _ in 0..<bitCount {
            let bit = try readBit()
            result = (result << 1) | UInt32(bit)
        }
        return result
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

    lazy private(set) var previewView = QRCodeScanPreviewView(session: session)

    private let sessionQueue = DispatchQueue(label: "QRCodeScanner.sessionQueue")

    private let session = AVCaptureSession()
    private let output: QRCodeScanOutput

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

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            self.captureOrientation = initialCaptureOrientation
            self.session.sessionPreset = .high

            try self.setCurrentInput(position: .back)

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
