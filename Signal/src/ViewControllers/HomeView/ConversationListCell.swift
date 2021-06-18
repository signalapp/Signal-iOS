//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class ConversationListCell: UITableViewCell {

    @objc
    public static let reuseIdentifier = "ConversationListCell"

    private let avatarView = ConversationAvatarView(diameterPoints: ConversationListCell.avatarSize,
                                                    localUserDisplayMode: .noteToSelf,
                                                    shouldLoadAsync: false)

    private let nameLabel = UILabel()
    private let snippetLabel = UILabel()
    private let dateTimeLabel = UILabel()
    private let messageStatusIconView = UIImageView()
    private let messageStatusWrapper = UIView.container()
    private let typingIndicatorView = TypingIndicatorView()
    private let typingIndicatorWrapper = UIView.container()
    private let muteIconView = UIImageView()
    private let muteIconWrapper = UIView.container()

    private let unreadBadge = NeverClearView()
    private let unreadLabel = UILabel()

    private var viewConstraints = [NSLayoutConstraint]()

    @objc(ConversationListCellConfiguration)
    public class Configuration: NSObject {
        let thread: ThreadViewModel
        let shouldLoadAvatarAsync: Bool
        let isBlocked: Bool
        let overrideSnippet: NSAttributedString?
        let overrideDate: Date?

        @objc
        public init(thread: ThreadViewModel,
                    shouldLoadAvatarAsync: Bool,
                    isBlocked: Bool,
                    overrideSnippet: NSAttributedString? = nil,
                    overrideDate: Date? = nil) {
            self.thread = thread
            self.shouldLoadAvatarAsync = shouldLoadAvatarAsync
            self.isBlocked = isBlocked
            self.overrideSnippet = overrideSnippet
            self.overrideDate = overrideDate
        }
    }
    private var configuration: Configuration?

    private var thread: ThreadViewModel? {
        configuration?.thread
    }
    private var overrideSnippet: NSAttributedString? {
        configuration?.overrideSnippet
    }
    private var hasOverrideSnippet: Bool {
        overrideSnippet != nil
    }

    // MARK: -

    private var unreadFont: UIFont {
        UIFont.ows_dynamicTypeCaption1Clamped.ows_semibold
    }

    private var dateTimeFont: UIFont {
        UIFont.ows_dynamicTypeCaption1Clamped
    }

    private var snippetFont: UIFont {
        .ows_dynamicTypeSubheadlineClamped
    }

    private var nameFont: UIFont {
        UIFont.ows_dynamicTypeBodyClamped.ows_semibold
    }

    // Used for profile names.
    private var nameSecondaryFont: UIFont {
        UIFont.ows_dynamicTypeBodyClamped.ows_italic
    }

    private var snippetColor: UIColor {
        Theme.isDarkThemeEnabled ? .ows_gray25 : .ows_gray45
    }

    // This value is now larger than AvatarBuilder.standardAvatarSizePoints.
    private static let avatarSize: UInt = 56

    private let avatarHSpacing: UInt = 12

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

        contentView.addSubview(avatarView)
        avatarView.autoPinEdge(toSuperviewEdge: .leading, withInset: 16)
        avatarView.autoVCenterInSuperview()
        // Ensure that the cell's contents never overflow the cell bounds.
        avatarView.autoPinEdge(toSuperviewEdge: .top, withInset: 12, relation: .greaterThanOrEqual)
        avatarView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 12, relation: .greaterThanOrEqual)

        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.font = nameFont
        nameLabel.setContentHuggingHorizontalLow()

        dateTimeLabel.setContentHuggingHorizontalHigh()
        dateTimeLabel.setCompressionResistanceHorizontalHigh()

        typingIndicatorWrapper.setContentHuggingHorizontalHigh()
        typingIndicatorWrapper.setCompressionResistanceHorizontalHigh()

        messageStatusWrapper.setContentHuggingHorizontalHigh()
        messageStatusWrapper.setCompressionResistanceHorizontalHigh()

        muteIconWrapper.setContentHuggingHorizontalHigh()
        muteIconWrapper.setCompressionResistanceHorizontalHigh()

        muteIconView.setTemplateImageName("bell-disabled-outline-24",
                                          tintColor: Theme.primaryTextColor)
        muteIconView.setContentHuggingHorizontalHigh()
        muteIconView.setCompressionResistanceHorizontalHigh()
        muteIconWrapper.addSubview(muteIconView)
        muteIconView.autoPinEdgesToSuperviewEdges(withInsets: UIEdgeInsets(top: 0, leading: 0, bottom: 2, trailing: 0))

        let topRowSpacer = UIView.hStretchingSpacer()

        let topRowView = UIStackView(arrangedSubviews: [
            nameLabel,
            muteIconWrapper,
            topRowSpacer,
            dateTimeLabel
        ])
        topRowView.axis = .horizontal
        topRowView.alignment = .lastBaseline
        topRowView.spacing = 6

        snippetLabel.numberOfLines = 2
        snippetLabel.lineBreakMode = .byWordWrapping
        snippetLabel.setContentHuggingHorizontalLow()
        snippetLabel.setCompressionResistanceHorizontalLow()

        let bottomRowView = UIStackView(arrangedSubviews: [
            typingIndicatorWrapper,
            snippetLabel,
            messageStatusWrapper
        ])
        bottomRowView.axis = .horizontal
        bottomRowView.alignment = .top
        bottomRowView.spacing = 6

        let vStackView = UIStackView(arrangedSubviews: [ topRowView, bottomRowView ])
        vStackView.axis = .vertical
        vStackView.spacing = 1

        contentView.addSubview(vStackView)
        vStackView.autoPinLeading(toTrailingEdgeOf: avatarView, offset: CGFloat(avatarHSpacing))
        vStackView.autoVCenterInSuperview()
        // Ensure that the cell's contents never overflow the cell bounds.
        vStackView.autoPinEdge(toSuperviewEdge: .top, withInset: 7, relation: .greaterThanOrEqual)
        vStackView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 9, relation: .greaterThanOrEqual)
        vStackView.autoPinTrailingToSuperviewMargin()
        vStackView.isUserInteractionEnabled = false

        messageStatusIconView.setContentHuggingHorizontalHigh()
        messageStatusIconView.setCompressionResistanceHorizontalHigh()
        messageStatusWrapper.addSubview(messageStatusIconView)
        messageStatusIconView.autoPinWidthToSuperview()
        messageStatusIconView.autoVCenterInSuperview()

        unreadLabel.textColor = .ows_white
        unreadLabel.lineBreakMode = .byTruncatingTail
        unreadLabel.textAlignment = .center
        unreadLabel.setContentHuggingHigh()
        unreadLabel.setCompressionResistanceHigh()

        unreadBadge.backgroundColor = .ows_accentBlue
        unreadBadge.addSubview(unreadLabel)
        unreadLabel.autoCenterInSuperview()
        unreadBadge.setContentHuggingHigh()
        unreadBadge.setCompressionResistanceHigh()
        contentView.addSubview(unreadBadge)

        typingIndicatorView.configureForConversationList()
        typingIndicatorView.setContentHuggingHorizontalHigh()
        typingIndicatorView.setCompressionResistanceHorizontalHigh()
        typingIndicatorWrapper.addSubview(typingIndicatorView)
        typingIndicatorView.autoPinWidthToSuperview()
        typingIndicatorView.autoVCenterInSuperview()

        // TODO: ?
        self.selectionStyle = .default
    }

    @objc
    public func configure(_ configuration: Configuration) {
        AssertIsOnMainThread()

        OWSTableItem.configureCell(self)

        self.configuration = configuration

        let thread = configuration.thread

        avatarView.shouldLoadAsync = configuration.shouldLoadAvatarAsync
        avatarView.configureWithSneakyTransaction(thread: thread.threadRecord)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(otherUsersProfileDidChange(notification:)),
                                               name: .otherUsersProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(typingIndicatorStateDidChange),
                                               name: TypingIndicatorsImpl.typingIndicatorStateDidChange,
                                               object: nil)

        updateNameLabel()

        // We update the fonts every time this cell is configured to ensure that
        // changes to the dynamic type settings are reflected.
        snippetLabel.font = snippetFont
        snippetLabel.textColor = snippetColor

        let snippetLineHeight = CGFloat(ceil(1.1 * snippetFont.ows_semibold.lineHeight))

        let muteIconSize: CGFloat = 16

        viewConstraints.append(contentsOf: [
            muteIconView.autoSetDimension(.width, toSize: muteIconSize),
            muteIconView.autoSetDimension(.height, toSize: muteIconSize),

            // These views should align with the first (of two) of the snippet,
            // so their a v-center within wrappers with the height of a single
            // snippet line.
            messageStatusWrapper.autoSetDimension(.height, toSize: snippetLineHeight),
            typingIndicatorWrapper.autoSetDimension(.height, toSize: snippetLineHeight)
        ])

        updatePreview()

        if let labelDate = configuration.overrideDate ?? thread.conversationListInfo?.lastMessageDate {
            dateTimeLabel.text = DateUtil.formatDateShort(labelDate)
        } else {
            dateTimeLabel.text = nil
        }

        if hasUnreadStyle {
            dateTimeLabel.font = dateTimeFont.ows_semibold
            dateTimeLabel.textColor = Theme.primaryTextColor
        } else {
            dateTimeLabel.font = dateTimeFont
            dateTimeLabel.textColor = snippetColor
        }

        var shouldHideStatusIndicator = false

        if hasOverrideSnippet {
            // If we're using the conversation list cell to render search results,
            // don't show "unread badge" or "message status" indicator.
            unreadBadge.isHidden = true
            shouldHideStatusIndicator = true
        } else if hasUnreadStyle {
            // If there are unread messages, show the "unread badge."
            unreadBadge.isHidden = false

            let unreadCount = thread.unreadCount
            if unreadCount > 0 {
                unreadLabel.text = OWSFormat.formatUInt(unreadCount)
            } else {
                unreadLabel.text = nil
            }

            unreadLabel.font = unreadFont
            let unreadBadgeHeight = ceil(unreadLabel.font.lineHeight * 1.5)
            unreadBadge.layer.cornerRadius = unreadBadgeHeight / 2
            unreadBadge.layer.borderColor = Theme.backgroundColor.cgColor
            unreadBadge.layer.borderWidth = 2

            NSLayoutConstraint.autoSetPriority(.defaultHigh) {
                // This is a bit arbitrary, but it should scale with the size of dynamic text
                let minMargin = CeilEven(unreadBadgeHeight * 0.5)

                viewConstraints.append(contentsOf: [
                    // badge sizing
                    unreadBadge.autoMatch(.width, to: .width, of: unreadLabel, withOffset: minMargin, relation: .greaterThanOrEqual),
                    unreadBadge.autoSetDimension(.width, toSize: unreadBadgeHeight, relation: .greaterThanOrEqual),
                    unreadBadge.autoSetDimension(.height, toSize: unreadBadgeHeight),
                    unreadBadge.autoPinEdge(.trailing, to: .trailing, of: avatarView, withOffset: 6),
                    unreadBadge.autoPinEdge(.top, to: .top, of: avatarView)
                ])
            }
        } else {
            unreadBadge.isHidden = true
        }

        if !shouldHideStatusIndicator,
           let outgoingMessage = thread.lastMessageForInbox as? TSOutgoingMessage {
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
                statusIndicatorImage = UIImage(named: "message_status_sent")
                shouldHideStatusIndicator = outgoingMessage.wasRemotelyDeleted
            case .delivered:
                statusIndicatorImage = UIImage(named: "message_status_delivered")
                shouldHideStatusIndicator = outgoingMessage.wasRemotelyDeleted
            case .read, .viewed:
                statusIndicatorImage = UIImage(named: "message_status_read")
                shouldHideStatusIndicator = outgoingMessage.wasRemotelyDeleted
            case .failed:
                statusIndicatorImage = UIImage(named: "error-outline-12")
                messageStatusViewTintColor = .ows_accentRed
            case .pending:
                statusIndicatorImage = UIImage(named: "error-outline-12")
                messageStatusViewTintColor = .ows_gray60
            }

            messageStatusIconView.image = statusIndicatorImage?.withRenderingMode(.alwaysTemplate)
            messageStatusIconView.tintColor = messageStatusViewTintColor
            messageStatusWrapper.isHidden = shouldHideStatusIndicator || statusIndicatorImage == nil
            if shouldAnimateStatusIcon {
                let animation = CABasicAnimation(keyPath: "transform.rotation.z")
                animation.toValue = NSNumber(value: Double.pi * 2)
                animation.duration = kSecondInterval * 1
                animation.isCumulative = true
                animation.repeatCount = .greatestFiniteMagnitude
                messageStatusIconView.layer.add(animation, forKey: "animation")
            } else {
                messageStatusIconView.layer.removeAllAnimations()
            }
        } else {
            messageStatusWrapper.isHidden = true
        }
    }

    private var hasUnreadStyle: Bool {
        guard let thread = thread else {
            return false
        }
        return thread.hasUnreadMessages && overrideSnippet == nil
    }

    private func attributedSnippet(forThread thread: ThreadViewModel,
                                   isBlocked: Bool) -> NSAttributedString {

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
            if let addedToGroupByName = thread.conversationListInfo?.addedToGroupByName {
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
            if let draftText = thread.conversationListInfo?.draftText?.nilIfEmpty,
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
            } else if thread.conversationListInfo?.hasVoiceMemoDraft == true,
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
                if let lastMessageText = thread.conversationListInfo?.lastMessageText.filterStringForDisplay().nilIfEmpty {
                    if let senderName = thread.conversationListInfo?.lastMessageSenderName {
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

    private func shouldShowMuteIndicator(forThread thread: ThreadViewModel, isBlocked: Bool) -> Bool {
        !hasOverrideSnippet && !isBlocked && !thread.hasPendingMessageRequest && thread.isMuted
    }

    // MARK: - Reuse

    @objc
    public override func prepareForReuse() {
        super.prepareForReuse()

        NSLayoutConstraint.deactivate(viewConstraints)
        viewConstraints = []

        configuration = nil
        messageStatusWrapper.isHidden = false
        avatarView.image = nil
        avatarView.reset()

        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Name

    @objc
    private func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let address = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress,
              address.isValid,
              let contactThread = thread?.threadRecord as? TSContactThread,
              contactThread.contactAddress == address else {
            return
        }
        updateNameLabel()
    }

    @objc
    private func typingIndicatorStateDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let thread = self.thread,
              let notificationThreadId = notification.object as? String,
              thread.threadRecord.uniqueId == notificationThreadId else {
            return
        }

        updatePreview()
    }

    private func updateNameLabel() {
        AssertIsOnMainThread()

        nameLabel.font = nameFont
        nameLabel.textColor = Theme.primaryTextColor

        guard let thread = self.thread else {
            owsFailDebug("Missing thread.")
            nameLabel.attributedText = nil
            return
        }

        nameLabel.text = {
            if thread.threadRecord is TSContactThread {
                if thread.threadRecord.isNoteToSelf {
                    return MessageStrings.noteToSelf
                } else {
                    return thread.name
                }
            } else {
                if let name = thread.name.nilIfEmpty {
                    return name
                } else {
                    return MessageStrings.newGroupDefaultTitle
                }
            }
        }()
    }

    // MARK: - Typing Indicators

    private var shouldShowTypingIndicators: Bool {
        if !hasOverrideSnippet,
           let thread = self.thread,
           nil != typingIndicatorsImpl.typingAddress(forThread: thread.threadRecord) {
            return true
        }
        return false
    }

    private func updatePreview() {
        AssertIsOnMainThread()

        guard let configuration = self.configuration else {
            return
        }

        // We use "override snippets" to show "message" search results.
        // We don't want to show typing indicators in that case.
        if shouldShowTypingIndicators {
            // We want to be able to show/hide the typing indicators without
            // any "jitter" in the cell layout.
            //
            // Therefore we do not hide the snippet label, but use it to
            // display two lines of non-rendering text so that it retains its
            // full height.
            snippetLabel.attributedText = " \n ".asAttributedString(attributes: [
                .font: snippetFont
            ])
            snippetLabel.textColor = Theme.backgroundColor
            typingIndicatorWrapper.isHidden = false
            typingIndicatorView.startAnimation()
        } else {
            var attributedText: NSAttributedString = {
                if let overrideSnippet = self.overrideSnippet {
                    return overrideSnippet
                }
                return self.attributedSnippet(forThread: configuration.thread,
                                              isBlocked: configuration.isBlocked)
            }()
            // Ensure that the snippet is at least two lines so that it is top-aligned.
            //
            // UILabel appears to have an issue where it's height is
            // too large if its text is just a series of empty lines,
            // so we include spaces to avoid that issue.
            attributedText = attributedText.stringByAppendingString(" \n \n",
                                                                    attributes: [
                                                                        .font: snippetFont
                              ])
            snippetLabel.attributedText = attributedText

            typingIndicatorWrapper.isHidden = true
            typingIndicatorView.stopAnimation()
        }

        muteIconWrapper.isHidden = !shouldShowMuteIndicator(forThread: configuration.thread,
                                                          isBlocked: configuration.isBlocked)
        muteIconView.tintColor = snippetColor
    }
}
