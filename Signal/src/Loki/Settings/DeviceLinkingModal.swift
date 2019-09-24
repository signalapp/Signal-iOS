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
        result.text = "word word word"
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()
    
    private lazy var authorizeButton: OWSFlatButton = {
        let result = OWSFlatButton.button(title: NSLocalizedString("Authorize", comment: ""), font: .ows_dynamicTypeBodyClamped, titleColor: .white, backgroundColor: .clear, target: self, selector: #selector(authorizeDeviceLink))
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
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
    
    @objc convenience init(modeAsString: String, delegate: DeviceLinkingModalDelegate?) {
        guard let mode = Mode(rawValue: modeAsString) else { preconditionFailure("Invalid mode: \(modeAsString).") }
        self.init(mode: mode, delegate: delegate)
    }
    
    required init?(coder: NSCoder) { preconditionFailure() }
    override init(nibName: String?, bundle: Bundle?) { preconditionFailure() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let _ = DeviceLinkingSession.startListeningForLinkingRequests(with: self)
    }
    
    override func populateContentView() {
        let buttonStackView = UIStackView(arrangedSubviews: [ authorizeButton, cancelButton ])
        let stackView = UIStackView(arrangedSubviews: [ topSpacer, spinner, UIView.spacer(withHeight: 8), titleLabel, subtitleLabel, mnemonicLabel, buttonStackView ])
        contentView.addSubview(stackView)
        stackView.spacing = 16
        stackView.axis = .vertical
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .fillEqually
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
            case .master: return NSLocalizedString("Click the \"Link Device\" button on your other device to start the linking process", comment: "")
            case .slave: return NSLocalizedString("Please verify that the words below match the ones shown on your other device.", comment: "")
            }
        }()
        mnemonicLabel.isHidden = (mode == .master)
        let buttonHeight = cancelButton.button.titleLabel!.font.pointSize * 48 / 17
        authorizeButton.set(.height, to: buttonHeight)
        cancelButton.set(.height, to: buttonHeight)
        authorizeButton.isHidden = true
        stackView.pin(.leading, to: .leading, of: contentView, withInset: 16)
        stackView.pin(.top, to: .top, of: contentView, withInset: 16)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: 16)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: 16)
    }
    
    // MARK: Device Linking
    func requestUserAuthorization(for deviceLink: DeviceLink) {
        self.deviceLink = deviceLink
        self.topSpacer.isHidden = true
        self.spinner.stopAnimating()
        self.spinner.isHidden = true
        self.titleLabel.text = NSLocalizedString("Linking Request Received", comment: "")
        self.subtitleLabel.text = NSLocalizedString("Please check that the words below match the words shown on the device being linked.", comment: "")
        self.mnemonicLabel.isHidden = false
        self.authorizeButton.isHidden = false
    }
    
    @objc private func authorizeDeviceLink() {
        let deviceLink = self.deviceLink!
        let session = DeviceLinkingSession.current!
        session.authorizeDeviceLink(deviceLink)
        session.stopListeningForLinkingRequests()
        dismiss(animated: true, completion: nil)
    }
}
