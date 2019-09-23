import NVActivityIndicatorView

// TODO: Use the same kind of modal to show the user their QR code and seed

@objc(LKDeviceLinkingModal)
final class DeviceLinkingModal : UIViewController, LokiDeviceLinkingSessionDelegate {
    private var deviceLink: LokiDeviceLink?
    
    // MARK: Components
    private lazy var contentView: UIView = {
        let result = UIView()
        result.backgroundColor = .lokiDarkGray()
        result.layer.cornerRadius = 4
        result.layer.masksToBounds = false
        result.layer.shadowColor = UIColor.black.cgColor
        result.layer.shadowRadius = 8
        result.layer.shadowOpacity = 0.64
        return result
    }()
    
    private lazy var topSpacer = UIView.spacer(withHeight: 8)
    
    private lazy var spinner = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: .white, padding: nil)
    
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Theme.primaryColor
        result.font = UIFont.ows_dynamicTypeHeadlineClamped
        result.text = NSLocalizedString("Waiting for Device", comment: "")
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Theme.primaryColor
        result.font = UIFont.ows_dynamicTypeCaption1Clamped
        result.text = NSLocalizedString("Click the \"Link Device\" button on your other device to start the linking process", comment: "")
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
    
    private lazy var cancelButton: OWSFlatButton = {
        let result = OWSFlatButton.button(title: NSLocalizedString("Cancel", comment: ""), font: .ows_dynamicTypeBodyClamped, titleColor: .white, backgroundColor: .clear, target: self, selector: #selector(cancel))
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpViewHierarchy()
        let _ = LokiDeviceLinkingSession.startListeningForLinkingRequests(with: self)
    }
    
    private func setUpViewHierarchy() {
        view.backgroundColor = .clear
        view.addSubview(contentView)
        contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32).isActive = true
        view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 32).isActive = true
        contentView.center(.vertical, in: view)
        let buttonStackView = UIStackView(arrangedSubviews: [ authorizeButton, cancelButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .fillEqually
        let stackView = UIStackView(arrangedSubviews: [ topSpacer, spinner, UIView.spacer(withHeight: 8), titleLabel, subtitleLabel, mnemonicLabel, buttonStackView ])
        stackView.spacing = 16
        contentView.addSubview(stackView)
        stackView.axis = .vertical
        stackView.pin(.leading, to: .leading, of: contentView, withInset: 16)
        stackView.pin(.top, to: .top, of: contentView, withInset: 16)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: 16)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: 16)
        spinner.set(.height, to: 64)
        spinner.startAnimating()
        mnemonicLabel.isHidden = true
        let buttonHeight = cancelButton.button.titleLabel!.font.pointSize * 48 / 17
        authorizeButton.set(.height, to: buttonHeight)
        cancelButton.set(.height, to: buttonHeight)
        authorizeButton.isHidden = true
    }
    
    // MARK: Device Linking
    func requestUserAuthorization(for deviceLink: LokiDeviceLink) {
        self.deviceLink = deviceLink
        self.topSpacer.isHidden = true
        self.spinner.stopAnimating()
        self.spinner.isHidden = true
        self.titleLabel.text = NSLocalizedString("Linking Request Received", comment: "")
        self.subtitleLabel.text = NSLocalizedString("Please check that the words below match the words shown on the device being linked.", comment: "")
        self.mnemonicLabel.isHidden = false
        self.authorizeButton.isHidden = false
    }
    
    // MARK: Interaction
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        let location = touch.location(in: view)
        if contentView.frame.contains(location) {
            super.touchesBegan(touches, with: event)
        } else {
            cancel()
        }
    }
    
    @objc private func authorizeDeviceLink() {
        let deviceLink = self.deviceLink!
        let session = LokiDeviceLinkingSession.current!
        session.authorizeDeviceLink(deviceLink)
        session.stopListeningForLinkingRequests()
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func cancel() {
        LokiDeviceLinkingSession.current?.stopListeningForLinkingRequests()
        dismiss(animated: true, completion: nil)
    }
}
