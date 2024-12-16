//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public class ContactCellAccessoryView: NSObject {
    let accessoryView: UIView
    let size: CGSize

    public init(accessoryView: UIView, size: CGSize) {
        self.accessoryView = accessoryView
        self.size = size
    }
}

// MARK: -

public class ContactCellConfiguration: NSObject {
    fileprivate enum CellDataSource {
        case address(SignalServiceAddress)
        case groupThread(TSGroupThread)
        case `static`(name: String, avatar: UIImage)
    }

    fileprivate let dataSource: CellDataSource

    public let localUserDisplayMode: LocalUserDisplayMode

    public var forceDarkAppearance = false

    public var accessoryMessage: String?

    public var customName: String?

    public var accessoryView: ContactCellAccessoryView?

    public var attributedSubtitle: NSAttributedString?

    public var shouldShowContactIcon = false

    public var allowUserInteraction = false

    public var badged = true // TODO: Badges — Default false? Configure each use-case?

    public var storyState: StoryContextViewState?

    public var hasAccessoryText: Bool {
        accessoryMessage?.nilIfEmpty != nil
    }

    public init(address: SignalServiceAddress, localUserDisplayMode: LocalUserDisplayMode) {
        self.dataSource = .address(address)
        self.localUserDisplayMode = localUserDisplayMode
        super.init()
    }

    public init(groupThread: TSGroupThread, localUserDisplayMode: LocalUserDisplayMode) {
        self.dataSource = .groupThread(groupThread)
        self.localUserDisplayMode = localUserDisplayMode
        super.init()
    }

    public init(name: String, avatar: UIImage) {
        self.dataSource = .static(name: name, avatar: avatar)
        self.localUserDisplayMode = .asUser
        super.init()
    }

    public func useVerifiedSubtitle() {
        let text = NSMutableAttributedString()
        text.append(SignalSymbol.safetyNumber.attributedString(for: .caption1, clamped: true))
        text.append(" ", attributes: [:])
        text.append(SafetyNumberStrings.verified, attributes: [:])
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

    public static var avatarSizeClass: ConversationAvatarView.Configuration.SizeClass { .thirtySix }
    private var avatarDataSource: ConversationAvatarDataSource? {
        switch configuration?.dataSource {
        case .groupThread(let thread): return .thread(thread)
        case .address(let address): return .address(address)
        case .static(_, let avatar): return .asset(avatar: avatar, badge: nil)
        case nil: return nil
        }
    }

    // TODO: Update localUserDisplayMode.
    private let avatarView = ConversationAvatarView(
        sizeClass: avatarSizeClass,
        localUserDisplayMode: .asUser,
        useAutolayout: false)

    public var tooltipTailReferenceView: UIView { return avatarView }

    public static let avatarTextHSpacing: CGFloat = 12

    private lazy var groupStoryBadgeView: UIView = {
        let backgroundView = UIView.container()
        let symbolView = UIImageView(image: UIImage(named: "stories-fill-compact"))
        backgroundView.addSubview(symbolView)
        symbolView.tintColor = .ows_white
        symbolView.autoSetDimensions(to: .square(12))
        symbolView.autoCenterInSuperview()
        return backgroundView
    }()

    private let nameLabel = CVLabel()
    private let subtitleLabel = CVLabel()
    private let accessoryLabel = CVLabel()

    private let textStack = ManualStackView(name: "textStack")

    public init() {
        super.init(name: "ContactCellView")

        nameLabel.lineBreakMode = .byTruncatingTail
        accessoryLabel.textAlignment = .right

        self.shouldDeactivateConstraints = false
    }

    private var nameLabelFont: UIFont { OWSTableItem.primaryLabelFont }
    fileprivate static var subtitleFont: UIFont { .dynamicTypeCaption1Clamped }

    private func nameLabelColor(forceDarkAppearance: Bool) -> UIColor {
        forceDarkAppearance ? Theme.darkThemePrimaryColor : Theme.primaryTextColor
    }

    private func configureFontsAndColors(forceDarkAppearance: Bool) {
        nameLabel.font = nameLabelFont
        subtitleLabel.font = Self.subtitleFont
        accessoryLabel.font = .dynamicTypeSubheadlineClamped

        nameLabel.textColor = nameLabelColor(forceDarkAppearance: forceDarkAppearance)
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

        avatarView.update(transaction) { config in
            config.dataSource = avatarDataSource
            config.addBadgeIfApplicable = configuration.badged
            config.localUserDisplayMode = configuration.localUserDisplayMode
            if let storyState = configuration.storyState {
                config.storyConfiguration = .fixed(storyState)
            } else {
                config.storyConfiguration = .disabled
            }
        }

        if avatarDataSource?.isGroupAvatar ?? false,
           let storyState = configuration.storyState {
            // Group story. Add badge
            avatarView.addSubview(groupStoryBadgeView)
            let badgeColor: UIColor
            switch storyState {
            case .unviewed:
                badgeColor = .ows_accentBlue
            case .viewed, .noStories:
                badgeColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray25
            }
            let size: CGFloat = 20
            groupStoryBadgeView.backgroundColor = badgeColor
            groupStoryBadgeView.layer.cornerRadius = size/2
            groupStoryBadgeView.layer.masksToBounds = true
            groupStoryBadgeView.autoSetDimensions(to: .square(size))
            groupStoryBadgeView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -2)
            groupStoryBadgeView.autoPinEdge(toSuperviewEdge: .trailing, withInset: -5)
        } else {
            // Not a group or not a story. Remove badge
            groupStoryBadgeView.removeFromSuperview()
        }

        // Update fonts to reflect changes to dynamic type.
        configureFontsAndColors(forceDarkAppearance: configuration.forceDarkAppearance)

        updateNameLabels(configuration: configuration, transaction: transaction)

        // Configure self.
        do {
            var rootStackSubviews: [UIView] = [ avatarView ]
            let avatarSize = Self.avatarSizeClass.size
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
        if case .address = configuration?.dataSource {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(otherUsersProfileChanged(notification:)),
                                                   name: UserProfileNotifications.otherUsersProfileDidChange,
                                                   object: nil)
        }
    }

    // MARK: -

    private func updateNameLabelsWithSneakyTransaction(configuration: ContactCellConfiguration) {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            updateNameLabels(configuration: configuration, transaction: transaction)
        }
    }

    private func updateNameLabels(configuration: ContactCellConfiguration,
                                  transaction: SDSAnyReadTransaction) {
        AssertIsOnMainThread()

        let textColor = self.nameLabelColor(forceDarkAppearance: configuration.forceDarkAppearance)

        let nameString = { () -> NSAttributedString in
            if let customName = configuration.customName?.nilIfEmpty {
                return customName.asAttributedString
            }

            switch configuration.dataSource {
            case .address(let address):
                let name = SSKEnvironment.shared.contactManagerRef.nameForAddress(
                    address,
                    localUserDisplayMode: configuration.localUserDisplayMode,
                    short: false,
                    transaction: transaction
                )

                switch (address.isLocalAddress, configuration.localUserDisplayMode) {
                case (false, _), (true, .asLocalUser), (true, .asUser):
                    return name
                case (true, .noteToSelf):
                    let verifiedIcon = NSAttributedString.with(
                        image: Theme.iconImage(.official),
                        font: .dynamicTypeSubheadline,
                        centerVerticallyRelativeTo: .dynamicTypeBody
                    )
                    return name.stringByAppendingString(" ").stringByAppendingString(verifiedIcon)
                }
            case .groupThread(let thread):
                let threadName = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: transaction)
                return threadName.asAttributedString(attributes: [
                    .foregroundColor: textColor,
                ])
            case .static(let name, _):
                return name.asAttributedString
            }
        }()

        if configuration.shouldShowContactIcon {
            let contactIcon = SignalSymbol.personCircle.attributedString(
                dynamicTypeBaseSize: 14,
                weight: .bold,
                leadingCharacter: .space,
                attributes: [.foregroundColor: textColor]
            )
            nameLabel.attributedText = nameString.stringByAppendingString(contactIcon)
        } else {
            nameLabel.attributedText = nameString
        }
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
        guard let changedAddress = notification.userInfo?[UserProfileNotifications.profileAddressKey] as? SignalServiceAddress,
              changedAddress.isValid else {
            owsFailDebug("changedAddress was unexpectedly nil")
            return
        }

        if case .address(changedAddress) = configuration.dataSource {
            updateNameLabelsWithSneakyTransaction(configuration: configuration)
        }
    }
}
