//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public class CVComponentState: Equatable {
    let messageCellType: CVMessageCellType

    // TODO: Can/should we eliminate/populate this?
    struct SenderName: Equatable {
        let senderName: NSAttributedString
    }
    let senderName: SenderName?

    struct SenderAvatar: Equatable {
        let senderAvatar: UIImage
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
        let mediaAlbumHasPendingManualDownloadAttachment: Bool
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

        // TODO: convert OWSQuotedReplyModel to Swift.
        var quotedReplyModel: OWSQuotedReplyModel { viewState.quotedReplyModel }
        var displayableQuotedText: DisplayableText? { viewState.displayableQuotedText }
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
        // TODO: convert ContactShareViewModel to Swift?
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
            guard let lhs = lhs.state as? NSObject else {
                owsFailDebug("Invalid value.")
                return false
            }
            guard let rhs = rhs.state as? NSObject else {
                owsFailDebug("Invalid value.")
                return false
            }
            return NSObject.isNullableObject(lhs, equalTo: rhs)
        }
    }
    let linkPreview: LinkPreview?

    struct SystemMessage: Equatable {
        let title: NSAttributedString
        let titleColor: UIColor
        let action: CVMessageAction?
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
        let avatar: UIImage?
    }
    let typingIndicator: TypingIndicator?

    struct ThreadDetails: Equatable {
        let avatar: UIImage?
        let titleText: String
        let detailsText: String?
        let mutualGroupsText: NSAttributedString?
    }
    let threadDetails: ThreadDetails?

    struct BottomButtons: Equatable {
        let actions: [CVMessageAction]
    }
    let bottomButtons: BottomButtons?

    struct FailedOrPendingDownloads: Equatable {
        let attachmentPointers: [TSAttachmentPointer]
    }
    let failedOrPendingDownloads: FailedOrPendingDownloads?

    struct SendFailureBadge: Equatable {
    }
    let sendFailureBadge: SendFailureBadge?

    fileprivate init(messageCellType: CVMessageCellType,
                     senderName: SenderName?,
                     senderAvatar: SenderAvatar?,
                     bodyText: BodyText?,
                     bodyMedia: BodyMedia?,
                     genericAttachment: GenericAttachment?,
                     audioAttachment: AudioAttachment?,
                     viewOnce: ViewOnce?,
                     quotedReply: QuotedReply?,
                     sticker: Sticker?,
                     contactShare: ContactShare?,
                     linkPreview: LinkPreview?,
                     systemMessage: SystemMessage?,
                     dateHeader: DateHeader?,
                     unreadIndicator: UnreadIndicator?,
                     reactions: Reactions?,
                     typingIndicator: TypingIndicator?,
                     threadDetails: ThreadDetails?,
                     bottomButtons: BottomButtons?,
                     failedOrPendingDownloads: FailedOrPendingDownloads?,
                     sendFailureBadge: SendFailureBadge?) {

        self.messageCellType = messageCellType
        self.senderName = senderName
        self.senderAvatar = senderAvatar
        self.bodyText = bodyText
        self.bodyMedia = bodyMedia
        self.genericAttachment = genericAttachment
        self.audioAttachment = audioAttachment
        self.viewOnce = viewOnce
        self.quotedReply = quotedReply
        self.sticker = sticker
        self.contactShare = contactShare
        self.linkPreview = linkPreview
        self.systemMessage = systemMessage
        self.dateHeader = dateHeader
        self.unreadIndicator = unreadIndicator
        self.reactions = reactions
        self.typingIndicator = typingIndicator
        self.threadDetails = threadDetails
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
                    lhs.audioAttachment == rhs.audioAttachment &&
                    lhs.viewOnce == rhs.viewOnce &&
                    lhs.quotedReply == rhs.quotedReply &&
                    lhs.sticker == rhs.sticker &&
                    lhs.contactShare == rhs.contactShare &&
                    lhs.linkPreview == rhs.linkPreview &&
                    lhs.systemMessage == rhs.systemMessage &&
                    lhs.dateHeader == rhs.dateHeader &&
                    lhs.unreadIndicator == rhs.unreadIndicator &&
                    lhs.reactions == rhs.reactions &&
                    lhs.typingIndicator == rhs.typingIndicator &&
                    lhs.threadDetails == rhs.threadDetails &&
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
        typealias ViewOnce = CVComponentState.ViewOnce
        typealias QuotedReply = CVComponentState.QuotedReply
        typealias Sticker = CVComponentState.Sticker
        typealias SystemMessage = CVComponentState.SystemMessage
        typealias ContactShare = CVComponentState.ContactShare
        typealias Reactions = CVComponentState.Reactions
        typealias LinkPreview = CVComponentState.LinkPreview
        typealias DateHeader = CVComponentState.DateHeader
        typealias UnreadIndicator = CVComponentState.UnreadIndicator
        typealias TypingIndicator = CVComponentState.TypingIndicator
        typealias ThreadDetails = CVComponentState.ThreadDetails
        typealias FailedOrPendingDownloads = CVComponentState.FailedOrPendingDownloads
        typealias BottomButtons = CVComponentState.BottomButtons
        typealias SendFailureBadge = CVComponentState.SendFailureBadge

        let interaction: TSInteraction
        let itemBuildingContext: CVItemBuildingContext

        var senderName: SenderName?
        var senderAvatar: SenderAvatar?
        var bodyText: BodyText?
        var bodyMedia: BodyMedia?
        var genericAttachment: GenericAttachment?
        var audioAttachment: AudioAttachment?
        var viewOnce: ViewOnce?
        var quotedReply: QuotedReply?
        var sticker: Sticker?
        var systemMessage: SystemMessage?
        var contactShare: ContactShare?
        var linkPreview: LinkPreview?
        var dateHeader: DateHeader?
        var unreadIndicator: UnreadIndicator?
        var typingIndicator: TypingIndicator?
        var threadDetails: ThreadDetails?
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
                                    audioAttachment: audioAttachment,
                                    viewOnce: viewOnce,
                                    quotedReply: quotedReply,
                                    sticker: sticker,
                                    contactShare: contactShare,
                                    linkPreview: linkPreview,
                                    systemMessage: systemMessage,
                                    dateHeader: dateHeader,
                                    unreadIndicator: unreadIndicator,
                                    reactions: reactions,
                                    typingIndicator: typingIndicator,
                                    threadDetails: threadDetails,
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
            if bodyMedia != nil {
                return .bodyMedia
            }
            if bodyText != nil {
                return .textOnlyMessage
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

    lazy var isJumbomojiMessage: Bool = {
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
           let attachmentStream = firstItem.attachmentStream,
           attachmentStream.isBorderless {
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

    // MARK: - Dependencies

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private static var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private static var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    // MARK: -

    mutating func populateAndBuild() throws -> CVComponentState {

        if let reactionState = InteractionReactionState(interaction: interaction,
                                                        transaction: transaction),
           reactionState.hasReactions {
            self.reactions = Reactions(reactionState: reactionState,
                                       viewState: CVReactionCountsView.buildState(with: reactionState))
        }

        self.senderAvatar = tryToBuildSenderAvatar()

        self.failedOrPendingDownloads = tryToBuildFailedOrPendingDownloads()

        switch interaction.interactionType() {
        case .threadDetails:
            self.threadDetails = buildThreadDetails()
            return build()
        case .typingIndicator:
            guard let typingIndicatorInteraction = interaction as? TypingIndicatorInteraction else {
                owsFailDebug("Invalid typingIndicator.")
                return build()
            }
            let avatar = { () -> UIImage? in
                guard thread.isGroupThread else {
                    return nil
                }
                return self.avatarBuilder.buildAvatar(forAddress: typingIndicatorInteraction.address,
                                                      diameter: UInt(ConversationStyle.groupMessageAvatarDiameter))
            }()
            self.typingIndicator = TypingIndicator(address: typingIndicatorInteraction.address,
                                                   avatar: avatar)
            return build()
        case .info, .error, .call:
            let currentCallThreadId = viewStateSnapshot.currentCallThreadId
            self.systemMessage = CVComponentSystemMessage.buildComponentState(interaction: interaction,
                                                                              threadViewModel: threadViewModel,
                                                                              currentCallThreadId: currentCallThreadId,
                                                                              transaction: transaction)
            return build()
        case .unreadIndicator, .dateHeader:
            return build()
        case .incomingMessage, .outgoingMessage:
            guard let message = interaction as? TSMessage else {
                owsFailDebug("Invalid message.")
                return build()
            }
            return try populateAndBuild(message: message)
        case .unknown:
            owsFailDebug("Unknown interaction type.")
            return build()
        default:
            owsFailDebug("Invalid interaction type: \(NSStringFromOWSInteractionType(interaction.interactionType()))")
            return build()
        }
    }

    private func tryToBuildSenderAvatar() -> SenderAvatar? {
        guard thread.isGroupThread,
              let incomingMessage = interaction as? TSIncomingMessage else {
            return nil
        }
        guard let avatar = self.avatarBuilder.buildAvatar(forAddress: incomingMessage.authorAddress,
                                                          diameter: UInt(ConversationStyle.groupMessageAvatarDiameter)) else {
            owsFailDebug("Could build avatar image")
            return nil
        }
        return SenderAvatar(senderAvatar: avatar)
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

    mutating func populateAndBuild(message: TSMessage) throws -> CVComponentState {

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
        buildQuotedReply(message: message)

        try buildBodyText(message: message)

        if let outgoingMessage = message as? TSOutgoingMessage,
           outgoingMessage.messageState == .failed {
            self.sendFailureBadge = SendFailureBadge()
        }

        do {
            // TODO: Rename this method to TSMessage.bodyAttachments(...)?
            let bodyAttachments = message.mediaAttachments(with: transaction.unwrapGrdbRead)
            let mediaAlbumItems = buildMediaAlbumItems(for: bodyAttachments, message: message)
            if mediaAlbumItems.count > 0 {
                var mediaAlbumHasFailedAttachment = false
                var mediaAlbumHasPendingAttachment = false
                var mediaAlbumHasPendingManualDownloadAttachment = false
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
                        mediaAlbumHasPendingManualDownloadAttachment = true
                    @unknown default:
                        owsFailDebug("Invalid attachment pointer state.")
                        continue
                    }
                }

                self.bodyMedia = BodyMedia(items: mediaAlbumItems,
                                           mediaAlbumHasFailedAttachment: mediaAlbumHasFailedAttachment,
                                           mediaAlbumHasPendingAttachment: mediaAlbumHasPendingAttachment,
                                           mediaAlbumHasPendingManualDownloadAttachment: mediaAlbumHasPendingManualDownloadAttachment)
                return build()
            }

            // Only media galleries should have more than one attachment.
            owsAssertDebug(bodyAttachments.count <= 1)
            if let bodyAttachment = bodyAttachments.first {
                try buildNonMediaAttachment(bodyAttachment: bodyAttachment)
            }
        }

        if let linkPreview = message.linkPreview {
            try buildLinkPreview(message: message, linkPreview: linkPreview)
        }

        let result = build()
        if result.messageCellType == .unknown {
            Logger.verbose("message: \(message.debugDescription)")
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
                case .sending:
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
            let mediaAttachments: [TSAttachment] = message.mediaAttachments(with: transaction.unwrapGrdbRead)
            // We currently only support single attachments for view-once messages.
            guard let mediaAttachment = mediaAttachments.first else {
                owsFailDebug("Missing attachment.")
                return buildViewOnce(viewOnceState: .incomingInvalidContent)
            }
            if let attachmentPointer = mediaAttachment as? TSAttachmentPointer {
                switch attachmentPointer.state {
                case .enqueued, .downloading:
                    return buildViewOnce(viewOnceState: .incomingDownloading(attachmentPointer: attachmentPointer))
                case .failed:
                    return buildViewOnce(viewOnceState: .incomingFailed)
                case .pendingMessageRequest, .pendingManualDownload:
                    return buildViewOnce(viewOnceState: .incomingPending)
                @unknown default:
                    owsFailDebug("Invalid value.")
                    return buildViewOnce(viewOnceState: .incomingFailed)
                }
            } else if let attachmentStream = mediaAttachment as? TSAttachmentStream {
                if attachmentStream.isValidVisualMedia
                    && (attachmentStream.isImage || attachmentStream.isAnimated || attachmentStream.isVideo) {
                    return buildViewOnce(viewOnceState: .incomingAvailable(attachmentStream: attachmentStream))
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
        let state = CVContactShareView.buildState(contactShare: contactShare,
                                                  isIncoming: isIncoming,
                                                  conversationStyle: conversationStyle,
                                                  transaction: transaction)
        self.contactShare = ContactShare(state: state)

        let hasSendTextButton = !contactShare.systemContactsWithSignalAccountPhoneNumbers(transaction: transaction).isEmpty
        let hasInviteButton = !contactShare.systemContactPhoneNumbers().isEmpty
        let hasAddToContactsButton = !contactShare.e164PhoneNumbers().isEmpty

        if hasSendTextButton {
            let action = CVMessageAction(title: CommonStrings.sendMessage,
                                         accessibilityIdentifier: "send_message_to_contact_share",
                                         action: .cvc_didTapSendMessage(contactShare: contactShare))
            bottomButtonsActions.append(action)
        } else if hasInviteButton {
            let action = CVMessageAction(title: NSLocalizedString("ACTION_INVITE",
                                                                  comment: "Label for 'invite' button in contact view."),
                                         accessibilityIdentifier: "invite_contact_share",
                                         action: .cvc_didTapSendInvite(contactShare: contactShare))
            bottomButtonsActions.append(action)
        } else if hasAddToContactsButton {
            let action = CVMessageAction(title: NSLocalizedString("CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER",
                                                                  comment: "Message shown in conversation view that offers to add an unknown user to your phone's contacts."),
                                         accessibilityIdentifier: "add_to_contacts",
                                         action: .cvc_didTapAddToContacts(contactShare: contactShare))
            bottomButtonsActions.append(action)
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
            let mediaSize = attachmentStream.imageSize()
            guard attachmentStream.isValidImage,
                  mediaSize.width > 0,
                  mediaSize.height > 0 else {
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
            @unknown default:
                throw OWSAssertionError("Invalid sticker.")
            }
            return build()
        } else {
            throw OWSAssertionError("Invalid sticker.")
        }
    }

    // TODO: Should we validate and throw errors?
    mutating func buildQuotedReply(message: TSMessage) {
        guard let quotedMessage = message.quotedMessage else {
            return
        }
        let quotedReplyModel = OWSQuotedReplyModel.quotedReply(with: quotedMessage, transaction: transaction)
        var displayableQuotedText: DisplayableText?
        if let quotedBody = quotedReplyModel.body,
           !quotedBody.isEmpty {
            displayableQuotedText = CVComponentState.displayableQuotedText(text: quotedBody,
                                                                           ranges: quotedReplyModel.bodyRanges,
                                                                           interaction: message,
                                                                           transaction: transaction)
        }
        let viewState = QuotedMessageView.stateForConversation(quotedReplyModel: quotedReplyModel,
                                                               displayableQuotedText: displayableQuotedText,
                                                               conversationStyle: conversationStyle,
                                                               isOutgoing: isOutgoing,
                                                               transaction: transaction)
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
            guard attachment.isVisualMedia else {
                // Well behaving clients should not send a mix of visual media (like JPG) and non-visual media (like PDF's)
                // Since we're not coped to handle a mix of media, return @[]
                owsAssertDebug(mediaAlbumItems.count == 0)
                return []
            }

            var caption: String?
            if let rawCaption = attachment.caption {
                caption = CVComponentState.displayableCaption(text: rawCaption,
                                                              attachmentId: attachment.uniqueId,
                                                              transaction: transaction).displayTextValue.stringValue
            }

            guard let attachmentStream = attachment as? TSAttachmentStream else {
                var mediaSize: CGSize = .zero
                if let attachmentPointer = attachment as? TSAttachmentPointer,
                   attachmentPointer.mediaSize.width > 0,
                   attachmentPointer.mediaSize.height > 0 {
                    mediaSize = attachmentPointer.mediaSize
                } else {
                    owsFailDebug("Invalid attachment.")
                }
                mediaAlbumItems.append(CVMediaAlbumItem(attachment: attachment,
                                                                  attachmentStream: nil,
                                                                  caption: caption,
                                                                  mediaSize: mediaSize))
                continue
            }

            guard attachmentStream.isValidVisualMedia else {
                Logger.warn("Filtering invalid media.")
                mediaAlbumItems.append(CVMediaAlbumItem(attachment: attachment,
                                                                  attachmentStream: nil,
                                                                  caption: caption,
                                                                  mediaSize: .zero))
                continue
            }
            let mediaSize = attachmentStream.imageSize()
            if mediaSize.width <= 0 || mediaSize.height <= 0 {
                Logger.warn("Filtering media with invalid size.")
                mediaAlbumItems.append(CVMediaAlbumItem(attachment: attachment,
                                                                  attachmentStream: nil,
                                                                  caption: caption,
                                                                  mediaSize: .zero))
                continue
            }

            mediaAlbumItems.append(CVMediaAlbumItem(attachment: attachment,
                                                              attachmentStream: attachmentStream,
                                                              caption: caption,
                                                              mediaSize: mediaSize))
        }
        return mediaAlbumItems
    }

    mutating func buildNonMediaAttachment(bodyAttachment: TSAttachment?) throws {

        guard let attachment = bodyAttachment else {
            throw OWSAssertionError("Missing attachment.")
        }

        if attachment.isAudio, let audioAttachment = AudioAttachment(attachment: attachment) {
            self.audioAttachment = audioAttachment
            return
        }

        self.genericAttachment = GenericAttachment(attachment: attachment)
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
                guard linkPreviewAttachment.isImage else {
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

            //            self.linkPreview = LinkPreview(linkPreview: linkPreview,
            //                                           linkPreviewAttachment: linkPreviewAttachment,
            //                                           groupInviteLinkViewModel: nil)
            let state = LinkPreviewSent(linkPreview: linkPreview,
                                        imageAttachment: linkPreviewAttachment,
                                        conversationStyle: conversationStyle)
            self.linkPreview = LinkPreview(linkPreview: linkPreview,
                                           linkPreviewAttachment: linkPreviewAttachment,
                                           state: state)
        }
    }
}

// MARK: - DisplayableText

public extension CVComponentState {

    static func displayableBodyText(text: String,
                                    ranges: MessageBodyRanges?,
                                    interaction: TSInteraction,
                                    transaction: SDSAnyReadTransaction) -> DisplayableText {

        let cacheKey = "body-\(interaction.uniqueId)"

        let mentionStyle: Mention.Style = (interaction as? TSOutgoingMessage != nil) ? .outgoing : .incoming
        return Self.displayableText(cacheKey: cacheKey,
                                    mentionStyle: mentionStyle,
                                    transaction: transaction) {
            MessageBody(text: text, ranges: ranges ?? .empty)
        }
    }

    static func displayableBodyText(oversizeTextAttachment attachmentStream: TSAttachmentStream,
                                    ranges: MessageBodyRanges?,
                                    interaction: TSInteraction,
                                    transaction: SDSAnyReadTransaction) -> DisplayableText {

        let cacheKey = "oversize-body-\(interaction.uniqueId)"

        let mentionStyle: Mention.Style = (interaction as? TSOutgoingMessage != nil) ? .outgoing : .incoming
        return Self.displayableText(cacheKey: cacheKey,
                                    mentionStyle: mentionStyle,
                                    transaction: transaction) {
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
            return MessageBody(text: text, ranges: ranges ?? .empty)
        }
    }
}

// MARK: -

fileprivate extension CVComponentState {

    static func displayableQuotedText(text: String,
                                      ranges: MessageBodyRanges?,
                                      interaction: TSInteraction,
                                      transaction: SDSAnyReadTransaction) -> DisplayableText {

        let cacheKey = "quoted-\(interaction.uniqueId)"

        let mentionStyle: Mention.Style = .quotedReply
        return Self.displayableText(cacheKey: cacheKey,
                                    mentionStyle: mentionStyle,
                                    transaction: transaction) {
            MessageBody(text: text, ranges: ranges ?? .empty)
        }
    }

    static func displayableCaption(text: String,
                                   attachmentId: String,
                                   transaction: SDSAnyReadTransaction) -> DisplayableText {

        let cacheKey = "attachment-caption-\(attachmentId)"

        let mentionStyle: Mention.Style = .incoming
        return CVComponentState.displayableText(cacheKey: cacheKey,
                                                mentionStyle: mentionStyle,
                                                transaction: transaction) {
            MessageBody(text: text, ranges: .empty)
        }
    }

    // TODO: Now that we're caching the displayable text on the view items,
    //       I'm not sure if we still need this cache.
    private static let displayableTextCache: NSCache<NSString, DisplayableText> = {
        let cache = NSCache<NSString, DisplayableText>()
        // Cache the results for up to 1,000 messages.
        cache.countLimit = 1000
        return cache
    }()

    static func displayableText(cacheKey: String,
                                mentionStyle: Mention.Style,
                                transaction: SDSAnyReadTransaction,
                                messageBodyBlock: () -> MessageBody) -> DisplayableText {
        owsAssertDebug(!cacheKey.isEmpty)

        if let displayableText = displayableTextCache.object(forKey: cacheKey as NSString) {
            return displayableText
        }
        let messageBody = messageBodyBlock()
        let displayableText = DisplayableText.displayableText(withMessageBody: messageBody,
                                                              mentionStyle: mentionStyle,
                                                              transaction: transaction)
        displayableTextCache.setObject(displayableText, forKey: cacheKey as NSString)
        return displayableText
    }
}
