//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

public enum CVAttachmentTapAction: Int {
    case handledByDelegate
    case `default`
}

public protocol CVComponentDelegate: AnyObject {

    func enqueueReload()

    func enqueueReloadWithoutCaches()

    // MARK: - Body Text Items

    func didTapBodyTextItem(_ item: CVTextLabel.Item)

    func didLongPressBodyTextItem(_ item: CVTextLabel.Item)

    // MARK: - System Message Items

    func didTapSystemMessageItem(_ item: CVTextLabel.Item)

    // MARK: - Long Press

    func didLongPressTextViewItem(_ cell: CVCell,
                                  itemViewModel: CVItemViewModelImpl,
                                  shouldAllowReply: Bool)

    func didLongPressMediaViewItem(_ cell: CVCell,
                                   itemViewModel: CVItemViewModelImpl,
                                   shouldAllowReply: Bool)

    func didLongPressQuote(_ cell: CVCell,
                           itemViewModel: CVItemViewModelImpl,
                           shouldAllowReply: Bool)

    func didLongPressSystemMessage(_ cell: CVCell,
                                   itemViewModel: CVItemViewModelImpl)

    func didLongPressSticker(_ cell: CVCell,
                             itemViewModel: CVItemViewModelImpl,
                             shouldAllowReply: Bool)

    func didChangeLongPress(_ itemViewModel: CVItemViewModelImpl)

    func didEndLongPress(_ itemViewModel: CVItemViewModelImpl)

    func didCancelLongPress(_ itemViewModel: CVItemViewModelImpl)

    // MARK: -

    func didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl)

    func didTapSenderAvatar(_ interaction: TSInteraction)

    func shouldAllowReplyForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool

    func didTapReactions(reactionState: InteractionReactionState,
                         message: TSMessage)

    var hasPendingMessageRequest: Bool { get }

    func didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl)

    func didTapFailedOrPendingDownloads(_ message: TSMessage)

    func didTapBrokenVideo()

    // MARK: - Messages

    func didTapBodyMedia(itemViewModel: CVItemViewModelImpl,
                         attachmentStream: TSAttachmentStream,
                         imageView: UIView)

    func didTapGenericAttachment(_ attachment: CVComponentGenericAttachment) -> CVAttachmentTapAction

    func didTapQuotedReply(_ quotedReply: QuotedReplyModel)

    func didTapLinkPreview(_ linkPreview: OWSLinkPreview)

    func didTapContactShare(_ contactShare: ContactShareViewModel)

    func didTapSendMessage(toContactShare contactShare: ContactShareViewModel)

    func didTapSendInvite(toContactShare contactShare: ContactShareViewModel)

    func didTapAddToContacts(contactShare: ContactShareViewModel)

    func didTapStickerPack(_ stickerPackInfo: StickerPackInfo)

    func didTapGroupInviteLink(url: URL)

    func didTapProxyLink(url: URL)

    func didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl)

    func didTapShowEditHistory(_ itemViewModel: CVItemViewModelImpl)

    func prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl)

    typealias EndCellAnimation = () -> Void
    func beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation

    var view: UIView! { get }

    var isConversationPreview: Bool { get }

    var wallpaperBlurProvider: WallpaperBlurProvider? { get }

    var spoilerReveal: SpoilerRevealState { get }

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
    func willWrapGift(_ messageUniqueId: String) -> Bool

    /// Invoked just before a gift is shaken.
    ///
    /// This allows the view controller to indicate that a particular gift
    /// shouldn't be shaken (or that it shouldn’t be shaken again).
    ///
    /// - Parameter messageUniqueId: The gift's TSMessage's uniqueId.
    /// - Returns: Whether or not the gift should be shaken.
    func willShakeGift(_ messageUniqueId: String) -> Bool

    /// Invoked just before a gift is unwrapped.
    func willUnwrapGift(_ itemViewModel: CVItemViewModelImpl)

    /// Invoked when the button on a gift is tapped.
    func didTapGiftBadge(_ itemViewModel: CVItemViewModelImpl, profileBadge: ProfileBadge, isExpired: Bool, isRedeemed: Bool)

    // MARK: - Selection

    var selectionState: CVSelectionState { get }

    // MARK: - System Cell

    func didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress)

    func didTapUnverifiedIdentityChange(_ address: SignalServiceAddress)

    func didTapInvalidIdentityKeyErrorMessage(_ message: TSInvalidIdentityKeyErrorMessage)

    func didTapCorruptedMessage(_ message: TSErrorMessage)

    func didTapSessionRefreshMessage(_ message: TSErrorMessage)

    // See: resendGroupUpdate
    func didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage)

    func didTapShowFingerprint(_ address: SignalServiceAddress)

    func didTapIndividualCall(_ call: TSCall)

    func didTapGroupCall()

    func didTapPendingOutgoingMessage(_ message: TSOutgoingMessage)

    func didTapFailedOutgoingMessage(_ message: TSOutgoingMessage)

    func didTapGroupMigrationLearnMore()

    func didTapGroupInviteLinkPromotion(groupModel: TSGroupModel)

    func didTapViewGroupDescription(groupModel: TSGroupModel?)

    func didTapShowConversationSettings()

    func didTapShowConversationSettingsAndShowMemberRequests()

    func didTapBlockRequest(
        groupModel: TSGroupModelV2,
        requesterName: String,
        requesterUuid: UUID
    )

    func didTapShowUpgradeAppUI()

    func didTapUpdateSystemContact(_ address: SignalServiceAddress,
                                   newNameComponents: PersonNameComponents)
    func didTapPhoneNumberChange(uuid: UUID,
                                 phoneNumberOld: String,
                                 phoneNumberNew: String)

    func didTapViewOnceAttachment(_ interaction: TSInteraction)

    func didTapViewOnceExpired(_ interaction: TSInteraction)

    func didTapUnknownThreadWarningGroup()
    func didTapUnknownThreadWarningContact()
    func didTapDeliveryIssueWarning(_ message: TSErrorMessage)
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
        case didTapPreviouslyVerifiedIdentityChange(address: SignalServiceAddress)
        case didTapUnverifiedIdentityChange(address: SignalServiceAddress)
        case didTapInvalidIdentityKeyErrorMessage(errorMessage: TSInvalidIdentityKeyErrorMessage)
        case didTapCorruptedMessage(errorMessage: TSErrorMessage)
        case didTapSessionRefreshMessage(errorMessage: TSErrorMessage)
        case didTapResendGroupUpdate(errorMessage: TSErrorMessage)
        case didTapGroupMigrationLearnMore
        case didTapViewGroupDescription(groupModel: TSGroupModel?)
        case didTapGroupInviteLinkPromotion(groupModel: TSGroupModel)
        case didTapShowConversationSettingsAndShowMemberRequests
        case didTapBlockRequest(groupModel: TSGroupModelV2, requesterName: String, requesterUuid: UUID)
        case didTapShowUpgradeAppUI
        case didTapUpdateSystemContact(address: SignalServiceAddress, newNameComponents: PersonNameComponents)
        case didTapPhoneNumberChange(uuid: UUID, phoneNumberOld: String, phoneNumberNew: String)
        case didTapIndividualCall(call: TSCall)
        case didTapGroupCall
        case didTapSendMessage(contactShare: ContactShareViewModel)
        case didTapSendInvite(contactShare: ContactShareViewModel)
        case didTapAddToContacts(contactShare: ContactShareViewModel)
        case didTapUnknownThreadWarningGroup
        case didTapUnknownThreadWarningContact
        case didTapDeliveryIssueWarning(errorMessage: TSErrorMessage)

        func perform(delegate: CVComponentDelegate) {
            switch self {
            case .none:
                break
            case .didTapPreviouslyVerifiedIdentityChange(let address):
                delegate.didTapPreviouslyVerifiedIdentityChange(address)
            case .didTapUnverifiedIdentityChange(let address):
                delegate.didTapUnverifiedIdentityChange(address)
            case .didTapInvalidIdentityKeyErrorMessage(let errorMessage):
                delegate.didTapInvalidIdentityKeyErrorMessage(errorMessage)
            case .didTapCorruptedMessage(let errorMessage):
                delegate.didTapCorruptedMessage(errorMessage)
            case .didTapSessionRefreshMessage(let errorMessage):
                delegate.didTapSessionRefreshMessage(errorMessage)
            case .didTapResendGroupUpdate(let errorMessage):
                delegate.didTapResendGroupUpdateForErrorMessage(errorMessage)
            case .didTapGroupMigrationLearnMore:
                delegate.didTapGroupMigrationLearnMore()
            case .didTapViewGroupDescription(let groupModel):
                delegate.didTapViewGroupDescription(groupModel: groupModel)
            case .didTapGroupInviteLinkPromotion(let groupModel):
                delegate.didTapGroupInviteLinkPromotion(groupModel: groupModel)
            case .didTapShowConversationSettingsAndShowMemberRequests:
                delegate.didTapShowConversationSettingsAndShowMemberRequests()
            case .didTapBlockRequest(let groupModel, let requesterName, let requesterUuid):
                delegate.didTapBlockRequest(groupModel: groupModel, requesterName: requesterName, requesterUuid: requesterUuid)
            case .didTapShowUpgradeAppUI:
                delegate.didTapShowUpgradeAppUI()
            case .didTapUpdateSystemContact(let address, let newNameComponents):
                delegate.didTapUpdateSystemContact(address, newNameComponents: newNameComponents)
            case .didTapPhoneNumberChange(let uuid, let phoneNumberOld, let phoneNumberNew):
                delegate.didTapPhoneNumberChange(uuid: uuid, phoneNumberOld: phoneNumberOld, phoneNumberNew: phoneNumberNew)
            case .didTapIndividualCall(let call):
                delegate.didTapIndividualCall(call)
            case .didTapGroupCall:
                delegate.didTapGroupCall()
            case .didTapSendMessage(let contactShare):
                delegate.didTapSendMessage(toContactShare: contactShare)
            case .didTapSendInvite(let contactShare):
                delegate.didTapSendInvite(toContactShare: contactShare)
            case .didTapAddToContacts(let contactShare):
                delegate.didTapAddToContacts(contactShare: contactShare)
            case .didTapUnknownThreadWarningGroup:
                delegate.didTapUnknownThreadWarningGroup()
            case .didTapUnknownThreadWarningContact:
                delegate.didTapUnknownThreadWarningContact()
            case .didTapDeliveryIssueWarning(let errorMessage):
                delegate.didTapDeliveryIssueWarning(errorMessage)
            }
        }
    }
}
