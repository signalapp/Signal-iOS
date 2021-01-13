//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// TODO: Remove cvc_ prefix once we've removed old CV logic.
@objc
public protocol CVComponentDelegate {

    // MARK: - Long Press

    @objc
    func cvc_didLongPressTextViewItem(_ cell: CVCell,
                                      itemViewModel: CVItemViewModelImpl,
                                      shouldAllowReply: Bool)

    @objc
    func cvc_didLongPressMediaViewItem(_ cell: CVCell,
                                       itemViewModel: CVItemViewModelImpl,
                                       shouldAllowReply: Bool)

    @objc
    func cvc_didLongPressQuote(_ cell: CVCell,
                               itemViewModel: CVItemViewModelImpl,
                               shouldAllowReply: Bool)

    @objc
    func cvc_didLongPressSystemMessage(_ cell: CVCell,
                                       itemViewModel: CVItemViewModelImpl)

    @objc
    func cvc_didLongPressSticker(_ cell: CVCell,
                                 itemViewModel: CVItemViewModelImpl,
                                 shouldAllowReply: Bool)

    @objc
    func cvc_didChangeLongpress(_ itemViewModel: CVItemViewModelImpl)

    @objc
    func cvc_didEndLongpress(_ itemViewModel: CVItemViewModelImpl)

    @objc
    func cvc_didCancelLongpress(_ itemViewModel: CVItemViewModelImpl)

    // MARK: -

    @objc
    func cvc_didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl)

    @objc
    func cvc_didTapSenderAvatar(_ interaction: TSInteraction)

    @objc
    func cvc_shouldAllowReplyForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool

    @objc
    func cvc_didTapReactions(reactionState: InteractionReactionState,
                             message: TSMessage)

    @objc
    var cvc_hasPendingMessageRequest: Bool { get }

    @objc
    func cvc_didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl)

    @objc
    func cvc_didTapFailedOrPendingDownloads(_ message: TSMessage)

    // MARK: - Messages

    func cvc_didTapBodyMedia(itemViewModel: CVItemViewModelImpl,
                             attachmentStream: TSAttachmentStream,
                             imageView: UIView)

    func cvc_didTapGenericAttachment(_ attachment: CVComponentGenericAttachment)

    func cvc_didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel)

    func cvc_didTapLinkPreview(_ linkPreview: OWSLinkPreview)

    func cvc_didTapContactShare(_ contactShare: ContactShareViewModel)

    func cvc_didTapSendMessage(toContactShare contactShare: ContactShareViewModel)

    func cvc_didTapSendInvite(toContactShare contactShare: ContactShareViewModel)

    func cvc_didTapAddToContacts(contactShare: ContactShareViewModel)

    func cvc_didTapStickerPack(_ stickerPackInfo: StickerPackInfo)

    func cvc_didTapGroupInviteLink(url: URL)

    func cvc_didTapMention(_ mention: Mention)

    // MARK: - Selection

    @objc
    var isShowingSelectionUI: Bool { get }

    @objc
    func cvc_isMessageSelected(_ interaction: TSInteraction) -> Bool

    @objc
    func cvc_didSelectViewItem(_ itemViewModel: CVItemViewModelImpl)

    @objc
    func cvc_didDeselectViewItem(_ itemViewModel: CVItemViewModelImpl)

    // MARK: - System Cell

    @objc
    func cvc_didTapNonBlockingIdentityChange(_ address: SignalServiceAddress)

    @objc
    func cvc_didTapInvalidIdentityKeyErrorMessage(_ message: TSInvalidIdentityKeyErrorMessage)

    @objc
    func cvc_didTapCorruptedMessage(_ message: TSErrorMessage)

    @objc
    func cvc_didTapSessionRefreshMessage(_ message: TSErrorMessage)

    // See: resendGroupUpdate
    @objc
    func cvc_didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage)

    @objc
    func cvc_didTapShowFingerprint(_ address: SignalServiceAddress)

    @objc
    func cvc_didTapIndividualCall(_ call: TSCall)

    @objc
    func cvc_didTapGroupCall()

    @objc
    func cvc_didTapFailedOutgoingMessage(_ message: TSOutgoingMessage)

    @objc
    func cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: TSInfoMessage,
                                                          oldGroupModel: TSGroupModel,
                                                          newGroupModel: TSGroupModel)

    @objc
    func cvc_didTapGroupInviteLinkPromotion(groupModel: TSGroupModel)

    @objc
    func cvc_didTapShowConversationSettings()

    @objc
    func cvc_didTapShowConversationSettingsAndShowMemberRequests()

    @objc
    func cvc_didTapShowUpgradeAppUI()

    @objc
    func cvc_didTapUpdateSystemContact(_ address: SignalServiceAddress,
                                       newNameComponents: PersonNameComponents)

    @objc
    func cvc_didTapViewOnceAttachment(_ interaction: TSInteraction)

    @objc
    func cvc_didTapViewOnceExpired(_ interaction: TSInteraction)
}

// MARK: -

struct CVMessageAction: Equatable {
    let title: String
    let accessibilityIdentifier: String
    let action: Action

    func perform(delegate: CVComponentDelegate) {
        action.perform(delegate: delegate)
    }

    enum Action: Equatable {
        case cvc_didTapNonBlockingIdentityChange(address: SignalServiceAddress)
        case cvc_didTapInvalidIdentityKeyErrorMessage(errorMessage: TSInvalidIdentityKeyErrorMessage)
        case cvc_didTapCorruptedMessage(errorMessage: TSErrorMessage)
        case cvc_didTapSessionRefreshMessage(errorMessage: TSErrorMessage)
        case cvc_didTapResendGroupUpdate(errorMessage: TSErrorMessage)
        case cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: TSInfoMessage,
                                                              oldGroupModel: TSGroupModel,
                                                              newGroupModel: TSGroupModel)
        case cvc_didTapGroupInviteLinkPromotion(groupModel: TSGroupModel)
        case cvc_didTapShowConversationSettingsAndShowMemberRequests
        case cvc_didTapShowUpgradeAppUI
        case cvc_didTapUpdateSystemContact(address: SignalServiceAddress,
                                           newNameComponents: PersonNameComponents)
        case cvc_didTapIndividualCall(call: TSCall)
        case cvc_didTapGroupCall
        case cvc_didTapSendMessage(contactShare: ContactShareViewModel)
        case cvc_didTapSendInvite(contactShare: ContactShareViewModel)
        case cvc_didTapAddToContacts(contactShare: ContactShareViewModel)

        func perform(delegate: CVComponentDelegate) {
            switch self {
            case .cvc_didTapNonBlockingIdentityChange(let address):
                delegate.cvc_didTapNonBlockingIdentityChange(address)
            case .cvc_didTapInvalidIdentityKeyErrorMessage(let errorMessage):
                delegate.cvc_didTapInvalidIdentityKeyErrorMessage(errorMessage)
            case .cvc_didTapCorruptedMessage(let errorMessage):
                delegate.cvc_didTapCorruptedMessage(errorMessage)
            case .cvc_didTapSessionRefreshMessage(let errorMessage):
                delegate.cvc_didTapSessionRefreshMessage(errorMessage)
            case .cvc_didTapResendGroupUpdate(let errorMessage):
                delegate.cvc_didTapResendGroupUpdateForErrorMessage(errorMessage)
            case .cvc_didTapShowGroupMigrationLearnMoreActionSheet(let infoMessage,
                                                                   let oldGroupModel,
                                                                   let newGroupModel):
                delegate.cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: infoMessage,
                                                                          oldGroupModel: oldGroupModel,
                                                                          newGroupModel: newGroupModel)
            case .cvc_didTapGroupInviteLinkPromotion(let groupModel):
                delegate.cvc_didTapGroupInviteLinkPromotion(groupModel: groupModel)
            case .cvc_didTapShowConversationSettingsAndShowMemberRequests:
                delegate.cvc_didTapShowConversationSettingsAndShowMemberRequests()
            case .cvc_didTapShowUpgradeAppUI:
                delegate.cvc_didTapShowUpgradeAppUI()
            case .cvc_didTapUpdateSystemContact(let address, let newNameComponents):
                delegate.cvc_didTapUpdateSystemContact(address, newNameComponents: newNameComponents)
            case .cvc_didTapIndividualCall(let call):
                delegate.cvc_didTapIndividualCall(call)
            case .cvc_didTapGroupCall:
                delegate.cvc_didTapGroupCall()
            case .cvc_didTapSendMessage(let contactShare):
                delegate.cvc_didTapSendMessage(toContactShare: contactShare)
            case .cvc_didTapSendInvite(let contactShare):
                delegate.cvc_didTapSendInvite(toContactShare: contactShare)
            case .cvc_didTapAddToContacts(let contactShare):
                delegate.cvc_didTapAddToContacts(contactShare: contactShare)
            }
        }
    }
}
