//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation
import SignalServiceKit
import Vision

public protocol QRCodeSampleBufferScannerDelegate: AnyObject {
    /// A boolean indicating if the scanner should attempt to process QR codes.
    /// This property will be accessed off the main thread.
    var shouldProcessQRCodes: Bool { get }
    /// Informs the delegate that a QR code has been found.
    /// This function will be called on the main thread.
    func qrCodeFound(string qrCodeString: String?, data qrCodeData: Data?)
    /// Informs the delegate that there was an error in the
    /// `VNDetectBarcodesRequest`.
    /// This function will be called on the main thread.
    func scanFailed(error: any Error)
}

final public class QRCodeSampleBufferScanner: NSObject {
    private weak var delegate: QRCodeSampleBufferScannerDelegate?

    public init(delegate: QRCodeSampleBufferScannerDelegate?) {
        self.delegate = delegate
    }

    private lazy var detectQRCodeRequest: VNDetectBarcodesRequest = {
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.delegate?.scanFailed(error: error)
                }
                return
            }
            self.processClassification(request: request)
        }

        request.symbologies = [ .qr ]

        return request
    }()

    private func processClassification(request: VNRequest) {
        guard let delegate, delegate.shouldProcessQRCodes else { return }

        typealias QRCode = (string: String?, data: Data?)
        let qrCode: QRCode? = (request.results ?? [])
            .lazy
            .compactMap { $0 as? VNBarcodeObservation }
            .filter { (barcode: VNBarcodeObservation) -> Bool in
                barcode.symbology == .qr
                && barcode.barcodeDescriptor is CIQRCodeDescriptor
                && barcode.confidence > 0.9
            }
            .sorted { $0.confidence > $1.confidence }
            .compactMap { (barcode: VNBarcodeObservation) -> QRCode? in
                guard let qrCodeDescriptor = barcode.barcodeDescriptor as? CIQRCodeDescriptor else {
                    return nil
                }
                let qrCodeCodewords = qrCodeDescriptor.errorCorrectedPayload
                let qrCodeVersion = qrCodeDescriptor.symbolVersion
                let qrCodeString: String? = barcode.payloadStringValue
                let qrCodeData: Data? = QRCodePayload.parse(
                    codewords: qrCodeCodewords,
                    qrCodeVersion: qrCodeVersion
                )?.data

                guard qrCodeString != nil || qrCodeData != nil else {
                    return nil
                }

                return (qrCodeString, qrCodeData)
            }
            .first

        guard let qrCode else { return }

        Logger.info("Scanned QR Code.")

        DispatchQueue.main.async {
            delegate.qrCodeFound(string: qrCode.string, data: qrCode.data)
        }
    }
}

extension QRCodeSampleBufferScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right
        )
        do {
            try imageRequestHandler.perform([detectQRCodeRequest])
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }
}

public enum QRCodeScanOutcome: UInt {
    case stopScanning
    case continueScanning
}

// MARK: -

public protocol QRCodeScanDelegate: AnyObject {
    // A QR code scan might yield a String payload, Data payload or both.
    //
    // * Traditional QR code payloads are Strings, but that's not true of
    //   payloads like our safety numbers/fingerprints.  In that case,
    //   a Data payload will be present but not a String payload.
    // * iOS tries to parse QR code payloads as Strings but doesn't
    //   expose the underlying Data payload, only the "codewords" (an
    //   encoded form of the Data payload).
    //   We use QRCodePayload to parse the Data payload from the
    //   "codewords". QRCodePayload only supports a narrow set of "modes"
    //   & "configurations".  iOS supports presumably the entire QR code
    //   standard.  If a QR code contains Kanji, for example, a String
    //   payload will be present (parsed by iOS) but not a Data payload.
    //
    // In some scenarios, we require a Data payload.  If a Data payload
    // cannot be parsed, qrCodeScanViewScanned should presumably exit
    // and return .continueScanning to ignore the scanned QR code. Or
    // an error alert might be presented.
    //
    // In other scenarios, we require a String payload, e.g. when we
    // expect a URL.  Similarly, if a String payload is required and
    // not present, we probably want to ignore the scanned QR code and
    // continue scanning.
    @discardableResult
    func qrCodeScanViewScanned(
        qrCodeData: Data?,
        qrCodeString: String?
    ) -> QRCodeScanOutcome

    // QRCodeScanViewController DRYs up asking for camera permissions, etc.
    // If scanning cannot be performed (e.g. a user declined to grant camera
    // permissions), the delegate will be asked to dismiss.
    func qrCodeScanViewDismiss(_ qrCodeScanViewController: QRCodeScanViewController)

    var shouldShowUploadPhotoButton: Bool { get }
    func didTapUploadPhotoButton(_ qrCodeScanViewController: QRCodeScanViewController)
}

public extension QRCodeScanDelegate {
    var shouldShowUploadPhotoButton: Bool { false }
    func didTapUploadPhotoButton(_ qrCodeScanViewController: QRCodeScanViewController) {}
}

// MARK: -

final public class QRCodeScanViewController: OWSViewController {

    public enum Appearance {
        case framed
        case unadorned

        fileprivate var backgroundColor: UIColor {
            switch self {
            case .framed:
                return .ows_black
            case .unadorned:
                return .clear
            }
        }
    }

    private let appearance: Appearance
    private let showUploadPhotoButton: Bool

    public weak var delegate: QRCodeScanDelegate?

    private let delegateHasAcceptedScanResults = AtomicBool(false, lock: .init())

    private var scanner: QRCodeScanner?

    private lazy var sampleBufferScanner = QRCodeSampleBufferScanner(delegate: self)

    public var prefersFrontFacingCamera = false {
        didSet {
            scanner?.prefersFrontFacingCamera = prefersFrontFacingCamera
        }
    }

    public init(appearance: Appearance, showUploadPhotoButton: Bool = false) {
        self.appearance = appearance
        self.showUploadPhotoButton = showUploadPhotoButton
        super.init()
    }

    public override var prefersStatusBarHidden: Bool {
        return !DependenciesBridge.shared.currentCallProvider.hasCurrentCall
    }

    public override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    private lazy var uploadPhotoButton: UIButton = {
        let button = OWSRoundedButton { [weak self] in
            guard let self else { return }
            self.delegate?.didTapUploadPhotoButton(self)
        }

        button.ows_contentEdgeInsets = UIEdgeInsets(margin: 14)

        // Always use dark theming since it sits over the scan mask.
        button.setTemplateImageName(
            Theme.iconName(.buttonPhotoLibrary),
            tintColor: .ows_white
        )
        button.backgroundColor = .ows_whiteAlpha20

        return button
    }()

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        AssertIsOnMainThread()

        super.viewDidLoad()

        view.backgroundColor = appearance.backgroundColor

        addObservers()
    }

    public override func viewDidAppear(_ animated: Bool) {
        AssertIsOnMainThread()

        super.viewDidAppear(animated)

        tryToStartScanning()
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if let interfaceOrientation = self.view.window?.windowScene?.interfaceOrientation {
            self.scanner?.updateVideoPreviewOrientation(interfaceOrientation)
        }
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(logSessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(logSessionInterruptError),
            name: .AVCaptureSessionWasInterrupted,
            object: nil
        )
    }

    @objc
    private func didEnterBackground() {
        AssertIsOnMainThread()

        stopScanning()
    }

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()

        if self.view.window != nil {
            tryToStartScanning()
        }
    }

    @objc
    private func logSessionRuntimeError(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            Logger.info("Error running AVCaptureSession: no specific error provided")
            return
        }

        Logger.error("Error running AVCaptureSession: \(error.localizedDescription)")
    }

    @objc
    private func logSessionInterruptError(notification: Notification) {
        if let userInfo = notification.userInfo {
            guard let reasonValue = userInfo[AVCaptureSessionInterruptionReasonKey] as? NSNumber,
                  let reason = AVCaptureSession.InterruptionReason(rawValue: reasonValue.intValue) else {
                Logger.info("session was interrupted for no apparent reason")
                return
            }
            Logger.info("session was interrupted with reason code: \(reason.rawValue)")
        }
    }

    // MARK: - Scanning

    private func stopScanning() {
        scanner = nil
        viewfinderAnimator?.stopAnimation(true)
        viewfinderAnimator = nil
    }

    @objc
    public func tryToStartScanning() {
        AssertIsOnMainThread()

        guard nil == scanner else {
            Logger.info("Early return because scanner is not nil")
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

    private var viewfinderAnimator: UIViewPropertyAnimator?

    /// Continuously animates the viewfinder, updating `viewfinderAnimator` with the latest animator.
    ///
    /// - Important:
    ///
    /// Stop the animation (stored in `viewfinderAnimator`) when the view disappears.
    ///
    /// - Parameters:
    ///   - frame: The viewfinder frame to animate.
    ///   - isReversed: `false` if the viewfinder frame should enlarge,
    ///   `true` if it should shrink.
    private func animateViewfinder(frame: UIView, isReversed: Bool = false) {
        guard view.window != nil else { return }
        let animator = UIViewPropertyAnimator(
            duration: 0.35,
            springDamping: 1,
            springResponse: 0.35
        )
        animator.addAnimations {
            frame.transform = isReversed ? .identity : .scale(1.1)
        }
        animator.addCompletion { [weak self] _ in
            self?.animateViewfinder(frame: frame, isReversed: !isReversed)
        }
        // Play every 1 second, so subtract the animation duration from 1 second
        animator.startAnimation(afterDelay: 1 - 0.35)
        viewfinderAnimator = animator
    }

    private func startScanning() {
        AssertIsOnMainThread()

        guard
            scanner == nil,
            !delegateHasAcceptedScanResults.get()
        else {
            Logger.info("Early return. Scanner is not nil or delegate has already accepted scan results")
            return
        }

        let scanner = QRCodeScanner(
            prefersFrontFacingCamera: self.prefersFrontFacingCamera,
            sampleBufferDelegate: self.sampleBufferScanner
        )
        self.scanner = scanner

        view.removeAllSubviews()

        let previewView = scanner.previewView
        view.addSubview(previewView)
        previewView.autoPinEdgesToSuperviewEdges()

        switch appearance {
        case .unadorned:
            break
        case .framed:
            let shouldAnimateScale = !UIAccessibility.isReduceMotionEnabled

            let viewfinder = UIImage(named: "qr_viewfinder")
            let frame = UIImageView(image: viewfinder)
            self.view.addSubview(frame)
            frame.autoHCenterInSuperview()
            frame.centerYAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.centerYAnchor,
                constant: showUploadPhotoButton ? -16 : 0
            ).isActive = true

            frame.layer.opacity = 0
            if shouldAnimateScale {
                frame.transform = .scale(1.2)
            }
            let entranceAnimator = UIViewPropertyAnimator(
                duration: 0.3,
                springDamping: 1,
                springResponse: 0.3
            )
            entranceAnimator.addAnimations {
                frame.layer.opacity = 1
                frame.transform = .identity
            }

            entranceAnimator.startAnimation()

            if shouldAnimateScale {
                animateViewfinder(frame: frame)
            }
        }

        if showUploadPhotoButton {
            view.addSubview(uploadPhotoButton)
            uploadPhotoButton.autoSetDimensions(to: .square(52))
            uploadPhotoButton.autoHCenterInSuperview()
            uploadPhotoButton.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 16)
        }

        let initialOrientation = self.view.window!.windowScene!.interfaceOrientation
        firstly {
            scanner.startVideoCapture(initialOrientation: initialOrientation)
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
                                        message: error.userErrorDescription,
                                        buttonTitle: CommonStrings.dismissButton,
                                        buttonAction: { [weak self] _ in
                                            guard let self = self else { return }
                                            self.delegate?.qrCodeScanViewDismiss(self)
                                        })
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

// iOS tries to parse QR code payloads as Strings but doesn't
// expose the underlying Data payload, only the "codewords" (an
// encoded form of the Data payload).
//
// QRCodePayload can parse some Data payloads from the "codewords".
// QRCodePayload only supports a narrow set of "modes"
// & "configurations", but this is sufficient for the cases where
// we need it: safety number fingerprints.
//
// This isn't an efficient way to parse the codewords, but
// correctness matters and perf doesn't, since QR code payloads
// are inherently small. Therefore, this approach favors simplicity
// over efficiency.
final public class QRCodePayload {
    public let version: Int
    public let mode: Mode
    public let bytes: [UInt8]

    public var data: Data {
        Data(bytes)
    }
    public var asString: String? {
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
                             qrCodeVersion version: Int) -> QRCodePayload? {
        // QR Code Standard
        // ISO/IEC 18004:2015
        // https://www.iso.org/standard/62021.html
        do {
            let bitstream = QRCodeBitStream(codewords: codewords)

            let modeLength: UInt = 4
            let modeBits = try bitstream.readUInt8(bitCount: modeLength)
            guard let mode = Mode(rawValue: UInt(modeBits)) else {
                let ignoreUnknownMode = CurrentAppContext().isRunningTests
                if ignoreUnknownMode {
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
final private class QRCodeBitStream {
    private var bits: [UInt8]

    init(codewords: Data) {
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

extension QRCodeScanViewController: QRCodeSampleBufferScannerDelegate {
    public var shouldProcessQRCodes: Bool {
        !delegateHasAcceptedScanResults.get()
    }

    public func qrCodeFound(string qrCodeString: String?, data qrCodeData: Data?) {
        guard
            let delegate = self.delegate,
            !delegateHasAcceptedScanResults.get()
        else {
            Logger.info("Early return, delegate has already accepted scan results")
            return
        }

        let outcome = delegate.qrCodeScanViewScanned(
            qrCodeData: qrCodeData,
            qrCodeString: qrCodeString
        )

        switch outcome {
        case .stopScanning:
            self.delegateHasAcceptedScanResults.set(true)
            self.stopScanning()

            ImpactHapticFeedback.impactOccurred(style: .medium)
        case .continueScanning:
            break
        }
    }

    public func scanFailed(error: Error) {
        showFailureUI(error: error)
    }
}

// MARK: -

enum QRCodeScanError: Error {
    case assertionError(description: String)
    case initializationFailed
    case captureFailed
}

// MARK: -

final private class QRCodeScanner {

    lazy private(set) var previewView = QRCodeScanPreviewView(session: session)

    private let sessionQueue = DispatchQueue(label: "org.signal.qrcode-scanner")

    private let session = AVCaptureSession()
    private let output: QRCodeScanOutput

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

    init(
        prefersFrontFacingCamera: Bool,
        sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate
    ) {
        self.prefersFrontFacingCamera = prefersFrontFacingCamera
        output = QRCodeScanOutput(sampleBufferDelegate: sampleBufferDelegate)

        if #available(iOS 16.0, *) {
            if session.isMultitaskingCameraAccessSupported {
                session.isMultitaskingCameraAccessEnabled = true
            }
        }
    }

    deinit {
        sessionQueue.async(.promise) { [session] in
            session.stopRunning()
        }.done {
            Logger.info("stopCapture completed")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    // MARK: - Public

    func updateVideoPreviewOrientation(_ newValue: UIInterfaceOrientation) {
        sessionQueue.async {
            let captureOrientation = AVCaptureVideoOrientation(interfaceOrientation: newValue) ?? .portrait
            if self.captureOrientation == captureOrientation {
                return
            }
            self.captureOrientation = captureOrientation
            self._updateVideoPreviewConnectionOrientation()
        }
    }

    private func _updateVideoPreviewConnectionOrientation() {
        assertIsOnSessionQueue()
        guard let videoConnection = previewView.previewLayer.connection else {
            Logger.info("previewView hasn't completed setup yet.")
            return
        }
        if videoConnection.isVideoOrientationSupported {
            videoConnection.videoOrientation = self.captureOrientation
        }
    }

    public var prefersFrontFacingCamera: Bool {
        didSet {
            sessionQueue.async {
                guard self.session.isRunning else {
                    // No need to update yet.
                    return
                }
                self.session.beginConfiguration()
                try? self.setCurrentInput()
                self.session.commitConfiguration()
            }
        }
    }

    public func startVideoCapture(initialOrientation: UIInterfaceOrientation) -> Promise<Void> {
        AssertIsOnMainThread()

        guard !Platform.isSimulator else {
            // Trying to actually set up the capture session will fail on a simulator
            // since we don't have actual capture devices. But it's useful to be able
            // to mostly run the capture code on the simulator to work with layout.
            return Promise.value(())
        }

        // If the session is already running, no need to do anything.
        guard !self.session.isRunning else {
            Logger.info("Early return, session already running")
            return Promise.value(())
        }

        let initialCaptureOrientation = AVCaptureVideoOrientation(interfaceOrientation: initialOrientation) ?? .portrait

        return sessionQueue.async(.promise) { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            self.captureOrientation = initialCaptureOrientation
            self.session.sessionPreset = .high

            try self.setCurrentInput()

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
            self._updateVideoPreviewConnectionOrientation()
        }
    }

    public func assertIsOnSessionQueue() {
        assertOnQueue(sessionQueue)
    }

    // This method should be called on the serial queue,
    // and between calls to session.beginConfiguration/commitConfiguration
    public func setCurrentInput() throws {
        assertIsOnSessionQueue()

        let device = try selectCaptureDevice()

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

        // Remove any existing inputs.
        session.inputs.forEach {
            session.removeInput($0)
        }
        session.addInput(newInput)
    }

    private func selectCaptureDevice() throws -> AVCaptureDevice {
        assertIsOnSessionQueue()

        // Camera types in descending order of preference.
        var deviceTypes = [AVCaptureDevice.DeviceType]()
        deviceTypes.append(.builtInWideAngleCamera)
        deviceTypes.append(.builtInUltraWideCamera)
        deviceTypes.append(.builtInDualWideCamera)
        deviceTypes.append(.builtInTripleCamera)
        deviceTypes.append(.builtInDualCamera)
        deviceTypes.append(.builtInTelephotoCamera)

        func selectDevice(session: AVCaptureDevice.DiscoverySession) -> AVCaptureDevice? {
            var deviceMap = [AVCaptureDevice.DeviceType: AVCaptureDevice]()
            for device in session.devices {
                deviceMap[device.deviceType] = device
            }
            for deviceType in deviceTypes {
                if let device = deviceMap[deviceType] {
                    return device
                }
            }
            return nil
        }

        let preferredPosition: AVCaptureDevice.Position =
            prefersFrontFacingCamera ? .front : .back
        let preferredSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: preferredPosition
        )
        if let device = selectDevice(session: preferredSession) {
            return device
        }
        // Failover to other camera.
        let failoverPosition: AVCaptureDevice.Position =
            prefersFrontFacingCamera ? .back : .front
        let failoverSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: failoverPosition
        )
        if let device = selectDevice(session: failoverSession) {
            return device
        }

        throw QRCodeScanError.assertionError(description: "Missing videoDevice.")
    }
}

// MARK: -

final private class QRCodeScanPreviewView: UIView {

    let previewLayer: AVCaptureVideoPreviewLayer

    override var bounds: CGRect {
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

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: -

final private class QRCodeScanOutput {

    let videoDataOutput = AVCaptureVideoDataOutput()

    // MARK: - Init

    init(sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        videoDataOutput.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.setSampleBufferDelegate(
            sampleBufferDelegate,
            queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
    }
}

// MARK: -

public extension AVCaptureVideoOrientation {
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
