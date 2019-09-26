import NVActivityIndicatorView

@objc(LKDeviceLinkingModal)
final class DeviceLinkingModal : Modal, DeviceLinkingSessionDelegate {
    private let mode: Mode
    private let delegate: DeviceLinkingModalDelegate?
    private var deviceLink: DeviceLink?
    
    // MARK: Types
    enum Mode : String { case master, slave }
    
    // MARK: Components
    private lazy var topSpacer = UIView.spacer(withHeight: 8)
    
    private lazy var spinner = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: .white, padding: nil)
    
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Theme.primaryColor
        result.font = UIFont.ows_dynamicTypeHeadlineClamped
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Theme.primaryColor
        result.font = UIFont.ows_dynamicTypeCaption1Clamped
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()
    
    private lazy var mnemonicLabel: UILabel = {
        let result = UILabel()
        result.textColor = Theme.primaryColor
        result.font = UIFont.ows_dynamicTypeCaption1Clamped
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()

    private lazy var buttonStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ authorizeButton, cancelButton ])
        result.axis = .horizontal
        result.distribution = .fillEqually
        return result
    }()
    
    private lazy var authorizeButton: OWSFlatButton = {
        let result = OWSFlatButton.button(title: NSLocalizedString("Authorize", comment: ""), font: .ows_dynamicTypeBodyClamped, titleColor: .white, backgroundColor: .clear, target: self, selector: #selector(authorizeDeviceLink))
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()

    private lazy var bottomSpacer = UIView.spacer(withHeight: 8)
    
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
        let stackView = UIStackView(arrangedSubviews: [ topSpacer, spinner, UIView.spacer(withHeight: 8), titleLabel, subtitleLabel, mnemonicLabel, buttonStackView, bottomSpacer ])
        contentView.addSubview(stackView)
        stackView.spacing = 16
        stackView.axis = .vertical
        spinner.set(.height, to: 64)
        spinner.startAnimating()
        titleLabel.text = {
            switch mode {
            case .master: return NSLocalizedString("Waiting for Device", comment: "")
            case .slave: return NSLocalizedString("Waiting for Authorization", comment: "")
            }
        }()
        subtitleLabel.text = {
            switch mode {
            case .master: return NSLocalizedString("Create a new account on your other device and click \"Link Device\" when you're at the \"Create Your Loki Messenger Account\" step to start the linking process", comment: "")
            case .slave: return NSLocalizedString("Please check that the words below match the ones shown on your other device", comment: "")
            }
        }()
        mnemonicLabel.isHidden = (mode == .master)
        if mode == .slave {
            let hexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey.removing05PrefixIfNeeded()
            mnemonicLabel.text = Mnemonic.encode(hexEncodedString: hexEncodedPublicKey).split(separator: " ")[0..<3].joined(separator: " ")
        }
        let buttonHeight = cancelButton.button.titleLabel!.font.pointSize * 48 / 17
        authorizeButton.set(.height, to: buttonHeight)
        cancelButton.set(.height, to: buttonHeight)
        authorizeButton.isHidden = true
        bottomSpacer.isHidden = true
        stackView.pin(.leading, to: .leading, of: contentView, withInset: 16)
        stackView.pin(.top, to: .top, of: contentView, withInset: 16)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: 16)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: 16)
    }
    
    // MARK: Device Linking
    func requestUserAuthorization(for deviceLink: DeviceLink) {
        self.deviceLink = deviceLink
        topSpacer.isHidden = true
        spinner.stopAnimating()
        spinner.isHidden = true
        titleLabel.text = NSLocalizedString("Linking Request Received", comment: "")
        subtitleLabel.text = NSLocalizedString("Please check that the words below match the ones shown on your other device", comment: "")
        let hexEncodedPublicKey = deviceLink.slave.hexEncodedPublicKey.removing05PrefixIfNeeded()
        mnemonicLabel.text = Mnemonic.encode(hexEncodedString: hexEncodedPublicKey).split(separator: " ")[0..<3].joined(separator: " ")
        mnemonicLabel.isHidden = false
        authorizeButton.isHidden = false
    }
    
    @objc private func authorizeDeviceLink() {
        let deviceLink = self.deviceLink!
        let linkingAuthorizationMessage = DeviceLinkingUtilities.getLinkingAuthorizationMessage(for: deviceLink)
        (0..<4).forEach { _ in ThreadUtil.enqueue(linkingAuthorizationMessage) }
        let session = DeviceLinkingSession.current!
        session.stopListeningForLinkingRequests()
        session.markLinkingRequestAsProcessed()
        dismiss(animated: true, completion: nil)
        LokiStorageAPI.addDeviceLink(deviceLink).catch { error in
            print("[Loki] Failed to add device link due to error: \(error).")
        }
    }
    
    func handleDeviceLinkAuthorized(_ deviceLink: DeviceLink) {
        let session = DeviceLinkingSession.current!
        session.stopListeningForLinkingAuthorization()
        topSpacer.isHidden = true
        spinner.stopAnimating()
        spinner.isHidden = true
        titleLabel.text = NSLocalizedString("Device Link Authorized", comment: "")
        subtitleLabel.text = NSLocalizedString("Your device has been linked successfully", comment: "")
        mnemonicLabel.isHidden = true
        buttonStackView.isHidden = true
        bottomSpacer.isHidden = false
        LokiStorageAPI.addDeviceLink(deviceLink).catch { error in
            print("[Loki] Failed to add device link due to error: \(error).")
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            self.delegate?.handleDeviceLinkAuthorized(deviceLink)
            self.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc override func cancel() {
        let session = DeviceLinkingSession.current!
        session.stopListeningForLinkingRequests()
        session.markLinkingRequestAsProcessed() // Only relevant in master mode
        delegate?.handleDeviceLinkingModalDismissed() // Only relevant in slave mode
        dismiss(animated: true, completion: nil)
    }
}
