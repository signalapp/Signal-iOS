@objc(LKSessionRestoreBannerView)
final class SessionRestoreBannerView : UIView {
    private let thread: TSThread
    @objc public var onRestore: (() -> Void)?
    @objc public var onDismiss: (() -> Void)?
    
    private lazy var bannerView: UIView = {
        let bannerView = UIView.container()
        bannerView.backgroundColor = UIColor.lokiGray()
        bannerView.layer.cornerRadius = 2.5;
        
        // Use a shadow to "pop" the indicator above the other views.
        bannerView.layer.shadowColor = UIColor.black.cgColor
        bannerView.layer.shadowOffset = CGSize(width: 2, height: 3)
        bannerView.layer.shadowRadius = 2
        bannerView.layer.shadowOpacity = 0.35
        return bannerView
    }()
    
    private lazy var label: UILabel = {
        let result = UILabel()
        result.textColor = UIColor.white
        result.font = UIFont.ows_dynamicTypeSubheadlineClamped
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    private lazy var buttonStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .horizontal
        result.distribution = .fillEqually
        return result
    }()

    private lazy var buttonFont = UIFont.ows_dynamicTypeBodyClamped.ows_mediumWeight()
    private lazy var buttonHeight = buttonFont.pointSize * 48 / 17
    
    // MARK: Lifecycle
    @objc init(thread: TSThread) {
        self.thread = thread;
        super.init(frame: CGRect.zero)
        initialize()
    }
       
    required init?(coder: NSCoder) { fatalError("Using SessionRestoreBannerView.init(coder:) isn't allowed. Use SessionRestoreBannerView.init(thread:) instead.") }
    override init(frame: CGRect) { fatalError("Using SessionRestoreBannerView.init(frame:) isn't allowed. Use SessionRestoreBannerView.init(thread:) instead.") }
    
    private func initialize() {
        // Set up UI
        let mainStackView = UIStackView()
        mainStackView.axis = .vertical
        mainStackView.distribution = .fill
        mainStackView.addArrangedSubview(label)
        mainStackView.addArrangedSubview(buttonStackView)
        
        let restoreButton = OWSFlatButton.button(title: NSLocalizedString("Restore session", comment: ""), font: buttonFont, titleColor: .ows_materialBlue, backgroundColor: .white, target: self, selector:#selector(restore))
        restoreButton.setBackgroundColors(upColor: .clear, downColor: .clear)
        restoreButton.autoSetDimension(.height, toSize: buttonHeight)
        buttonStackView.addArrangedSubview(restoreButton)
        
        let dismissButton = OWSFlatButton.button(title: NSLocalizedString("DISMISS_BUTTON_TEXT", comment: ""), font: buttonFont, titleColor: .ows_white, backgroundColor: .white, target: self, selector:#selector(dismiss))
        dismissButton.setBackgroundColors(upColor: .clear, downColor: .clear)
        dismissButton.autoSetDimension(.height, toSize: buttonHeight)
        buttonStackView.addArrangedSubview(dismissButton)
        
        bannerView.addSubview(mainStackView)
        mainStackView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 16, left: 16, bottom: 8, right: 16))
        
        addSubview(bannerView)
        bannerView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
       
        if let contactID = thread.contactIdentifier() {
            let displayName = Environment.shared.contactsManager.profileName(forRecipientId: contactID) ?? contactID
            label.text = String(format: NSLocalizedString("Would you like to start a new session with %@?", comment: ""), displayName)
        }
   }
    
    @objc private func restore() { onRestore?() }
    
    @objc private func dismiss() { onDismiss?() }
}
