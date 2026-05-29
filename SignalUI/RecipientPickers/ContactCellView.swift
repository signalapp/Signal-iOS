//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public class ContactCellView: ManualStackView {

    public struct Configuration {
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

        public var accessory: ContactCellView.Accessory?

        public var attributedSubtitle: NSAttributedString?

        public var shouldShowContactIcon = false

        public var allowUserInteraction = false

        public var badged = true // TODO: Badges — Default false? Configure each use-case?

        public var storyState: StoryContextViewState?

        public var hasAccessoryText: Bool {
            accessoryMessage?.nilIfEmpty != nil
        }

        public var avatarSizeClass: ConversationAvatarView.Configuration.SizeClass?

        public var memberLabel: MemberLabelForRendering?

        public init(address: SignalServiceAddress, localUserDisplayMode: LocalUserDisplayMode) {
            self.dataSource = .address(address)
            self.localUserDisplayMode = localUserDisplayMode
        }

        public init(groupThread: TSGroupThread, localUserDisplayMode: LocalUserDisplayMode) {
            self.dataSource = .groupThread(groupThread)
            self.localUserDisplayMode = localUserDisplayMode
        }

        public init(name: String, avatar: UIImage) {
            self.dataSource = .static(name: name, avatar: avatar)
            self.localUserDisplayMode = .asUser
        }

        public mutating func useVerifiedSubtitle() {
            let text = NSMutableAttributedString()
            text.append(SignalSymbol.safetyNumber.attributedString(for: .caption1, clamped: true))
            text.append(" ", attributes: [:])
            text.append(SafetyNumberStrings.verified, attributes: [:])
            self.attributedSubtitle = text
        }
    }

    public struct Accessory {
        let accessoryView: UIView
        let size: CGSize

        public init(accessoryView: UIView, size: CGSize) {
            self.accessoryView = accessoryView
            self.size = size
        }
    }

    public static var avatarSizeClass: ConversationAvatarView.Configuration.SizeClass { .thirtySix }

    private func avatarDataSource(configuration: Configuration) -> ConversationAvatarDataSource {
        switch configuration.dataSource {
        case .groupThread(let thread): return .thread(thread)
        case .address(let address): return .address(address)
        case .static(_, let avatar): return .asset(avatar: avatar, badge: nil)
        }
    }

    // TODO: Update localUserDisplayMode.
    private let avatarView = ConversationAvatarView(
        sizeClass: avatarSizeClass,
        localUserDisplayMode: .asUser,
        useAutolayout: false,
    )

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

        if
            let nameLabelText = nameLabel.attributedText?.string.nilIfEmpty,
            let nameLabelColor = nameLabel.textColor
        {
            nameLabel.attributedText = nameLabelText.asAttributedString(attributes: [
                .foregroundColor: nameLabelColor,
            ])
        }
    }

    public func configure(
        configuration: Configuration,
        transaction: DBReadTransaction,
    ) {
        owsAssertDebug(!shouldDeactivateConstraints)

        setupObservations(configuration: configuration)

        isUserInteractionEnabled = configuration.allowUserInteraction

        let avatarDataSource = avatarDataSource(configuration: configuration)

        avatarView.update(transaction) { config in
            config.dataSource = avatarDataSource
            config.addBadgeIfApplicable = configuration.badged
            config.localUserDisplayMode = configuration.localUserDisplayMode
            if let storyState = configuration.storyState {
                config.storyConfiguration = .fixed(storyState)
            } else {
                config.storyConfiguration = .disabled
            }
            if let sizeClass = configuration.avatarSizeClass {
                config.sizeClass = sizeClass
            }
        }

        if avatarDataSource.isGroupAvatar, let storyState = configuration.storyState {
            // Group story. Add badge
            avatarView.addSubview(groupStoryBadgeView)
            let badgeColor: UIColor
            switch storyState {
            case .unviewed:
                badgeColor = .Signal.accent
            case .viewed, .noStories:
                badgeColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray25
            }
            let size: CGFloat = 20
            groupStoryBadgeView.backgroundColor = badgeColor
            groupStoryBadgeView.layer.cornerRadius = size / 2
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
            var rootStackSubviews: [UIView] = [avatarView]
            let avatarSize = configuration.avatarSizeClass?.size ?? Self.avatarSizeClass.size
            var rootStackSubviewInfos = [avatarSize.asManualSubviewInfo(hasFixedSize: true)]

            // Configure textStack.
            do {
                var textStackSubviews: [UILabel] = [nameLabel]
                let nameSize = nameLabel.sizeThatFits(.square(.greatestFiniteMagnitude))
                var textStackSubviewInfos = [nameSize.asManualSubviewInfo]

                if
                    let memberLabel = configuration.memberLabel
                {
                    let memberLabelLabel = CVCapsuleLabel(
                        attributedText: NSAttributedString(string: memberLabel.label),
                        textColor: memberLabel.groupNameColor,
                        font: nil,
                        highlightRange: NSRange(location: 0, length: (memberLabel.label as NSString).length),
                        highlightFont: .dynamicTypeCaption1Clamped,
                        axLabelPrefix: OWSLocalizedString(
                            "MEMBER_LABEL_AX_PREFIX",
                            comment: "Accessibility prefix for member labels.",
                        ),
                        presentationContext: .nonMessageBubble,
                        numberOfLines: 1,
                        signalSymbolRange: nil,
                        onTap: nil,
                    )

                    textStackSubviews.append(memberLabelLabel)
                    let memberLabelSize = memberLabelLabel.labelSize(maxWidth: .greatestFiniteMagnitude)

                    textStackSubviewInfos.append(memberLabelSize.asManualSubviewInfo)
                } else if let attributedSubtitle = configuration.attributedSubtitle?.nilIfEmpty {
                    subtitleLabel.attributedText = attributedSubtitle

                    textStackSubviews.append(subtitleLabel)
                    let subtitleSize = subtitleLabel.sizeThatFits(.square(.greatestFiniteMagnitude))
                    textStackSubviewInfos.append(subtitleSize.asManualSubviewInfo)
                }

                let textStackConfig = ManualStackView.Config(
                    axis: .vertical,
                    alignment: .leading,
                    spacing: 0,
                    layoutMargins: .zero,
                )
                let textStackMeasurement = textStack.configure(
                    config: textStackConfig,
                    subviews: textStackSubviews,
                    subviewInfos: textStackSubviewInfos,
                )
                rootStackSubviews.append(textStack)
                rootStackSubviewInfos.append(textStackMeasurement.measuredSize.asManualSubviewInfo)
            }

            var accessory = configuration.accessory
            if let accessoryMessage = configuration.accessoryMessage {
                accessoryLabel.text = accessoryMessage
                let labelSize = accessoryLabel.sizeThatFits(.square(.greatestFiniteMagnitude))
                accessory = Accessory(
                    accessoryView: accessoryLabel,
                    size: labelSize,
                )
            }
            if let accessory {
                rootStackSubviews.append(accessory.accessoryView)
                rootStackSubviewInfos.append(accessory.size.asManualSubviewInfo(hasFixedSize: true))
            }

            let rootStackConfig = ManualStackView.Config(
                axis: .horizontal,
                alignment: .center,
                spacing: Self.avatarTextHSpacing,
                layoutMargins: .zero,
            )
            let rootStackMeasurement = ManualStackView.measure(
                config: rootStackConfig,
                subviewInfos: rootStackSubviewInfos,
            )
            self.configure(
                config: rootStackConfig,
                measurement: rootStackMeasurement,
                subviews: rootStackSubviews,
            )
        }
    }

    // MARK: - Notifications

    private var observation: NotificationCenter.Observer?

    private func setupObservations(configuration: Configuration) {
        if let observation {
            NotificationCenter.default.removeObserver(observation)
            self.observation = nil
        }

        if case .address = configuration.dataSource {
            observation = NotificationCenter.default.addObserver(
                name: UserProfileNotifications.otherUsersProfileDidChange,
            ) { [weak self] notification in
                guard
                    let changedAddress = notification.userInfo?[UserProfileNotifications.profileAddressKey] as? SignalServiceAddress,
                    changedAddress.isValid
                else {
                    owsFailDebug("changedAddress was unexpectedly nil")
                    return
                }
                if case .address(changedAddress) = configuration.dataSource {
                    self?.updateNameLabelsWithSneakyTransaction(configuration: configuration)
                }
            }
        }
    }

    // MARK: -

    private func updateNameLabelsWithSneakyTransaction(configuration: Configuration) {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            updateNameLabels(configuration: configuration, transaction: transaction)
        }
    }

    private func updateNameLabels(
        configuration: Configuration,
        transaction: DBReadTransaction,
    ) {
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
                    transaction: transaction,
                )

                switch (address.isLocalAddress, configuration.localUserDisplayMode) {
                case (false, _), (true, .asLocalUser), (true, .asUser):
                    return name
                case (true, .noteToSelf):
                    let verifiedIcon = NSAttributedString.with(
                        image: Theme.iconImage(.official),
                        font: .dynamicTypeSubheadline,
                        centerVerticallyRelativeTo: .dynamicTypeBody,
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
                attributes: [.foregroundColor: textColor],
            )
            nameLabel.attributedText = nameString.stringByAppendingString(contactIcon)
        } else {
            nameLabel.attributedText = nameString
        }
    }

    override public func reset() {
        super.reset()

        if let observation {
            NotificationCenter.default.removeObserver(observation)
            self.observation = nil
        }

        avatarView.reset()
        textStack.reset()

        nameLabel.text = nil
        subtitleLabel.text = nil
        accessoryLabel.text = nil
    }
}
