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
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 32),
            contentView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        // Spinner
        contentView.addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            spinner.heightAnchor.constraint(equalToConstant: 64),
            spinner.widthAnchor.constraint(equalToConstant: 64)
        ])
        spinner.startAnimating()
        // Title label
        contentView.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 32),
            contentView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 16)
        ])
        // Subtitle label
        contentView.addSubview(subtitleLabel)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor, constant: 16)
        ])
        // Cancel button
        contentView.addSubview(cancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        let cancelButtonHeight = cancelButton.button.titleLabel!.font.pointSize * 48 / 17
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cancelButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 16),
            contentView.bottomAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: 16),
            cancelButton.heightAnchor.constraint(equalToConstant: cancelButtonHeight)
        ])
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
            dismiss(animated: true, completion: nil)
        }
    }
    
    @objc private func cancel() {
        dismiss(animated: true, completion: nil)
    }
}
