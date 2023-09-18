//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

public class ChatListCell: UITableViewCell {

    public static let reuseIdentifier = "ChatListCell"

    private var avatarView: ConversationAvatarView?
    private let nameLabel = CVLabel()
    private let snippetLabel = CVLabel()
    private let dateTimeLabel = CVLabel()
    private let messageStatusIconView = CVImageView()
    private let typingIndicatorView = TypingIndicatorView()
    private let badgeView = CVImageView()
    private let muteIconView = CVImageView()

    private let unreadBadge = NeverClearView(name: "unreadBadge")
    private let unreadLabel = CVLabel()

    private let outerHStack = ManualStackViewWithLayer(name: "outerHStack")
    private let avatarStack = ManualStackView(name: "avatarStack")
    private let vStack = ManualStackView(name: "vStack")
    private let topRowStack = ManualStackView(name: "topRowStack")
    private let bottomRowStack = ManualStackView(name: "bottomRowStack")
    // The "Wrapper" shows either "snippet label" or "typing indicator".
    private let bottomRowWrapper = ManualLayoutView(name: "bottomRowWrapper")

    public var isCellVisible = false {
        didSet {
            updateTypingIndicatorState()
            spoilerConfigBuilder.isViewVisible = isCellVisible
        }
    }

    private var cvviews: [CVView] {
        [
            nameLabel,
            snippetLabel,
            dateTimeLabel,
            messageStatusIconView,
            badgeView,
            muteIconView,
            unreadLabel,

            avatarStack,
            bottomRowWrapper
        ]
    }

    private struct ReuseToken {
        let hasVerifiedBadge: Bool
        let hasMuteIndicator: Bool
        let hasMessageStatusToken: Bool
        let hasUnreadBadge: Bool
    }

    private var reuseToken: ReuseToken?

    // MARK: - Configuration

    fileprivate enum UnreadMode {
        case none
        case unreadWithCount(count: UInt)
        case unreadWithoutCount
    }

    // Compare with CLVCellContentToken:
    //
    // * Configuration captures _how_ the view wants to render the cell.
    //   ChatListCell is used by chat list and Home Search view and they
    //   render cells differently. Configuration reflects that.
    //   Configuration is cheap to build.
    // * CLVCellContentToken captures (only) the exact content that will
    //   be rendered in the cell, its measurement/layout, etc.
    //   CLVCellContentToken is expensive to build.
    struct Configuration {

        struct OverrideSnippet {
            let text: CVTextValue
            let config: HydratedMessageBody.DisplayConfiguration
        }

        let thread: ThreadViewModel
        let lastReloadDate: Date?
        let isBlocked: Bool
        let overrideSnippet: OverrideSnippet?
        let overrideDate: Date?

        fileprivate var hasOverrideSnippet: Bool {
            overrideSnippet != nil
        }
        fileprivate var unreadMode: UnreadMode {
            guard !hasOverrideSnippet else {
                // If we're using the conversation list cell to render search results,
                // don't show "unread badge" or "message status" indicator.
                return .none
            }
            guard thread.hasUnreadMessages else {
                return .none
            }
            let unreadCount = thread.unreadCount
            if unreadCount > 0 {
                return .unreadWithCount(count: unreadCount)
            } else {
                return .unreadWithoutCount
            }
        }

        init(
            thread: ThreadViewModel,
            lastReloadDate: Date?,
            isBlocked: Bool,
            overrideSnippet: OverrideSnippet? = nil,
            overrideDate: Date? = nil
        ) {
            self.thread = thread
            self.lastReloadDate = lastReloadDate
            self.isBlocked = isBlocked
            self.overrideSnippet = overrideSnippet
            self.overrideDate = overrideDate
        }
    }
    private var cellContentToken: CLVCellContentToken?
    public var nextUpdateTimestamp: Date?
    var thread: TSThread? {
        cellContentToken?.thread
    }

    // MARK: - View Constants

    private static var unreadFont: UIFont {
        UIFont.dynamicTypeCaption1Clamped
    }

    private static var dateTimeFont: UIFont {
        .dynamicTypeCaption1Clamped
    }

    private static var snippetFont: UIFont {
        .dynamicTypeSubheadlineClamped
    }

    private static var nameFont: UIFont {
        UIFont.dynamicTypeBodyClamped.semibold()
    }

    // Used for profile names.
    private static var nameSecondaryFont: UIFont {
        UIFont.dynamicTypeBodyClamped.italic()
    }

    private static var snippetColor: ThemedColor {
        return ThemedColor(light: .ows_gray45, dark: .ows_gray25)
    }

    // This value is now larger than AvatarBuilder.standardAvatarSizePoints.
    private static let avatarSize: UInt = 56
    private static let muteIconSize: CGFloat = 16

    // MARK: -

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        multipleSelectionBackgroundView = UIView(frame: contentView.bounds)
        contentView.addSubview(outerHStack)
        outerHStack.shouldDeactivateConstraints = false
        outerHStack.autoPinEdge(toSuperviewEdge: .leading)
        outerHStack.autoPinEdge(toSuperviewEdge: .trailing)
        outerHStack.autoPinHeightToSuperview()

        self.selectionStyle = .default
    }

    // This method can be invoked from any thread.
    static func measureCellHeight(cellContentToken: CLVCellContentToken) -> CGFloat {
        cellContentToken.measurements.outerHStackMeasurement.measuredSize.height
    }

    // This method can be invoked from any thread.
    internal static func buildCellContentToken(forConfiguration configuration: Configuration) -> CLVCellContentToken {
        let configs = buildCellConfigs(configuration: configuration)
        let measurements = buildMeasurements(configuration: configuration,
                                             configs: configs)
        let cellContentToken = CLVCellContentToken(configs: configs,
                                                  measurements: measurements)
        return cellContentToken
    }

    private static func buildCellConfigs(configuration: Configuration) -> CLVCellConfigs {
        let shouldShowMuteIndicator = Self.shouldShowMuteIndicator(configuration: configuration)
        let messageStatusToken = Self.buildMessageStatusToken(configuration: configuration)
        let unreadIndicatorLabelConfig = Self.buildUnreadIndicatorLabelConfig(configuration: configuration)

        return CLVCellConfigs(
            thread: configuration.thread.threadRecord,
            lastReloadDate: configuration.lastReloadDate,
            timestamp: configuration.overrideDate ?? configuration.thread.chatListInfo?.lastMessageDate,
            isBlocked: configuration.isBlocked,
            shouldShowVerifiedBadge: configuration.thread.threadRecord.isNoteToSelf,
            shouldShowMuteIndicator: shouldShowMuteIndicator,
            hasOverrideSnippet: configuration.hasOverrideSnippet,
            messageStatusToken: messageStatusToken,
            unreadIndicatorLabelConfig: unreadIndicatorLabelConfig,

            topRowStackConfig: Self.topRowStackConfig,
            bottomRowStackConfig: Self.bottomRowStackConfig,
            vStackConfig: Self.vStackConfig,
            outerHStackConfig: Self.outerHStackConfig,
            avatarStackConfig: Self.avatarStackConfig,
            snippetLabelConfig: Self.snippetLabelConfig(configuration: configuration),
            nameLabelConfig: Self.nameLabelConfig(configuration: configuration),
            dateTimeLabelConfig: Self.dateTimeLabelConfig(configuration: configuration)
        )
    }

    private static func buildMeasurements(configuration: Configuration,
                                          configs: CLVCellConfigs) -> CLVCellMeasurements {
        let shouldShowVerifiedBadge = configs.shouldShowVerifiedBadge
        let shouldShowMuteIndicator = configs.shouldShowMuteIndicator

        let topRowStackConfig = configs.topRowStackConfig
        let bottomRowStackConfig = configs.bottomRowStackConfig
        let vStackConfig = configs.vStackConfig
        let outerHStackConfig = configs.outerHStackConfig
        let avatarStackConfig = configs.avatarStackConfig
        let snippetLabelConfig = configs.snippetLabelConfig
        let nameLabelConfig = configs.nameLabelConfig
        let dateTimeLabelConfig = configs.dateTimeLabelConfig

        var topRowStackSubviewInfos = [ManualStackSubviewInfo]()
        let nameLabelSize = CVText.measureLabel(config: nameLabelConfig,
                                                maxWidth: .greatestFiniteMagnitude)
        topRowStackSubviewInfos.append(nameLabelSize.asManualSubviewInfo(horizontalFlowBehavior: .canCompress,
                                                                         verticalFlowBehavior: .fixed))
        if shouldShowVerifiedBadge {
            topRowStackSubviewInfos.append(CGSize(square: muteIconSize).asManualSubviewInfo(hasFixedSize: true))
        }
        if shouldShowMuteIndicator {
            topRowStackSubviewInfos.append(CGSize(square: muteIconSize).asManualSubviewInfo(hasFixedSize: true))
        }
        let dateLabelSize = CVText.measureLabel(config: dateTimeLabelConfig,
                                                maxWidth: CGFloat.greatestFiniteMagnitude)
        topRowStackSubviewInfos.append(dateLabelSize.asManualSubviewInfo(horizontalFlowBehavior: .canExpand,
                                                                         verticalFlowBehavior: .fixed))

        let avatarSize: CGSize = .square(CGFloat(ChatListCell.avatarSize))
        let avatarStackMeasurement = ManualStackView.measure(config: avatarStackConfig,
                                                             subviewInfos: [ avatarSize.asManualSubviewInfo(hasFixedSize: true) ])
        let avatarStackSize = avatarStackMeasurement.measuredSize

        let topRowStackMeasurement = ManualStackView.measure(config: topRowStackConfig,
                                                             subviewInfos: topRowStackSubviewInfos)
        let topRowStackSize = topRowStackMeasurement.measuredSize

        // Reserve space for two lines of snippet text, taking into account
        // the worst-case snippet content.
        let snippetLineHeight = CGFloat(ceil(snippetLabelConfig.font.semibold().lineHeight * 1.2))

        // Use a fixed size for the snippet label and its wrapper.
        let bottomRowWrapperSize = CGSize(width: 0, height: snippetLineHeight * 2)
        var bottomRowStackSubviewInfos: [ManualStackSubviewInfo] = [
            bottomRowWrapperSize.asManualSubviewInfo()
        ]

        if let messageStatusToken = configs.messageStatusToken {
            let statusIndicatorSize = messageStatusToken.image.size
            // The status indicator should vertically align with the
            // first line of the snippet.
            let locationOffset = CGPoint(x: 0, y: snippetLineHeight * -0.5)
            bottomRowStackSubviewInfos.append(statusIndicatorSize.asManualSubviewInfo(hasFixedSize: true,
                                                                                      locationOffset: locationOffset))
        }

        var unreadBadgeMeasurements: CLVUnreadBadgeMeasurements?
        if let unreadMeasurements = measureUnreadBadge(unreadIndicatorLabelConfig: configs.unreadIndicatorLabelConfig) {
            unreadBadgeMeasurements = unreadMeasurements
            let unreadBadgeSize = unreadMeasurements.badgeSize
            // The unread indicator should vertically align with the
            // first line of the snippet.
            let locationOffset = CGPoint(x: 0, y: snippetLineHeight * -0.5)
            bottomRowStackSubviewInfos.append(unreadBadgeSize.asManualSubviewInfo(hasFixedSize: true,
                                                                                  locationOffset: locationOffset))
        }

        let bottomRowStackMeasurement = ManualStackView.measure(config: bottomRowStackConfig,
                                                                subviewInfos: bottomRowStackSubviewInfos)
        let bottomRowStackSize = bottomRowStackMeasurement.measuredSize

        let vStackMeasurement = ManualStackView.measure(config: vStackConfig,
                                                        subviewInfos: [
                                                            topRowStackSize.asManualSubviewInfo,
                                                            bottomRowStackSize.asManualSubviewInfo
                                                        ])
        let vStackSize = vStackMeasurement.measuredSize

        let outerHStackMeasurement = ManualStackView.measure(config: outerHStackConfig,
                                                             subviewInfos: [
                                                                avatarStackSize.asManualSubviewInfo(hasFixedWidth: true),
                                                                vStackSize.asManualSubviewInfo
                                                             ])

        return CLVCellMeasurements(avatarStackMeasurement: avatarStackMeasurement,
                                  topRowStackMeasurement: topRowStackMeasurement,
                                  bottomRowStackMeasurement: bottomRowStackMeasurement,
                                  vStackMeasurement: vStackMeasurement,
                                  outerHStackMeasurement: outerHStackMeasurement,
                                  snippetLineHeight: snippetLineHeight,
                                  unreadBadgeMeasurements: unreadBadgeMeasurements)
    }

    func configure(
        cellContentToken: CLVCellContentToken,
        spoilerAnimationManager: SpoilerAnimationManager,
        asyncAvatarLoadingAllowed: Bool = true
    ) {
        AssertIsOnMainThread()

        OWSTableItem.configureCell(self)
        self.preservesSuperviewLayoutMargins = false
        self.contentView.preservesSuperviewLayoutMargins = false

        self.cellContentToken = cellContentToken

        let shouldShowMuteIndicator = cellContentToken.shouldShowMuteIndicator

        let configs = cellContentToken.configs
        let topRowStackConfig = configs.topRowStackConfig
        let bottomRowStackConfig = configs.bottomRowStackConfig
        let vStackConfig = configs.vStackConfig
        let outerHStackConfig = configs.outerHStackConfig
        let avatarStackConfig = configs.avatarStackConfig
        let snippetLabelConfig = configs.snippetLabelConfig
        let nameLabelConfig = configs.nameLabelConfig
        let dateTimeLabelConfig = configs.dateTimeLabelConfig

        let shouldShowVerifiedBadge = configs.thread.isNoteToSelf

        let measurements = cellContentToken.measurements
        let avatarStackMeasurement = measurements.avatarStackMeasurement
        let topRowStackMeasurement = measurements.topRowStackMeasurement
        let bottomRowStackMeasurement = measurements.bottomRowStackMeasurement
        let vStackMeasurement = measurements.vStackMeasurement
        let outerHStackMeasurement = measurements.outerHStackMeasurement
        let snippetLineHeight = measurements.snippetLineHeight

        snippetLabelConfig.applyForRendering(label: snippetLabel)
        spoilerConfigBuilder.text = snippetLabelConfig.text
        spoilerConfigBuilder.displayConfig = snippetLabelConfig.displayConfig
        spoilerConfigBuilder.animationManager = spoilerAnimationManager

        owsAssertDebug(avatarView == nil, "ChatListCell.configure without prior reset called")
        avatarView = ConversationAvatarView(sizeClass: .fiftySix, localUserDisplayMode: .noteToSelf, useAutolayout: true)
        avatarView?.updateWithSneakyTransactionIfNecessary({ config in
            config.dataSource = .thread(cellContentToken.thread)
            if asyncAvatarLoadingAllowed && cellContentToken.shouldLoadAvatarAsync {
                config.usePlaceholderImages()
            } else {
                config.applyConfigurationSynchronously()
            }
        })

        typingIndicatorView.configureForChatList()

        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(typingIndicatorStateDidChange),
                                               name: TypingIndicatorsImpl.typingIndicatorStateDidChange,
                                               object: nil)

        // The top row contains:
        //
        // * Name label
        // * Mute icon (optional)
        // * (spacing)
        // * Date/Time label (fixed width)
        //
        // If there's "overflow" (not enough space to render the entire name)
        // The name label should compress.
        //
        // If there's "underflow" (extra space in the layout) it should appear
        // before the date/time label.
        //
        // The catch is that mute icon should "hug" the name label, so the
        // name label can't expand to occupt any underflow in the layout.
        var topRowStackSubviews = [UIView]()

        nameLabelConfig.applyForRendering(label: nameLabel)
        topRowStackSubviews.append(nameLabel)

        if shouldShowVerifiedBadge {
            badgeView.image = Theme.iconImage(.official)
            badgeView.tintColor = .ows_signalBlue
            topRowStackSubviews.append(badgeView)
        }

        if shouldShowMuteIndicator {
            muteIconView.image = UIImage(imageLiteralResourceName: "bell-slash")
            muteIconView.tintColor = Self.snippetColor.color(isDarkThemeEnabled: Theme.isDarkThemeEnabled)
            topRowStackSubviews.append(muteIconView)
        }

        dateTimeLabelConfig.applyForRendering(label: dateTimeLabel)
        self.nextUpdateTimestamp = nil
        if let date = configs.timestamp, !DateUtil.dateIsOlderThanToday(date) {
            self.dateTimeLabel.text = DateUtil.formatDateShort(date)
            let calendar = Calendar.current
            let minutesDiff = calendar.dateComponents([.minute], from: date, to: Date()).minute ?? 0
            if minutesDiff <= 60 {
                let secondsDiff = (calendar.dateComponents([.second], from: date, to: Date()).second ?? 0) % 60
                self.nextUpdateTimestamp = Date().addingTimeInterval(Double(60 - secondsDiff))
            }
        }

        topRowStackSubviews.append(dateTimeLabel)

        // The bottom row layout is also complicated because we want to be able to
        // show/hide the typing indicator without reloading the cell. And we need
        // to switch between them without any "jitter" in the layout.
        //
        // The "Wrapper" shows either "snippet label" or "typing indicator".
        bottomRowWrapper.addSubview(snippetLabel) { [weak self] view in
            guard let self = self else { return }
            // Top-align the snippet text.
            let snippetSize = self.snippetLabel.sizeThatFits(view.bounds.size)
            if DebugFlags.internalLogging,
               snippetSize.height > snippetLineHeight * 2 {
                owsFailDebug("view: \(view.bounds.size), snippetSize: \(snippetSize), snippetLineHeight: \(snippetLineHeight), snippetLabelConfig: \(snippetLabelConfig)")
            }
            let snippetFrame = CGRect(x: 0,
                                      y: 0,
                                      width: view.width,
                                      height: min(view.bounds.height, ceil(snippetSize.height)))
            self.snippetLabel.frame = snippetFrame
        }
        let typingIndicatorSize = TypingIndicatorView.measurement().measuredSize
        bottomRowWrapper.addSubview(typingIndicatorView) { [weak self] _ in
            guard let self = self else { return }
            // Vertically align the typing indicator with the first line of the snippet label.
            self.typingIndicatorView.frame = CGRect(x: 0,
                                                    y: (snippetLineHeight - typingIndicatorSize.height) * 0.5,
                                                    width: typingIndicatorSize.width,
                                                    height: typingIndicatorSize.height)
        }
        updateTypingIndicatorState()

        var bottomRowStackSubviews: [UIView] = [ bottomRowWrapper ]
        if let messageStatusToken = configs.messageStatusToken {
            let statusIndicator = configureStatusIndicatorView(token: messageStatusToken)
            bottomRowStackSubviews.append(statusIndicator)
        }

        // If there are unread messages, show the "unread badge."
        if let unreadIndicatorLabelConfig = configs.unreadIndicatorLabelConfig,
           let unreadBadgeMeasurements = measurements.unreadBadgeMeasurements {
            let unreadBadge = configureUnreadBadge(unreadIndicatorLabelConfig: unreadIndicatorLabelConfig,
                                                   unreadBadgeMeasurements: unreadBadgeMeasurements)
            bottomRowStackSubviews.append(unreadBadge)
        }

        let avatarStackSubviews = [ avatarView! ]
        let vStackSubviews = [ topRowStack, bottomRowStack ]
        let outerHStackSubviews = [ avatarStack, vStack ]

        // It is only safe to reuse the bottom row wrapper if its subview list
        // hasn't changed.
        let newReuseToken = ReuseToken(
            hasVerifiedBadge: shouldShowVerifiedBadge,
            hasMuteIndicator: shouldShowMuteIndicator,
            hasMessageStatusToken: configs.messageStatusToken != nil,
            hasUnreadBadge: measurements.unreadBadgeMeasurements != nil
        )

        avatarStack.configure(config: avatarStackConfig,
                              measurement: avatarStackMeasurement,
                              subviews: avatarStackSubviews)

        // topRowStack can only be configured for reuse if
        // its subview list hasn't changed.
        if let oldReuseToken = self.reuseToken,
           oldReuseToken.hasMuteIndicator == newReuseToken.hasMuteIndicator,
           oldReuseToken.hasVerifiedBadge == newReuseToken.hasVerifiedBadge {
            topRowStack.configureForReuse(config: topRowStackConfig,
                                          measurement: topRowStackMeasurement)
        } else {
            topRowStack.reset()
            topRowStack.configure(config: topRowStackConfig,
                                  measurement: topRowStackMeasurement,
                                  subviews: topRowStackSubviews)
        }

        // It is only safe to reuse bottomRowStack if the same subset of subviews
        // are in use.
        if let oldReuseToken = self.reuseToken,
           oldReuseToken.hasMessageStatusToken == newReuseToken.hasMessageStatusToken,
           oldReuseToken.hasUnreadBadge == newReuseToken.hasUnreadBadge {
            bottomRowStack.configureForReuse(config: bottomRowStackConfig,
                                             measurement: bottomRowStackMeasurement)
        } else {
            bottomRowStack.reset()
            bottomRowStack.configure(config: bottomRowStackConfig,
                                     measurement: bottomRowStackMeasurement,
                                     subviews: bottomRowStackSubviews)
        }

        // vStack and outerHStack can always be configured for reuse.
        if self.reuseToken != nil {
            vStack.configureForReuse(config: vStackConfig,
                                     measurement: vStackMeasurement)

            outerHStack.configureForReuse(config: outerHStackConfig,
                                          measurement: outerHStackMeasurement)
        } else {
            vStack.configure(config: vStackConfig,
                             measurement: vStackMeasurement,
                             subviews: vStackSubviews)

            outerHStack.configure(config: outerHStackConfig,
                                  measurement: outerHStackMeasurement,
                                  subviews: outerHStackSubviews)
        }

        self.reuseToken = newReuseToken
    }

    // MARK: - Stack Configs

    private static var topRowStackConfig: ManualStackView.Config {
        ManualStackView.Config(axis: .horizontal,
                               alignment: .center,
                               spacing: 6,
                               layoutMargins: .zero)
    }

    private static var bottomRowStackConfig: ManualStackView.Config {
        ManualStackView.Config(axis: .horizontal,
                               alignment: .center,
                               spacing: 6,
                               layoutMargins: .zero)
    }

    private static var vStackConfig: ManualStackView.Config {
        ManualStackView.Config(axis: .vertical,
                               alignment: .fill,
                               spacing: 1,
                               layoutMargins: UIEdgeInsets(top: 7,
                                                           leading: 0,
                                                           bottom: 9,
                                                           trailing: 0))
    }

    private static var outerHStackConfig: ManualStackView.Config {
        ManualStackView.Config(axis: .horizontal,
                               alignment: .center,
                               spacing: 12,
                               layoutMargins: UIEdgeInsets(hMargin: 16, vMargin: 0))
    }

    private static var avatarStackConfig: ManualStackView.Config {
        ManualStackView.Config(axis: .horizontal,
                               alignment: .center,
                               spacing: 0,
                               layoutMargins: UIEdgeInsets(hMargin: 0, vMargin: 12))
    }

    // MARK: - Message Status Indicator

    private static func buildMessageStatusToken(configuration: Configuration) -> CLVMessageStatusToken? {

        // If we're using the conversation list cell to render search results,
        // don't show "unread badge" or "message status" indicator.
        let shouldHideStatusIndicator = configuration.hasOverrideSnippet
        let thread = configuration.thread
        guard !shouldHideStatusIndicator,
            let outgoingMessage = thread.lastMessageForInbox as? TSOutgoingMessage,
            let messageStatus = configuration.thread.chatListInfo?.lastMessageOutgoingStatus
        else {
            return nil
        }

        var statusIndicatorImage: UIImage?
        var messageStatusViewTintColor = snippetColor.color(isDarkThemeEnabled: Theme.isDarkThemeEnabled)
        var shouldAnimateStatusIcon = false

        switch messageStatus {
        case .uploading, .sending:
            statusIndicatorImage = UIImage(named: "message_status_sending")
            shouldAnimateStatusIcon = true
        case .sent, .skipped:
            if outgoingMessage.wasRemotelyDeleted {
                return nil
            }
            statusIndicatorImage = UIImage(named: "message_status_sent")
        case .delivered:
            if outgoingMessage.wasRemotelyDeleted {
                return nil
            }
            statusIndicatorImage = UIImage(named: "message_status_delivered")
        case .read, .viewed:
            if outgoingMessage.wasRemotelyDeleted {
                return nil
            }
            statusIndicatorImage = UIImage(named: "message_status_read")
        case .failed:
            statusIndicatorImage = UIImage(named: "error-circle-extra-small")
            messageStatusViewTintColor = .ows_accentRed
        case .pending:
            statusIndicatorImage = UIImage(named: "error-circle-extra-small")
            messageStatusViewTintColor = .ows_gray60
        }
        if statusIndicatorImage == nil {
            return nil
        }

        guard let image = statusIndicatorImage else {
            return nil
        }
        return CLVMessageStatusToken(image: image.withRenderingMode(.alwaysTemplate),
                                    tintColor: messageStatusViewTintColor,
                                    shouldAnimateStatusIcon: shouldAnimateStatusIcon)
    }

    private func configureStatusIndicatorView(token: CLVMessageStatusToken) -> UIView {
        messageStatusIconView.image = token.image.withRenderingMode(.alwaysTemplate)
        messageStatusIconView.tintColor = token.tintColor

        if token.shouldAnimateStatusIcon {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.toValue = NSNumber(value: Double.pi * 2)
            animation.duration = kSecondInterval * 1
            animation.isCumulative = true
            animation.repeatCount = .greatestFiniteMagnitude
            messageStatusIconView.layer.add(animation, forKey: "animation")
        } else {
            messageStatusIconView.layer.removeAllAnimations()
        }

        return messageStatusIconView
    }

    // MARK: - Unread Indicator

    private static func buildUnreadIndicatorLabelConfig(configuration: Configuration) -> CVLabelConfig? {
        let text: String
        switch configuration.unreadMode {
        case .none:
            // If we're using the conversation list cell to render search results,
            // don't show "unread badge" or "message status" indicator.
            //
            // Or there might simply be no unread messages / the thread is not
            // marked as unread.
            return nil
        case .unreadWithoutCount:
            text = ""
        case .unreadWithCount(let unreadCount):
            text = unreadCount > 0 ? OWSFormat.formatUInt(unreadCount) : ""
        }
        return CVLabelConfig.unstyledText(
            text,
            font: unreadFont,
            textColor: .ows_white,
            numberOfLines: 1,
            lineBreakMode: .byTruncatingTail,
            textAlignment: .center
        )
    }

    private static func measureUnreadBadge(unreadIndicatorLabelConfig: CVLabelConfig?) -> CLVUnreadBadgeMeasurements? {

        guard let unreadIndicatorLabelConfig = unreadIndicatorLabelConfig else {
            return nil
        }

        let unreadLabelSize = CVText.measureLabel(config: unreadIndicatorLabelConfig,
                                                  maxWidth: .greatestFiniteMagnitude)

        // This is a bit arbitrary, but it should scale with the size of dynamic text.
        let unreadBadgeHeight = ceil(unreadIndicatorLabelConfig.font.lineHeight * 1.25)
        // The "end caps" of the pill shape should be a half-circle.
        let minMargin = CeilEven(unreadBadgeHeight * 0.5)
        // Pill should be at least circular; can be wider.
        let badgeSize = CGSize(width: max(unreadBadgeHeight,
                                          unreadLabelSize.width + minMargin),
                               height: unreadBadgeHeight)

        return CLVUnreadBadgeMeasurements(badgeSize: badgeSize,
                                         unreadLabelSize: unreadLabelSize)
    }

    private func configureUnreadBadge(unreadIndicatorLabelConfig: CVLabelConfig,
                                      unreadBadgeMeasurements measurements: CLVUnreadBadgeMeasurements) -> UIView {

        let unreadLabel = self.unreadLabel
        unreadIndicatorLabelConfig.applyForRendering(label: unreadLabel)
        unreadLabel.removeFromSuperview()
        let unreadLabelSize = measurements.unreadLabelSize

        let unreadBadge = self.unreadBadge
        unreadBadge.backgroundColor = .ows_accentBlue
        unreadBadge.addSubview(unreadLabel) { view in
            // Center within badge.
            unreadLabel.frame = CGRect(origin: (view.frame.size - unreadLabelSize).asPoint * 0.5,
                                       size: unreadLabelSize)
        }

        let unreadBadgeHeight = measurements.badgeSize.height
        unreadBadge.layer.cornerRadius = unreadBadgeHeight / 2
        return unreadBadge
    }

    // MARK: - Label Configs

    private static func cvTextSnippet(configuration: Configuration) -> CVTextValue {
        owsAssertDebug(configuration.thread.chatListInfo != nil)
        let snippet: CLVSnippet = configuration.thread.chatListInfo?.snippet ?? .none

        switch snippet {
        case .blocked:
            return .attributedText(
                NSAttributedString(
                    string: OWSLocalizedString(
                        "HOME_VIEW_BLOCKED_CONVERSATION",
                        comment: "Table cell subtitle label for a conversation the user has blocked."
                    ),
                    attributes: [
                        .font: snippetFont,
                        .foregroundColor: snippetColor.color(isDarkThemeEnabled: Theme.isDarkThemeEnabled)
                    ]
                )
            )
        case .pendingMessageRequest(let addedToGroupByName):
            // If you haven't accepted the message request for this thread, don't show the latest message

            // For group threads, show who we think added you (if we know)
            if let addedToGroupByName = addedToGroupByName {
                let addedToGroupFormat = OWSLocalizedString(
                    "HOME_VIEW_MESSAGE_REQUEST_ADDED_TO_GROUP_FORMAT",
                    comment: "Table cell subtitle label for a group the user has been added to. {Embeds inviter name}"
                )
                return .attributedText(
                    NSAttributedString(
                        string: String(format: addedToGroupFormat, addedToGroupByName),
                        attributes: [
                            .font: snippetFont,
                            .foregroundColor: snippetColor.color(isDarkThemeEnabled: Theme.isDarkThemeEnabled)
                        ]
                    )
                )
            } else {
                // Otherwise just show a generic "message request" message
                let text = OWSLocalizedString(
                    "HOME_VIEW_MESSAGE_REQUEST_CONVERSATION",
                    comment: "Table cell subtitle label for a conversation the user has not accepted."
                )
                return .attributedText(
                    NSAttributedString(
                        string: text,
                        attributes: [
                            .font: snippetFont,
                            .foregroundColor: snippetColor.color(isDarkThemeEnabled: Theme.isDarkThemeEnabled)
                        ]
                    )
                )
            }
        case .draft(let draftText):
            let prefixText = OWSLocalizedString(
                "HOME_VIEW_DRAFT_PREFIX",
                comment: "A prefix indicating that a message preview is a draft"
            )
            let prefix = StyleOnlyMessageBody(
                text: prefixText,
                style: .italic
            )
            return .messageBody(draftText.addingStyledPrefix(prefix))
        case .voiceMemoDraft:
            let snippetText = NSMutableAttributedString()
            snippetText.append(
                OWSLocalizedString(
                    "HOME_VIEW_DRAFT_PREFIX",
                    comment: "A prefix indicating that a message preview is a draft"
                ),
                attributes: [
                    .font: snippetFont.italic(),
                    .foregroundColor: snippetColor.color(isDarkThemeEnabled: Theme.isDarkThemeEnabled)
                ]
            )
            snippetText.append(
                "🎤",
                attributes: [
                    .font: snippetFont,
                    .foregroundColor: snippetColor.color(isDarkThemeEnabled: Theme.isDarkThemeEnabled)
                ]
            )
            snippetText.append(
                " ",
                attributes: [
                    .font: snippetFont,
                    .foregroundColor: snippetColor.color(isDarkThemeEnabled: Theme.isDarkThemeEnabled)
                ]
            )
            snippetText.append(
                OWSLocalizedString(
                    "ATTACHMENT_TYPE_VOICE_MESSAGE",
                    comment: "Short text label for a voice message attachment, used for thread preview and on the lock screen"
                ),
                attributes: [
                    .font: snippetFont,
                    .foregroundColor: snippetColor.color(isDarkThemeEnabled: Theme.isDarkThemeEnabled)
                ]
            )
            return .attributedText(snippetText)
        case .contactSnippet(let lastMessageText):
            return .messageBody(lastMessageText)
        case .groupSnippet(let lastMessageText, let senderName):
            let prefix = StyleOnlyMessageBody(
                text: "\(senderName): ",
                style: .bold
            )
            return .messageBody(lastMessageText.addingStyledPrefix(prefix))
        case .none:
            return .text("")
        }
    }

    private static func shouldShowMuteIndicator(configuration: Configuration) -> Bool {
        !configuration.hasOverrideSnippet && !configuration.isBlocked && !configuration.thread.hasPendingMessageRequest && configuration.thread.isMuted
    }

    private static func dateTimeLabelConfig(configuration: Configuration) -> CVLabelConfig {
        let thread = configuration.thread
        var text: String = ""
        if let labelDate = configuration.overrideDate ?? thread.chatListInfo?.lastMessageDate {
            text = DateUtil.formatDateShort(labelDate)
        }
        return CVLabelConfig.unstyledText(
            text,
            font: dateTimeFont,
            textColor: snippetColor.color(isDarkThemeEnabled: Theme.isDarkThemeEnabled),
            textAlignment: .trailing
        )
    }

    private static func nameLabelConfig(configuration: Configuration) -> CVLabelConfig {
        let thread = configuration.thread
        let text: String = {
            if thread.threadRecord is TSContactThread {
                if thread.threadRecord.isNoteToSelf {
                    return MessageStrings.noteToSelf
                } else {
                    return thread.name
                }
            } else {
                if let name: String = thread.name.nilIfEmpty {
                    return name
                } else {
                    return MessageStrings.newGroupDefaultTitle
                }
            }
        }()
        return CVLabelConfig.unstyledText(
            text,
            font: nameFont,
            textColor: Theme.primaryTextColor,
            lineBreakMode: .byTruncatingTail
        )
    }

    private static func snippetLabelConfig(configuration: Configuration) -> CVLabelConfig {
        let textColor = snippetColor.color(isDarkThemeEnabled: Theme.isDarkThemeEnabled)
        let text: CVTextValue
        let displayConfig: HydratedMessageBody.DisplayConfiguration
        if let overrideSnippet = configuration.overrideSnippet {
            text = overrideSnippet.text
            displayConfig = overrideSnippet.config
        } else {
            text = self.cvTextSnippet(configuration: configuration)
            displayConfig = .conversationListSnippet(font: snippetFont, textColor: snippetColor)
        }
        return CVLabelConfig(
            text: text,
            displayConfig: displayConfig,
            font: snippetFont,
            textColor: textColor,
            numberOfLines: 2,
            lineBreakMode: .byTruncatingTail
        )
    }

    // MARK: - Reuse

    public override func prepareForReuse() {
        super.prepareForReuse()

        reset()
    }

    func reset() {
        nextUpdateTimestamp = nil
        isCellVisible = false

        for cvview in cvviews {
            cvview.reset()
        }
        avatarView = nil

        // Some ManualStackViews are _NOT_ reset to facilitate reuse.

        cellContentToken = nil
        typingIndicatorView.resetForReuse()
        spoilerConfigBuilder.text = nil

        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Spoiler animation

    private lazy var spoilerConfigBuilder = SpoilerableTextConfig.Builder(isViewVisible: isCellVisible) {
        didSet {
            snippetLabelSpoilerAnimator.updateAnimationState(spoilerConfigBuilder)
        }
    }

    private lazy var snippetLabelSpoilerAnimator: SpoilerableLabelAnimator = {
        let animator = SpoilerableLabelAnimator(label: snippetLabel)
        animator.updateAnimationState(spoilerConfigBuilder)
        return animator
    }()

    // MARK: - Name

    @objc
    private func typingIndicatorStateDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let thread = self.thread,
              let notificationThreadId = notification.object as? String,
              thread.uniqueId == notificationThreadId else {
            return
        }

        updateTypingIndicatorState()
    }

    // MARK: - Typing Indicators

    private var shouldShowTypingIndicators: Bool {
        guard let cellContentToken = self.cellContentToken else {
            return false
        }
        let thread = cellContentToken.thread
        if !cellContentToken.hasOverrideSnippet,
           nil != typingIndicatorsImpl.typingAddress(forThread: thread) {
            return true
        }
        return false
    }

    private func updateTypingIndicatorState() {
        AssertIsOnMainThread()

        let shouldShowTypingIndicators = self.shouldShowTypingIndicators && self.isCellVisible

        // We use "override snippets" to show "message" search results.
        // We don't want to show typing indicators in that case.
        if shouldShowTypingIndicators {
            snippetLabel.isHidden = true
            typingIndicatorView.isHidden = false
            typingIndicatorView.startAnimation()
        } else {
            snippetLabel.isHidden = false
            typingIndicatorView.isHidden = true
            typingIndicatorView.stopAnimation()
        }
    }

    public func ensureCellAnimations() {
        AssertIsOnMainThread()

        updateTypingIndicatorState()
    }
}

// MARK: -

private struct CLVMessageStatusToken {
    let image: UIImage
    let tintColor: UIColor
    let shouldAnimateStatusIcon: Bool
}

// MARK: -

private struct CLVCellConfigs {
    // State
    let thread: TSThread
    let lastReloadDate: Date?
    let timestamp: Date?
    let isBlocked: Bool
    let shouldShowVerifiedBadge: Bool
    let shouldShowMuteIndicator: Bool
    let hasOverrideSnippet: Bool
    let messageStatusToken: CLVMessageStatusToken?
    let unreadIndicatorLabelConfig: CVLabelConfig?

    // Configs
    let topRowStackConfig: ManualStackView.Config
    let bottomRowStackConfig: ManualStackView.Config
    let vStackConfig: ManualStackView.Config
    let outerHStackConfig: ManualStackView.Config
    let avatarStackConfig: ManualStackView.Config
    let snippetLabelConfig: CVLabelConfig
    let nameLabelConfig: CVLabelConfig
    let dateTimeLabelConfig: CVLabelConfig
}

// MARK: -

private struct CLVUnreadBadgeMeasurements {
    let badgeSize: CGSize
    let unreadLabelSize: CGSize
}

// MARK: -

private struct CLVCellMeasurements {
    let avatarStackMeasurement: ManualStackView.Measurement
    let topRowStackMeasurement: ManualStackView.Measurement
    let bottomRowStackMeasurement: ManualStackView.Measurement
    let vStackMeasurement: ManualStackView.Measurement
    let outerHStackMeasurement: ManualStackView.Measurement
    let snippetLineHeight: CGFloat
    let unreadBadgeMeasurements: CLVUnreadBadgeMeasurements?
}

// MARK: -

// Perf matters in chat list.  Configuring chat list cells is
// probably the biggest perf bottleneck.  In conversation view,
// we address this by doing cell measurement/arrangement off
// the main thread.  That's viable in conversation view because
// there's a "load window" so there's an upper bound on how
// many cells need to be prepared.
//
// Chat list has no load window.  Therefore, chat list defers
// the expensive work of a) building ThreadViewModel
// b) measurement/arrangement of cells.  threadViewModelCache
// caches a).  cellContentCache caches b).
//
// When configuring a chat list cell, we reuse any existing
// cell measurement in cellContentCache.  If none exists,
// we build one and store it in cellContentCache for next
// time.
//
// These content tokens can be preloaded async.
//
// Compare with Configuration:
//
// * Configuration captures _how_ the view wants to render the cell.
//   ChatListCell is used by chat list and Home Search view and they
//   render cells differently. Configuration reflects that.
//   Configuration is cheap to build.
// * CLVCellContentToken captures (only) the exact content that will
//   be rendered in the cell, its measurement/layout, etc.
//   CLVCellContentToken is expensive to build.
class CLVCellContentToken {
    fileprivate let configs: CLVCellConfigs
    fileprivate let measurements: CLVCellMeasurements

    fileprivate var thread: TSThread { configs.thread }
    fileprivate var isBlocked: Bool { configs.isBlocked }
    fileprivate var shouldShowMuteIndicator: Bool { configs.shouldShowMuteIndicator }
    fileprivate var hasOverrideSnippet: Bool { configs.hasOverrideSnippet }

    fileprivate var shouldLoadAvatarAsync: Bool {
        // We want reloads to load avatars sync, but subsequent avatar loads
        // (e.g. from scrolling) and the initial load should be async.
        guard let lastReloadDate = configs.lastReloadDate else {
            return true
        }
        let avatarAsyncLoadInterval = kSecondInterval * 1
        return abs(lastReloadDate.timeIntervalSinceNow) > avatarAsyncLoadInterval
    }

    fileprivate init(configs: CLVCellConfigs,
                     measurements: CLVCellMeasurements) {
        self.configs = configs
        self.measurements = measurements
    }
}

// MARK: -

class NeverClearView: ManualLayoutViewWithLayer {
    override var backgroundColor: UIColor? {
        didSet {
            if backgroundColor?.cgColor.alpha == 0 {
                backgroundColor = oldValue
            }
        }
    }
}
