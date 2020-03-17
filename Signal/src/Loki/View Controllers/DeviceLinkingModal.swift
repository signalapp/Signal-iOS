import NVActivityIndicatorView

@objc(LKDeviceLinkingModal)
final class DeviceLinkingModal : Modal, DeviceLinkingSessionDelegate {
    private let mode: Mode
    private let delegate: DeviceLinkingModalDelegate?
    private var deviceLink: DeviceLink?
    
    // MARK: Types
    enum Mode : String { case master, slave }
    
    // MARK: Components
    private lazy var spinner = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: Colors.text, padding: nil)
    
    private lazy var qrCodeImageViewContainer: UIView = {
        let result = UIView()
        result.addSubview(qrCodeImageView)
        qrCodeImageView.pin(.top, to: .top, of: result)
        qrCodeImageView.pin(.bottom, to: .bottom, of: result)
        qrCodeImageView.center(.horizontal, in: result)
        return result
    }()
    
    private lazy var qrCodeImageView: UIImageView = {
        let result = UIImageView()
        result.contentMode = .scaleAspectFit
        let size: CGFloat = 128
        result.set(.width, to: size)
        result.set(.height, to: size)
        return result
    }()
    
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text.withAlphaComponent(Values.unimportantElementOpacity)
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()
    
    private lazy var mnemonicLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()

    private lazy var buttonStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ cancelButton, authorizeButton ])
        result.axis = .horizontal
        result.spacing = Values.mediumSpacing
        result.distribution = .fillEqually
        return result
    }()
    
    private lazy var authorizeButton: UIButton = {
        let result = UIButton()
        result.set(.height, to: Values.mediumButtonHeight)
        result.layer.cornerRadius = Values.modalButtonCornerRadius
        result.backgroundColor = Colors.accent
        result.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        result.setTitleColor(Colors.text, for: UIControl.State.normal)
        result.setTitle(NSLocalizedString("Authorize", comment: ""), for: UIControl.State.normal)
        return result
    }()
    
    // MARK: Lifecycle
    init(mode: Mode, delegate: DeviceLinkingModalDelegate?) {
        self.mode = mode
        if mode == .slave {
            guard delegate != nil else { preconditionFailure("Missing delegate for device linking modal in slave mode.") }
        }
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    
    @objc(initWithMode:delegate:)
    convenience init(modeAsString: String, delegate: DeviceLinkingModalDelegate?) {
        guard let mode = Mode(rawValue: modeAsString) else { preconditionFailure("Invalid mode: \(modeAsString).") }
        self.init(mode: mode, delegate: delegate)
    }
    
    required init?(coder: NSCoder) { preconditionFailure() }
    override init(nibName: String?, bundle: Bundle?) { preconditionFailure() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        switch mode {
        case .master: let _ = DeviceLinkingSession.startListeningForLinkingRequests(with: self)
        case .slave: let _ = DeviceLinkingSession.startListeningForLinkingAuthorization(with: self)
        }
    }
    
    override func populateContentView() {
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel, mnemonicLabel, buttonStackView ])
        switch mode {
        case .master: stackView.insertArrangedSubview(qrCodeImageViewContainer, at: 0)
        case .slave: stackView.insertArrangedSubview(spinner, at: 0)
        }
        contentView.addSubview(stackView)
        stackView.spacing = Values.largeSpacing
        stackView.axis = .vertical
        switch mode {
        case .master:
            let hexEncodedPublicKey = getUserHexEncodedPublicKey()
            qrCodeImageView.image = QRCode.generate(for: hexEncodedPublicKey, hasBackground: true)
        case .slave:
            spinner.set(.height, to: 64)
            spinner.startAnimating()
        }
        titleLabel.text = {
            switch mode {
            case .master: return NSLocalizedString("Waiting for Device", comment: "")
            case .slave: return NSLocalizedString("Waiting for Authorization", comment: "")
            }
        }()
        subtitleLabel.text = {
            switch mode {
            case .master: return NSLocalizedString("Open Session on your secondary device and tap \"Link to an existing account\"", comment: "")
            case .slave: return NSLocalizedString("Please check that the words below match those shown on your other device", comment: "")
            }
        }()
        mnemonicLabel.isHidden = (mode == .master)
        if mode == .slave {
            let hexEncodedPublicKey = getUserHexEncodedPublicKey().removing05PrefixIfNeeded()
            mnemonicLabel.text = Mnemonic.hash(hexEncodedString: hexEncodedPublicKey)
        }
        authorizeButton.addTarget(self, action: #selector(authorizeDeviceLink), for: UIControl.Event.touchUpInside)
        authorizeButton.isHidden = true
        stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        stackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: Values.largeSpacing)
    }
    
    // MARK: Device Linking
    func requestUserAuthorization(for deviceLink: DeviceLink) {
        self.deviceLink = deviceLink
        qrCodeImageViewContainer.isHidden = true
        titleLabel.text = NSLocalizedString("Linking Request Received", comment: "")
        subtitleLabel.text = NSLocalizedString("Please check that the words below match those shown on your other device", comment: "")
        let hexEncodedPublicKey = deviceLink.slave.hexEncodedPublicKey.removing05PrefixIfNeeded()
        mnemonicLabel.text = Mnemonic.hash(hexEncodedString: hexEncodedPublicKey)
        mnemonicLabel.isHidden = false
        authorizeButton.isHidden = false
    }
    
    @objc private func authorizeDeviceLink() {
        let deviceLink = self.deviceLink!
        let linkingAuthorizationMessage = DeviceLinkingUtilities.getLinkingAuthorizationMessage(for: deviceLink)
        ThreadUtil.enqueue(linkingAuthorizationMessage)
        SSKEnvironment.shared.messageSender.send(linkingAuthorizationMessage, success: {
            let _ = SSKEnvironment.shared.syncManager.syncAllContacts()
            let _ = SSKEnvironment.shared.syncManager.syncAllGroups()
            let _ = SSKEnvironment.shared.syncManager.syncAllOpenGroups()
            let thread = TSContactThread.getOrCreateThread(contactId: deviceLink.slave.hexEncodedPublicKey)
            thread.friendRequestStatus = .friends
            thread.save()
        }) { _ in
            print("[Loki] Failed to send device link authorization message.")
        }
        let session = DeviceLinkingSession.current!
        session.stopListeningForLinkingRequests()
        session.markLinkingRequestAsProcessed()
        dismiss(animated: true, completion: nil)
        let master = DeviceLink.Device(hexEncodedPublicKey: deviceLink.master.hexEncodedPublicKey, signature: linkingAuthorizationMessage.masterSignature)
        let signedDeviceLink = DeviceLink(between: master, and: deviceLink.slave)
        LokiFileServerAPI.addDeviceLink(signedDeviceLink).done {
            self.delegate?.handleDeviceLinkAuthorized(signedDeviceLink) // Intentionally capture self strongly
        }.catch { error in
            print("[Loki] Failed to add device link due to error: \(error).")
        }
    }
    
    func handleDeviceLinkAuthorized(_ deviceLink: DeviceLink) {
        let session = DeviceLinkingSession.current!
        session.stopListeningForLinkingAuthorization()
        spinner.stopAnimating()
        spinner.isHidden = true
        titleLabel.text = NSLocalizedString("Device Link Authorized", comment: "")
        subtitleLabel.text = NSLocalizedString("Your device has been linked successfully", comment: "")
        mnemonicLabel.isHidden = true
        buttonStackView.isHidden = true
        LokiFileServerAPI.addDeviceLink(deviceLink).catch { error in
            print("[Loki] Failed to add device link due to error: \(error).")
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            self.dismiss(animated: true) {
                self.delegate?.handleDeviceLinkAuthorized(deviceLink)
            }
        }
    }
    
    @objc override func close() {
        guard let session = DeviceLinkingSession.current else {
            return print("[Loki] Device linking session missing.") // Should never occur
        }
        session.stopListeningForLinkingRequests()
        session.markLinkingRequestAsProcessed() // Only relevant in master mode
        delegate?.handleDeviceLinkingModalDismissed() // Only relevant in slave mode
        if let deviceLink = deviceLink {
            OWSPrimaryStorage.shared().dbReadWriteConnection.readWrite { transaction in
                OWSPrimaryStorage.shared().removePreKeyBundle(forContact: deviceLink.slave.hexEncodedPublicKey, transaction: transaction)
            }
        }
        dismiss(animated: true, completion: nil)
    }
}
