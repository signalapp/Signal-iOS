//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
public import UIKit

struct ConversationHeaderBuilder {
    weak var delegate: ConversationHeaderDelegate!
    let transaction: SDSAnyReadTransaction
    let sizeClass: ConversationAvatarView.Configuration.SizeClass
    let options: Options

    var subviews = [UIView]()

    struct Options: OptionSet {
        let rawValue: Int

        static let message   = Options(rawValue: 1 << 0)
        static let audioCall = Options(rawValue: 1 << 1)
        static let videoCall = Options(rawValue: 1 << 2)
        static let mute      = Options(rawValue: 1 << 3)
        static let search    = Options(rawValue: 1 << 4)

        static let renderLocalUserAsNoteToSelf = Options(rawValue: 1 << 5)
    }

    static func buildHeader(
        for thread: TSThread,
        sizeClass: ConversationAvatarView.Configuration.SizeClass,
        options: Options,
        delegate: ConversationHeaderDelegate
    ) -> UIView {
        if let groupThread = thread as? TSGroupThread {
            return ConversationHeaderBuilder.buildHeaderForGroup(
                groupThread: groupThread,
                sizeClass: sizeClass,
                options: options,
                delegate: delegate
            )
        } else if let contactThread = thread as? TSContactThread {
            return ConversationHeaderBuilder.buildHeaderForContact(
                contactThread: contactThread,
                sizeClass: sizeClass,
                options: options,
                delegate: delegate
            )
        } else {
            owsFailDebug("Invalid thread.")
            return UIView()
        }
    }

    static func buildHeaderForGroup(
        groupThread: TSGroupThread,
        sizeClass: ConversationAvatarView.Configuration.SizeClass,
        options: Options,
        delegate: ConversationHeaderDelegate
    ) -> UIView {
        // Make sure the view is loaded before we open a transaction,
        // because it can end up creating a transaction within.
        _ = delegate.view
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            self.buildHeaderForGroup(
                groupThread: groupThread,
                sizeClass: sizeClass,
                options: options,
                delegate: delegate,
                transaction: transaction
            )
        }
    }

    static func buildHeaderForGroup(
        groupThread: TSGroupThread,
        sizeClass: ConversationAvatarView.Configuration.SizeClass,
        options: Options,
        delegate: ConversationHeaderDelegate,
        transaction: SDSAnyReadTransaction
    ) -> UIView {
        var builder = ConversationHeaderBuilder(
            delegate: delegate,
            sizeClass: sizeClass,
            options: options,
            transaction: transaction
        )

        var isShowingGroupDescription = false
        if let groupModel = groupThread.groupModel as? TSGroupModelV2 {
            if let descriptionText = groupModel.descriptionText {
                isShowingGroupDescription = true
                builder.addGroupDescriptionPreview(text: descriptionText)
            } else if delegate.canEditConversationAttributes {
                isShowingGroupDescription = true
                builder.addCreateGroupDescriptionButton()
            }
        }

        if !isShowingGroupDescription && !groupThread.groupModel.isPlaceholder {
            let memberCount = groupThread.groupModel.groupMembership.fullMembers.count
            var groupMembersText = GroupViewUtils.formatGroupMembersLabel(memberCount: memberCount)
            if groupThread.isGroupV1Thread {
                groupMembersText.append(" ")
                groupMembersText.append("•")
                groupMembersText.append(" ")
                groupMembersText.append(OWSLocalizedString("GROUPS_LEGACY_GROUP_INDICATOR",
                                                          comment: "Label indicating a legacy group."))
            }
            builder.addSubtitleLabel(text: groupMembersText)
        }

        if groupThread.isGroupV1Thread {
            builder.addLegacyGroupView()
        }

        builder.addButtons()

        return builder.build()
    }

    static func buildHeaderForContact(
        contactThread: TSContactThread,
        sizeClass: ConversationAvatarView.Configuration.SizeClass,
        options: Options,
        delegate: ConversationHeaderDelegate
    ) -> UIView {
        // Make sure the view is loaded before we open a transaction,
        // because it can end up creating a transaction within.
        _ = delegate.view
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            self.buildHeaderForContact(
                contactThread: contactThread,
                sizeClass: sizeClass,
                options: options,
                delegate: delegate,
                transaction: transaction
            )
        }
    }

    static func buildHeaderForContact(
        contactThread: TSContactThread,
        sizeClass: ConversationAvatarView.Configuration.SizeClass,
        options: Options,
        delegate: ConversationHeaderDelegate,
        transaction: SDSAnyReadTransaction
    ) -> UIView {
        var builder = ConversationHeaderBuilder(
            delegate: delegate,
            sizeClass: sizeClass,
            options: options,
            transaction: transaction
        )

        if !contactThread.contactAddress.isLocalAddress,
           let bioText = SSKEnvironment.shared.profileManagerImplRef.profileBioForDisplay(
            for: contactThread.contactAddress,
            transaction: transaction
           ) {
            let label = builder.addSubtitleLabel(text: bioText)
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.textAlignment = .center
        }

        let recipientAddress = contactThread.contactAddress

        let identityManager = DependenciesBridge.shared.identityManager
        let isVerified = identityManager.verificationState(for: recipientAddress, tx: transaction.asV2Read) == .verified
        if isVerified {
            let subtitle = NSMutableAttributedString()
            subtitle.append(SignalSymbol.safetyNumber.attributedString(for: .subheadline, clamped: true))
            subtitle.append(" ")
            subtitle.append(SafetyNumberStrings.verified)
            builder.addSubtitleLabel(attributedText: subtitle)
        }

        builder.addButtons()

        return builder.build()
    }

    init(delegate: ConversationHeaderDelegate,
         sizeClass: ConversationAvatarView.Configuration.SizeClass,
         options: Options,
         transaction: SDSAnyReadTransaction) {

        self.delegate = delegate
        self.sizeClass = sizeClass
        self.options = options
        self.transaction = transaction

        addFirstSubviews(transaction: transaction)
    }

    mutating func addFirstSubviews(transaction: SDSAnyReadTransaction) {
        let avatarView = buildAvatarView(transaction: transaction)

        let avatarWrapper = UIView.container()
        avatarWrapper.addSubview(avatarView)
        avatarView.autoPinEdgesToSuperviewEdges()

        subviews.append(avatarWrapper)
        subviews.append(UIView.spacer(withHeight: 8))
        subviews.append(buildThreadNameLabel())
    }

    mutating func addButtons() {
        var buttons = [UIView]()

        if options.contains(.message) {
            buttons.append(buildIconButton(
                icon: .settingsChats,
                text: OWSLocalizedString(
                        "CONVERSATION_SETTINGS_MESSAGE_BUTTON",
                        comment: "Button to message the chat"
                    ),
                action: { [weak delegate] in
                    guard let delegate = delegate else { return }
                    SignalApp.shared.presentConversationForThread(delegate.thread, action: .compose, animated: true)
                }
            ))
        }

        if ConversationViewController.canCall(threadViewModel: delegate.threadViewModel) {
            let callService = AppEnvironment.shared.callService!
            let currentCall = callService.callServiceState.currentCall
            let hasCurrentCall = currentCall != nil
            let isCurrentCallForThread = { () -> Bool in
                switch currentCall?.mode {
                case nil: return false
                case .individual(let call): return call.thread.uniqueId == delegate.thread.uniqueId
                case .groupThread(let call): return call.groupId.serialize().asData == (delegate.thread as? TSGroupThread)?.groupId
                case .callLink: return false
                }
            }()

            if options.contains(.videoCall) {
                buttons.append(buildIconButton(
                    icon: .buttonVideoCall,
                    text: OWSLocalizedString(
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
                    icon: .buttonVoiceCall,
                    text: OWSLocalizedString(
                        "CONVERSATION_SETTINGS_VOICE_CALL_BUTTON",
                        comment: "Button to start a voice call"
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
                icon: .buttonMute,
                text: delegate.threadViewModel.isMuted
                    ? OWSLocalizedString(
                        "CONVERSATION_SETTINGS_MUTED_BUTTON",
                        comment: "Button to unmute the chat"
                    )
                    : OWSLocalizedString(
                        "CONVERSATION_SETTINGS_MUTE_BUTTON",
                        comment: "Button to mute the chat"
                    ),
                action: { [weak delegate] in
                    guard let delegate = delegate else { return }
                    ConversationSettingsViewController.showMuteUnmuteActionSheet(
                        for: delegate.threadViewModel,
                        from: delegate
                    ) { [weak delegate] in
                        delegate?.updateTableContents(shouldReload: true)
                    }
                }
            ))
        }

        if options.contains(.search), !delegate.isGroupV1Thread {
            buttons.append(buildIconButton(
                icon: .buttonSearch,
                text: OWSLocalizedString(
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
        let maxAvailableButtonWidth = delegate.tableViewController.view.width
            - (delegate.tableViewController.cellOuterInsets.totalWidth + totalSpacerWidth)
        let minButtonWidth = maxAvailableButtonWidth / 4

        var buttonWidth = max(maxIconButtonWidth, minButtonWidth)
        let needsTwoRows = buttonWidth * CGFloat(buttons.count) > maxAvailableButtonWidth
        if needsTwoRows { buttonWidth *= 2 }
        buttons.forEach { $0.autoSetDimension(.width, toSize: buttonWidth) }

        func addButtonRow(_ buttons: [UIView]) {
            let stackView = UIStackView()
            stackView.axis = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = spacerWidth
            buttons.forEach { stackView.addArrangedSubview($0) }
            subviews.append(stackView)
        }

        subviews.append(.spacer(withHeight: 20))

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
        let button = SettingsHeaderButton(
            text: text,
            icon: icon,
            backgroundColor: delegate.tableViewController.cellBackgroundColor,
            isEnabled: isEnabled
        ) { [weak delegate] in
            delegate?.tappedButton()
            action()
        }

        if maxIconButtonWidth < button.minimumWidth {
            maxIconButtonWidth = button.minimumWidth
        }

        return button
    }

    mutating func addGroupDescriptionPreview(text: String) {
        let previewView = GroupDescriptionPreviewView()
        previewView.descriptionText = text
        previewView.groupName = delegate.threadName(
            renderLocalUserAsNoteToSelf: true,
            transaction: transaction
        )
        previewView.font = .dynamicTypeSubheadlineClamped
        previewView.textColor = Theme.secondaryTextAndIconColor
        previewView.textAlignment = .center
        previewView.numberOfLines = 2

        subviews.append(UIView.spacer(withHeight: hasSubtitleLabel ? 4 : 8))
        subviews.append(previewView)
        hasSubtitleLabel = true
    }

    mutating func addCreateGroupDescriptionButton() {
        let button = OWSButton { [weak delegate] in delegate?.didTapAddGroupDescription() }
        button.setTitle(OWSLocalizedString(
            "GROUP_DESCRIPTION_PLACEHOLDER",
            comment: "Placeholder text for 'group description' field."
        ), for: .normal)
        button.setTitleColor(Theme.secondaryTextAndIconColor, for: .normal)
        button.titleLabel?.font = .dynamicTypeSubheadlineClamped

        subviews.append(UIView.spacer(withHeight: hasSubtitleLabel ? 4 : 8))
        subviews.append(button)
        hasSubtitleLabel = true
    }

    func buildAvatarView(transaction: SDSAnyReadTransaction) -> UIView {
        let avatarView = ConversationAvatarView(
            sizeClass: sizeClass,
            localUserDisplayMode: options.contains(.renderLocalUserAsNoteToSelf) ? .noteToSelf : .asUser)

        avatarView.update(transaction) {
            $0.dataSource = .thread(delegate.thread)
            $0.storyConfiguration = .autoUpdate()
        }
        avatarView.interactionDelegate = delegate

        // Track the most recent avatar view.
        delegate.avatarView = avatarView
        return avatarView
    }

    func buildThreadNameLabel() -> OWSButton {
        let button = OWSButton()
        button.setAttributedTitle(delegate.threadAttributedString(
            renderLocalUserAsNoteToSelf: options.contains(.renderLocalUserAsNoteToSelf),
            tx: transaction
        ), for: .normal)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.titleLabel?.setContentHuggingHigh()
        button.titleLabel?.autoMatch(.height, to: .height, of: button)
        if delegate.canTapThreadName {
            button.block = { [weak delegate] in
                delegate?.didTapThreadName()
            }
            button.dimsWhenHighlighted = true
        }
        return button
    }

    static func threadAttributedString(
        threadName: String,
        isNoteToSelf: Bool,
        isSystemContact: Bool,
        canTap: Bool,
        tx: SDSAnyReadTransaction
    ) -> NSAttributedString {
        let font = UIFont.dynamicTypeFont(ofStandardSize: 26, weight: .semibold)

        let attributedString = NSMutableAttributedString(string: threadName, attributes: [
            .foregroundColor: UIColor.label,
            .font: font,
        ])

        if isNoteToSelf {
            attributedString.append(" ")
            let verifiedBadgeImage = Theme.iconImage(.official)
            let verifiedBadgeAttachment = NSAttributedString.with(
                image: verifiedBadgeImage,
                font: .dynamicTypeTitle3,
                centerVerticallyRelativeTo: font,
                heightReference: .pointSize
            )
            attributedString.append(verifiedBadgeAttachment)
        }

        if isSystemContact {
            let contactIcon = SignalSymbol.personCircle.attributedString(
                dynamicTypeBaseSize: 20,
                weight: .bold,
                leadingCharacter: .nonBreakingSpace
            )
            attributedString.append(contactIcon)
        }

        if canTap {
            let chevron = SignalSymbol.chevronTrailing.attributedString(
                dynamicTypeBaseSize: 24,
                weight: .bold,
                leadingCharacter: .nonBreakingSpace,
                attributes: [.foregroundColor: Theme.snippetColor]
            )
            attributedString.append(chevron)
        }

        return attributedString
    }

    @discardableResult
    mutating func addSubtitleLabel(text: String) -> OWSLabel {
        addSubtitleLabel(attributedText: NSAttributedString(string: text))
    }

    private var hasSubtitleLabel = false

    @discardableResult
    mutating func addSubtitleLabel(attributedText: NSAttributedString) -> OWSLabel {
        subviews.append(UIView.spacer(withHeight: 4))
        let label = buildHeaderSubtitleLabel(attributedText: attributedText)
        subviews.append(label)
        hasSubtitleLabel = true
        return label
    }

    mutating func addLegacyGroupView() {
        subviews.append(UIView.spacer(withHeight: 12))

        let legacyGroupView = LegacyGroupView(viewController: delegate)
        legacyGroupView.configure()
        legacyGroupView.backgroundColor = delegate.tableViewController.cellBackgroundColor
        subviews.append(legacyGroupView)
    }

    func buildHeaderSubtitleLabel(attributedText: NSAttributedString) -> OWSLabel {
        let label = OWSLabel()

        // Defaults need to be set *before* assigning the attributed text,
        // or the attributes will get overridden
        label.textColor = Theme.secondaryTextAndIconColor
        label.lineBreakMode = .byTruncatingTail
        label.font = .dynamicTypeSubheadlineClamped

        label.attributedText = attributedText

        return label
    }

    func build() -> UIView {
        let header = UIStackView(arrangedSubviews: subviews)
        header.axis = .vertical
        header.alignment = .center
        header.layoutMargins = delegate.tableViewController.cellOuterInsetsWithMargin(bottom: 24)
        header.isLayoutMarginsRelativeArrangement = true

        header.isUserInteractionEnabled = true
        header.accessibilityIdentifier = UIView.accessibilityIdentifier(in: delegate, name: "mainSectionHeader")
        header.addBackgroundView(withBackgroundColor: delegate.tableViewController.tableBackgroundColor)

        return header
    }
}

// MARK: -

protocol ConversationHeaderDelegate: UIViewController, ConversationAvatarViewDelegate {
    var tableViewController: OWSTableViewController2 { get }

    var thread: TSThread { get }
    var threadViewModel: ThreadViewModel { get }

    func threadName(renderLocalUserAsNoteToSelf: Bool, transaction: SDSAnyReadTransaction) -> String

    var avatarView: ConversationAvatarView? { get set }

    var isGroupV1Thread: Bool { get }
    var canEditConversationAttributes: Bool { get }

    func updateTableContents(shouldReload: Bool)
    func tappedConversationSearch()

    func startCall(withVideo: Bool)

    func tappedButton()

    func didTapUnblockThread(completion: @escaping () -> Void)

    func didTapAddGroupDescription()

    var canTapThreadName: Bool { get }
    func didTapThreadName()
}

// MARK: -

extension ConversationHeaderDelegate {
    func threadName(renderLocalUserAsNoteToSelf: Bool, transaction: SDSAnyReadTransaction) -> String {
        var threadName: String
        if thread.isNoteToSelf, !renderLocalUserAsNoteToSelf {
            threadName = SSKEnvironment.shared.profileManagerRef.localFullName ?? ""
        } else {
            threadName = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: transaction)
        }

        if let contactThread = thread as? TSContactThread {
            if let phoneNumber = contactThread.contactAddress.phoneNumber,
               phoneNumber == threadName {
                threadName = PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(phoneNumber)
            }
        }

        return threadName
    }

    func threadAttributedString(renderLocalUserAsNoteToSelf: Bool, tx: SDSAnyReadTransaction) -> NSAttributedString {
        let threadName = threadName(renderLocalUserAsNoteToSelf: renderLocalUserAsNoteToSelf, transaction: tx)

        let isSystemContact =
        if let contactThread = self.thread as? TSContactThread {
            SSKEnvironment.shared.contactManagerRef.fetchSignalAccount(
                for: contactThread.contactAddress,
                transaction: tx
            ) != nil
        } else {
            false
        }

        return ConversationHeaderBuilder.threadAttributedString(
            threadName: threadName,
            isNoteToSelf: thread.isNoteToSelf,
            isSystemContact: isSystemContact,
            canTap: self.canTapThreadName,
            tx: tx
        )
    }

    func startCall(withVideo: Bool) {
        guard ConversationViewController.canCall(threadViewModel: threadViewModel) else {
            owsFailDebug("Tried to start a call when calls are disabled")
            return
        }
        let callTarget: CallTarget
        if let contactThread = thread as? TSContactThread {
            callTarget = .individual(contactThread)
        } else if let groupThread = thread as? TSGroupThread {
            if withVideo {
                if let groupId = try? groupThread.groupIdentifier {
                    callTarget = .groupThread(groupId)
                } else {
                    owsFailDebug("Tried to start a group call with an invalid groupId")
                    return
                }
            } else {
                owsFailDebug("Tried to start an audio only group call")
                return
            }
        } else {
            owsFailDebug("Tried to start an invalid call")
            return
        }

        guard !threadViewModel.isBlocked else {
            didTapUnblockThread { [weak self] in
                self?.startCall(withVideo: withVideo)
            }
            return
        }

        let callService = AppEnvironment.shared.callService!
        if let currentCall = callService.callServiceState.currentCall {
            if currentCall.mode.matches(callTarget) {
                AppEnvironment.shared.windowManagerRef.returnToCallView()
            } else {
                owsFailDebug("Tried to start call while call was ongoing")
            }
            return
        }

        // We initiated a call, so if there was a pending message request we should accept it.
        ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(thread)
        callService.initiateCall(to: callTarget, isVideo: withVideo)
    }
}

extension ConversationSettingsViewController: ConversationHeaderDelegate {
    var tableViewController: OWSTableViewController2 { self }

    func buildMainHeader() -> UIView {
        let options: ConversationHeaderBuilder.Options
        if callRecords.isEmpty {
            options = [.videoCall, .audioCall, .mute, .search, .renderLocalUserAsNoteToSelf]
        } else {
            // Call details
            options = [.message, .videoCall, .audioCall, .mute]
        }

        return ConversationHeaderBuilder.buildHeader(
            for: thread,
            sizeClass: .eightyEight,
            options: options,
            delegate: self
        )
    }

    func tappedButton() {}

    func didTapAddGroupDescription() {
        guard let groupThread = thread as? TSGroupThread else { return }
        let vc = GroupDescriptionViewController(
            groupModel: groupThread.groupModel,
            options: [.editable, .updateImmediately]
        )
        vc.descriptionDelegate = self
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    var canTapThreadName: Bool {
        !thread.isGroupThread && !thread.isNoteToSelf
    }

    func didTapThreadName() {
        guard let contactThread = self.thread as? TSContactThread else {
            owsFailDebug("Conversation name should only be tappable for contact threads")
            return
        }
        ContactAboutSheet(thread: contactThread, spoilerState: self.spoilerState)
            .present(from: self)
    }
}

extension ConversationSettingsViewController: GroupDescriptionViewControllerDelegate {
    func groupDescriptionViewControllerDidComplete(groupDescription: String?) {
        reloadThreadAndUpdateContent()
    }
}

// MARK: -

public class OWSLabel: UILabel {

    // MARK: - Tap

    public typealias TapBlock = () -> Void
    private var tapBlock: TapBlock?

    public func addTapGesture(_ tapBlock: @escaping TapBlock) {
        AssertIsOnMainThread()
        owsAssertDebug(self.tapBlock == nil)

        self.tapBlock = tapBlock
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
    }

    @objc
    private func didTap() {
        guard let tapBlock = tapBlock else {
            owsFailDebug("Missing tapBlock.")
            return
        }
        tapBlock()
    }

    // MARK: - Long Press

    public typealias LongPressBlock = () -> Void
    private var longPressBlock: LongPressBlock?

    public func addLongPressGesture(_ longPressBlock: @escaping LongPressBlock) {
        AssertIsOnMainThread()
        owsAssertDebug(self.longPressBlock == nil)

        self.longPressBlock = longPressBlock
        isUserInteractionEnabled = true
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(didLongPress)))
    }

    @objc
    private func didLongPress(sender: UIGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        guard let longPressBlock = longPressBlock else {
            owsFailDebug("Missing longPressBlock.")
            return
        }
        longPressBlock()
    }
}
