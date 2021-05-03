//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ContactCellConfiguration: NSObject {
    public let content: ConversationContent

    @objc
    public let localUserAvatarMode: LocalUserAvatarMode

    @objc
    public var useLargeAvatars = false

    @objc
    public var forceDarkAppearance = false

    @objc
    public var accessoryMessage: String?

    @objc
    public var customName: NSAttributedString?

    @objc
    public var accessoryView: UIView?

    @objc
    public var attributedSubtitle: NSAttributedString?

    @objc
    public var hasAccessoryText: Bool {
        accessoryMessage?.nilIfEmpty != nil
    }

    fileprivate var avatarSize: UInt {
        useLargeAvatars ? kStandardAvatarSize : kSmallAvatarSize
    }

    public init(content: ConversationContent,
                localUserAvatarMode: LocalUserAvatarMode) {
        self.content = content
        self.localUserAvatarMode = localUserAvatarMode

        super.init()
    }

    @objc(buildWithSneakyTransactionForaddress:localUserAvatarMode:)
    public static func buildWithSneakyTransaction(address: SignalServiceAddress,
                                                  localUserAvatarMode: LocalUserAvatarMode) -> ContactCellConfiguration {
        databaseStorage.read { transaction in
            build(address: address, localUserAvatarMode: localUserAvatarMode, transaction: transaction)
        }
    }

    @objc(buildForAddress:localUserAvatarMode:transaction:)
    public static func build(address: SignalServiceAddress,
                             localUserAvatarMode: LocalUserAvatarMode,
                             transaction: SDSAnyReadTransaction) -> ContactCellConfiguration {
        let content = ConversationContent.forAddress(address, transaction: transaction)
        return ContactCellConfiguration(content: content,
                                        localUserAvatarMode: localUserAvatarMode)
    }

    @objc(buildForThread:localUserAvatarMode:)
    public static func build(thread: TSThread,
                             localUserAvatarMode: LocalUserAvatarMode) -> ContactCellConfiguration {
        let content = ConversationContent.forThread(thread)
        return ContactCellConfiguration(content: content,
                                        localUserAvatarMode: localUserAvatarMode)
    }

    public func useVerifiedSubtitle() {
        let text = NSMutableAttributedString()
        text.appendTemplatedImage(named: "check-12",
                                  font: ContactCellView.subtitleFont)
        text.append(" ", attributes: [:])
        text.append(NSLocalizedString("PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                      comment: "Badge indicating that the user is verified."),
                    attributes: [:])
        self.attributedSubtitle = text
    }
}

// MARK: -

@objc
public class ContactCellView: UIStackView {

    private var configuration: ContactCellConfiguration? {
        didSet {
            ensureObservers()
        }
    }

//    // TODO: Remove.
//    @objc
//    public var accessoryMessage: String? { configuration?.accessoryMessage}
//
//    // TODO: Remove.
//    @objc
//    public var customName: NSAttributedString? { configuration?.customName }
//
//    // TODO: Pass as argument to configure.
//    @objc
//    public var useLargeAvatars: Bool { configuration?.useLargeAvatars ?? false }

    private var content: ConversationContent? { configuration?.content }
//        didSet {
//            ensureObservers()
//        }
//    }

//    @objc
//    public var accessoryMessage: String?
//
//    @objc
//    public var customName: NSAttributedString?
//
//    // TODO: Pass as argument to configure.
//    @objc
//    public var useLargeAvatars = false

    // - (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle
    // {
    //    self.subtitleLabel.attributedText = attributedSubtitle;
    // }
    //
    // - (void)setSubtitle:(nullable NSString *)subtitle
    // {
    //    [self setAttributedSubtitle:subtitle.asAttributedString];
    // }

    // TODO: Update localUserAvatarMode.
    private let avatarView = ConversationAvatarView(diameter: kSmallAvatarSize,
                                                    localUserAvatarMode: .asUser)

    @objc
    public static let avatarTextHSpacing: CGFloat = 12

    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let accessoryLabel = UILabel()

    private let accessoryViewContainer = UIView.transparentContainer()

    private let nameContainerView = UIStackView()

    @objc
    public required init() {
        super.init(frame: .zero)

        configure()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {

        self.layoutMargins = .zero

        nameLabel.lineBreakMode = .byTruncatingTail

        accessoryLabel.textAlignment = .right

        nameContainerView.axis = .vertical
        nameContainerView.addArrangedSubview(nameLabel)
        nameContainerView.addArrangedSubview(subtitleLabel)

        nameContainerView.setContentHuggingHorizontalLow()

        accessoryViewContainer.setContentHuggingHorizontalHigh()

        self.axis = .horizontal
        self.spacing = Self.avatarTextHSpacing
        self.alignment = .center
        self.addArrangedSubview(avatarView)
        self.addArrangedSubview(nameContainerView)
        self.addArrangedSubview(accessoryViewContainer)
    }

    fileprivate static var subtitleFont: UIFont {
        .ows_dynamicTypeCaption1Clamped
    }

    private func configureFontsAndColors(forceDarkAppearance: Bool) {
        nameLabel.font = OWSTableItem.primaryLabelFont
        subtitleLabel.font = Self.subtitleFont
        accessoryLabel.font = .ows_dynamicTypeSubheadlineClamped

        nameLabel.textColor = forceDarkAppearance ? Theme.darkThemePrimaryColor : Theme.primaryTextColor
        subtitleLabel.textColor = (forceDarkAppearance ? Theme.darkThemeSecondaryTextAndIconColor : Theme.secondaryTextAndIconColor)
        accessoryLabel.textColor = Theme.isDarkThemeEnabled ? .ows_gray25 : .ows_gray45

        if let nameLabelText = nameLabel.attributedText?.string.nilIfEmpty,
           let nameLabelColor = nameLabel.textColor {
            nameLabel.attributedText = nameLabelText.asAttributedString(attributes: [
                .foregroundColor: nameLabelColor
            ])
        }
    }

    public func configureWithSneakyTransaction(recipientAddress: SignalServiceAddress,
                                               localUserAvatarMode: LocalUserAvatarMode) {
        databaseStorage.read { transaction in
            configure(recipientAddress: recipientAddress,
                      localUserAvatarMode: localUserAvatarMode,
                      transaction: transaction)
        }
    }

    public func configure(recipientAddress address: SignalServiceAddress,
                          localUserAvatarMode: LocalUserAvatarMode,
                          transaction: SDSAnyReadTransaction) {
        owsAssertDebug(address.isValid)
        let content = ConversationContent.forAddress(address, transaction: transaction)
        let configuration = ContactCellConfiguration(content: content,
                                                     localUserAvatarMode: localUserAvatarMode)
        configure(configuration: configuration, transaction: transaction)

    }

    public func configure(thread: TSThread,
                          localUserAvatarMode: LocalUserAvatarMode,
                          transaction: SDSAnyReadTransaction) {
        let configuration = ContactCellConfiguration(content: ConversationContent.forThread(thread),
                                                     localUserAvatarMode: localUserAvatarMode)
        configure(configuration: configuration, transaction: transaction)
    }

    public func configure(configuration: ContactCellConfiguration,
                          transaction: SDSAnyReadTransaction) {

        self.configuration = configuration

        avatarView.configure(content: configuration.content,
                             diameter: configuration.avatarSize,
                             localUserAvatarMode: configuration.localUserAvatarMode,
                             transaction: transaction)

        // Update fonts to reflect changes to dynamic type.
        configureFontsAndColors(forceDarkAppearance: configuration.forceDarkAppearance)

        updateNameLabels(configuration: configuration, transaction: transaction)

        if let attributedSubtitle = configuration.attributedSubtitle {
            subtitleLabel.attributedText = attributedSubtitle
        }

        if let accessoryMessage = configuration.accessoryMessage {
            accessoryLabel.text = accessoryMessage
            owsAssertDebug(configuration.accessoryView == nil)
            configuration.accessoryView = accessoryLabel
        }

        if let accessoryView = configuration.accessoryView {
            owsAssertDebug(accessoryViewContainer.subviews.isEmpty)

            accessoryViewContainer.addSubview(accessoryView)

            // Trailing-align the accessory view.
            accessoryView.autoPinEdge(toSuperviewMargin: .top)
            accessoryView.autoPinEdge(toSuperviewMargin: .bottom)
            accessoryView.autoPinEdge(toSuperviewMargin: .trailing)
            accessoryView.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        }

        // Force layout, since imageView isn't being initally rendered on App Store optimized build.
        //
        // TODO: Is this still necessary?
        layoutSubviews()
    }

    // MARK: - Notifications

    private func ensureObservers() {
        NotificationCenter.default.removeObserver(self)

        guard let content = content else {
            return
        }

        switch content {
        case .contact, .unknownContact:
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(otherUsersProfileChanged(notification:)),
                                                   name: .otherUsersProfileDidChange,
                                                   object: nil)
        case .group:
            break
        }
    }

    // MARK: -

    private func updateNameLabelsWithSneakyTransaction(configuration: ContactCellConfiguration) {
        databaseStorage.read { transaction in
            updateNameLabels(configuration: configuration, transaction: transaction)
        }
    }

    private func updateNameLabels(configuration: ContactCellConfiguration,
                                  transaction: SDSAnyReadTransaction) {
        if let customName = configuration.customName?.nilIfEmpty {
            nameLabel.attributedText = customName
        } else {
            func updateNameLabels(address: SignalServiceAddress) {
                if address.isLocalAddress {
                    nameLabel.text = MessageStrings.noteToSelf
                } else {
                    nameLabel.text = contactsManager.displayName(for: address,
                                                                 transaction: transaction)
                }
            }

            switch configuration.content {
            case .contact(let contactThread):
                updateNameLabels(address: contactThread.contactAddress)
            case .group(let groupThread):
                // TODO: Ensure nameLabel.textColor.
                let threadName = contactsManager.displayName(for: groupThread,
                                                             transaction: transaction)
                if let nameLabelColor = nameLabel.textColor {
                    nameLabel.attributedText = threadName.asAttributedString(attributes: [
                        .foregroundColor: nameLabelColor
                    ])
                } else {
                    owsFailDebug("Missing nameLabelColor.")
                }
            case .unknownContact(let contactAddress):
                updateNameLabels(address: contactAddress)
            }
        }

        // TODO: Is this necessary?
        nameLabel.setNeedsLayout()
    }

    @objc
    public func prepareForReuse() {
        NotificationCenter.default.removeObserver(self)

        avatarView.reset()

        self.configuration = nil
//        self.content = nil
//        self.accessoryMessage = nil
        self.nameLabel.text = nil
        self.subtitleLabel.text = nil
        self.accessoryLabel.text = nil
//        self.customName = nil
        accessoryViewContainer.removeAllSubviews()
//        self.useLargeAvatars = false
    }

    @objc
    private func otherUsersProfileChanged(notification: Notification) {
        AssertIsOnMainThread()

        guard let configuration = self.configuration else {
            return
        }
        guard let changedAddress = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress,
              changedAddress.isValid else {
            owsFailDebug("changedAddress was unexpectedly nil")
            return
        }
        guard let contactAddress = configuration.content.contactAddress else {
            // shouldn't call this for group threads
            owsFailDebug("contactAddress was unexpectedly nil")
            return
        }
        guard contactAddress == changedAddress else {
            // not this avatar
            return
        }

        updateNameLabelsWithSneakyTransaction(configuration: configuration)
    }
}
