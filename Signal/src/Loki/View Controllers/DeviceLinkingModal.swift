import NVActivityIndicatorView

@objc(LKDeviceLinkingModal)
final class DeviceLinkingModal : Modal, DeviceLinkingSessionDelegate {
    private let mode: Mode
    private let delegate: DeviceLinkingModalDelegate?
    private var deviceLink: DeviceLink?
    private var hasAuthorizedDeviceLink = false
    
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
        result.textColor = Colors.text
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

    private lazy var mainStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel, mnemonicLabel, buttonStackView ])
        result.spacing = Values.largeSpacing
        result.axis = .vertical
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
        switch mode {
        case .master: mainStackView.insertArrangedSubview(qrCodeImageViewContainer, at: 0)
        case .slave: mainStackView.insertArrangedSubview(spinner, at: 0)
        }
        contentView.addSubview(mainStackView)
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
            case .master: return NSLocalizedString("Download Session on your other device and tap \"Link to an existing account\" at the bottom of the landing screen. If you have an existing account on your other device already you will have to delete that account first.", comment: "")
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
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.largeSpacing)
    }
    
    // MARK: Device Linking
    func requestUserAuthorization(for deviceLink: DeviceLink) {
        self.deviceLink = deviceLink
        qrCodeImageViewContainer.isHidden = true
        titleLabel.text = NSLocalizedString("Linking Request Received", comment: "")
        subtitleLabel.text = NSLocalizedString("Please check that the words below match those shown on your other device", comment: "")
        let hexEncodedPublicKey = deviceLink.slave.publicKey.removing05PrefixIfNeeded()
        mnemonicLabel.text = Mnemonic.hash(hexEncodedString: hexEncodedPublicKey)
        mnemonicLabel.isHidden = false
        authorizeButton.isHidden = false
    }
    
    @objc private func authorizeDeviceLink() {
        guard !hasAuthorizedDeviceLink else { return }
        hasAuthorizedDeviceLink = true
        mainStackView.removeArrangedSubview(qrCodeImageViewContainer)
        mainStackView.insertArrangedSubview(spinner, at: 0)
        spinner.set(.height, to: 64)
        spinner.startAnimating()
        titleLabel.text = NSLocalizedString("Authorizing Device Link", comment: "")
        subtitleLabel.text = NSLocalizedString("Please wait while the device link is created. This can take up to a minute.", comment: "")
        mnemonicLabel.isHidden = true
        buttonStackView.isHidden = true
        let deviceLink = self.deviceLink!
        DeviceLinkingSession.current!.markLinkingRequestAsProcessed()
        DeviceLinkingSession.current!.stopListeningForLinkingRequests()
        let linkingAuthorizationMessage = DeviceLinkingUtilities.getLinkingAuthorizationMessage(for: deviceLink)
        let master = DeviceLink.Device(publicKey: deviceLink.master.publicKey, signature: linkingAuthorizationMessage.masterSignature)
        let signedDeviceLink = DeviceLink(between: master, and: deviceLink.slave)
        FileServerAPI.addDeviceLink(signedDeviceLink).done(on: DispatchQueue.main) { [weak self] in
            SSKEnvironment.shared.messageSender.send(linkingAuthorizationMessage, success: {
                let storage = OWSPrimaryStorage.shared()
                let slaveHexEncodedPublicKey = deviceLink.slave.publicKey
                try! Storage.writeSync { transaction in
                    let thread = TSContactThread.getOrCreateThread(withContactId: slaveHexEncodedPublicKey, transaction: transaction)
                    thread.save(with: transaction)
                }
                let _ = SSKEnvironment.shared.syncManager.syncAllGroups().ensure {
                    // Closed groups first because we prefer the session request mechanism
                    // to the AFR mechanism
                    let _ = SSKEnvironment.shared.syncManager.syncAllContacts()
                }
                let _ = SSKEnvironment.shared.syncManager.syncAllOpenGroups()
                DispatchQueue.main.async {
                    self?.dismiss(animated: true, completion: nil)
                    self?.delegate?.handleDeviceLinkAuthorized(signedDeviceLink)
                }
            }, failure: { error in
                print("[Loki] Failed to send device link authorization message.")
                let _ = FileServerAPI.removeDeviceLink(signedDeviceLink) // Attempt to roll back
                DispatchQueue.main.async {
                    self?.close()
                    let alert = UIAlertController(title: NSLocalizedString("Device Linking Failed", comment: ""), message: NSLocalizedString("Please check your internet connection and try again", comment: ""), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
                    self?.presentingViewController?.present(alert, animated: true, completion: nil)
                }
            })
        }.catch { [weak self] error in
            print("[Loki] Failed to add device link due to error: \(error).")
            DispatchQueue.main.async {
                self?.close() // TODO: Show a message to the user
                let alert = UIAlertController(title: NSLocalizedString("Device Linking Failed", comment: ""), message: NSLocalizedString("Please check your internet connection and try again", comment: ""), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
                self?.presentingViewController?.present(alert, animated: true, completion: nil)
            }
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
        FileServerAPI.addDeviceLink(deviceLink).catch { error in
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
            try! Storage.writeSync { transaction in
                OWSPrimaryStorage.shared().removePreKeyBundle(forContact: deviceLink.slave.publicKey, transaction: transaction)
            }
        }
        dismiss(animated: true, completion: nil)
    }
}
