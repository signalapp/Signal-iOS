//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation
import PromiseKit
import Vision

@objc
public enum QRCodeScanOutcome: UInt {
    case stopScanning
    case continueScanning
}

// MARK: -

@objc
protocol QRCodeScanDelegate: AnyObject {
    func qrCodeScanViewScanned(_ qrCodeScanViewController: QRCodeScanViewController,
                               qrCodeData: Data?,
                               qrCodeString: String?) -> QRCodeScanOutcome

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
        let barcodes: [VNBarcodeObservation] = filterBarcodes().sorted { (left, right) in
            // If multiple bardcodes found, prefer barcode with higher confidence.
            // In practice, all QR codes have confidence of 1.0.
            left.confidence > right.confidence
        }

        struct QRCode {
            let qrCodeCodewords: Data
            let qrCodeVersion: Int
            // One or both will be non-nil.
            let qrCodeString: String?
            let qrCodeData: Data?
        }
        let qrCodes: [QRCode] = barcodes.compactMap { barcode in
            guard let barcodeDescriptor = barcode.barcodeDescriptor as? CIQRCodeDescriptor else {
                return nil
            }
            let qrCodeCodewords = barcodeDescriptor.errorCorrectedPayload
            let qrCodeVersion = barcodeDescriptor.symbolVersion
            let qrCodeString: String? = barcode.payloadStringValue
            let qrCodeData: Data? = QRCodePayload.parse(codewords: qrCodeCodewords,
                                                        qrCodeVersion: qrCodeVersion)?.data
            guard qrCodeString != nil || qrCodeData != nil else {
                return nil
            }
            return QRCode(qrCodeCodewords: qrCodeCodewords,
                          qrCodeVersion: qrCodeVersion,
                          qrCodeString: qrCodeString,
                          qrCodeData: qrCodeData)
        }

        guard !qrCodes.isEmpty else {
            return
        }
        guard let qrCode = qrCodes.first else {
            return
        }

        Logger.info("Scanned QR Code.")

        let qrCodeCodewords = qrCode.qrCodeCodewords
        Logger.verbose("----- qrCodeCodewords: \(qrCodeCodewords.count), \(qrCodeCodewords.hexadecimalString), \(qrCodeCodewords.base64EncodedString())")

        let qrCodeVersion = qrCode.qrCodeVersion
        Logger.verbose("----- qrCodeVersion: \(qrCodeVersion)")

        if let qrCodeString = qrCode.qrCodeString {
            Logger.verbose("----- qrCodeString: \(qrCodeString.count), \(qrCodeString)")
        }
        if let qrCodeData = qrCode.qrCodeData {
            Logger.verbose("----- qrCodeData: \(qrCodeData.count), \(qrCodeData.hexadecimalString)")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let delegate = self.delegate else {
                return
            }

            let outcome = delegate.qrCodeScanViewScanned(self,
                                                          qrCodeData: qrCode.qrCodeData,
                                                          qrCodeString: qrCode.qrCodeString)
            switch outcome {
            case .stopScanning:
                self.stopScanning()

                // Vibrate
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            case .continueScanning:
                break
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

    // There are even more modes, but it'll improve logging a bit 
    // to identify these modes even though we don't support them.
    //
    // TODO: We currently only support .byte mode.
    public enum Mode: UInt {
        case numeric = 1
        case alphaNumeric = 2
        case bytes = 4
        case kanji = 8
    }

    public static func parse(codewords: Data,
                             qrCodeVersion version: Int,
                             ignoreUnknownMode: Bool = false) -> QRCodePayload? {
        // QR Code Standard
        // ISO/IEC 18004:2015
        // https://www.iso.org/standard/62021.html
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
            return QRCodePayload(version: version, mode: mode, bytes: bytes)
        } catch {
            owsFailDebug("Error: \(error)")
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

    // This method should be called on the serial queue,
    // and between calls to session.beginConfiguration/commitConfiguration
    public func setCurrentInput(position: AVCaptureDevice.Position) throws {
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

        session.addInput(newInput)
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

    let videoDataOutput = AVCaptureVideoDataOutput()

    // MARK: - Init

    required init(sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        videoDataOutput.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.setSampleBufferDelegate(
            sampleBufferDelegate,
            queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
    }
}
