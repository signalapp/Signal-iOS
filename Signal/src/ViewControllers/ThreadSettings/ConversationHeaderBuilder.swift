//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

struct ConversationHeaderBuilder: Dependencies {
    weak var delegate: ConversationHeaderDelegate!
    let transaction: SDSAnyReadTransaction

    var subviews = [UIView]()

    struct ButtonOptions: OptionSet {
        let rawValue: Int

        static let message   = ButtonOptions(rawValue: 1 << 0)
        static let audioCall = ButtonOptions(rawValue: 1 << 1)
        static let videoCall = ButtonOptions(rawValue: 1 << 2)
        static let mute      = ButtonOptions(rawValue: 1 << 3)
        static let search    = ButtonOptions(rawValue: 1 << 4)
    }

    static func buildHeader(for thread: TSThread, options: ButtonOptions, delegate: ConversationHeaderDelegate) -> UIView {
        if let groupThread = thread as? TSGroupThread {
            return ConversationHeaderBuilder.buildHeaderForGroup(groupThread: groupThread, options: options, delegate: delegate)
        } else if let contactThread = thread as? TSContactThread {
            return ConversationHeaderBuilder.buildHeaderForContact(contactThread: contactThread, options: options, delegate: delegate)
        } else {
            owsFailDebug("Invalid thread.")
            return UIView()
        }
    }

    static func buildHeaderForGroup(groupThread: TSGroupThread, options: ButtonOptions, delegate: ConversationHeaderDelegate) -> UIView {
        databaseStorage.read { transaction in
            self.buildHeaderForGroup(groupThread: groupThread, options: options, delegate: delegate, transaction: transaction)
        }
    }

    static func buildHeaderForGroup(
        groupThread: TSGroupThread,
        options: ButtonOptions,
        delegate: ConversationHeaderDelegate,
        transaction: SDSAnyReadTransaction
    ) -> UIView {
        var builder = ConversationHeaderBuilder(delegate: delegate, transaction: transaction)

        if !groupThread.groupModel.isPlaceholder {
            let memberCount = groupThread.groupModel.groupMembership.fullMembers.count
            var groupMembersText = GroupViewUtils.formatGroupMembersLabel(memberCount: memberCount)
            if groupThread.isGroupV1Thread {
                groupMembersText.append(" ")
                groupMembersText.append("•")
                groupMembersText.append(" ")
                groupMembersText.append(NSLocalizedString("GROUPS_LEGACY_GROUP_INDICATOR",
                                                          comment: "Label indicating a legacy group."))
            }
            builder.addSubtitleLabel(text: groupMembersText)
        }

        if groupThread.isGroupV1Thread {
            builder.addLegacyGroupView(groupThread: groupThread)
        }

        builder.addButtons(options: options)

        return builder.build()
    }

    static func buildHeaderForContact(contactThread: TSContactThread, options: ButtonOptions, delegate: ConversationHeaderDelegate) -> UIView {
        databaseStorage.read { transaction in
            self.buildHeaderForContact(contactThread: contactThread, options: options, delegate: delegate, transaction: transaction)
        }
    }

    static func buildHeaderForContact(
        contactThread: TSContactThread,
        options: ButtonOptions,
        delegate: ConversationHeaderDelegate,
        transaction: SDSAnyReadTransaction
    ) -> UIView {
        var builder = ConversationHeaderBuilder(delegate: delegate, transaction: transaction)

        if !contactThread.contactAddress.isLocalAddress,
           let bioText = profileManagerImpl.profileBioForDisplay(
            for: contactThread.contactAddress,
            transaction: transaction
           ) {
            let label = builder.addSubtitleLabel(text: bioText)
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.textAlignment = .center
        }

        let threadName = contactsManager.displayName(for: contactThread, transaction: transaction)
        let recipientAddress = contactThread.contactAddress
        if let phoneNumber = recipientAddress.phoneNumber {
            let formattedPhoneNumber =
                PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
            if threadName != formattedPhoneNumber {
                builder.addSubtitleLabel(text: formattedPhoneNumber)
            }
        }

        let isVerified = identityManager.verificationState(
            for: recipientAddress,
            transaction: transaction
        ) == .verified
        if isVerified {
            let subtitle = NSMutableAttributedString()
            subtitle.appendTemplatedImage(named: "check-12", font: .ows_dynamicTypeSubheadlineClamped)
            subtitle.append(" ")
            subtitle.append(NSLocalizedString("PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                              comment: "Badge indicating that the user is verified."))
            builder.addSubtitleLabel(attributedText: subtitle)
        }

        builder.addButtons(options: options)

        return builder.build()
    }

    init(delegate: ConversationHeaderDelegate, transaction: SDSAnyReadTransaction) {

        self.delegate = delegate
        self.transaction = transaction

        addFirstSubviews()
    }

    mutating func addFirstSubviews() {
        let avatarView = buildAvatarView()

        let avatarWrapper = UIView.container()
        avatarWrapper.addSubview(avatarView)
        avatarView.autoPinEdgesToSuperviewEdges()

        let avatarButton = OWSButton { [weak delegate] in
            delegate?.tappedAvatar()
        }
        avatarWrapper.addSubview(avatarButton)
        avatarButton.autoPinEdgesToSuperviewEdges()

        subviews.append(avatarWrapper)
        subviews.append(UIView.spacer(withHeight: 8))
        subviews.append(buildThreadNameLabel())
    }

    mutating func addButtons(options: ButtonOptions) {
        var buttons = [UIView]()

        if options.contains(.message) {
            buttons.append(buildIconButton(
                icon: .settingsChats,
                text: NSLocalizedString(
                        "CONVERSATION_SETTINGS_MESSAGE_BUTTON",
                        comment: "Button to message the chat"
                    ),
                action: { [weak delegate] in
                    guard let delegate = delegate else { return }
                    delegate.signalApp.presentConversation(for: delegate.thread, animated: true)
                }
            ))
        }

        if ConversationViewController.canCall(threadViewModel: delegate.threadViewModel) {
            let isCurrentCallForThread = callService.currentCall?.thread.uniqueId == delegate.thread.uniqueId
            let hasCurrentCall = callService.currentCall != nil

            if options.contains(.videoCall) {
                buttons.append(buildIconButton(
                    icon: .videoCall,
                    text: NSLocalizedString(
                        "CONVERSATION_SETTINGS_VIDEO_CALL_BUTTON",
                        comment: "Button to start a video call"
                    ),
                    isEnabled: isCurrentCallForThread || !hasCurrentCall,
                    action: { [weak delegate] in
                        delegate?.startCall(withVideo: true)
                    }
                ))
            }

            if !delegate.thread.isGroupThread, options.contains(.audioCall) {
                buttons.append(buildIconButton(
                    icon: .audioCall,
                    text: NSLocalizedString(
                        "CONVERSATION_SETTINGS_AUDIO_CALL_BUTTON",
                        comment: "Button to start a audio call"
                    ),
                    isEnabled: isCurrentCallForThread || !hasCurrentCall,
                    action: { [weak delegate] in
                        delegate?.startCall(withVideo: false)
                    }
                ))
            }
        }

        if options.contains(.mute) {
            buttons.append(buildIconButton(
                icon: .settingsMuted,
                text: delegate.thread.isMuted
                    ? NSLocalizedString(
                        "CONVERSATION_SETTINGS_MUTED_BUTTON",
                        comment: "Button to unmute the chat"
                    )
                    : NSLocalizedString(
                        "CONVERSATION_SETTINGS_MUTE_BUTTON",
                        comment: "Button to mute the chat"
                    ),
                action: { [weak delegate] in
                    guard let delegate = delegate else { return }
                    ConversationSettingsViewController.showMuteUnmuteActionSheet(
                        for: delegate.thread,
                        from: delegate
                    ) { [weak delegate] in
                        delegate?.updateTableContents(shouldReload: true)
                    }
                }
            ))
        }

        if options.contains(.search), !delegate.groupViewHelper.isBlockedByMigration {
            buttons.append(buildIconButton(
                icon: .settingsSearch,
                text: NSLocalizedString(
                    "CONVERSATION_SETTINGS_SEARCH_BUTTON",
                    comment: "Button to search the chat"
                ),
                action: { [weak delegate] in
                    delegate?.tappedConversationSearch()
                }
            ))
        }

        let spacerWidth: CGFloat = 8
        let totalSpacerWidth = CGFloat(buttons.count - 1) * spacerWidth
        let maxAvailableButtonWidth = delegate.view.width - (OWSTableViewController2.cellHOuterMargin + totalSpacerWidth)
        let minButtonWidth = maxAvailableButtonWidth / 4

        var buttonWidth = max(maxIconButtonWidth, minButtonWidth)
        let needsTwoRows = buttonWidth * CGFloat(buttons.count) > maxAvailableButtonWidth
        if needsTwoRows { buttonWidth = buttonWidth * 2 }
        buttons.forEach { $0.autoSetDimension(.width, toSize: buttonWidth) }

        func addButtonRow(_ buttons: [UIView]) {
            let stackView = UIStackView()
            stackView.axis = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = spacerWidth
            buttons.forEach { stackView.addArrangedSubview($0) }
            subviews.append(stackView)
        }

        subviews.append(.spacer(withHeight: 24))

        if needsTwoRows {
            addButtonRow(Array(buttons.prefix(Int(ceil(CGFloat(buttons.count) / 2)))))
            subviews.append(.spacer(withHeight: 8))
            addButtonRow(buttons.suffix(Int(floor(CGFloat(buttons.count) / 2))))
        } else {
            addButtonRow(buttons)
        }
    }

    private var maxIconButtonWidth: CGFloat = 0
    mutating func buildIconButton(icon: ThemeIcon, text: String, isEnabled: Bool = true, action: @escaping () -> Void) -> UIView {
        let button = OWSButton(block: action)
        button.dimsWhenHighlighted = true
        button.isEnabled = isEnabled
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        button.setBackgroundImage(UIImage(color: delegate.cellBackgroundColor), for: .normal)

        let imageView = UIImageView()
        imageView.setTemplateImageName(Theme.iconName(icon), tintColor: Theme.primaryTextColor)
        imageView.autoSetDimension(.height, toSize: 24)
        imageView.contentMode = .scaleAspectFit

        button.addSubview(imageView)
        imageView.autoPinWidthToSuperview()
        imageView.autoPinEdge(toSuperviewEdge: .top, withInset: 8)

        let label = UILabel()
        label.font = .ows_dynamicTypeCaption2Clamped
        label.textColor = Theme.primaryTextColor
        label.textAlignment = .center
        label.text = text
        label.sizeToFit()
        label.setCompressionResistanceHorizontalHigh()

        let buttonMinimumWidth = label.width + 24
        if maxIconButtonWidth < buttonMinimumWidth {
            maxIconButtonWidth = buttonMinimumWidth
        }

        button.addSubview(label)
        label.autoPinWidthToSuperview(withMargin: 12)
        label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 6)
        label.autoPinEdge(.top, to: .bottom, of: imageView, withOffset: 2)

        return button
    }

    func buildAvatarView() -> UIView {
        let avatarSize: UInt = 88
        let avatarImage = OWSAvatarBuilder.buildImage(
            thread: delegate.thread,
            diameter: avatarSize,
            transaction: transaction
        )
        let avatarView = AvatarImageView(image: avatarImage)
        avatarView.autoSetDimensions(to: CGSize(square: CGFloat(avatarSize)))
        // Track the most recent avatar view.
        delegate.avatarView = avatarView
        return avatarView
    }

    func buildThreadNameLabel() -> UILabel {
        let label = UILabel()
        label.text = delegate.threadName(transaction: transaction)
        label.textColor = Theme.primaryTextColor
        // TODO: See if design really wants this custom font size.
        label.font = UIFont.ows_semiboldFont(withSize: UIFont.ows_dynamicTypeTitle1Clamped.pointSize * (13/14))
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    @discardableResult
    mutating func addSubtitleLabel(text: String) -> UILabel {
        addSubtitleLabel(attributedText: NSAttributedString(string: text))
    }

    private var hasSubtitleLabel = false

    @discardableResult
    mutating func addSubtitleLabel(attributedText: NSAttributedString) -> UILabel {
        subviews.append(UIView.spacer(withHeight: hasSubtitleLabel ? 4 : 8))
        let label = buildHeaderSubtitleLabel(attributedText: attributedText)
        subviews.append(label)
        hasSubtitleLabel = true
        return label
    }

    mutating func addLegacyGroupView(groupThread: TSGroupThread) {
        subviews.append(UIView.spacer(withHeight: 12))

        let migrationInfo = GroupsV2Migration.migrationInfoForManualMigration(groupThread: groupThread,
                                                                              transaction: transaction)
        let legacyGroupView = LegacyGroupView(
            groupThread: groupThread,
            migrationInfo: migrationInfo,
            viewController: delegate
        )
        legacyGroupView.configure()
        legacyGroupView.backgroundColor = delegate.cellBackgroundColor
        subviews.append(legacyGroupView)
    }

    func buildHeaderSubtitleLabel(attributedText: NSAttributedString) -> UILabel {
        let label = UILabel()

        // Defaults need to be set *before* assigning the attributed text,
        // or the attributes will get overriden
        label.textColor = Theme.secondaryTextAndIconColor
        label.lineBreakMode = .byTruncatingTail
        label.font = .ows_dynamicTypeSubheadlineClamped

        label.attributedText = attributedText

        return label
    }

    func build() -> UIView {
        let header = UIStackView(arrangedSubviews: subviews)
        header.axis = .vertical
        header.alignment = .center
        header.layoutMargins = UIEdgeInsets(
            top: 0,
            leading: OWSTableViewController2.cellHOuterMargin,
            bottom: 24,
            trailing: OWSTableViewController2.cellHOuterMargin
        )
        header.isLayoutMarginsRelativeArrangement = true

        header.isUserInteractionEnabled = true
        header.accessibilityIdentifier = UIView.accessibilityIdentifier(in: delegate, name: "mainSectionHeader")
        header.addBackgroundView(withBackgroundColor: delegate.tableBackgroundColor)

        return header
    }
}

protocol ConversationHeaderDelegate: OWSTableViewController2, Dependencies {
    var thread: TSThread { get }
    var threadViewModel: ThreadViewModel { get }

    var threadName: String { get }
    func threadName(transaction: SDSAnyReadTransaction) -> String

    var avatarView: UIImageView? { get set }

    var groupViewHelper: GroupViewHelper { get }

    func tappedAvatar()
    func updateTableContents(shouldReload: Bool)
    func tappedConversationSearch()

    func startCall(withVideo: Bool)

    func didTapUnblockThread(completion: @escaping () -> Void)
}

extension ConversationHeaderDelegate {
    var threadName: String {
        databaseStorage.read { transaction in
            self.threadName(transaction: transaction)
        }
    }

    func threadName(transaction: SDSAnyReadTransaction) -> String {
        var threadName = contactsManager.displayName(for: thread, transaction: transaction)

        if let contactThread = thread as? TSContactThread {
            if let phoneNumber = contactThread.contactAddress.phoneNumber,
               phoneNumber == threadName {
                threadName = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
            }
        }

        return threadName
    }

    func startCall(withVideo: Bool) {
        guard ConversationViewController.canCall(threadViewModel: threadViewModel) else {
            return owsFailDebug("Tried to start a can when calls are disabled")
        }
        guard withVideo || !thread.isGroupThread else {
            return owsFailDebug("Tried to start an audio only group call")
        }

        guard !blockingManager.isThreadBlocked(thread) else {
            didTapUnblockThread { [weak self] in
                self?.startCall(withVideo: withVideo)
            }
            return
        }

        if let currentCall = callService.currentCall {
            if currentCall.thread.uniqueId == thread.uniqueId {
                windowManager.returnToCallView()
            } else {
                owsFailDebug("Tried to start call while call was ongoing")
            }
        } else if let groupThread = thread as? TSGroupThread {
            // We initiated a call, so if there was a pending message request we should accept it.
            ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
            GroupCallViewController.presentLobby(thread: groupThread)
        } else if let contactThread = thread as? TSContactThread {

            let didShowSNAlert = SafetyNumberConfirmationSheet.presentIfNecessary(
                address: contactThread.contactAddress,
                confirmationText: CallStrings.confirmAndCallButtonTitle
            ) { [weak self] didConfirmIdentity in
                guard didConfirmIdentity else { return }
                self?.startCall(withVideo: withVideo)
            }

            guard !didShowSNAlert else { return }

            // We initiated a call, so if there was a pending message request we should accept it.
            ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)

            outboundIndividualCallInitiator.initiateCall(address: contactThread.contactAddress, isVideo: withVideo)
        }
    }
}

extension ConversationSettingsViewController: ConversationHeaderDelegate {
    func buildMainHeader() -> UIView {
        ConversationHeaderBuilder.buildHeader(for: thread, options: [.videoCall, .audioCall, .mute, .search], delegate: self)
    }
}
