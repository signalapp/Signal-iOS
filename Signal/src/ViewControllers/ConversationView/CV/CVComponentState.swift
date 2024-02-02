//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MobileCoin
import SignalMessaging
import SignalServiceKit
import SignalUI

public class CVComponentState: Equatable, Dependencies {
    let messageCellType: CVMessageCellType

    struct SenderName: Equatable {
        let senderName: NSAttributedString
        let senderNameColor: UIColor
    }
    let senderName: SenderName?

    struct SenderAvatar: Equatable {
        let avatarDataSource: ConversationAvatarDataSource
    }
    let senderAvatar: SenderAvatar?

    enum BodyText: Equatable {
        case bodyText(displayableText: DisplayableText)

        // TODO: Should we have oversizeTextFailed?
        case oversizeTextDownloading

        // We use the "body text" component to
        // render the "remotely deleted" indicator.
        case remotelyDeleted

        var displayableText: DisplayableText? {
            if case .bodyText(let displayableText) = self {
                return displayableText
            }
            return nil
        }

        func textValue(isTextExpanded: Bool) -> CVTextValue? {
            switch self {
            case .bodyText(let displayableText):
                return displayableText.textValue(isTextExpanded: isTextExpanded)
            default:
                return nil
            }
        }

        var jumbomojiCount: UInt? {
            switch self {
            case .bodyText(let displayableText):
                return displayableText.jumbomojiCount
            default:
                return nil
            }
        }

        var isJumbomojiMessage: Bool {
            guard let jumbomojiCount = jumbomojiCount else {
                return false
            }
            return jumbomojiCount > 0
        }
    }
    let bodyText: BodyText?

    struct BodyMedia: Equatable {
        let items: [CVMediaAlbumItem]
        let mediaAlbumHasFailedAttachment: Bool
        let mediaAlbumHasPendingAttachment: Bool
    }
    let bodyMedia: BodyMedia?

    struct GenericAttachment: Equatable {
        let attachment: TSAttachment

        var attachmentStream: TSAttachmentStream? {
            attachment as? TSAttachmentStream
        }
        var attachmentPointer: TSAttachmentPointer? {
            attachment as? TSAttachmentPointer
        }
    }
    let genericAttachment: GenericAttachment?

    public struct PaymentAttachment: Equatable, Dependencies {
        let notification: TSPaymentNotification
        let model: TSPaymentModel?
        let otherUserShortName: String

        var status: TSPaymentState? { model?.paymentState }
    }
    var paymentAttachment: PaymentAttachment?

    // It's not practical to reload the audio cell every time
    // playback state or progress changes.  Therefore we only
    // capture the stable state related to the audio. Dynamic
    // state is obtained from CVAudioPlayer.
    //
    // NOTE: We use the existing AudioAttachment entity,
    //       not a custom struct.
    let audioAttachment: AudioAttachment?

    struct ViewOnce: Equatable {
        let viewOnceState: ViewOnceState
    }
    let viewOnce: ViewOnce?

    struct QuotedReply: Equatable {
        let viewState: QuotedMessageView.State

        var quotedReplyModel: QuotedReplyModel { viewState.quotedReplyModel }
    }
    let quotedReply: QuotedReply?

    enum Sticker: Equatable {
        case available(stickerMetadata: StickerMetadata,
                       attachmentStream: TSAttachmentStream)
        case downloading(attachmentPointer: TSAttachmentPointer)
        case failedOrPending(attachmentPointer: TSAttachmentPointer)

        public var stickerMetadata: StickerMetadata? {
            switch self {
            case .available(let stickerMetadata, _):
                return stickerMetadata
            case .downloading, .failedOrPending:
                return nil
            }
        }
        public var attachmentStream: TSAttachmentStream? {
            switch self {
            case .available(_, let attachmentStream):
                return attachmentStream
            case .downloading:
                return nil
            case .failedOrPending:
                return nil
            }
        }
        public var attachmentPointer: TSAttachmentPointer? {
            switch self {
            case .available:
                return nil
            case .downloading(let attachmentPointer):
                return attachmentPointer
            case .failedOrPending(let attachmentPointer):
                return attachmentPointer
            }
        }
    }
    let sticker: Sticker?

    struct ContactShare: Equatable {
        let state: CVContactShareView.State
    }
    let contactShare: ContactShare?

    struct LinkPreview: Equatable {
        // TODO: convert OWSLinkPreview to Swift?
        let linkPreview: OWSLinkPreview
        let linkPreviewAttachment: TSAttachment?
        let state: LinkPreviewState

        // MARK: - Equatable

        public static func == (lhs: LinkPreview, rhs: LinkPreview) -> Bool {
            return lhs.state === rhs.state
        }
    }
    let linkPreview: LinkPreview?

    struct GiftBadge: Equatable {
        let messageUniqueId: String
        let otherUserShortName: String
        let cachedBadge: CachedBadge
        let expirationDate: Date
        let redemptionState: OWSGiftBadgeRedemptionState
    }
    let giftBadge: GiftBadge?

    struct SystemMessage: Equatable {
        typealias ReferencedUser = CVTextLabel.ReferencedUserItem

        let title: NSAttributedString
        let titleColor: UIColor
        let titleSelectionBackgroundColor: UIColor
        let action: CVMessageAction?

        /// Represents users whose names appear in the title. Only applies to
        /// system messages in group threads.
        let namesInTitle: [ReferencedUser]

        init(
            title: NSAttributedString,
            titleColor: UIColor,
            titleSelectionBackgroundColor: UIColor,
            action: CVMessageAction?
        ) {
            let mutableTitle = NSMutableAttributedString(attributedString: title)
            mutableTitle.removeAttribute(
                .addressOfName,
                range: NSRange(location: 0, length: mutableTitle.length)
            )
            self.title = NSAttributedString(attributedString: mutableTitle)

            self.titleColor = titleColor
            self.titleSelectionBackgroundColor = titleSelectionBackgroundColor
            self.action = action

            self.namesInTitle = {
                // Extract the addresses for names in the string. These are only
                // stored for system messages in group threads.

                var referencedUsers = [ReferencedUser]()

                title.enumerateAddressesOfNames { address, range, _ in
                    if let address = address {
                        referencedUsers.append(ReferencedUser(
                            address: address,
                            range: range
                        ))
                    }
                }

                return referencedUsers
            }()
        }
    }
    let systemMessage: SystemMessage?

    struct DateHeader: Equatable {
    }
    let dateHeader: DateHeader?

    struct UnreadIndicator: Equatable {
    }
    let unreadIndicator: UnreadIndicator?

    struct Reactions: Equatable {
        let reactionState: InteractionReactionState
        let viewState: CVReactionCountsView.State
    }
    let reactions: Reactions?

    struct TypingIndicator: Equatable {
        let address: SignalServiceAddress
        let avatarDataSource: ConversationAvatarDataSource?
    }
    let typingIndicator: TypingIndicator?

    struct ThreadDetails: Equatable {
        let avatarDataSource: ConversationAvatarDataSource?
        let isAvatarBlurred: Bool
        let titleText: String
        let shouldShowVerifiedBadge: Bool
        let bioText: String?
        let detailsText: String?
        let mutualGroupsText: NSAttributedString?
        let groupDescriptionText: String?
    }
    let threadDetails: ThreadDetails?

    typealias UnknownThreadWarning = CVComponentState.SystemMessage
    let unknownThreadWarning: UnknownThreadWarning?

    typealias DefaultDisappearingMessageTimer = CVComponentState.SystemMessage
    let defaultDisappearingMessageTimer: DefaultDisappearingMessageTimer?

    struct BottomButtons: Equatable {
        let actions: [CVMessageAction]
    }
    let bottomButtons: BottomButtons?

    struct FailedOrPendingDownloads: Equatable {
        let attachmentPointers: [TSAttachmentPointer]
    }
    let failedOrPendingDownloads: FailedOrPendingDownloads?

    struct SendFailureBadge: Equatable {
        let color: UIColor
    }
    let sendFailureBadge: SendFailureBadge?

    fileprivate init(messageCellType: CVMessageCellType,
                     senderName: SenderName?,
                     senderAvatar: SenderAvatar?,
                     bodyText: BodyText?,
                     bodyMedia: BodyMedia?,
                     genericAttachment: GenericAttachment?,
                     paymentAttachment: PaymentAttachment?,
                     audioAttachment: AudioAttachment?,
                     viewOnce: ViewOnce?,
                     quotedReply: QuotedReply?,
                     sticker: Sticker?,
                     contactShare: ContactShare?,
                     linkPreview: LinkPreview?,
                     giftBadge: GiftBadge?,
                     systemMessage: SystemMessage?,
                     dateHeader: DateHeader?,
                     unreadIndicator: UnreadIndicator?,
                     reactions: Reactions?,
                     typingIndicator: TypingIndicator?,
                     threadDetails: ThreadDetails?,
                     unknownThreadWarning: UnknownThreadWarning?,
                     defaultDisappearingMessageTimer: DefaultDisappearingMessageTimer?,
                     bottomButtons: BottomButtons?,
                     failedOrPendingDownloads: FailedOrPendingDownloads?,
                     sendFailureBadge: SendFailureBadge?) {

        self.messageCellType = messageCellType
        self.senderName = senderName
        self.senderAvatar = senderAvatar
        self.bodyText = bodyText
        self.bodyMedia = bodyMedia
        self.genericAttachment = genericAttachment
        self.paymentAttachment = paymentAttachment
        self.audioAttachment = audioAttachment
        self.viewOnce = viewOnce
        self.quotedReply = quotedReply
        self.sticker = sticker
        self.contactShare = contactShare
        self.linkPreview = linkPreview
        self.giftBadge = giftBadge
        self.systemMessage = systemMessage
        self.dateHeader = dateHeader
        self.unreadIndicator = unreadIndicator
        self.reactions = reactions
        self.typingIndicator = typingIndicator
        self.threadDetails = threadDetails
        self.unknownThreadWarning = unknownThreadWarning
        self.defaultDisappearingMessageTimer = defaultDisappearingMessageTimer
        self.bottomButtons = bottomButtons
        self.failedOrPendingDownloads = failedOrPendingDownloads
        self.sendFailureBadge = sendFailureBadge
    }

    // MARK: - Equatable

    public static func == (lhs: CVComponentState, rhs: CVComponentState) -> Bool {
        return (lhs.messageCellType == rhs.messageCellType &&
                    lhs.senderName == rhs.senderName &&
                    lhs.senderAvatar == rhs.senderAvatar &&
                    lhs.bodyText == rhs.bodyText &&
                    lhs.bodyMedia == rhs.bodyMedia &&
                    lhs.genericAttachment == rhs.genericAttachment &&
                    lhs.paymentAttachment == rhs.paymentAttachment &&
                    lhs.audioAttachment == rhs.audioAttachment &&
                    lhs.viewOnce == rhs.viewOnce &&
                    lhs.quotedReply == rhs.quotedReply &&
                    lhs.sticker == rhs.sticker &&
                    lhs.contactShare == rhs.contactShare &&
                    lhs.linkPreview == rhs.linkPreview &&
                    lhs.giftBadge == rhs.giftBadge &&
                    lhs.systemMessage == rhs.systemMessage &&
                    lhs.dateHeader == rhs.dateHeader &&
                    lhs.unreadIndicator == rhs.unreadIndicator &&
                    lhs.reactions == rhs.reactions &&
                    lhs.typingIndicator == rhs.typingIndicator &&
                    lhs.threadDetails == rhs.threadDetails &&
                    lhs.unknownThreadWarning == rhs.unknownThreadWarning &&
                    lhs.defaultDisappearingMessageTimer == rhs.defaultDisappearingMessageTimer &&
                    lhs.bottomButtons == rhs.bottomButtons &&
                    lhs.failedOrPendingDownloads == rhs.failedOrPendingDownloads &&
                    lhs.sendFailureBadge == rhs.sendFailureBadge)
    }

    // MARK: - Building

    fileprivate struct Builder: CVItemBuilding {
        typealias SenderName = CVComponentState.SenderName
        typealias SenderAvatar = CVComponentState.SenderAvatar
        typealias BodyText = CVComponentState.BodyText
        typealias BodyMedia = CVComponentState.BodyMedia
        typealias GenericAttachment = CVComponentState.GenericAttachment
        typealias PaymentAttachment = CVComponentState.PaymentAttachment
        typealias ViewOnce = CVComponentState.ViewOnce
        typealias QuotedReply = CVComponentState.QuotedReply
        typealias Sticker = CVComponentState.Sticker
        typealias SystemMessage = CVComponentState.SystemMessage
        typealias ContactShare = CVComponentState.ContactShare
        typealias Reactions = CVComponentState.Reactions
        typealias LinkPreview = CVComponentState.LinkPreview
        typealias GiftBadge = CVComponentState.GiftBadge
        typealias DateHeader = CVComponentState.DateHeader
        typealias UnreadIndicator = CVComponentState.UnreadIndicator
        typealias TypingIndicator = CVComponentState.TypingIndicator
        typealias ThreadDetails = CVComponentState.ThreadDetails
        typealias UnknownThreadWarning = CVComponentState.UnknownThreadWarning
        typealias DefaultDisappearingMessageTimer = CVComponentState.DefaultDisappearingMessageTimer
        typealias FailedOrPendingDownloads = CVComponentState.FailedOrPendingDownloads
        typealias BottomButtons = CVComponentState.BottomButtons
        typealias SendFailureBadge = CVComponentState.SendFailureBadge

        let interaction: TSInteraction
        let itemBuildingContext: CVItemBuildingContext

        var revealedSpoilerIdsSnapshot: Set<StyleIdType> {
            return itemBuildingContext.viewStateSnapshot.spoilerReveal[.fromInteraction(interaction)] ?? Set()
        }

        var senderName: SenderName?
        var senderAvatar: SenderAvatar?
        var bodyText: BodyText?
        var bodyMedia: BodyMedia?
        var genericAttachment: GenericAttachment?
        var paymentAttachment: PaymentAttachment?
        var audioAttachment: AudioAttachment?
        var viewOnce: ViewOnce?
        var quotedReply: QuotedReply?
        var sticker: Sticker?
        var systemMessage: SystemMessage?
        var contactShare: ContactShare?
        var linkPreview: LinkPreview?
        var giftBadge: GiftBadge?
        var dateHeader: DateHeader?
        var unreadIndicator: UnreadIndicator?
        var typingIndicator: TypingIndicator?
        var threadDetails: ThreadDetails?
        var unknownThreadWarning: UnknownThreadWarning?
        var defaultDisappearingMessageTimer: DefaultDisappearingMessageTimer?
        var reactions: Reactions?
        var failedOrPendingDownloads: FailedOrPendingDownloads?
        var sendFailureBadge: SendFailureBadge?

        var bottomButtonsActions = [CVMessageAction]()

        init(interaction: TSInteraction, itemBuildingContext: CVItemBuildingContext) {
            self.interaction = interaction
            self.itemBuildingContext = itemBuildingContext
        }

        mutating func build() -> CVComponentState {
            var bottomButtons: BottomButtons?
            if !bottomButtonsActions.isEmpty {
                bottomButtons = BottomButtons(actions: bottomButtonsActions)
            }

            return CVComponentState(messageCellType: messageCellType,
                                    senderName: senderName,
                                    senderAvatar: senderAvatar,
                                    bodyText: bodyText,
                                    bodyMedia: bodyMedia,
                                    genericAttachment: genericAttachment,
                                    paymentAttachment: paymentAttachment,
                                    audioAttachment: audioAttachment,
                                    viewOnce: viewOnce,
                                    quotedReply: quotedReply,
                                    sticker: sticker,
                                    contactShare: contactShare,
                                    linkPreview: linkPreview,
                                    giftBadge: giftBadge,
                                    systemMessage: systemMessage,
                                    dateHeader: dateHeader,
                                    unreadIndicator: unreadIndicator,
                                    reactions: reactions,
                                    typingIndicator: typingIndicator,
                                    threadDetails: threadDetails,
                                    unknownThreadWarning: unknownThreadWarning,
                                    defaultDisappearingMessageTimer: defaultDisappearingMessageTimer,
                                    bottomButtons: bottomButtons,
                                    failedOrPendingDownloads: failedOrPendingDownloads,
                                    sendFailureBadge: sendFailureBadge)
        }

        // MARK: -

        lazy var isIncoming: Bool = {
            interaction as? TSIncomingMessage != nil
        }()

        lazy var isOutgoing: Bool = {
            interaction as? TSOutgoingMessage != nil
        }()

        lazy var messageCellType: CVMessageCellType = {
            if dateHeader != nil {
                return .dateHeader
            }
            if unreadIndicator != nil {
                return .unreadIndicator
            }
            if typingIndicator != nil {
                return .typingIndicator
            }
            if threadDetails != nil {
                return .threadDetails
            }
            if unknownThreadWarning != nil {
                return .unknownThreadWarning
            }
            if defaultDisappearingMessageTimer != nil {
                return .defaultDisappearingMessageTimer
            }
            if systemMessage != nil {
                return .systemMessage
            }
            if let sticker = self.sticker {
                return .stickerMessage
            }
            if viewOnce != nil {
                return .viewOnce
            }
            if contactShare != nil {
                return .contactShare
            }
            if audioAttachment != nil {
                return .audio
            }
            if genericAttachment != nil {
                return .genericAttachment
            }
            if paymentAttachment != nil {
                return .paymentAttachment
            }
            if giftBadge != nil {
                return .giftBadge
            }
            if bodyMedia != nil {
                return .bodyMedia
            }
            if bodyText != nil {
                return .textOnlyMessage
            }
            if quotedReply != nil {
                return .quoteOnlyMessage
            }

            owsFailDebug("Unknown state.")
            return .unknown
        }()
    }

    // MARK: - Convenience

    lazy var isSticker: Bool = {
        sticker != nil
    }()

    lazy var activeComponentStateKeys: Set<CVComponentKey> = {

        var result = Set<CVComponentKey>()

        if senderName != nil {
            result.insert(.senderName)
        }
        if senderAvatar != nil {
            result.insert(.senderAvatar)
        }
        if bodyText != nil {
            result.insert(.bodyText)
        }
        if bodyMedia != nil {
            result.insert(.bodyMedia)
        }
        if genericAttachment != nil {
            result.insert(.genericAttachment)
        }
        if paymentAttachment != nil {
            result.insert(.paymentAttachment)
        }
        if audioAttachment != nil {
            result.insert(.audioAttachment)
        }
        if viewOnce != nil {
            result.insert(.viewOnce)
        }
        if quotedReply != nil {
            result.insert(.quotedReply)
        }
        if sticker != nil {
            result.insert(.sticker)
        }
        if contactShare != nil {
            result.insert(.contactShare)
        }
        if linkPreview != nil {
            result.insert(.linkPreview)
        }
        if giftBadge != nil {
            result.insert(.giftBadge)
        }
        if systemMessage != nil {
            result.insert(.systemMessage)
        }
        if dateHeader != nil {
            result.insert(.dateHeader)
        }
        if unreadIndicator != nil {
            result.insert(.unreadIndicator)
        }
        if reactions != nil {
            result.insert(.reactions)
        }
        if typingIndicator != nil {
            result.insert(.typingIndicator)
        }
        if threadDetails != nil {
            result.insert(.threadDetails)
        }
        if unknownThreadWarning != nil {
            result.insert(.unknownThreadWarning)
        }
        if defaultDisappearingMessageTimer != nil {
            result.insert(.defaultDisappearingMessageTimer)
        }
        if bottomButtons != nil {
            result.insert(.bottomButtons)
        }
        if failedOrPendingDownloads != nil {
            result.insert(.failedOrPendingDownloads)
        }
        if sendFailureBadge != nil {
            result.insert(.sendFailureBadge)
        }
        return result
    }()

    lazy var isTextOnlyMessage: Bool = {
        let validKeys: [CVComponentKey] = [
            .senderName,
            .senderAvatar,
            .bodyText,
            .footer,
            .reactions,
            .sendFailureBadge
        ]
        return activeComponentStateKeys.isSubset(of: Set(validKeys))
    }()

    lazy var isBorderlessJumbomojiMessage: Bool = {
        isTextOnlyMessage && (bodyText?.isJumbomojiMessage == true)
    }()

    lazy var isBodyMediaOnlyMessage: Bool = {
        let validKeys: [CVComponentKey] = [
            .senderName,
            .senderAvatar,
            .bodyMedia,
            .footer,
            .reactions,
            .sendFailureBadge
        ]
        return activeComponentStateKeys.isSubset(of: Set(validKeys))
    }()

    lazy var isBorderlessBodyMediaMessage: Bool = {
        if isBodyMediaOnlyMessage,
           let bodyMedia = bodyMedia,
           bodyMedia.items.count == 1,
           let firstItem = bodyMedia.items.first,
           firstItem.attachmentType == .borderless
        {
            return true
        }
        return false
    }()
}

// MARK: -

extension CVComponentState {

    static func buildDateHeader(interaction: TSInteraction,
                                itemBuildingContext: CVItemBuildingContext) -> CVComponentState {
        var builder = CVComponentState.Builder(interaction: interaction,
                                               itemBuildingContext: itemBuildingContext)
        builder.dateHeader = DateHeader()
        return builder.build()
    }

    static func buildUnreadIndicator(interaction: TSInteraction,
                                     itemBuildingContext: CVItemBuildingContext) -> CVComponentState {
        var builder = CVComponentState.Builder(interaction: interaction,
                                               itemBuildingContext: itemBuildingContext)
        builder.unreadIndicator = UnreadIndicator()
        return builder.build()
    }

    static func build(interaction: TSInteraction,
                      itemBuildingContext: CVItemBuildingContext) throws -> CVComponentState {
        var builder = CVComponentState.Builder(interaction: interaction,
                                               itemBuildingContext: itemBuildingContext)
        return try builder.populateAndBuild()
    }
}

// MARK: -

fileprivate extension CVComponentState.Builder {

    mutating func populateAndBuild() throws -> CVComponentState {

        if let reactionState = InteractionReactionState(interaction: interaction,
                                                        transaction: transaction),
           reactionState.hasReactions {
            self.reactions = Reactions(reactionState: reactionState,
                                       viewState: CVReactionCountsView.buildState(with: reactionState))
        }

        self.senderAvatar = tryToBuildSenderAvatar()

        self.failedOrPendingDownloads = tryToBuildFailedOrPendingDownloads()

        switch interaction.interactionType {
        case .threadDetails:
            self.threadDetails = buildThreadDetails()
            return build()
        case .unknownThreadWarning:
            self.unknownThreadWarning = CVComponentSystemMessage.buildUnknownThreadWarningState(interaction: interaction,
                                                                                                threadViewModel: threadViewModel,
                                                                                                transaction: transaction)
            return build()
        case .defaultDisappearingMessageTimer:
            self.defaultDisappearingMessageTimer = CVComponentSystemMessage.buildDefaultDisappearingMessageTimerState(
                interaction: interaction,
                threadViewModel: threadViewModel,
                transaction: transaction
            )
            return build()
        case .typingIndicator:
            guard let typingIndicatorInteraction = interaction as? TypingIndicatorInteraction else {
                owsFailDebug("Invalid typingIndicator.")
                return build()
            }
            let avatarDataSource = { () -> ConversationAvatarDataSource? in
                guard thread.isGroupThread else {
                    return nil
                }
                return self.avatarBuilder.buildAvatarDataSource(
                    forAddress: typingIndicatorInteraction.address,
                    includingBadge: true,
                    localUserDisplayMode: .asUser,
                    diameterPoints: UInt(ConversationStyle.groupMessageAvatarSizeClass.diameter))
            }()
            self.typingIndicator = TypingIndicator(address: typingIndicatorInteraction.address,
                                                   avatarDataSource: avatarDataSource)
            return build()
        case .info, .error, .call:
            let currentCallThreadId = viewStateSnapshot.currentCallThreadId
            self.systemMessage = CVComponentSystemMessage.buildComponentState(interaction: interaction,
                                                                              threadViewModel: threadViewModel,
                                                                              currentCallThreadId: currentCallThreadId,
                                                                              transaction: transaction)
            return build()
        case .unreadIndicator:
            unreadIndicator = CVComponentState.UnreadIndicator()
            return build()
        case .dateHeader:
            dateHeader = CVComponentState.DateHeader()
            return build()
        case .incomingMessage, .outgoingMessage:
            guard let message = interaction as? TSMessage else {
                owsFailDebug("Invalid message.")
                return build()
            }
            return try populateAndBuild(message: message, revealedSpoilerIdsSnapshot: revealedSpoilerIdsSnapshot)
        case .unknown:
            owsFailDebug("Unknown interaction type.")
            return build()
        default:
            owsFailDebug("Invalid interaction type: \(NSStringFromOWSInteractionType(interaction.interactionType))")
            return build()
        }
    }

    private func tryToBuildSenderAvatar() -> SenderAvatar? {
        guard thread.isGroupThread,
              let incomingMessage = interaction as? TSIncomingMessage else {
            return nil
        }
        guard let avatarDataSource = self.avatarBuilder.buildAvatarDataSource(
            forAddress: incomingMessage.authorAddress,
            includingBadge: true,
            localUserDisplayMode: .asUser,
            diameterPoints: UInt(ConversationStyle.groupMessageAvatarSizeClass.diameter)
        ) else {
            owsFailDebug("Could build avatar image")
            return nil
        }
        return SenderAvatar(avatarDataSource: avatarDataSource)
    }

    private func tryToBuildFailedOrPendingDownloads() -> FailedOrPendingDownloads? {
        guard let message = interaction as? TSMessage else {
            return nil
        }
        let attachmentPointers = message.failedOrPendingAttachments(transaction: transaction)
        guard !attachmentPointers.isEmpty else {
            return nil
        }
        return FailedOrPendingDownloads(attachmentPointers: attachmentPointers)
    }

    mutating func populateAndBuild(
        message: TSMessage,
        revealedSpoilerIdsSnapshot: Set<StyleIdType>
    ) throws -> CVComponentState {

        if message.wasRemotelyDeleted {
            // If the message has been remotely deleted, suppress everything else.
            self.bodyText = .remotelyDeleted
            return build()
        }

        if message.isViewOnceMessage {
            return try buildViewOnceMessage(message: message)
        }

        if let contact = message.contactShare {
            return try buildContact(message: message, contact: contact)
        }

        if let messageSticker = message.messageSticker {
            return try buildSticker(message: message, messageSticker: messageSticker)
        }

        // Check for quoted replies _before_ media album handling,
        // since that logic may exit early.
        buildQuotedReply(message: message, revealedSpoilerIdsSnapshot: revealedSpoilerIdsSnapshot)

        try buildBodyText(message: message)

        if let outgoingMessage = message as? TSOutgoingMessage {
            let messageStatus: MessageReceiptStatus
            if
                let paymentMessage = message as? OWSPaymentMessage,
                let receipt = paymentMessage.paymentNotification?.mcReceiptData,
                let model = PaymentFinder.paymentModels(
                    forMcReceiptData: receipt,
                    transaction: transaction
                ).first
            {
                messageStatus = MessageRecipientStatusUtils.recipientStatus(
                    outgoingMessage: outgoingMessage,
                    paymentModel: model
                )
            } else {
                messageStatus = MessageRecipientStatusUtils.recipientStatus(
                    outgoingMessage: outgoingMessage
                )
            }

            switch messageStatus {
            case .failed:
                sendFailureBadge = SendFailureBadge(color: .ows_accentRed)
            case .pending:
                sendFailureBadge = SendFailureBadge(color: .ows_gray60)
            default:
                break
            }
        }

        // Could be incoming or outgoing; protocol covers both
        if let paymentMessage = message as? OWSPaymentMessage,
           let paymentNotification = paymentMessage.paymentNotification {
            return buildPaymentAttachment(paymentNotification: paymentNotification)
        }

        if let giftBadge = message.giftBadge {
            return try buildGiftBadge(messageUniqueId: message.uniqueId, giftBadge: giftBadge)
        }

        do {
            // TODO: Rename this method to TSMessage.bodyAttachments(...)?
            let bodyAttachments = message.mediaAttachments(with: transaction)
            let mediaAlbumItems = buildMediaAlbumItems(for: bodyAttachments, message: message)
            if mediaAlbumItems.count > 0 {
                var mediaAlbumHasFailedAttachment = false
                var mediaAlbumHasPendingAttachment = false
                for attachment in bodyAttachments {
                    guard let attachmentPointer = attachment as? TSAttachmentPointer else {
                        continue
                    }
                    switch attachmentPointer.state {
                    case .downloading, .enqueued:
                        continue
                    case .failed:
                        mediaAlbumHasFailedAttachment = true
                    case .pendingMessageRequest:
                        mediaAlbumHasPendingAttachment = true
                    case .pendingManualDownload:
                        mediaAlbumHasPendingAttachment = true
                    }
                }

                self.bodyMedia = BodyMedia(items: mediaAlbumItems,
                                           mediaAlbumHasFailedAttachment: mediaAlbumHasFailedAttachment,
                                           mediaAlbumHasPendingAttachment: mediaAlbumHasPendingAttachment)
                return build()
            }

            // Only media galleries should have more than one attachment.
            owsAssertDebug(bodyAttachments.count <= 1)
            if let bodyAttachment = bodyAttachments.first {
                try buildNonMediaAttachment(bodyAttachment: bodyAttachment)
            }
        }

        if !threadViewModel.hasPendingMessageRequest,
           let linkPreview = message.linkPreview {
            try buildLinkPreview(message: message, linkPreview: linkPreview)
        }

        let result = build()
        if result.messageCellType == .unknown {
            owsFailDebug("Unknown message cell type.")
        }
        return result
    }
}

// MARK: -

fileprivate extension CVComponentState.Builder {

    mutating func buildThreadDetails() -> ThreadDetails {
        owsAssertDebug(interaction as? ThreadDetailsInteraction != nil)

        return CVComponentThreadDetails.buildComponentState(thread: thread,
                                                            transaction: transaction,
                                                            avatarBuilder: avatarBuilder)
    }

    // TODO: Should we throw more?
    mutating func buildViewOnceMessage(message: TSMessage) throws -> CVComponentState {
        owsAssertDebug(message.isViewOnceMessage)

        func buildViewOnce(viewOnceState: ViewOnceState) -> CVComponentState {
            self.viewOnce = ViewOnce(viewOnceState: viewOnceState)
            return self.build()
        }

        if let outgoingMessage = message as? TSOutgoingMessage {
            let viewOnceState: ViewOnceState
            if message.isViewOnceComplete {
                viewOnceState = .outgoingSentExpired
            } else {
                switch outgoingMessage.messageState {
                case .sending, .pending:
                    viewOnceState = .outgoingSending
                case .failed:
                    viewOnceState = .outgoingFailed
                default:
                    viewOnceState = .outgoingSentExpired
                }
            }
            return buildViewOnce(viewOnceState: viewOnceState)
        } else if nil != message as? TSIncomingMessage {
            if message.isViewOnceComplete {
                return buildViewOnce(viewOnceState: .incomingExpired)
            }
            let hasMoreThanOneAttachment: Bool = message.attachmentIds.count > 1
            let hasBodyText: Bool = !(message.body?.isEmpty ?? true)
            if hasMoreThanOneAttachment || hasBodyText {
                // Refuse to render incoming "view once" messages if they
                // have more than one attachment or any body text.
                owsFailDebug("Invalid content.")
                return buildViewOnce(viewOnceState: .incomingInvalidContent)
            }
            let mediaAttachments: [TSAttachment] = message.mediaAttachments(with: transaction)
            // We currently only support single attachments for view-once messages.
            guard let mediaAttachment = mediaAttachments.first else {
                owsFailDebug("Missing attachment.")
                return buildViewOnce(viewOnceState: .incomingInvalidContent)
            }
            let attachmentType = mediaAttachment.attachmentType(forContainingMessage: message, transaction: transaction)
            if let attachmentPointer = mediaAttachment as? TSAttachmentPointer {
                switch attachmentPointer.state {
                case .enqueued, .downloading:
                    return buildViewOnce(viewOnceState: .incomingDownloading(
                        attachmentPointer: attachmentPointer,
                        attachmentType: attachmentType
                    ))
                case .failed:
                    return buildViewOnce(viewOnceState: .incomingFailed)
                case .pendingMessageRequest, .pendingManualDownload:
                    return buildViewOnce(viewOnceState: .incomingPending)
                }
            } else if let attachmentStream = mediaAttachment as? TSAttachmentStream {
                if attachmentStream.isValidVisualMedia
                    && (
                        attachmentStream.isImageMimeType
                        || attachmentStream.getAnimatedMimeType() != .notAnimated
                        || attachmentStream.isVideoMimeType
                    )
                {
                    return buildViewOnce(viewOnceState: .incomingAvailable(
                        attachmentStream: attachmentStream,
                        attachmentType: attachmentType
                    ))
                }
            }

            owsFailDebug("Invalid content.")
            return buildViewOnce(viewOnceState: .incomingInvalidContent)
        } else {
            throw OWSAssertionError("Invalid message.")
        }
    }

    // TODO: Should we throw more?
    mutating func buildContact(message: TSMessage, contact: OWSContact) throws -> CVComponentState {
        let contactShare = ContactShareViewModel(contactShareRecord: contact, transaction: transaction)
        let state = CVContactShareView.buildState(
            contactShare: contactShare,
            isIncoming: isIncoming,
            conversationStyle: conversationStyle,
            transaction: transaction
        )
        self.contactShare = ContactShare(state: state)

        let phoneNumberPartition = contactShare.dbRecord.phoneNumberPartition(tx: transaction)
        let phoneNumberAction: CVMessageAction? = phoneNumberPartition.map(
            ifSendablePhoneNumbers: {
                // If system contacts are known/linkable, show a "Send" button.
                return CVMessageAction(
                    title: CommonStrings.sendMessage,
                    accessibilityIdentifier: "send_message_to_contact_share",
                    action: .didTapSendMessage(phoneNumbers: $0)
                )
            },
            elseIfInvitablePhoneNumbers: { _ in
                // If system contacts aren't registered, show an "Invite" button.
                return CVMessageAction(
                    title: OWSLocalizedString("ACTION_INVITE", comment: "Label for 'invite' button in contact view."),
                    accessibilityIdentifier: "invite_contact_share",
                    action: .didTapSendInvite(contactShare: contactShare)
                )
            },
            elseIfAddablePhoneNumbers: { _ in
                // Otherwise, offer to add the number(s) to your address book.
                return CVMessageAction(
                    title: OWSLocalizedString("CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER", comment: "Message shown in conversation view that offers to add an unknown user to your phone's contacts."),
                    accessibilityIdentifier: "add_to_contacts",
                    action: .didTapAddToContacts(contactShare: contactShare)
                )
            },
            elseIfNoPhoneNumbers: {
                return nil
            }
        )
        if let phoneNumberAction {
            bottomButtonsActions.append(phoneNumberAction)
        }

        return build()
    }

    // TODO: Should we throw more?
    mutating func buildSticker(message: TSMessage, messageSticker: MessageSticker) throws -> CVComponentState {

        guard let attachment = TSAttachment.anyFetch(uniqueId: messageSticker.attachmentId,
                                                     transaction: transaction) else {
            throw OWSAssertionError("Missing sticker attachment.")
        }
        if let attachmentStream = attachment as? TSAttachmentStream {
            let mediaSize = attachmentStream.imageSizePoints
            guard attachmentStream.isValidImage,
                  mediaSize.isNonEmpty else {
                throw OWSAssertionError("Invalid sticker.")
            }
            let stickerType = StickerManager.stickerType(forContentType: attachmentStream.contentType)
            guard let stickerDataUrl = attachmentStream.originalMediaURL else {
                throw OWSAssertionError("Invalid sticker.")
            }
            let stickerMetadata = StickerMetadata(stickerInfo: messageSticker.info,
                                                  stickerType: stickerType,
                                                  stickerDataUrl: stickerDataUrl,
                                                  emojiString: messageSticker.emoji)
            self.sticker = .available(stickerMetadata: stickerMetadata,
                                      attachmentStream: attachmentStream)
            return build()
        } else if let attachmentPointer = attachment as? TSAttachmentPointer {
            switch attachmentPointer.state {
            case .enqueued, .downloading:
                Logger.verbose("Sticker downloading.")
                self.sticker = .downloading(attachmentPointer: attachmentPointer)
            case .failed, .pendingManualDownload, .pendingMessageRequest:
                Logger.verbose("Sticker failed or pending.")
                self.sticker = .failedOrPending(attachmentPointer: attachmentPointer)
            }
            return build()
        } else {
            throw OWSAssertionError("Invalid sticker.")
        }
    }

    // TODO: Should we validate and throw errors?
    mutating func buildQuotedReply(
        message: TSMessage,
        revealedSpoilerIdsSnapshot: Set<StyleIdType>
    ) {
        guard let quotedReplyModel = QuotedReplyModel(message: message, transaction: transaction) else {
            return
        }
        var displayableQuotedText: DisplayableText?
        if let quotedBody = quotedReplyModel.body,
           !quotedBody.isEmpty {
            displayableQuotedText = CVComponentState.displayableQuotedText(
                text: quotedBody,
                ranges: quotedReplyModel.bodyRanges,
                interaction: message,
                revealedSpoilerIdsSnapshot: revealedSpoilerIdsSnapshot,
                transaction: transaction
            )
        }
        let viewState = QuotedMessageView.stateForConversation(
            quotedReplyModel: quotedReplyModel,
            displayableQuotedText: displayableQuotedText,
            conversationStyle: conversationStyle,
            isOutgoing: isOutgoing,
            transaction: transaction
        )
        self.quotedReply = QuotedReply(viewState: viewState)
    }

    mutating func buildBodyText(message: TSMessage) throws {
        bodyText = try CVComponentBodyText.buildComponentState(message: message,
                                                               transaction: transaction)
    }

    // MARK: -

    func buildMediaAlbumItems(for mediaAttachments: [TSAttachment],
                              message: TSMessage) -> [CVMediaAlbumItem] {

        var mediaAlbumItems = [CVMediaAlbumItem]()
        for attachment in mediaAttachments {
            guard attachment.isVisualMediaMimeType else {
                // Well behaving clients should not send a mix of visual media (like JPG) and non-visual media (like PDF's)
                // Since we're not coped to handle a mix of media, return @[]
                owsAssertDebug(mediaAlbumItems.count == 0)
                return []
            }

            // TODO: this should pull all the message->attachment edge metadata in one method.
            let caption = attachment.caption(forContainingMessage: message, transaction: transaction)
            let attachmentType = attachment.attachmentType(forContainingMessage: message, transaction: transaction)
            let hasCaption = caption.map {
                return CVComponentState.displayableCaption(
                    text: $0,
                    attachmentId: attachment.uniqueId,
                    transaction: transaction
                ).fullTextValue.isEmpty.negated
            } ?? false

            guard let attachmentStream = attachment as? TSAttachmentStream else {
                var mediaSize: CGSize = .zero
                if let attachmentPointer = attachment as? TSAttachmentPointer,
                   attachmentPointer.mediaSize.isNonEmpty {
                    mediaSize = attachmentPointer.mediaSize
                } else {
                    owsFailDebug("Invalid attachment.")
                }
                mediaAlbumItems.append(CVMediaAlbumItem(attachment: attachment,
                                                        attachmentStream: nil,
                                                        attachmentType: attachmentType,
                                                        hasCaption: hasCaption,
                                                        mediaSize: mediaSize,
                                                        isBroken: false))
                continue
            }

            guard attachmentStream.isValidVisualMediaIgnoringSize(true) else {
                Logger.warn("Filtering invalid media.")
                mediaAlbumItems.append(CVMediaAlbumItem(attachment: attachment,
                                                        attachmentStream: nil,
                                                        attachmentType: attachmentType,
                                                        hasCaption: hasCaption,
                                                        mediaSize: .zero,
                                                        isBroken: true))
                continue
            }
            let mediaSize = attachmentStream.imageSizePixels
            if !mediaSize.isNonEmpty {
                Logger.warn("Filtering media with invalid size.")
                mediaAlbumItems.append(CVMediaAlbumItem(attachment: attachment,
                                                        attachmentStream: nil,
                                                        attachmentType: attachmentType,
                                                        hasCaption: hasCaption,
                                                        mediaSize: .zero,
                                                        isBroken: true))
                continue
            }

            mediaAlbumItems.append(CVMediaAlbumItem(attachment: attachment,
                                                    attachmentStream: attachmentStream,
                                                    attachmentType: attachmentType,
                                                    hasCaption: hasCaption,
                                                    mediaSize: mediaSize,
                                                    isBroken: false))
        }
        return mediaAlbumItems
    }

    mutating func buildNonMediaAttachment(bodyAttachment: TSAttachment?) throws {

        guard let attachment = bodyAttachment else {
            throw OWSAssertionError("Missing attachment.")
        }

        let isVoiceMessage: Bool
        if let message = interaction as? TSMessage {
            isVoiceMessage = attachment.isVoiceMessage(inContainingMessage: message, transaction: transaction)
        } else {
            isVoiceMessage = false
        }

        if attachment.isAudioMimeType, let audioAttachment = AudioAttachment(
            attachment: attachment,
            owningMessage: interaction as? TSMessage,
            metadata: nil,
            isVoiceMessage: isVoiceMessage
        ) {
            self.audioAttachment = audioAttachment
            return
        }

        self.genericAttachment = GenericAttachment(attachment: attachment)
    }

    mutating func buildPaymentAttachment(
        paymentNotification: TSPaymentNotification
    ) -> CVComponentState {

        // Note: there should only ever be one payment model per receipt,
        // but this is unenforced.
        let paymentModel: TSPaymentModel? = PaymentFinder.paymentModels(
            forMcReceiptData: paymentNotification.mcReceiptData,
            transaction: itemBuildingContext.transaction
        ).first

        self.paymentAttachment = PaymentAttachment(
            notification: paymentNotification,
            model: paymentModel,
            // Only used for 1:1 threads, but not enforced.
            otherUserShortName: threadViewModel.shortName ?? threadViewModel.name
        )

        return build()
    }

    mutating func buildLinkPreview(message: TSMessage, linkPreview: OWSLinkPreview) throws {
        guard bodyText != nil else {
            owsFailDebug("Missing body text.")
            return
        }
        guard let urlString = linkPreview.urlString else {
            owsFailDebug("Missing urlString.")
            return
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Invalid urlString.")
            return
        }
        if let groupInviteLinkInfo = GroupManager.parseGroupInviteLink(url) {
            let groupInviteLinkViewModel = CVComponentState.configureGroupInviteLink(url, message: message,
                                                                                     groupInviteLinkInfo: groupInviteLinkInfo)
            if !groupInviteLinkViewModel.isExpired {
                let linkType: LinkPreviewLinkType = (isIncoming
                                                        ? .incomingMessageGroupInviteLink
                                                        : .outgoingMessageGroupInviteLink)
                let state = LinkPreviewGroupLink(linkType: linkType,
                                                 linkPreview: linkPreview,
                                                 groupInviteLinkViewModel: groupInviteLinkViewModel,
                                                 conversationStyle: conversationStyle)
                self.linkPreview = LinkPreview(linkPreview: linkPreview,
                                               linkPreviewAttachment: nil,
                                               state: state)
            }
        } else {
            let linkPreviewAttachment = { () -> TSAttachment? in
                guard let imageAttachmentId = linkPreview.imageAttachmentId,
                      !imageAttachmentId.isEmpty else {
                    return nil
                }

                guard let linkPreviewAttachment = TSAttachment.anyFetch(uniqueId: imageAttachmentId,
                                                                        transaction: self.transaction) else {
                    owsFailDebug("Could not load link preview image attachment.")
                    return nil
                }
                guard linkPreviewAttachment.isImageMimeType else {
                    owsFailDebug("Link preview attachment isn't an image.")
                    return nil
                }
                guard let attachmentStream = linkPreviewAttachment as? TSAttachmentStream else {
                    return nil
                }
                guard attachmentStream.isValidImage else {
                    owsFailDebug("Link preview image attachment isn't valid.")
                    return nil
                }
                return attachmentStream
            }()

            let state = LinkPreviewSent(linkPreview: linkPreview,
                                        imageAttachment: linkPreviewAttachment,
                                        conversationStyle: conversationStyle)
            self.linkPreview = LinkPreview(linkPreview: linkPreview,
                                           linkPreviewAttachment: linkPreviewAttachment,
                                           state: state)
        }
    }

    private mutating func buildGiftBadge(messageUniqueId: String, giftBadge: OWSGiftBadge) throws -> CVComponentState {
        let (level, expirationDate) = try giftBadge.getReceiptDetails()
        self.giftBadge = GiftBadge(
            messageUniqueId: messageUniqueId,
            otherUserShortName: threadViewModel.shortName ?? threadViewModel.name,
            cachedBadge: SubscriptionManagerImpl.getCachedBadge(level: .giftBadge(level)),
            expirationDate: expirationDate,
            redemptionState: giftBadge.redemptionState
        )
        return build()
    }
}

// MARK: - DisplayableText

public extension CVComponentState {

    static func displayableBodyText(text: String,
                                    ranges: MessageBodyRanges?,
                                    interaction: TSInteraction,
                                    transaction: SDSAnyReadTransaction) -> DisplayableText {
        return DisplayableText.displayableText(
            withMessageBody: MessageBody(text: text, ranges: ranges ?? .empty),
            transaction: transaction)
    }

    static func displayableBodyText(oversizeTextAttachment attachmentStream: TSAttachmentStream,
                                    ranges: MessageBodyRanges?,
                                    interaction: TSInteraction,
                                    transaction: SDSAnyReadTransaction) -> DisplayableText {

        let text = { () -> String in
            do {
                guard let url = attachmentStream.originalMediaURL else {
                    owsFailDebug("Missing originalMediaURL.")
                    return ""
                }
                let data = try Data(contentsOf: url)
                guard let string = String(data: data, encoding: .utf8) else {
                    owsFailDebug("Couldn't parse oversize text.")
                    return ""
                }
                return string
            } catch {
                owsFailDebug("Couldn't load oversize text: \(error).")
                return ""
            }
        }()

        return DisplayableText.displayableText(
            withMessageBody: MessageBody(text: text, ranges: ranges ?? .empty),
            transaction: transaction)
    }
}

// MARK: -

fileprivate extension CVComponentState {

    static func displayableQuotedText(
        text: String,
        ranges: MessageBodyRanges?,
        interaction: TSInteraction,
        revealedSpoilerIdsSnapshot: Set<StyleIdType>,
        transaction: SDSAnyReadTransaction
    ) -> DisplayableText {
        return DisplayableText.displayableText(
            withMessageBody: MessageBody(text: text, ranges: ranges ?? .empty),
            transaction: transaction
        )
    }

    static func displayableCaption(text: String,
                                   attachmentId: String,
                                   transaction: SDSAnyReadTransaction) -> DisplayableText {
        return DisplayableText.displayableText(
            withMessageBody: MessageBody(text: text, ranges: .empty),
            transaction: transaction
        )
    }
}

// MARK: -

public extension CVComponentState {
    var hasPrimaryAndSecondaryContentForSelection: Bool {
        var hasPrimaryContent = false

        // Search for a component that qualifies as "non-body text primary".
        for key in activeComponentStateKeys {
            switch key {
            case .bodyText, .linkPreview:
                // "Primary" content is not body text.
                // A link preview is associated with the body text.
                break
            case .bodyMedia, .sticker, .audioAttachment, .genericAttachment, .contactShare:
                hasPrimaryContent = true
            case .senderName, .senderAvatar, .footer, .reactions, .bottomButtons, .sendFailureBadge, .dateHeader, .unreadIndicator, .typingIndicator, .threadDetails, .failedOrPendingDownloads, .unknownThreadWarning, .defaultDisappearingMessageTimer, .messageRoot:
                // "Primary" content is not just metadata / UI.
                break
            case .giftBadge:
                // Gift badges can't be forwarded.
                break
            case .viewOnce:
                // We should never forward view-once messages.
                break
            case .systemMessage:
                // We should never forward system messages.
                break
            case .quotedReply:
                // Quoted replies are never forwarded.
                break
            case .paymentAttachment:
                // Payments can't be forwarded.
                break
            }
        }

        let hasSecondaryContent = bodyText != nil

        return hasPrimaryContent && hasSecondaryContent
    }
}
