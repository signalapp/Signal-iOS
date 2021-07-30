//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class HomeViewCell: UITableViewCell {

    @objc
    public static let reuseIdentifier = "HomeViewCell"

    private let avatarView = ConversationAvatarView(diameterPoints: HomeViewCell.avatarSize,
                                                    localUserDisplayMode: .noteToSelf,
                                                    shouldLoadAsync: false)

    private let nameLabel = CVLabel()
    private let snippetLabel = CVLabel()
    private let dateTimeLabel = CVLabel()
    private let messageStatusIconView = CVImageView()
    private let typingIndicatorView = TypingIndicatorView()
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
        }
    }

    private var cvviews: [CVView] {
        [
            avatarView,
            nameLabel,
            snippetLabel,
            dateTimeLabel,
            messageStatusIconView,
            muteIconView,
            unreadLabel,

            outerHStack,
            avatarStack,
            vStack,
            topRowStack,
            bottomRowStack,
            bottomRowWrapper
        ]
    }

    // MARK: - Configuration

    struct Configuration {
        let thread: ThreadViewModel
        let lastReloadDate: Date?
        let isBlocked: Bool
        let overrideSnippet: NSAttributedString?
        let overrideDate: Date?
        let cellContentCache: LRUCache<String, HVCellContentToken>

        fileprivate var hasOverrideSnippet: Bool {
            overrideSnippet != nil
        }
        fileprivate var hasUnreadStyle: Bool {
            thread.hasUnreadMessages && overrideSnippet == nil
        }

        init(thread: ThreadViewModel,
             lastReloadDate: Date?,
             isBlocked: Bool,
             overrideSnippet: NSAttributedString? = nil,
             overrideDate: Date? = nil,
             cellContentCache: LRUCache<String, HVCellContentToken>) {
            self.thread = thread
            self.lastReloadDate = lastReloadDate
            self.isBlocked = isBlocked
            self.overrideSnippet = overrideSnippet
            self.overrideDate = overrideDate
            self.cellContentCache = cellContentCache
        }
    }
    private var cellContentToken: HVCellContentToken?
    private var thread: TSThread? {
        cellContentToken?.thread
    }

    // MARK: - View Constants

    private static var unreadFont: UIFont {
        UIFont.ows_dynamicTypeCaption1Clamped.ows_semibold
    }

    private static var dateTimeFont: UIFont {
        .ows_dynamicTypeCaption1Clamped
    }

    private static var snippetFont: UIFont {
        .ows_dynamicTypeSubheadlineClamped
    }

    private static var nameFont: UIFont {
        UIFont.ows_dynamicTypeBodyClamped.ows_semibold
    }

    // Used for profile names.
    private static var nameSecondaryFont: UIFont {
        UIFont.ows_dynamicTypeBodyClamped.ows_italic
    }

    private static var snippetColor: UIColor {
        Theme.isDarkThemeEnabled ? .ows_gray25 : .ows_gray45
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
        self.backgroundColor = Theme.backgroundColor

        contentView.addSubview(outerHStack)
        outerHStack.shouldDeactivateConstraints = false
        outerHStack.autoPinEdge(toSuperviewEdge: .leading)
        outerHStack.autoPinTrailingToSuperviewMargin()
        outerHStack.autoPinHeightToSuperview()

        self.selectionStyle = .default
    }

    static func measureCellHeight(configuration: Configuration) -> CGFloat {
        AssertIsOnMainThread()

        let cellContentToken = Self.cellContentToken(forConfiguration: configuration)
        return cellContentToken.measurements.outerHStackMeasurement.measuredSize.height
    }

    func configure(configuration: Configuration) {
        AssertIsOnMainThread()

        let cellContentToken = Self.cellContentToken(forConfiguration: configuration)
        configure(cellContentToken: cellContentToken)
    }

    // Perf matters in home view.  Configuring home view cells is
    // probably the biggest perf bottleneck.  In conversation view,
    // we address this by doing cell measurement/arrangement off
    // the main thread.  That's viable in conversation view because
    // there's a "load window" so there's an upper bound on how
    // many cells need to be prepared.
    //
    // Home view has no load window.  Therefore, home view defers
    // the expensive work of a) building ThreadViewModel
    // b) measurement/arrangement of cells.  threadViewModelCache
    // caches a).  cellContentCache caches b).
    //
    // When configuring a hohome view cell, we reuse any existing
    // cell measurement in cellContentCache.  If none exists,
    // we build one and store it in cellContentCache for next
    // time.
    private static func cellContentToken(forConfiguration configuration: Configuration) -> HVCellContentToken {
        let cellContentCache = configuration.cellContentCache

        // If we have an existing HVCellContentToken, use it.
        // Cell measurement/arrangement is expensive.
        let cacheKey = configuration.thread.threadRecord.uniqueId
        if let cellContentToken = cellContentCache.get(key: cacheKey) {
            return cellContentToken
        }

        let configs = buildCellConfigs(configuration: configuration)
        let measurements = buildMeasurements(configuration: configuration,
                                             configs: configs)
        let cellContentToken = HVCellContentToken(configs: configs,
                                                  measurements: measurements)
        cellContentCache.set(key: cacheKey, value: cellContentToken)
        return cellContentToken
    }

    private static func buildCellConfigs(configuration: Configuration) -> HVCellConfigs {
        let shouldShowMuteIndicator = Self.shouldShowMuteIndicator(configuration: configuration)
        let messageStatusToken = Self.buildMessageStatusToken(configuration: configuration)
        let unreadIndicatorLabelConfig = Self.buildUnreadIndicatorLabelConfig(configuration: configuration)

        return HVCellConfigs(
            thread: configuration.thread.threadRecord,
            lastReloadDate: configuration.lastReloadDate,
            isBlocked: configuration.isBlocked,
            shouldShowMuteIndicator: shouldShowMuteIndicator,
            hasUnreadStyle: configuration.hasUnreadStyle,
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
                                          configs: HVCellConfigs) -> HVCellMeasurements {
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
        if shouldShowMuteIndicator {
            topRowStackSubviewInfos.append(CGSize(square: muteIconSize).asManualSubviewInfo(hasFixedSize: true))
        }
        let dateLabelSize = CVText.measureLabel(config: dateTimeLabelConfig,
                                                maxWidth: CGFloat.greatestFiniteMagnitude)
        topRowStackSubviewInfos.append(dateLabelSize.asManualSubviewInfo(horizontalFlowBehavior: .canExpand,
                                                                         verticalFlowBehavior: .fixed))

        let avatarSize: CGSize = .square(CGFloat(HomeViewCell.avatarSize))
        let avatarStackMeasurement = ManualStackView.measure(config: avatarStackConfig,
                                                             subviewInfos: [ avatarSize.asManualSubviewInfo(hasFixedSize: true) ])
        let avatarStackSize = avatarStackMeasurement.measuredSize

        let topRowStackMeasurement = ManualStackView.measure(config: topRowStackConfig,
                                                             subviewInfos: topRowStackSubviewInfos)
        let topRowStackSize = topRowStackMeasurement.measuredSize

        // Reserve space for two lines of snippet text, taking into account
        // the worst-case snippet content.
        let snippetLineHeight = CGFloat(ceil(snippetLabelConfig.font.ows_semibold.lineHeight * 1.2))

        // Use a fixed size for the snippet label and its wrapper.
        let bottomRowWrapperSize = CGSize(width: 0, height: snippetLineHeight * 2)
        var bottomRowStackSubviewInfos: [ManualStackSubviewInfo] = [
            bottomRowWrapperSize.asManualSubviewInfo()
        ]
        if let messageStatusToken = configs.messageStatusToken {
            let statusIndicatorSize = messageStatusToken.image.size
            // The status indicator should vertically align with the
            // first line of the snippet.
            let locationOffset = CGPoint(x: 0,
                                         y: snippetLineHeight * -0.5)
            bottomRowStackSubviewInfos.append(statusIndicatorSize.asManualSubviewInfo(hasFixedSize: true,
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

        return HVCellMeasurements(avatarStackMeasurement: avatarStackMeasurement,
                                  topRowStackMeasurement: topRowStackMeasurement,
                                  bottomRowStackMeasurement: bottomRowStackMeasurement,
                                  vStackMeasurement: vStackMeasurement,
                                  outerHStackMeasurement: outerHStackMeasurement,
                                  snippetLineHeight: snippetLineHeight)
    }

    private func configure(cellContentToken: HVCellContentToken) {
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

        let measurements = cellContentToken.measurements
        let avatarStackMeasurement = measurements.avatarStackMeasurement
        let topRowStackMeasurement = measurements.topRowStackMeasurement
        let bottomRowStackMeasurement = measurements.bottomRowStackMeasurement
        let vStackMeasurement = measurements.vStackMeasurement
        let outerHStackMeasurement = measurements.outerHStackMeasurement
        let snippetLineHeight = measurements.snippetLineHeight

        snippetLabelConfig.applyForRendering(label: snippetLabel)

        avatarView.shouldLoadAsync = cellContentToken.shouldLoadAvatarAsync
        avatarView.configureWithSneakyTransaction(thread: cellContentToken.thread)

        typingIndicatorView.configureForHomeView()

        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(otherUsersProfileDidChange(notification:)),
                                               name: .otherUsersProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(typingIndicatorStateDidChange),
                                               name: TypingIndicatorsImpl.typingIndicatorStateDidChange,
                                               object: nil)

        // Avatar

        let avatarSize: CGSize = .square(CGFloat(HomeViewCell.avatarSize))

        // Unread Indicator

        // If there are unread messages, show the "unread badge."
        if let unreadIndicatorLabelConfig = configs.unreadIndicatorLabelConfig {
            let unreadLabel = self.unreadLabel
            unreadIndicatorLabelConfig.applyForRendering(label: unreadLabel)
            unreadLabel.removeFromSuperview()
            let unreadLabelSize = unreadLabel.sizeThatFits(.square(.greatestFiniteMagnitude))

            let unreadBadge = self.unreadBadge
            unreadBadge.backgroundColor = .ows_accentBlue
            unreadBadge.addSubview(unreadLabel) { view in
                // Center within badge.
                unreadLabel.frame = CGRect(origin: (view.frame.size - unreadLabelSize).asPoint * 0.5,
                                           size: unreadLabelSize)
            }

            let unreadBadgeHeight = ceil(unreadLabel.font.lineHeight * 1.5)
            unreadBadge.layer.cornerRadius = unreadBadgeHeight / 2
            unreadBadge.layer.borderColor = Theme.backgroundColor.cgColor
            unreadBadge.layer.borderWidth = 2
            // This is a bit arbitrary, but it should scale with the size of dynamic text
            let minMargin = CeilEven(unreadBadgeHeight * 0.5)
            // Pill should be at least circular; can be wider.
            let unreadBadgeSize = CGSize(width: max(unreadBadgeHeight,
                                                    unreadLabelSize.width + minMargin),
                                         height: unreadBadgeHeight)
            avatarStack.addSubview(unreadBadge) { view in
                unreadBadge.frame = CGRect(origin: CGPoint(x: view.width - unreadBadgeSize.width + 6,
                                                           y: (view.height - avatarSize.height) * 0.5),
                                           size: unreadBadgeSize)
            }
            // The unread badge should appear on top of the avatar, but it is added
            // to the view hierarchy first (in the "configure" below where we leverage
            // existing measurement/arrangements).  We solve that by nudging the zPosition
            // of the unread badge.
            unreadBadge.layer.zPosition = +1
        }

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

        if shouldShowMuteIndicator {
            muteIconView.setTemplateImageName("bell-disabled-outline-24",
                                              tintColor: Theme.primaryTextColor)
            muteIconView.tintColor = Self.snippetColor
            topRowStackSubviews.append(muteIconView)
        }

        dateTimeLabelConfig.applyForRendering(label: dateTimeLabel)
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
                owsFailDebug("view: \(view.bounds.size), snippetSize: \(snippetSize), snippetLineHeight: \(snippetLineHeight), snippetLabelConfig: \(snippetLabelConfig.stringValue)")
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

        var bottomRowStackSubviews: [UIView] = [ bottomRowWrapper ]
        if let messageStatusToken = cellContentToken.configs.messageStatusToken {
            let statusIndicator = configureStatusIndicatorView(token: messageStatusToken)
            bottomRowStackSubviews.append(statusIndicator)
        }

        updateTypingIndicatorState()

        let avatarStackSubviews = [ avatarView ]
        let vStackSubviews = [ topRowStack, bottomRowStack ]
        let outerHStackSubviews = [ avatarStack, vStack ]

        avatarStack.configure(config: avatarStackConfig,
                              measurement: avatarStackMeasurement,
                              subviews: avatarStackSubviews)

        topRowStack.configure(config: topRowStackConfig,
                              measurement: topRowStackMeasurement,
                              subviews: topRowStackSubviews)

        bottomRowStack.configure(config: bottomRowStackConfig,
                                 measurement: bottomRowStackMeasurement,
                                 subviews: bottomRowStackSubviews)

        vStack.configure(config: vStackConfig,
                         measurement: vStackMeasurement,
                         subviews: vStackSubviews)

        outerHStack.configure(config: outerHStackConfig,
                              measurement: outerHStackMeasurement,
                              subviews: outerHStackSubviews)
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

    private static func buildMessageStatusToken(configuration: Configuration) -> HVMessageStatusToken? {

        // If we're using the conversation list cell to render search results,
        // don't show "unread badge" or "message status" indicator.
        let shouldHideStatusIndicator = configuration.hasOverrideSnippet
        let thread = configuration.thread
        guard !shouldHideStatusIndicator,
              let outgoingMessage = thread.lastMessageForInbox as? TSOutgoingMessage else {
            return nil
        }

        var statusIndicatorImage: UIImage?
        var messageStatusViewTintColor = snippetColor
        var shouldAnimateStatusIcon = false

        let messageStatus =
            MessageRecipientStatusUtils.recipientStatus(outgoingMessage: outgoingMessage)
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
            statusIndicatorImage = UIImage(named: "error-outline-12")
            messageStatusViewTintColor = .ows_accentRed
        case .pending:
            statusIndicatorImage = UIImage(named: "error-outline-12")
            messageStatusViewTintColor = .ows_gray60
        }
        if statusIndicatorImage == nil {
            return nil
        }

        guard let image = statusIndicatorImage else {
            return nil
        }
        return HVMessageStatusToken(image: image.withRenderingMode(.alwaysTemplate),
                                    tintColor: messageStatusViewTintColor,
                                    shouldAnimateStatusIcon: shouldAnimateStatusIcon)
    }

    private func configureStatusIndicatorView(token: HVMessageStatusToken) -> UIView {
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
        guard !configuration.hasOverrideSnippet else {
            // If we're using the conversation list cell to render search results,
            // don't show "unread badge" or "message status" indicator.
            return nil
        }
        guard configuration.hasUnreadStyle else {
            return nil
        }

        let thread = configuration.thread
        let unreadCount = thread.unreadCount
        let text = unreadCount > 0 ? OWSFormat.formatUInt(unreadCount) : ""
        return CVLabelConfig(text: text,
                             font: unreadFont,
                             textColor: .ows_white,
                             numberOfLines: 1,
                             lineBreakMode: .byTruncatingTail,
                             textAlignment: .center)
    }

    // MARK: - Label Configs

    private static func attributedSnippet(configuration: Configuration) -> NSAttributedString {
        let thread = configuration.thread
        let isBlocked = configuration.isBlocked
        let hasUnreadStyle = configuration.hasUnreadStyle

        let snippetText = NSMutableAttributedString()
        if isBlocked {
            // If thread is blocked, don't show a snippet or mute status.
            snippetText.append(NSLocalizedString("HOME_VIEW_BLOCKED_CONVERSATION",
                                                 comment: "Table cell subtitle label for a conversation the user has blocked."),
                               attributes: [
                                .font: snippetFont,
                                .foregroundColor: snippetColor
                               ])
        } else if thread.hasPendingMessageRequest {
            // If you haven't accepted the message request for this thread, don't show the latest message

            // For group threads, show who we think added you (if we know)
            if let addedToGroupByName = thread.homeViewInfo?.addedToGroupByName {
                let addedToGroupFormat = NSLocalizedString("HOME_VIEW_MESSAGE_REQUEST_ADDED_TO_GROUP_FORMAT",
                                                           comment: "Table cell subtitle label for a group the user has been added to. {Embeds inviter name}")
                snippetText.append(String(format: addedToGroupFormat, addedToGroupByName),
                                   attributes: [
                                    .font: snippetFont,
                                    .foregroundColor: snippetColor
                                   ])

                // Otherwise just show a generic "message request" message
            } else {
                snippetText.append(NSLocalizedString("HOME_VIEW_MESSAGE_REQUEST_CONVERSATION",
                                                     comment: "Table cell subtitle label for a conversation the user has not accepted."),
                                   attributes: [
                                    .font: snippetFont,
                                    .foregroundColor: snippetColor
                                   ])
            }
        } else {
            if let draftText = thread.homeViewInfo?.draftText?.nilIfEmpty,
               !hasUnreadStyle {
                snippetText.append(NSLocalizedString("HOME_VIEW_DRAFT_PREFIX",
                                                     comment: "A prefix indicating that a message preview is a draft"),
                                   attributes: [
                                    .font: snippetFont.ows_italic,
                                    .foregroundColor: snippetColor
                                   ])
                snippetText.append(draftText,
                                   attributes: [
                                    .font: snippetFont,
                                    .foregroundColor: snippetColor
                                   ])
            } else if thread.homeViewInfo?.hasVoiceMemoDraft == true,
                      !hasUnreadStyle {
                snippetText.append(NSLocalizedString("HOME_VIEW_DRAFT_PREFIX",
                                                     comment: "A prefix indicating that a message preview is a draft"),
                                   attributes: [
                                    .font: snippetFont.ows_italic,
                                    .foregroundColor: snippetColor
                                   ])
                snippetText.append("🎤",
                                   attributes: [
                                    .font: snippetFont,
                                    .foregroundColor: snippetColor
                                   ])
                snippetText.append(" ",
                                   attributes: [
                                    .font: snippetFont,
                                    .foregroundColor: snippetColor
                                   ])
                snippetText.append(NSLocalizedString("ATTACHMENT_TYPE_VOICE_MESSAGE",
                                                     comment: "Short text label for a voice message attachment, used for thread preview and on the lock screen"),
                                   attributes: [
                                    .font: snippetFont,
                                    .foregroundColor: snippetColor
                                   ])
            } else {
                if let lastMessageText = thread.homeViewInfo?.lastMessageText.filterStringForDisplay().nilIfEmpty {
                    if let senderName = thread.homeViewInfo?.lastMessageSenderName {
                        snippetText.append(senderName,
                                           attributes: [
                                            .font: snippetFont.ows_medium,
                                            .foregroundColor: snippetColor
                                           ])
                        snippetText.append(":",
                                           attributes: [
                                            .font: snippetFont.ows_medium,
                                            .foregroundColor: snippetColor
                                           ])
                        snippetText.append(" ",
                                           attributes: [
                                            .font: snippetFont
                                           ])
                    }

                    snippetText.append(lastMessageText,
                                       attributes: [
                                        .font: snippetFont,
                                        .foregroundColor: snippetColor
                                       ])
                }
            }
        }

        return snippetText
    }

    private static func shouldShowMuteIndicator(configuration: Configuration) -> Bool {
        !configuration.hasOverrideSnippet && !configuration.isBlocked && !configuration.thread.hasPendingMessageRequest && configuration.thread.isMuted
    }

    private static func dateTimeLabelConfig(configuration: Configuration) -> CVLabelConfig {
        let thread = configuration.thread
        var text: String = ""
        if let labelDate = configuration.overrideDate ?? thread.homeViewInfo?.lastMessageDate {
            text = DateUtil.formatDateShort(labelDate)
        }
        if configuration.hasUnreadStyle {
            return CVLabelConfig(text: text,
                                 font: dateTimeFont.ows_semibold,
                                 textColor: Theme.primaryTextColor,
                                 textAlignment: .trailing)
        } else {
            return CVLabelConfig(text: text,
                                 font: dateTimeFont,
                                 textColor: snippetColor,
                                 textAlignment: .trailing)
        }
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
        return CVLabelConfig(text: text,
                             font: nameFont,
                             textColor: Theme.primaryTextColor,
                             lineBreakMode: .byTruncatingTail)
    }

    private static func snippetLabelConfig(configuration: Configuration) -> CVLabelConfig {
        let attributedText: NSAttributedString = {
            if let overrideSnippet = configuration.overrideSnippet {
                return overrideSnippet
            }
            return self.attributedSnippet(configuration: configuration)
        }()
        return CVLabelConfig(attributedText: attributedText,
                             font: snippetFont,
                             textColor: snippetColor,
                             numberOfLines: 2,
                             lineBreakMode: .byTruncatingTail)
    }

    // MARK: - Reuse

    @objc
    public override func prepareForReuse() {
        super.prepareForReuse()

        reset()
    }

    private func reset() {
        isCellVisible = false

        for cvview in cvviews {
            cvview.reset()
        }

        cellContentToken = nil
        avatarView.image = nil
        avatarView.reset()
        typingIndicatorView.resetForReuse()

        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Name

    @objc
    private func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let address = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress,
              address.isValid,
              let contactThread = thread as? TSContactThread,
              contactThread.contactAddress == address else {
            return
        }
        guard let cellContentToken = self.cellContentToken else {
            return
        }
        reset()
        configure(cellContentToken: cellContentToken)
    }

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

private struct HVMessageStatusToken {
    let image: UIImage
    let tintColor: UIColor
    let shouldAnimateStatusIcon: Bool
}

// MARK: -

private struct HVCellConfigs {
    // State
    let thread: TSThread
    let lastReloadDate: Date?
    let isBlocked: Bool
    let shouldShowMuteIndicator: Bool
    let hasUnreadStyle: Bool
    let hasOverrideSnippet: Bool
    let messageStatusToken: HVMessageStatusToken?
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

private struct HVCellMeasurements {
    let avatarStackMeasurement: ManualStackView.Measurement
    let topRowStackMeasurement: ManualStackView.Measurement
    let bottomRowStackMeasurement: ManualStackView.Measurement
    let vStackMeasurement: ManualStackView.Measurement
    let outerHStackMeasurement: ManualStackView.Measurement
    let snippetLineHeight: CGFloat
}

// MARK: -

class HVCellContentToken {
    fileprivate let configs: HVCellConfigs
    fileprivate let measurements: HVCellMeasurements

    fileprivate var thread: TSThread { configs.thread }
    fileprivate var isBlocked: Bool { configs.isBlocked }
    fileprivate var shouldShowMuteIndicator: Bool { configs.shouldShowMuteIndicator }
    fileprivate var hasUnreadStyle: Bool { configs.hasUnreadStyle }
    fileprivate var hasOverrideSnippet: Bool { configs.hasOverrideSnippet }

    fileprivate var shouldLoadAvatarAsync: Bool {
        guard let lastReloadDate = configs.lastReloadDate else {
            return false
        }
        // We want initial loads and reloads to load avatars sync,
        // but subsequent avatar loads (e.g. from scrolling) should
        // be async.
        let avatarAsyncLoadInterval = kSecondInterval * 1
        return abs(lastReloadDate.timeIntervalSinceNow) > avatarAsyncLoadInterval
    }

    fileprivate init(configs: HVCellConfigs,
                     measurements: HVCellMeasurements) {
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
