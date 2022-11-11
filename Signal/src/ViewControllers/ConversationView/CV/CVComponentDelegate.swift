//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public enum CVAttachmentTapAction: Int {
    case handledByDelegate
    case `default`
}

// TODO: can remove the cvc_ prefix, was necessary when this was @objc
public protocol CVComponentDelegate: AnyObject {

    func cvc_enqueueReload()

    func cvc_enqueueReloadWithoutCaches()

    // MARK: - Body Text Items

    func cvc_didTapBodyTextItem(_ item: CVTextLabel.Item)

    func cvc_didLongPressBodyTextItem(_ item: CVTextLabel.Item)

    // MARK: - System Message Items

    func cvc_didTapSystemMessageItem(_ item: CVTextLabel.Item)

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

    func cvc_didTapBrokenVideo()

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

    func cvc_didTapProxyLink(url: URL)

    func cvc_didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl)

    func cvc_prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl)

    typealias EndCellAnimation = () -> Void
    func cvc_beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation

    var view: UIView! { get }

    var isConversationPreview: Bool { get }

    var wallpaperBlurProvider: WallpaperBlurProvider? { get }

    // MARK: - Gift Badges

    /// Invoked just before a gift is wrapped.
    ///
    /// This allows the view controller to indicate that a particular gift
    /// shouldn't be wrapped (or that *no* gifts should be wrapped, by always
    /// returning false).
    ///
    /// This may not be invoked if the gift has already been redeemed.
    ///
    /// - Parameter messageUniqueId: The gift's TSMessage's uniqueId.
    /// - Returns: Whether or not the gift should be wrapped.
    func cvc_willWrapGift(_ messageUniqueId: String) -> Bool

    /// Invoked just before a gift is shaken.
    ///
    /// This allows the view controller to indicate that a particular gift
    /// shouldn't be shaken (or that it shouldn’t be shaken again).
    ///
    /// - Parameter messageUniqueId: The gift's TSMessage's uniqueId.
    /// - Returns: Whether or not the gift should be shaken.
    func cvc_willShakeGift(_ messageUniqueId: String) -> Bool

    /// Invoked just before a gift is unwrapped.
    func cvc_willUnwrapGift(_ itemViewModel: CVItemViewModelImpl)

    /// Invoked when the button on a gift is tapped.
    func cvc_didTapGiftBadge(_ itemViewModel: CVItemViewModelImpl, profileBadge: ProfileBadge, isExpired: Bool, isRedeemed: Bool)

    // MARK: - Selection

    var selectionState: CVSelectionState { get }

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

    func cvc_didTapBlockRequest(
        groupModel: TSGroupModelV2,
        requesterName: String,
        requesterUuid: UUID
    )

    func cvc_didTapShowUpgradeAppUI()

    func cvc_didTapUpdateSystemContact(_ address: SignalServiceAddress,
                                       newNameComponents: PersonNameComponents)
    func cvc_didTapPhoneNumberChange(uuid: UUID,
                                     phoneNumberOld: String,
                                     phoneNumberNew: String)

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
        case cvc_didTapBlockRequest(
            groupModel: TSGroupModelV2,
            requesterName: String,
            requesterUuid: UUID
        )
        case cvc_didTapShowUpgradeAppUI
        case cvc_didTapUpdateSystemContact(address: SignalServiceAddress,
                                           newNameComponents: PersonNameComponents)
        case cvc_didTapPhoneNumberChange(uuid: UUID,
                                         phoneNumberOld: String,
                                         phoneNumberNew: String)
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
            case .cvc_didTapBlockRequest(let groupModel, let requesterName, let requesterUuid):
                delegate.cvc_didTapBlockRequest(
                    groupModel: groupModel,
                    requesterName: requesterName,
                    requesterUuid: requesterUuid
                )
            case .cvc_didTapShowUpgradeAppUI:
                delegate.cvc_didTapShowUpgradeAppUI()
            case .cvc_didTapUpdateSystemContact(let address, let newNameComponents):
                delegate.cvc_didTapUpdateSystemContact(address, newNameComponents: newNameComponents)
            case .cvc_didTapPhoneNumberChange(let uuid, let phoneNumberOld, let phoneNumberNew):
                delegate.cvc_didTapPhoneNumberChange(uuid: uuid,
                                                     phoneNumberOld: phoneNumberOld,
                                                     phoneNumberNew: phoneNumberNew)
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
