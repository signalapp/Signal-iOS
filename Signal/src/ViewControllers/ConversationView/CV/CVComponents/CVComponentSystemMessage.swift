//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentSystemMessage: CVComponentBase, CVRootComponent {

    public var cellReuseIdentifier: CVCellReuseIdentifier {
        CVCellReuseIdentifier.systemMessage
    }

    public let isDedicatedCell = true

    private let systemMessage: CVComponentState.SystemMessage

    typealias Action = CVMessageAction
    fileprivate var action: Action? { systemMessage.action }

    required init(itemModel: CVItemModel, systemMessage: CVComponentState.SystemMessage) {
        self.systemMessage = systemMessage

        super.init(itemModel: itemModel)
    }

    public func configure(cellView: UIView,
                          cellMeasurement: CVCellMeasurement,
                          componentDelegate: CVComponentDelegate,
                          cellSelection: CVCellSelection,
                          swipeToReplyState: CVSwipeToReplyState,
                          componentView: CVComponentView) {

        configureForRendering(componentView: componentView,
                              cellMeasurement: cellMeasurement,
                              componentDelegate: componentDelegate)

        let rootView = componentView.rootView
        if rootView.superview == nil {
            owsAssertDebug(cellView.layoutMargins == .zero)
            owsAssertDebug(cellView.subviews.isEmpty)

            cellView.addSubview(rootView)
            cellView.layoutMargins = cellLayoutMargins
            rootView.autoPinEdgesToSuperviewMargins()
        }
    }

    private var cellLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(top: 0,
                     leading: conversationStyle.fullWidthGutterLeading,
                     bottom: 0,
                     trailing: conversationStyle.fullWidthGutterTrailing)
    }

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .fill,
                          spacing: ConversationStyle.messageStackSpacing,
                          layoutMargins: .zero)
    }

    private var vStackConfig: CVStackViewConfig {
        let layoutMargins = UIEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
        return CVStackViewConfig(axis: .vertical,
                                 alignment: .center,
                                 spacing: 12,
                                 layoutMargins: layoutMargins)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewSystemMessage()
    }

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentView as? CVComponentViewSystemMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let outerStack = componentView.outerStack
        let vStackView = componentView.vStackView
        let selectionView = componentView.selectionView
        let titleLabel = componentView.titleLabel
        let backgroundView = componentView.backgroundView

        backgroundView.backgroundColor = Theme.backgroundColor
        backgroundView.isHidden = isShowingSelectionUI

        if isShowingSelectionUI {
            selectionView.isSelected = componentDelegate.cvc_isMessageSelected(interaction)
        }
        selectionView.isHiddenInStackView = !isShowingSelectionUI

        titleLabelConfig.applyForRendering(label: titleLabel)

        let isReusing = componentView.rootView.superview != nil
        if !isReusing {
            outerStack.apply(config: outerStackConfig)
            vStackView.apply(config: vStackConfig)

            outerStack.addArrangedSubview(selectionView)
            outerStack.addArrangedSubview(vStackView)
            vStackView.addArrangedSubview(titleLabel)
        }

        if let action = action, !itemViewState.shouldCollapseSystemMessageAction {
            let button = OWSButton(title: action.title) {}
            componentView.button = button
            button.accessibilityIdentifier = action.accessibilityIdentifier
            button.titleLabel?.textAlignment = .center
            button.titleLabel?.font = UIFont.ows_dynamicTypeFootnote.ows_semibold
            if nil != interaction as? OWSGroupCallMessage {
                let buttonTitleColor: UIColor = Theme.isDarkThemeEnabled ? .ows_whiteAlpha90 : .white
                button.setTitleColor(buttonTitleColor, for: .normal)
                button.backgroundColor = UIColor.ows_accentGreen
            } else {
                button.setTitleColor(Theme.conversationButtonTextColor, for: .normal)
                button.backgroundColor = Theme.conversationButtonBackgroundColor
            }
            button.contentEdgeInsets = UIEdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12)
            button.layer.cornerRadius = buttonHeight / 2
            button.autoSetDimension(.height, toSize: buttonHeight)
            button.isUserInteractionEnabled = false
            vStackView.addArrangedSubview(button)
        }
    }

    private var titleLabelConfig: CVLabelConfig {
        CVLabelConfig(attributedText: systemMessage.title,
                      font: Self.titleLabelFont,
                      textColor: systemMessage.titleColor,
                      numberOfLines: 0,
                      lineBreakMode: .byWordWrapping,
                      textAlignment: .center)
    }

    private static var titleLabelFont: UIFont {
        UIFont.ows_dynamicTypeFootnote
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var availableWidth = max(0, maxWidth - cellLayoutMargins.totalWidth)
        if isShowingSelectionUI {
            // Account for selection UI when doing measurement.
            availableWidth -= ConversationStyle.selectionViewWidth + outerStackConfig.spacing
        }

        var height: CGFloat = 0

        let titleSize = CVText.measureLabel(config: titleLabelConfig,
                                            maxWidth: availableWidth)
        height += titleSize.height
        height += cellLayoutMargins.totalHeight
        if action != nil, !itemViewState.shouldCollapseSystemMessageAction {
            height += buttonHeight + vStackConfig.spacing
        }
        height += vStackConfig.layoutMargins.totalHeight

        // Full width.
        return CGSize(width: maxWidth, height: height).ceil
    }

    // Should this reflect dynamic type used in the button?
    private let buttonHeight: CGFloat = 28

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let componentView = componentView as? CVComponentViewSystemMessage else {
            owsFailDebug("Unexpected componentView.")
            return false
        }

        if isShowingSelectionUI {
            let selectionView = componentView.selectionView
            let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
            if componentDelegate.cvc_isMessageSelected(interaction) {
                selectionView.isSelected = false
                componentDelegate.cvc_didDeselectViewItem(itemViewModel)
            } else {
                selectionView.isSelected = true
                componentDelegate.cvc_didSelectViewItem(itemViewModel)
            }
            // Suppress other tap handling during selection mode.
            return true
        }

        if let action = systemMessage.action {
            let rootView = componentView.rootView
            if rootView.containsGestureLocation(sender) {
                action.action.perform(delegate: componentDelegate)
                return true
            }
        }

        return false
    }

    public override func findLongPressHandler(sender: UILongPressGestureRecognizer,
                                              componentDelegate: CVComponentDelegate,
                                              componentView: CVComponentView,
                                              renderItem: CVRenderItem) -> CVLongPressHandler? {
        return CVLongPressHandler(delegate: componentDelegate,
                                  renderItem: renderItem,
                                  gestureLocation: .systemMessage)
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewSystemMessage: NSObject, CVComponentView {

        fileprivate let outerStack = OWSStackView(name: "systemMessage.outerStack")
        fileprivate let vStackView = OWSStackView(name: "systemMessage.vStackView")
        fileprivate let titleLabel = UILabel()
        fileprivate let selectionView = MessageSelectionView()
        fileprivate lazy var backgroundView = outerStack.addBackgroundView(withBackgroundColor: .clear, cornerRadius: 8)

        fileprivate var button: OWSButton?

        public var isDedicatedCellView = false

        public var rootView: UIView {
            outerStack
        }

        // MARK: -

        override required init() {
            super.init()

            titleLabel.textAlignment = .center
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            owsAssertDebug(isDedicatedCellView)

            if !isDedicatedCellView {
                outerStack.reset()
                vStackView.reset()
            }

            titleLabel.text = nil

            button?.removeFromSuperview()
            button = nil

            backgroundView.backgroundColor = .clear
        }
    }
}

// MARK: -

extension CVComponentSystemMessage {

    static func buildComponentState(interaction: TSInteraction,
                                    threadViewModel: ThreadViewModel,
                                    currentCallThreadId: String?,
                                    transaction: SDSAnyReadTransaction) -> CVComponentState.SystemMessage {

        let title = Self.title(forInteraction: interaction, transaction: transaction)
        let titleColor = Self.textColor(forInteraction: interaction)
        let action = Self.action(forInteraction: interaction,
                                 threadViewModel: threadViewModel,
                                 currentCallThreadId: currentCallThreadId,
                                 transaction: transaction)

        return CVComponentState.SystemMessage(title: title, titleColor: titleColor, action: action)
    }

    private static func title(forInteraction interaction: TSInteraction,
                              transaction: SDSAnyReadTransaction) -> NSAttributedString {

        let font = Self.titleLabelFont
        let labelText = NSMutableAttributedString()

        if let infoMessage = interaction as? TSInfoMessage,
           infoMessage.messageType == .typeGroupUpdate,
           let groupUpdates = infoMessage.groupUpdateItems(transaction: transaction),
           !groupUpdates.isEmpty {

            for (index, update) in groupUpdates.enumerated() {
                let iconName = Self.iconName(forGroupUpdateType: update.type)
                labelText.appendTemplatedImage(named: iconName,
                                               font: font,
                                               heightReference: ImageAttachmentHeightReference.lineHeight)
                labelText.append("  ", attributes: [:])
                labelText.append(update.text, attributes: [:])

                let isLast = index == groupUpdates.count - 1
                if !isLast {
                    labelText.append("\n", attributes: [:])
                }
            }

            if groupUpdates.count > 1 {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.paragraphSpacing = 12
                paragraphStyle.alignment = .center
                labelText.addAttributeToEntireString(.paragraphStyle, value: paragraphStyle)
            }

            return labelText
        }

        if let icon = icon(forInteraction: interaction) {
            labelText.appendImage(icon.withRenderingMode(.alwaysTemplate),
                                  font: font,
                                  heightReference: ImageAttachmentHeightReference.lineHeight)
            labelText.append("  ", attributes: [:])
        }

        let systemMessageText = Self.systemMessageText(forInteraction: interaction,
                                                       transaction: transaction)
        owsAssertDebug(!systemMessageText.isEmpty)
        labelText.append(systemMessageText)

        let shouldShowTimestamp = interaction.interactionType() == .call
        if shouldShowTimestamp {
            labelText.append(LocalizationNotNeeded(" · "))
            labelText.append(DateUtil.formatTimestamp(asDate: interaction.timestamp))
            labelText.append(LocalizationNotNeeded(" "))
            labelText.append(DateUtil.formatTimestamp(asTime: interaction.timestamp))
        }

        return labelText
    }

    private static func systemMessageText(forInteraction interaction: TSInteraction,
                                          transaction: SDSAnyReadTransaction) -> String {

        if let errorMessage = interaction as? TSErrorMessage {
            return errorMessage.previewText(transaction: transaction)
        } else if let verificationMessage = interaction as? OWSVerificationStateChangeMessage {
            let isVerified = verificationMessage.verificationState == .verified
            let displayName = contactsManager.displayName(for: verificationMessage.recipientAddress, transaction: transaction)
            let format = (isVerified
                            ? (verificationMessage.isLocalChange
                                ? NSLocalizedString("VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_LOCAL",
                                                    comment: "Format for info message indicating that the verification state was verified on this device. Embeds {{user's name or phone number}}.")
                                : NSLocalizedString("VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_OTHER_DEVICE",
                                                    comment: "Format for info message indicating that the verification state was verified on another device. Embeds {{user's name or phone number}}."))
                            : (verificationMessage.isLocalChange
                                ? NSLocalizedString("VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_LOCAL",
                                                    comment: "Format for info message indicating that the verification state was unverified on this device. Embeds {{user's name or phone number}}.")
                                : NSLocalizedString("VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_OTHER_DEVICE",
                                                    comment: "Format for info message indicating that the verification state was unverified on another device. Embeds {{user's name or phone number}}.")))
            return String(format: format, displayName)
        } else if let infoMessage = interaction as? TSInfoMessage {
            return infoMessage.systemMessageText(with: transaction)
        } else if let call = interaction as? TSCall {
            return call.previewText(transaction: transaction)
        } else if let groupCall = interaction as? OWSGroupCallMessage {
            return groupCall.systemText(with: transaction)
        } else {
            owsFailDebug("Not a system message.")
            return ""
        }
    }

    private static func textColor(forInteraction interaction: TSInteraction) -> UIColor {
        if let call = interaction as? TSCall {
            switch call.callType {
            case .incomingMissed,
                 .incomingMissedBecauseOfChangedIdentity,
                 .incomingBusyElsewhere,
                 .incomingDeclined,
                 .incomingDeclinedElsewhere:
                // We use a custom red here, as we consider changing
                // our red everywhere for better accessibility
                return UIColor(rgbHex: 0xE51D0E)
            default:
                return Theme.secondaryTextAndIconColor
            }
        } else {
            return Theme.secondaryTextAndIconColor
        }
    }

    private static func icon(forInteraction interaction: TSInteraction) -> UIImage? {
        if let errorMessage = interaction as? TSErrorMessage {
            switch errorMessage.errorType {
            case .nonBlockingIdentityChange,
                 .wrongTrustedIdentityKey:
                return Theme.iconImage(.safetyNumber16)
            case .sessionRefresh:
                return Theme.iconImage(.refresh16)
            case .invalidKeyException,
                 .missingKeyId,
                 .noSession,
                 .invalidMessage,
                 .duplicateMessage,
                 .invalidVersion,
                 .unknownContactBlockOffer,
                 .groupCreationFailed:
                return nil
            @unknown default:
                owsFailDebug("Unknown value.")
                return nil
            }
        } else if let infoMessage = interaction as? TSInfoMessage {
            switch infoMessage.messageType {
            case .userNotRegistered,
                 .typeSessionDidEnd,
                 .typeUnsupportedMessage,
                 .addToContactsOffer,
                 .addUserToProfileWhitelistOffer,
                 .addGroupToProfileWhitelistOffer:
                return nil
            case .typeGroupUpdate,
                 .typeGroupQuit:
                return Theme.iconImage(.group16)
            case .unknownProtocolVersion:
                guard let message = interaction as? OWSUnknownProtocolVersionMessage else {
                    owsFailDebug("Invalid interaction.")
                    return nil
                }
                return Theme.iconImage(message.isProtocolVersionUnknown ? .error16 : .check16)
            case .typeDisappearingMessagesUpdate:
                guard let message = interaction as? OWSDisappearingConfigurationUpdateInfoMessage else {
                    owsFailDebug("Invalid interaction.")
                    return nil
                }
                let areDisappearingMessagesEnabled = message.configurationIsEnabled
                return Theme.iconImage(areDisappearingMessagesEnabled ? .timer16 : .timerDisabled16)
            case .verificationStateChange:
                guard let message = interaction as? OWSVerificationStateChangeMessage else {
                    owsFailDebug("Invalid interaction.")
                    return nil
                }
                guard message.verificationState == .verified else {
                    return nil
                }
                return Theme.iconImage(.check16)
            case .userJoinedSignal:
                return Theme.iconImage(.heart16)
            case .syncedThread:
                return Theme.iconImage(.info16)
            case .profileUpdate:
                return Theme.iconImage(.profile16)
            @unknown default:
                owsFailDebug("Unknown value.")
                return nil
            }
        } else if let call = interaction as? TSCall {

            let offerTypeString: String
            switch call.offerType {
            case .audio:
                offerTypeString = "phone"
            case .video:
                offerTypeString = "video"
            }

            let directionString: String
            switch call.callType {
            case .incomingMissed,
                 .incomingMissedBecauseOfChangedIdentity,
                 .incomingBusyElsewhere,
                 .incomingDeclined,
                 .incomingDeclinedElsewhere:
                directionString = "x"
            case .incoming,
                 .incomingIncomplete,
                 .incomingAnsweredElsewhere:
                directionString = "incoming"
            case .outgoing,
                 .outgoingIncomplete,
                 .outgoingMissed:
                directionString = "outgoing"
            @unknown default:
                owsFailDebug("Unknown value.")
                return nil
            }

            let themeString = Theme.isDarkThemeEnabled ? "solid" : "outline"

            let imageName = "\(offerTypeString)-\(directionString)-\(themeString)-16"
            return UIImage(named: imageName)
        } else if nil != interaction as? OWSGroupCallMessage {
            let imageName = Theme.isDarkThemeEnabled ? "video-solid-16" : "video-outline-16"
            return UIImage(named: imageName)
        } else {
            owsFailDebug("Unknown interaction type: \(type(of: interaction))")
            return nil
        }
    }

    private static func iconName(forGroupUpdateType groupUpdateType: GroupUpdateType) -> String {
        switch groupUpdateType {
        case .userMembershipState_left:
            return Theme.iconName(.leave16)
        case .userMembershipState_removed:
            return Theme.iconName(.memberRemove16)
        case .userMembershipState_invited,
             .userMembershipState_added,
             .userMembershipState_invitesNew:
            return Theme.iconName(.memberAdded16)
        case .groupCreated,
             .generic,
             .debug,
             .userMembershipState,
             .userMembershipState_invalidInvitesRemoved,
             .userMembershipState_invalidInvitesAdded,
             .groupInviteLink,
             .groupGroupLinkPromotion:
            return Theme.iconName(.group16)
        case .userMembershipState_invitesDeclined,
             .userMembershipState_invitesRevoked:
            return Theme.iconName(.memberDeclined16)
        case .accessAttributes,
             .accessMembers,
             .userRole:
            return Theme.iconName(.megaphone16)
        case .groupName:
            return Theme.iconName(.compose16)
        case .groupAvatar:
            return Theme.iconName(.photo16)
        case .disappearingMessagesState,
             .disappearingMessagesState_enabled:
            return Theme.iconName(.timer16)
        case .disappearingMessagesState_disabled:
            return Theme.iconName(.timerDisabled16)
        case .groupMigrated:
            return Theme.iconName(.megaphone16)
        case .groupMigrated_usersInvited:
            return Theme.iconName(.memberAdded16)
        case .groupMigrated_usersDropped:
            return Theme.iconName(.group16)
        }
    }

    // MARK: - Actions

    static func action(forInteraction interaction: TSInteraction,
                       threadViewModel: ThreadViewModel,
                       currentCallThreadId: String?,
                       transaction: SDSAnyReadTransaction) -> CVMessageAction? {

        let thread = threadViewModel.threadRecord

        if let errorMessage = interaction as? TSErrorMessage {
            return action(forErrorMessage: errorMessage)
        } else if let infoMessage = interaction as? TSInfoMessage {
            return action(forInfoMessage: infoMessage, transaction: transaction)
        } else if let call = interaction as? TSCall {
            return action(forCall: call, thread: thread, transaction: transaction)
        } else if let groupCall = interaction as? OWSGroupCallMessage {
            return action(forGroupCall: groupCall,
                          threadViewModel: threadViewModel,
                          currentCallThreadId: currentCallThreadId)
        } else {
            owsFailDebug("Invalid interaction.")
            return nil
        }
    }

    private static func action(forErrorMessage message: TSErrorMessage) -> CVMessageAction? {
        switch message.errorType {
        case .nonBlockingIdentityChange:
            guard let address = message.recipientAddress else {
                owsFailDebug("Missing address.")
                return nil
            }

            return CVMessageAction(title: NSLocalizedString("SYSTEM_MESSAGE_ACTION_VERIFY_SAFETY_NUMBER",
                                                            comment: "Label for button to verify a user's safety number."),
                                   accessibilityIdentifier: "verify_safety_number",
                                   action: .cvc_didTapNonBlockingIdentityChange(address: address))
        case .wrongTrustedIdentityKey:
            guard let message = message as? TSInvalidIdentityKeyErrorMessage else {
                owsFailDebug("Invalid interaction.")
                return nil
            }
            return Action(title: NSLocalizedString("SYSTEM_MESSAGE_ACTION_VERIFY_SAFETY_NUMBER",
                                                   comment: "Label for button to verify a user's safety number."),
                          accessibilityIdentifier: "verify_safety_number",
                          action: .cvc_didTapInvalidIdentityKeyErrorMessage(errorMessage: message))
        case .invalidKeyException,
             .missingKeyId,
             .noSession,
             .invalidMessage:
            return Action(title: NSLocalizedString("FINGERPRINT_SHRED_KEYMATERIAL_BUTTON",
                                                   comment: "Label for button to reset a session."),
                          accessibilityIdentifier: "reset_session",
                          action: .cvc_didTapCorruptedMessage(errorMessage: message))
        case .sessionRefresh:
            return Action(title: CommonStrings.learnMore,
                          accessibilityIdentifier: "learn_more",
                          action: .cvc_didTapSessionRefreshMessage(errorMessage: message))
        case .duplicateMessage,
             .invalidVersion:
            return nil
        case .unknownContactBlockOffer:
            owsFailDebug("TSErrorMessageUnknownContactBlockOffer")
            return nil
        case .groupCreationFailed:
            return Action(title: CommonStrings.retryButton,
                          accessibilityIdentifier: "retry_send_group",
                          action: .cvc_didTapResendGroupUpdate(errorMessage: message))
        @unknown default:
            owsFailDebug("Unknown value.")
            return nil
        }
    }

    private static func action(forInfoMessage infoMessage: TSInfoMessage,
                               transaction: SDSAnyReadTransaction) -> CVMessageAction? {

        switch infoMessage.messageType {
        case .userNotRegistered,
             .typeSessionDidEnd:
            return nil
        case .typeUnsupportedMessage:
            // Unused.
            return nil
        case .addToContactsOffer:
            // Unused.
            owsFailDebug("TSInfoMessageAddToContactsOffer")
            return nil
        case .addUserToProfileWhitelistOffer:
            // Unused.
            owsFailDebug("TSInfoMessageAddUserToProfileWhitelistOffer")
            return nil
        case .addGroupToProfileWhitelistOffer:
            // Unused.
            owsFailDebug("TSInfoMessageAddGroupToProfileWhitelistOffer")
            return nil
        case .typeGroupUpdate:
            guard let newGroupModel = infoMessage.newGroupModel else {
                return nil
            }
            if newGroupModel.wasJustCreatedByLocalUserV2 {
                return Action(title: NSLocalizedString("GROUPS_INVITE_FRIENDS_BUTTON",
                                                       comment: "Label for 'invite friends to group' button."),
                              accessibilityIdentifier: "group_invite_friends",
                              action: .cvc_didTapGroupInviteLinkPromotion(groupModel: newGroupModel))
            }
            guard let oldGroupModel = infoMessage.oldGroupModel else {
                return nil
            }

            guard let groupUpdates = infoMessage.groupUpdateItems(transaction: transaction),
                  !groupUpdates.isEmpty else {
                return nil
            }

            for groupUpdate in groupUpdates {
                if groupUpdate.type == .groupMigrated {
                    return Action(title: CommonStrings.learnMore,
                                  accessibilityIdentifier: "group_migration_learn_more",
                                  action: .cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: infoMessage,
                                                                                            oldGroupModel: oldGroupModel,
                                                                                            newGroupModel: newGroupModel))
                }
            }

            var newlyRequestingMembers = Set<SignalServiceAddress>()
            newlyRequestingMembers.formUnion(newGroupModel.groupMembership.requestingMembers)
            newlyRequestingMembers.subtract(oldGroupModel.groupMembership.requestingMembers)

            guard !newlyRequestingMembers.isEmpty else {
                return nil
            }
            let title = (newlyRequestingMembers.count > 1
                            ? NSLocalizedString("GROUPS_VIEW_REQUESTS_BUTTON",
                                                comment: "Label for button that lets the user view the requests to join the group.")
                            : NSLocalizedString("GROUPS_VIEW_REQUEST_BUTTON",
                                                comment: "Label for button that lets the user view the request to join the group."))
            return Action(title: title,
                          accessibilityIdentifier: "show_group_requests_button",
                          action: .cvc_didTapShowConversationSettingsAndShowMemberRequests)
        case .typeGroupQuit:
            return nil
        case .unknownProtocolVersion:
            guard let message = infoMessage as? OWSUnknownProtocolVersionMessage else {
                owsFailDebug("Unexpected message type.")
                return nil
            }
            guard message.isProtocolVersionUnknown else {
                return nil
            }
            return Action(title: NSLocalizedString("UNKNOWN_PROTOCOL_VERSION_UPGRADE_BUTTON",
                                                   comment: "Label for button that lets users upgrade the app."),
                          accessibilityIdentifier: "show_upgrade_app_ui",
                          action: .cvc_didTapShowUpgradeAppUI)
        case .typeDisappearingMessagesUpdate,
             .verificationStateChange,
             .userJoinedSignal,
             .syncedThread:
            return nil
        case .profileUpdate:
            guard let profileChangeAddress = infoMessage.profileChangeAddress else {
                owsFailDebug("Missing profileChangeAddress.")
                return nil
            }
            guard let profileChangeNewNameComponents = infoMessage.profileChangeNewNameComponents else {
                return nil
            }
            guard Self.contactsManager.isSystemContact(address: profileChangeAddress) else {
                return nil
            }
            let systemContactName = Self.contactsManager.nameFromSystemContacts(for: profileChangeAddress,
                                                                                transaction: transaction)
            let newProfileName = PersonNameComponentsFormatter.localizedString(from: profileChangeNewNameComponents,
                                                                               style: .`default`,
                                                                               options: [])
            let currentProfileName = Self.profileManager.fullName(for: profileChangeAddress,
                                                                  transaction: transaction)

            // Don't show the update contact button if the system contact name
            // is already equivalent to the new profile name.
            guard systemContactName != newProfileName else {
                return nil
            }

            // If the new profile name is not the current profile name, it's no
            // longer relevant to ask you to update your contact.
            guard currentProfileName != newProfileName else {
                return nil
            }

            return Action(title: NSLocalizedString("UPDATE_CONTACT_ACTION", comment: "Action sheet item"),
                          accessibilityIdentifier: "update_contact",
                          action: .cvc_didTapUpdateSystemContact(address: profileChangeAddress,
                                                                 newNameComponents: profileChangeNewNameComponents))
        @unknown default:
            owsFailDebug("Unknown value.")
            return nil
        }
    }

    private static func action(forCall call: TSCall,
                               thread: TSThread,
                               transaction: SDSAnyReadTransaction) -> CVMessageAction? {

        // TODO: Respect -canCall from ConversationViewController

        let hasPendingMessageRequest = {
            thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)
        }

        switch call.callType {
        case .incoming,
             .incomingMissed,
             .incomingMissedBecauseOfChangedIdentity,
             .incomingDeclined,
             .incomingAnsweredElsewhere,
             .incomingDeclinedElsewhere,
             .incomingBusyElsewhere:
            guard !hasPendingMessageRequest() else {
                return nil
            }
            // TODO: cvc_didTapGroupCall?
            return Action(title: NSLocalizedString("CALLBACK_BUTTON_TITLE", comment: "notification action"),
                          accessibilityIdentifier: "call_back",
                          action: .cvc_didTapIndividualCall(call: call))
        case .outgoing,
             .outgoingMissed:
            guard !hasPendingMessageRequest() else {
                return nil
            }
            // TODO: cvc_didTapGroupCall?
            return Action(title: NSLocalizedString("CALL_AGAIN_BUTTON_TITLE",
                                                   comment: "Label for button that lets users call a contact again."),
                          accessibilityIdentifier: "call_again",
                          action: .cvc_didTapIndividualCall(call: call))
        case .outgoingIncomplete,
             .incomingIncomplete:
            return nil
        @unknown default:
            owsFailDebug("Unknown value.")
            return nil
        }
    }

    private static func action(forGroupCall groupCallMessage: OWSGroupCallMessage,
                               threadViewModel: ThreadViewModel,
                               currentCallThreadId: String?) -> CVMessageAction? {

        let thread = threadViewModel.threadRecord
        // Assume the current thread supports calling if we have no delegate. This ensures we always
        // overestimate cell measurement in cases where the current thread doesn't support calling.
        let isCallingSupported = ConversationViewController.canCall(threadViewModel: threadViewModel)
        let isCallActive = (!groupCallMessage.hasEnded && !groupCallMessage.joinedMemberAddresses.isEmpty)

        guard isCallingSupported, isCallActive else {
            return nil
        }

        // TODO: We need to touch thread whenever current call changes.
        let isCurrentCallForThread = currentCallThreadId == thread.uniqueId

        let joinTitle = NSLocalizedString("GROUP_CALL_JOIN_BUTTON", comment: "Button to join an ongoing group call")
        let returnTitle = NSLocalizedString("CALL_RETURN_BUTTON", comment: "Button to return to the current call")
        let title = isCurrentCallForThread ? returnTitle : joinTitle

        return Action(title: title,
                      accessibilityIdentifier: "group_call_button",
                      action: .cvc_didTapGroupCall)
    }
}
