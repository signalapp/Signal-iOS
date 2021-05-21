//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ContactCellAccessoryView: NSObject {
    let accessoryView: UIView
    let size: CGSize

    public init(accessoryView: UIView, size: CGSize) {
        self.accessoryView = accessoryView
        self.size = size
    }
}

// MARK: -

@objc
public class ContactCellConfiguration: NSObject {
    public let content: ConversationContent

    @objc
    public let localUserDisplayMode: LocalUserDisplayMode

    @objc
    public var useLargeAvatars = false

    @objc
    public var forceDarkAppearance = false

    @objc
    public var accessoryMessage: String?

    @objc
    public var customName: String?

    @objc
    public var accessoryView: ContactCellAccessoryView?

    @objc
    public var attributedSubtitle: NSAttributedString?

    @objc
    public var allowUserInteraction = false

    @objc
    public var hasAccessoryText: Bool {
        accessoryMessage?.nilIfEmpty != nil
    }

    fileprivate var avatarSize: UInt {
        useLargeAvatars ? AvatarBuilder.standardAvatarSizePoints : AvatarBuilder.smallAvatarSizePoints
    }

    public init(content: ConversationContent,
                localUserDisplayMode: LocalUserDisplayMode) {
        self.content = content
        self.localUserDisplayMode = localUserDisplayMode

        super.init()
    }

    @objc(buildWithSneakyTransactionForaddress:localUserDisplayMode:)
    public static func buildWithSneakyTransaction(address: SignalServiceAddress,
                                                  localUserDisplayMode: LocalUserDisplayMode) -> ContactCellConfiguration {
        databaseStorage.read { transaction in
            build(address: address, localUserDisplayMode: localUserDisplayMode, transaction: transaction)
        }
    }

    @objc(buildForAddress:localUserDisplayMode:transaction:)
    public static func build(address: SignalServiceAddress,
                             localUserDisplayMode: LocalUserDisplayMode,
                             transaction: SDSAnyReadTransaction) -> ContactCellConfiguration {
        let content = ConversationContent.forAddress(address, transaction: transaction)
        return ContactCellConfiguration(content: content,
                                        localUserDisplayMode: localUserDisplayMode)
    }

    @objc(buildForThread:localUserDisplayMode:)
    public static func build(thread: TSThread,
                             localUserDisplayMode: LocalUserDisplayMode) -> ContactCellConfiguration {
        let content = ConversationContent.forThread(thread)
        return ContactCellConfiguration(content: content,
                                        localUserDisplayMode: localUserDisplayMode)
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

public class ContactCellView: ManualStackView {

    private var configuration: ContactCellConfiguration? {
        didSet {
            ensureObservers()
        }
    }

    private var content: ConversationContent? { configuration?.content }

    // TODO: Update localUserDisplayMode.
    private let avatarView = ConversationAvatarView(diameterPoints: AvatarBuilder.smallAvatarSizePoints,
                                                    localUserDisplayMode: .asUser)

    @objc
    public static let avatarTextHSpacing: CGFloat = 12

    private let nameLabel = CVLabel()
    private let subtitleLabel = CVLabel()
    private let accessoryLabel = CVLabel()

    private let textStack = ManualStackView(name: "textStack")

    public required init() {
        super.init(name: "ContactCellView")

        nameLabel.lineBreakMode = .byTruncatingTail
        accessoryLabel.textAlignment = .right
        avatarView.shouldDeactivateConstraints = true

        self.shouldDeactivateConstraints = false
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String, arrangedSubviews: [UIView] = []) {
        owsFail("Do not use this initializer.")
    }

    private var nameLabelFont: UIFont { OWSTableItem.primaryLabelFont }
    fileprivate static var subtitleFont: UIFont { .ows_dynamicTypeCaption1Clamped }

    private func configureFontsAndColors(forceDarkAppearance: Bool) {
        nameLabel.font = nameLabelFont
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

    public func configure(configuration: ContactCellConfiguration,
                          transaction: SDSAnyReadTransaction) {
        AssertIsOnMainThread()
        owsAssertDebug(!shouldDeactivateConstraints)

        self.configuration = configuration

        self.isUserInteractionEnabled = configuration.allowUserInteraction

        avatarView.configure(content: configuration.content,
                             diameterPoints: configuration.avatarSize,
                             localUserDisplayMode: configuration.localUserDisplayMode,
                             transaction: transaction)

        // Update fonts to reflect changes to dynamic type.
        configureFontsAndColors(forceDarkAppearance: configuration.forceDarkAppearance)

        updateNameLabels(configuration: configuration, transaction: transaction)

        // Configure self.
        do {
            var rootStackSubviews: [UIView] = [ avatarView ]
            let avatarSize = CGSize.square(CGFloat(configuration.avatarSize))
            var rootStackSubviewInfos = [ avatarSize.asManualSubviewInfo(hasFixedSize: true) ]

            // Configure textStack.
            do {
                var textStackSubviews = [ nameLabel ]
                let nameSize = nameLabel.sizeThatFits(.square(.greatestFiniteMagnitude))
                var textStackSubviewInfos = [ nameSize.asManualSubviewInfo ]

                if let attributedSubtitle = configuration.attributedSubtitle?.nilIfEmpty {
                    subtitleLabel.attributedText = attributedSubtitle

                    textStackSubviews.append(subtitleLabel)
                    let subtitleSize = subtitleLabel.sizeThatFits(.square(.greatestFiniteMagnitude))
                    textStackSubviewInfos.append(subtitleSize.asManualSubviewInfo)
                }

                let textStackConfig = ManualStackView.Config(axis: .vertical,
                                                             alignment: .leading,
                                                             spacing: 0,
                                                             layoutMargins: .zero)
                let textStackMeasurement = textStack.configure(config: textStackConfig,
                                                               subviews: textStackSubviews,
                                                               subviewInfos: textStackSubviewInfos)
                rootStackSubviews.append(textStack)
                rootStackSubviewInfos.append(textStackMeasurement.measuredSize.asManualSubviewInfo)
            }

            if let accessoryMessage = configuration.accessoryMessage {
                accessoryLabel.text = accessoryMessage
                let labelSize = accessoryLabel.sizeThatFits(.square(.greatestFiniteMagnitude))
                configuration.accessoryView = ContactCellAccessoryView(accessoryView: accessoryLabel,
                                                                       size: labelSize)
            }
            if let accessoryView = configuration.accessoryView {
                rootStackSubviews.append(accessoryView.accessoryView)
                rootStackSubviewInfos.append(accessoryView.size.asManualSubviewInfo(hasFixedSize: true))
            }

            let rootStackConfig = ManualStackView.Config(axis: .horizontal,
                                                         alignment: .center,
                                                         spacing: Self.avatarTextHSpacing,
                                                         layoutMargins: .zero)
            let rootStackMeasurement = ManualStackView.measure(config: rootStackConfig,
                                                               subviewInfos: rootStackSubviewInfos)
            self.configure(config: rootStackConfig,
                           measurement: rootStackMeasurement,
                           subviews: rootStackSubviews)
        }
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
        AssertIsOnMainThread()

        nameLabel.attributedText = { () -> NSAttributedString in
            if let customName = configuration.customName?.nilIfEmpty {
                return customName.asAttributedString
            }
            func nameForAddress(_ address: SignalServiceAddress) -> NSAttributedString {
                let name: String
                if address.isLocalAddress {
                    switch configuration.localUserDisplayMode {
                    case .noteToSelf:
                        name = MessageStrings.noteToSelf
                    case .asLocalUser:
                        name = NSLocalizedString("GROUP_MEMBER_LOCAL_USER",
                                                 comment: "Label indicating the local user.")
                    case .asUser:
                        name = contactsManager.displayName(for: address,
                                                           transaction: transaction)
                    }
                } else {
                    name = contactsManager.displayName(for: address,
                                                       transaction: transaction)
                }
                return name.asAttributedString
            }

            switch configuration.content {
            case .contact(let contactThread):
                return nameForAddress(contactThread.contactAddress)
            case .group(let groupThread):
                // TODO: Ensure nameLabel.textColor.
                let threadName = contactsManager.displayName(for: groupThread,
                                                             transaction: transaction)
                if let nameLabelColor = nameLabel.textColor {
                    return threadName.asAttributedString(attributes: [
                        .foregroundColor: nameLabelColor
                    ])
                } else {
                    owsFailDebug("Missing nameLabelColor.")
                    return TSGroupThread.defaultGroupName.asAttributedString
                }
            case .unknownContact(let contactAddress):
                return nameForAddress(contactAddress)
            }
        }()
    }

    public override func reset() {
        super.reset()

        NotificationCenter.default.removeObserver(self)

        configuration = nil

        avatarView.reset()
        textStack.reset()

        nameLabel.text = nil
        subtitleLabel.text = nil
        accessoryLabel.text = nil
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
