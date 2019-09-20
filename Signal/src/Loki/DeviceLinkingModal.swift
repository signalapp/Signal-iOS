import NVActivityIndicatorView

@objc(LKDeviceLinkingModal)
final class DeviceLinkingModal : UIViewController, LokiDeviceLinkingSessionDelegate {
    
    private lazy var deviceLinkingSession: LokiDeviceLinkingSession = {
        return LokiDeviceLinkingSession(delegate: self)
    }()
    
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
    
    private lazy var cancelButton: OWSFlatButton = {
        let result = OWSFlatButton.button(title: NSLocalizedString("Cancel", comment: ""), font: .ows_dynamicTypeBodyClamped, titleColor: .white, backgroundColor: .clear, target: self, selector: #selector(cancel))
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpViewHierarchy()
        deviceLinkingSession.startListeningForLinkingRequests()
    }
    
    private func setUpViewHierarchy() {
        view.backgroundColor = .clear
        // Content view
        view.addSubview(contentView)
        contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32).isActive = true
        view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 32).isActive = true
        contentView.center(.vertical, in: view)
        // Spinner
        contentView.addSubview(spinner)
        spinner.center(.horizontal, in: contentView)
        spinner.pin(.top, to: .top, of: contentView, withInset: 32)
        spinner.set(.width, to: 64)
        spinner.set(.height, to: 64)
        spinner.startAnimating()
        // Title label
        contentView.addSubview(titleLabel)
        titleLabel.pin(.leading, to: .leading, of: contentView, withInset: 16)
        titleLabel.pin(.top, to: .bottom, of: spinner, withInset: 32)
        contentView.pin(.trailing, to: .trailing, of: titleLabel, withInset: 16)
        // Subtitle label
        contentView.addSubview(subtitleLabel)
        subtitleLabel.pin(.leading, to: .leading, of: contentView, withInset: 16)
        subtitleLabel.pin(.top, to: .bottom, of: titleLabel, withInset: 32)
        contentView.pin(.trailing, to: .trailing, of: subtitleLabel, withInset: 16)
        // Cancel button
        contentView.addSubview(cancelButton)
        cancelButton.pin(.leading, to: .leading, of: contentView, withInset: 16)
        cancelButton.pin(.top, to: .bottom, of: subtitleLabel, withInset: 16)
        contentView.pin(.trailing, to: .trailing, of: cancelButton, withInset: 16)
        contentView.pin(.bottom, to: .bottom, of: cancelButton, withInset: 16)
        let cancelButtonHeight = cancelButton.button.titleLabel!.font.pointSize * 48 / 17
        cancelButton.set(.height, to: cancelButtonHeight)
    }
    
    // MARK: Device Linking
    func requestUserAuthorization(for deviceLink: LokiDeviceLink) {
    
    }
    
    func handleDeviceLinkingSessionTimeout() {
        
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
    
    @objc private func cancel() {
        deviceLinkingSession.stopListeningForLinkingRequests()
        dismiss(animated: true, completion: nil)
    }
}
