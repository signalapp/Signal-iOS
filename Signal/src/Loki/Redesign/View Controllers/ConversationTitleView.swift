
@objc final class ConversationTitleView : UIView {
    private let thread: TSThread
    
    // MARK: Components
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.lineBreakMode = .byTruncatingTail
        return result
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.lineBreakMode = .byTruncatingTail
        return result
    }()
    
    // MARK: Lifecycle
    @objc init(thread: TSThread) {
        self.thread = thread
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
        update()
        NotificationCenter.default.addObserver(self, selector: #selector(handleProfileChangedNotification(_:)), name: NSNotification.Name(rawValue: kNSNotificationName_OtherUsersProfileDidChange), object: nil)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(thread:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(thread:) instead.")
    }
    
    private func setUpViewHierarchy() {
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 0) // Compensate for settings button trailing margin
        stackView.isLayoutMarginsRelativeArrangement = true
        addSubview(stackView)
        stackView.pin(to: self)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Updating
    private func update() {
        let title: String
        if thread.isGroupThread() {
            if thread.name().isEmpty {
                title = NSLocalizedString("New Group", comment: "")
            } else {
                title = thread.name()
            }
        } else {
            if thread.isNoteToSelf() {
                title = NSLocalizedString("Note to Self", comment: "")
            } else {
                let hexEncodedPublicKey = thread.contactIdentifier()!
                title = DisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? hexEncodedPublicKey
            }
        }
        titleLabel.text = title
        let subtitle = NSMutableAttributedString()
        if thread.isMuted {
            subtitle.append(NSAttributedString(string: "\u{e067}  ", attributes: [ .font : UIFont.ows_elegantIconsFont(10), .foregroundColor : Colors.unimportant ]))
        }
        subtitle.append(NSAttributedString(string: "26 members")) // TODO: Implement
        subtitleLabel.attributedText = subtitle
    }
    
    @objc private func handleProfileChangedNotification(_ notification: Notification) {
        guard let hexEncodedPublicKey = notification.userInfo?[kNSNotificationKey_ProfileRecipientId] as? String, let thread = self.thread as? TSContactThread,
            hexEncodedPublicKey == thread.contactIdentifier() else { return }
        update()
    }
    
    // MARK: Layout
    public override var intrinsicContentSize: CGSize {
        return UIView.layoutFittingExpandedSize
    }
}
