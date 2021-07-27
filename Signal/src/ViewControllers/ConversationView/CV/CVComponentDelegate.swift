//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum CVAttachmentTapAction: Int {
    case handledByDelegate
    case `default`
}

// TODO: Remove cvc_ prefix once we've removed old CV logic.
@objc
public protocol CVComponentDelegate {

    // MARK: - Body Text Items

    func cvc_didTapBodyTextItem(_ item: CVBodyTextLabel.ItemObject)

    func cvc_didLongPressBodyTextItem(_ item: CVBodyTextLabel.ItemObject)

    // MARK: - Long Press

    func cvc_didLongPressTextViewItem(_ cell: CVCell,
                                      itemViewModel: CVItemViewModelImpl,
                                      shouldAllowReply: Bool)

    func cvc_didLongPressMediaViewItem(_ cell: CVCell,
                                       itemViewModel: CVItemViewModelImpl,
                                       shouldAllowReply: Bool)

    func cvc_didLongPressQuote(_ cell: CVCell,
                               itemViewModel: CVItemViewModelImpl,
                               shouldAllowReply: Bool)

    func cvc_didLongPressSystemMessage(_ cell: CVCell,
                                       itemViewModel: CVItemViewModelImpl)

    func cvc_didLongPressSticker(_ cell: CVCell,
                                 itemViewModel: CVItemViewModelImpl,
                                 shouldAllowReply: Bool)

    func cvc_didChangeLongpress(_ itemViewModel: CVItemViewModelImpl)

    func cvc_didEndLongpress(_ itemViewModel: CVItemViewModelImpl)

    func cvc_didCancelLongpress(_ itemViewModel: CVItemViewModelImpl)

    // MARK: -

    func cvc_didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl)

    func cvc_didTapSenderAvatar(_ interaction: TSInteraction)

    func cvc_shouldAllowReplyForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool

    func cvc_didTapReactions(reactionState: InteractionReactionState,
                             message: TSMessage)

    var cvc_hasPendingMessageRequest: Bool { get }

    func cvc_didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl)

    func cvc_didTapFailedOrPendingDownloads(_ message: TSMessage)

    // MARK: - Messages

    func cvc_didTapBodyMedia(itemViewModel: CVItemViewModelImpl,
                             attachmentStream: TSAttachmentStream,
                             imageView: UIView)

    func cvc_didTapGenericAttachment(_ attachment: CVComponentGenericAttachment) -> CVAttachmentTapAction

    func cvc_didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel)

    func cvc_didTapLinkPreview(_ linkPreview: OWSLinkPreview)

    func cvc_didTapContactShare(_ contactShare: ContactShareViewModel)

    func cvc_didTapSendMessage(toContactShare contactShare: ContactShareViewModel)

    func cvc_didTapSendInvite(toContactShare contactShare: ContactShareViewModel)

    func cvc_didTapAddToContacts(contactShare: ContactShareViewModel)

    func cvc_didTapStickerPack(_ stickerPackInfo: StickerPackInfo)

    func cvc_didTapGroupInviteLink(url: URL)

    func cvc_didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl)

    func cvc_prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl)

    typealias EndCellAnimation = () -> Void
    func cvc_beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation

    var view: UIView { get }

    var isConversationPreview: Bool { get }

    var wallpaperBlurProvider: WallpaperBlurProvider? { get }

    // MARK: - Selection

    var isShowingSelectionUI: Bool { get }

    func cvc_isMessageSelected(_ interaction: TSInteraction) -> Bool

    func cvc_didSelectViewItem(_ itemViewModel: CVItemViewModelImpl)

    func cvc_didDeselectViewItem(_ itemViewModel: CVItemViewModelImpl)

    // MARK: - System Cell

    func cvc_didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress)

    func cvc_didTapUnverifiedIdentityChange(_ address: SignalServiceAddress)

    func cvc_didTapInvalidIdentityKeyErrorMessage(_ message: TSInvalidIdentityKeyErrorMessage)

    func cvc_didTapCorruptedMessage(_ message: TSErrorMessage)

    func cvc_didTapSessionRefreshMessage(_ message: TSErrorMessage)

    // See: resendGroupUpdate
    func cvc_didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage)

    func cvc_didTapShowFingerprint(_ address: SignalServiceAddress)

    func cvc_didTapIndividualCall(_ call: TSCall)

    func cvc_didTapGroupCall()

    func cvc_didTapPendingOutgoingMessage(_ message: TSOutgoingMessage)

    func cvc_didTapFailedOutgoingMessage(_ message: TSOutgoingMessage)

    func cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: TSInfoMessage,
                                                          oldGroupModel: TSGroupModel,
                                                          newGroupModel: TSGroupModel)

    func cvc_didTapGroupInviteLinkPromotion(groupModel: TSGroupModel)

    func cvc_didTapViewGroupDescription(groupModel: TSGroupModel?)

    func cvc_didTapShowConversationSettings()

    func cvc_didTapShowConversationSettingsAndShowMemberRequests()

    func cvc_didTapShowUpgradeAppUI()

    func cvc_didTapUpdateSystemContact(_ address: SignalServiceAddress,
                                       newNameComponents: PersonNameComponents)

    func cvc_didTapViewOnceAttachment(_ interaction: TSInteraction)

    func cvc_didTapViewOnceExpired(_ interaction: TSInteraction)

    func cvc_didTapUnknownThreadWarningGroup()
    func cvc_didTapUnknownThreadWarningContact()
    func cvc_didTapDeliveryIssueWarning(_ message: TSErrorMessage)
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
        case none
        case cvc_didTapPreviouslyVerifiedIdentityChange(address: SignalServiceAddress)
        case cvc_didTapUnverifiedIdentityChange(address: SignalServiceAddress)
        case cvc_didTapInvalidIdentityKeyErrorMessage(errorMessage: TSInvalidIdentityKeyErrorMessage)
        case cvc_didTapCorruptedMessage(errorMessage: TSErrorMessage)
        case cvc_didTapSessionRefreshMessage(errorMessage: TSErrorMessage)
        case cvc_didTapResendGroupUpdate(errorMessage: TSErrorMessage)
        case cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: TSInfoMessage,
                                                              oldGroupModel: TSGroupModel,
                                                              newGroupModel: TSGroupModel)
        case cvc_didTapViewGroupDescription(groupModel: TSGroupModel?)
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
        case cvc_didTapUnknownThreadWarningGroup
        case cvc_didTapUnknownThreadWarningContact
        case cvc_didTapDeliveryIssueWarning(errorMessage: TSErrorMessage)

        func perform(delegate: CVComponentDelegate) {
            switch self {
            case .none:
                break
            case .cvc_didTapPreviouslyVerifiedIdentityChange(let address):
                delegate.cvc_didTapPreviouslyVerifiedIdentityChange(address)
            case .cvc_didTapUnverifiedIdentityChange(let address):
                delegate.cvc_didTapUnverifiedIdentityChange(address)
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
            case .cvc_didTapViewGroupDescription(let groupModel):
                delegate.cvc_didTapViewGroupDescription(groupModel: groupModel)
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
            case .cvc_didTapUnknownThreadWarningGroup:
                delegate.cvc_didTapUnknownThreadWarningGroup()
            case .cvc_didTapUnknownThreadWarningContact:
                delegate.cvc_didTapUnknownThreadWarningContact()
            case .cvc_didTapDeliveryIssueWarning(let errorMessage):
                delegate.cvc_didTapDeliveryIssueWarning(errorMessage)
            }
        }
    }
}
