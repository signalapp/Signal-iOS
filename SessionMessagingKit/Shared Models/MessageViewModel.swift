// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SessionUtilitiesKit

fileprivate typealias ViewModel = MessageViewModel
fileprivate typealias AttachmentInteractionInfo = MessageViewModel.AttachmentInteractionInfo
fileprivate typealias ReactionInfo = MessageViewModel.ReactionInfo
fileprivate typealias TypingIndicatorInfo = MessageViewModel.TypingIndicatorInfo

public struct MessageViewModel: FetchableRecordWithRowId, Decodable, Equatable, Hashable, Identifiable, Differentiable {
    public static let threadIdKey: SQL = SQL(stringLiteral: CodingKeys.threadId.stringValue)
    public static let threadVariantKey: SQL = SQL(stringLiteral: CodingKeys.threadVariant.stringValue)
    public static let threadIsTrustedKey: SQL = SQL(stringLiteral: CodingKeys.threadIsTrusted.stringValue)
    public static let threadHasDisappearingMessagesEnabledKey: SQL = SQL(stringLiteral: CodingKeys.threadHasDisappearingMessagesEnabled.stringValue)
    public static let threadOpenGroupServerKey: SQL = SQL(stringLiteral: CodingKeys.threadOpenGroupServer.stringValue)
    public static let threadOpenGroupPublicKeyKey: SQL = SQL(stringLiteral: CodingKeys.threadOpenGroupPublicKey.stringValue)
    public static let threadContactNameInternalKey: SQL = SQL(stringLiteral: CodingKeys.threadContactNameInternal.stringValue)
    public static let rowIdKey: SQL = SQL(stringLiteral: CodingKeys.rowId.stringValue)
    public static let authorNameInternalKey: SQL = SQL(stringLiteral: CodingKeys.authorNameInternal.stringValue)
    public static let stateKey: SQL = SQL(stringLiteral: CodingKeys.state.stringValue)
    public static let hasAtLeastOneReadReceiptKey: SQL = SQL(stringLiteral: CodingKeys.hasAtLeastOneReadReceipt.stringValue)
    public static let mostRecentFailureTextKey: SQL = SQL(stringLiteral: CodingKeys.mostRecentFailureText.stringValue)
    public static let isTypingIndicatorKey: SQL = SQL(stringLiteral: CodingKeys.isTypingIndicator.stringValue)
    public static let isSenderOpenGroupModeratorKey: SQL = SQL(stringLiteral: CodingKeys.isSenderOpenGroupModerator.stringValue)
    public static let profileKey: SQL = SQL(stringLiteral: CodingKeys.profile.stringValue)
    public static let quoteKey: SQL = SQL(stringLiteral: CodingKeys.quote.stringValue)
    public static let quoteAttachmentKey: SQL = SQL(stringLiteral: CodingKeys.quoteAttachment.stringValue)
    public static let linkPreviewKey: SQL = SQL(stringLiteral: CodingKeys.linkPreview.stringValue)
    public static let linkPreviewAttachmentKey: SQL = SQL(stringLiteral: CodingKeys.linkPreviewAttachment.stringValue)
    public static let currentUserPublicKeyKey: SQL = SQL(stringLiteral: CodingKeys.currentUserPublicKey.stringValue)
    public static let cellTypeKey: SQL = SQL(stringLiteral: CodingKeys.cellType.stringValue)
    public static let authorNameKey: SQL = SQL(stringLiteral: CodingKeys.authorName.stringValue)
    public static let shouldShowProfileKey: SQL = SQL(stringLiteral: CodingKeys.shouldShowProfile.stringValue)
    public static let positionInClusterKey: SQL = SQL(stringLiteral: CodingKeys.positionInCluster.stringValue)
    public static let isOnlyMessageInClusterKey: SQL = SQL(stringLiteral: CodingKeys.isOnlyMessageInCluster.stringValue)
    public static let isLastKey: SQL = SQL(stringLiteral: CodingKeys.isLast.stringValue)
    
    public static let profileString: String = CodingKeys.profile.stringValue
    public static let quoteString: String = CodingKeys.quote.stringValue
    public static let quoteAttachmentString: String = CodingKeys.quoteAttachment.stringValue
    public static let linkPreviewString: String = CodingKeys.linkPreview.stringValue
    public static let linkPreviewAttachmentString: String = CodingKeys.linkPreviewAttachment.stringValue
    
    public enum Position: Int, Decodable, Equatable, Hashable, DatabaseValueConvertible {
        case top
        case middle
        case bottom
    }
    
    public enum CellType: Int, Decodable, Equatable, Hashable, DatabaseValueConvertible {
        case textOnlyMessage
        case mediaMessage
        case audio
        case genericAttachment
        case typingIndicator
    }
    
    public var differenceIdentifier: Int64 { id }
    
    // Thread Info
    
    public let threadId: String
    public let threadVariant: SessionThread.Variant
    public let threadIsTrusted: Bool
    public let threadHasDisappearingMessagesEnabled: Bool
    public let threadOpenGroupServer: String?
    public let threadOpenGroupPublicKey: String?
    private let threadContactNameInternal: String?
    
    // Interaction Info
    
    public let rowId: Int64
    public let id: Int64
    public let variant: Interaction.Variant
    public let timestampMs: Int64
    public let authorId: String
    private let authorNameInternal: String?
    public let body: String?
    public let rawBody: String?
    public let expiresStartedAtMs: Double?
    public let expiresInSeconds: TimeInterval?
    
    public let state: RecipientState.State
    public let hasAtLeastOneReadReceipt: Bool
    public let mostRecentFailureText: String?
    public let isSenderOpenGroupModerator: Bool
    public let isTypingIndicator: Bool?
    public let profile: Profile?
    public let quote: Quote?
    public let quoteAttachment: Attachment?
    public let linkPreview: LinkPreview?
    public let linkPreviewAttachment: Attachment?
    
    public let currentUserPublicKey: String
    
    // Post-Query Processing Data
    
    /// This value includes the associated attachments
    public let attachments: [Attachment]?
    
    /// This value includes the associated reactions
    public let reactionInfo: [ReactionInfo]?
    
    /// This value defines what type of cell should appear and is generated based on the interaction variant
    /// and associated attachment data
    public let cellType: CellType
    
    /// This value includes the author name information
    public let authorName: String

    /// This value will be used to populate the author label, if it's null then the label will be hidden
    ///
    /// **Note:** This will only be populated for incoming messages
    public let senderName: String?

    /// A flag indicating whether the profile view should be displayed
    public let shouldShowProfile: Bool

    /// This value will be used to populate the date header, if it's null then the header will be hidden
    public let dateForUI: Date?
    
    /// This value specifies whether the body contains only emoji characters
    public let containsOnlyEmoji: Bool?
    
    /// This value specifies the number of emoji characters the body contains
    public let glyphCount: Int?
    
    /// This value indicates the variant of the previous ViewModel item, if it's null then there is no previous item
    public let previousVariant: Interaction.Variant?
    
    /// This value indicates the position of this message within a cluser of messages
    public let positionInCluster: Position
    
    /// This value indicates whether this is the only message in a cluser of messages
    public let isOnlyMessageInCluster: Bool
    
    /// This value indicates whether this is the last message in the thread
    public let isLast: Bool
    
    /// This is the users blinded key (will only be set for messages within open groups)
    public let currentUserBlindedPublicKey: String?

    // MARK: - Mutation
    
    public func with(
        attachments: Updatable<[Attachment]> = .existing,
        reactionInfo: Updatable<[ReactionInfo]> = .existing
    ) -> MessageViewModel {
        return MessageViewModel(
            threadId: self.threadId,
            threadVariant: self.threadVariant,
            threadIsTrusted: self.threadIsTrusted,
            threadHasDisappearingMessagesEnabled: self.threadHasDisappearingMessagesEnabled,
            threadOpenGroupServer: self.threadOpenGroupServer,
            threadOpenGroupPublicKey: self.threadOpenGroupPublicKey,
            threadContactNameInternal: self.threadContactNameInternal,
            rowId: self.rowId,
            id: self.id,
            variant: self.variant,
            timestampMs: self.timestampMs,
            authorId: self.authorId,
            authorNameInternal: self.authorNameInternal,
            body: self.body,
            rawBody: self.rawBody,
            expiresStartedAtMs: self.expiresStartedAtMs,
            expiresInSeconds: self.expiresInSeconds,
            state: self.state,
            hasAtLeastOneReadReceipt: self.hasAtLeastOneReadReceipt,
            mostRecentFailureText: self.mostRecentFailureText,
            isSenderOpenGroupModerator: self.isSenderOpenGroupModerator,
            isTypingIndicator: self.isTypingIndicator,
            profile: self.profile,
            quote: self.quote,
            quoteAttachment: self.quoteAttachment,
            linkPreview: self.linkPreview,
            linkPreviewAttachment: self.linkPreviewAttachment,
            currentUserPublicKey: self.currentUserPublicKey,
            attachments: (attachments ?? self.attachments),
            reactionInfo: (reactionInfo ?? self.reactionInfo),
            cellType: self.cellType,
            authorName: self.authorName,
            senderName: self.senderName,
            shouldShowProfile: self.shouldShowProfile,
            dateForUI: self.dateForUI,
            containsOnlyEmoji: self.containsOnlyEmoji,
            glyphCount: self.glyphCount,
            previousVariant: self.previousVariant,
            positionInCluster: self.positionInCluster,
            isOnlyMessageInCluster: self.isOnlyMessageInCluster,
            isLast: self.isLast,
            currentUserBlindedPublicKey: self.currentUserBlindedPublicKey
        )
    }
    
    public func withClusteringChanges(
        prevModel: MessageViewModel?,
        nextModel: MessageViewModel?,
        isLast: Bool,
        currentUserBlindedPublicKey: String?
    ) -> MessageViewModel {
        let cellType: CellType = {
            guard self.isTypingIndicator != true else { return .typingIndicator }
            guard self.variant != .standardIncomingDeleted else { return .textOnlyMessage }
            guard let attachment: Attachment = self.attachments?.first else { return .textOnlyMessage }

            // The only case which currently supports multiple attachments is a 'mediaMessage'
            // (the album view)
            guard self.attachments?.count == 1 else { return .mediaMessage }

            // Quote and LinkPreview overload the 'attachments' array and use it for their
            // own purposes, otherwise check if the attachment is visual media
            guard self.quote == nil else { return .textOnlyMessage }
            guard self.linkPreview == nil else { return .textOnlyMessage }
            
            // Pending audio attachments won't have a duration
            if
                attachment.isAudio && (
                    ((attachment.duration ?? 0) > 0) ||
                    (
                        attachment.state != .downloaded &&
                        attachment.state != .uploaded
                    )
                )
            {
                return .audio
            }

            if attachment.isVisualMedia {
                return .mediaMessage
            }
            
            return .genericAttachment
        }()
        let authorDisplayName: String = Profile.displayName(
            for: self.threadVariant,
            id: self.authorId,
            name: self.authorNameInternal,
            nickname: nil  // Folded into 'authorName' within the Query
        )
        let shouldShowDateOnThisModel: Bool = {
            guard self.isTypingIndicator != true else { return false }
            guard self.variant != .infoCall else { return true }    // Always show on calls
            guard let prevModel: ViewModel = prevModel else { return true }
            
            return MessageViewModel.shouldShowDateBreak(
                between: prevModel.timestampMs,
                and: self.timestampMs
            )
        }()
        let shouldShowDateOnNextModel: Bool = {
            // Should be nothing after a typing indicator
            guard self.isTypingIndicator != true else { return false }
            guard let nextModel: ViewModel = nextModel else { return false }

            return MessageViewModel.shouldShowDateBreak(
                between: self.timestampMs,
                and: nextModel.timestampMs
            )
        }()
        let (positionInCluster, isOnlyMessageInCluster): (Position, Bool) = {
            let isFirstInCluster: Bool = (
                prevModel == nil ||
                shouldShowDateOnThisModel || (
                    self.variant == .standardOutgoing &&
                    prevModel?.variant != .standardOutgoing
                ) || (
                    (
                        self.variant == .standardIncoming ||
                        self.variant == .standardIncomingDeleted
                    ) && (
                        prevModel?.variant != .standardIncoming &&
                        prevModel?.variant != .standardIncomingDeleted
                    )
                ) ||
                self.authorId != prevModel?.authorId
            )
            let isLastInCluster: Bool = (
                nextModel == nil ||
                shouldShowDateOnNextModel || (
                    self.variant == .standardOutgoing &&
                    nextModel?.variant != .standardOutgoing
                ) || (
                    (
                        self.variant == .standardIncoming ||
                        self.variant == .standardIncomingDeleted
                    ) && (
                        nextModel?.variant != .standardIncoming &&
                        nextModel?.variant != .standardIncomingDeleted
                    )
                ) ||
                self.authorId != nextModel?.authorId
            )

            let isOnlyMessageInCluster: Bool = (isFirstInCluster && isLastInCluster)

            switch (isFirstInCluster, isLastInCluster) {
                case (true, true), (false, false): return (.middle, isOnlyMessageInCluster)
                case (true, false): return (.top, isOnlyMessageInCluster)
                case (false, true): return (.bottom, isOnlyMessageInCluster)
            }
        }()
        
        return ViewModel(
            threadId: self.threadId,
            threadVariant: self.threadVariant,
            threadIsTrusted: self.threadIsTrusted,
            threadHasDisappearingMessagesEnabled: self.threadHasDisappearingMessagesEnabled,
            threadOpenGroupServer: self.threadOpenGroupServer,
            threadOpenGroupPublicKey: self.threadOpenGroupPublicKey,
            threadContactNameInternal: self.threadContactNameInternal,
            rowId: self.rowId,
            id: self.id,
            variant: self.variant,
            timestampMs: self.timestampMs,
            authorId: self.authorId,
            authorNameInternal: self.authorNameInternal,
            body: (!self.variant.isInfoMessage ?
                self.body :
                // Info messages might not have a body so we should use the 'previewText' value instead
                Interaction.previewText(
                    variant: self.variant,
                    body: self.body,
                    threadContactDisplayName: Profile.displayName(
                        for: self.threadVariant,
                        id: self.threadId,
                        name: self.threadContactNameInternal,
                        nickname: nil  // Folded into 'threadContactNameInternal' within the Query
                    ),
                    authorDisplayName: authorDisplayName,
                    attachmentDescriptionInfo: self.attachments?.first.map { firstAttachment in
                        Attachment.DescriptionInfo(
                            id: firstAttachment.id,
                            variant: firstAttachment.variant,
                            contentType: firstAttachment.contentType,
                            sourceFilename: firstAttachment.sourceFilename
                        )
                    },
                    attachmentCount: self.attachments?.count,
                    isOpenGroupInvitation: (self.linkPreview?.variant == .openGroupInvitation)
                )
            ),
            rawBody: self.body,
            expiresStartedAtMs: self.expiresStartedAtMs,
            expiresInSeconds: self.expiresInSeconds,
            state: self.state,
            hasAtLeastOneReadReceipt: self.hasAtLeastOneReadReceipt,
            mostRecentFailureText: self.mostRecentFailureText,
            isSenderOpenGroupModerator: self.isSenderOpenGroupModerator,
            isTypingIndicator: self.isTypingIndicator,
            profile: self.profile,
            quote: self.quote,
            quoteAttachment: self.quoteAttachment,
            linkPreview: self.linkPreview,
            linkPreviewAttachment: self.linkPreviewAttachment,
            currentUserPublicKey: self.currentUserPublicKey,
            attachments: self.attachments,
            reactionInfo: self.reactionInfo,
            cellType: cellType,
            authorName: authorDisplayName,
            senderName: {
                // Only show for group threads
                guard self.threadVariant == .openGroup || self.threadVariant == .closedGroup else {
                    return nil
                }
                
                // Only show for incoming messages
                guard self.variant == .standardIncoming || self.variant == .standardIncomingDeleted else {
                    return nil
                }
                    
                // Only if there is a date header or the senders are different
                guard shouldShowDateOnThisModel || self.authorId != prevModel?.authorId else {
                    return nil
                }
                    
                return authorDisplayName
            }(),
            shouldShowProfile: (
                // Only group threads
                (self.threadVariant == .openGroup || self.threadVariant == .closedGroup) &&
                
                // Only incoming messages
                (self.variant == .standardIncoming || self.variant == .standardIncomingDeleted) &&
                
                // Show if the next message has a different sender, isn't a standard message or has a "date break"
                (
                    self.authorId != nextModel?.authorId ||
                    (nextModel?.variant != .standardIncoming && nextModel?.variant != .standardIncomingDeleted) ||
                    shouldShowDateOnNextModel
                ) &&
                
                // Need a profile to be able to show it
                self.profile != nil
            ),
            dateForUI: (shouldShowDateOnThisModel ?
                Date(timeIntervalSince1970: (TimeInterval(self.timestampMs) / 1000)) :
                nil
            ),
            containsOnlyEmoji: self.body?.containsOnlyEmoji,
            glyphCount: self.body?.glyphCount,
            previousVariant: prevModel?.variant,
            positionInCluster: positionInCluster,
            isOnlyMessageInCluster: isOnlyMessageInCluster,
            isLast: isLast,
            currentUserBlindedPublicKey: currentUserBlindedPublicKey
        )
    }
}

// MARK: - AttachmentInteractionInfo

public extension MessageViewModel {
    struct AttachmentInteractionInfo: FetchableRecordWithRowId, Decodable, Identifiable, Equatable, Comparable {
        public static let rowIdKey: SQL = SQL(stringLiteral: CodingKeys.rowId.stringValue)
        public static let attachmentKey: SQL = SQL(stringLiteral: CodingKeys.attachment.stringValue)
        public static let interactionAttachmentKey: SQL = SQL(stringLiteral: CodingKeys.interactionAttachment.stringValue)
        
        public static let attachmentString: String = CodingKeys.attachment.stringValue
        public static let interactionAttachmentString: String = CodingKeys.interactionAttachment.stringValue
        
        public let rowId: Int64
        public let attachment: Attachment
        public let interactionAttachment: InteractionAttachment
        
        // MARK: - Identifiable
        
        public var id: String {
            "\(interactionAttachment.interactionId)-\(interactionAttachment.albumIndex)"
        }
        
        // MARK: - Comparable
        
        public static func < (lhs: AttachmentInteractionInfo, rhs: AttachmentInteractionInfo) -> Bool {
            return (lhs.interactionAttachment.albumIndex < rhs.interactionAttachment.albumIndex)
        }
    }
}

// MARK: - ReactionInfo

public extension MessageViewModel {
    struct ReactionInfo: FetchableRecordWithRowId, Decodable, Identifiable, Equatable, Comparable, Hashable, Differentiable {
        public static let rowIdKey: SQL = SQL(stringLiteral: CodingKeys.rowId.stringValue)
        public static let reactionKey: SQL = SQL(stringLiteral: CodingKeys.reaction.stringValue)
        public static let profileKey: SQL = SQL(stringLiteral: CodingKeys.profile.stringValue)
        
        public static let reactionString: String = CodingKeys.reaction.stringValue
        public static let profileString: String = CodingKeys.profile.stringValue
        
        public let rowId: Int64
        public let reaction: Reaction
        public let profile: Profile?
        
        // MARK: - Identifiable
        
        public var differenceIdentifier: String { return id }
        
        public var id: String {
            "\(reaction.emoji)-\(reaction.interactionId)-\(reaction.authorId)"
        }
        
        // MARK: - Comparable
        
        public static func < (lhs: ReactionInfo, rhs: ReactionInfo) -> Bool {
            return (lhs.reaction.sortId < rhs.reaction.sortId)
        }
    }
}

// MARK: - TypingIndicatorInfo

public extension MessageViewModel {
    struct TypingIndicatorInfo: FetchableRecordWithRowId, Decodable, Identifiable, Equatable {
        public static let rowIdKey: SQL = SQL(stringLiteral: CodingKeys.rowId.stringValue)
        public static let threadIdKey: SQL = SQL(stringLiteral: CodingKeys.threadId.stringValue)
        
        public let rowId: Int64
        public let threadId: String
        
        // MARK: - Identifiable
        
        public var id: String { threadId }
    }
}

// MARK: - Convenience Initialization

public extension MessageViewModel {
    static let genericId: Int64 = -1
    static let typingIndicatorId: Int64 = -2
    
    // Note: This init method is only used system-created cells or empty states
    init(isTypingIndicator: Bool? = nil) {
        self.threadId = "INVALID_THREAD_ID"
        self.threadVariant = .contact
        self.threadIsTrusted = false
        self.threadHasDisappearingMessagesEnabled = false
        self.threadOpenGroupServer = nil
        self.threadOpenGroupPublicKey = nil
        self.threadContactNameInternal = nil
        
        // Interaction Info
        
        let targetId: Int64 = (isTypingIndicator == true ?
            MessageViewModel.typingIndicatorId :
            MessageViewModel.genericId
        )
        self.rowId = targetId
        self.id = targetId
        self.variant = .standardOutgoing
        self.timestampMs = Int64.max
        self.authorId = ""
        self.authorNameInternal = nil
        self.body = nil
        self.rawBody = nil
        self.expiresStartedAtMs = nil
        self.expiresInSeconds = nil
        
        self.state = .sent
        self.hasAtLeastOneReadReceipt = false
        self.mostRecentFailureText = nil
        self.isSenderOpenGroupModerator = false
        self.isTypingIndicator = isTypingIndicator
        self.profile = nil
        self.quote = nil
        self.quoteAttachment = nil
        self.linkPreview = nil
        self.linkPreviewAttachment = nil
        self.currentUserPublicKey = ""
        
        // Post-Query Processing Data
        
        self.attachments = nil
        self.reactionInfo = nil
        self.cellType = .typingIndicator
        self.authorName = ""
        self.senderName = nil
        self.shouldShowProfile = false
        self.dateForUI = nil
        self.containsOnlyEmoji = nil
        self.glyphCount = nil
        self.previousVariant = nil
        self.positionInCluster = .middle
        self.isOnlyMessageInCluster = true
        self.isLast = true
        self.currentUserBlindedPublicKey = nil
    }
}

// MARK: - Convenience

extension MessageViewModel {
    private static let maxMinutesBetweenTwoDateBreaks: Int = 5
    
    /// Returns the difference in minutes, ignoring seconds
    ///
    /// If both dates are the same date, returns 0
    /// If firstDate is one minute before secondDate, returns 1
    ///
    /// **Note:** Assumes both dates use the "current" calendar
    private static func minutesFrom(_ firstDate: Date, to secondDate: Date) -> Int? {
        let calendar: Calendar = Calendar.current
        let components1: DateComponents = calendar.dateComponents(
            [.era, .year, .month, .day, .hour, .minute],
            from: firstDate
        )
        let components2: DateComponents = calendar.dateComponents(
            [.era, .year, .month, .day, .hour, .minute],
            from: secondDate
        )
        
        guard
            let date1: Date = calendar.date(from: components1),
            let date2: Date = calendar.date(from: components2)
        else { return nil }
        
        return calendar.dateComponents([.minute], from: date1, to: date2).minute
    }
    
    fileprivate static func shouldShowDateBreak(between timestamp1: Int64, and timestamp2: Int64) -> Bool {
        let date1: Date = Date(timeIntervalSince1970: (TimeInterval(timestamp1) / 1000))
        let date2: Date = Date(timeIntervalSince1970: (TimeInterval(timestamp2) / 1000))
        
        return ((minutesFrom(date1, to: date2) ?? 0) > maxMinutesBetweenTwoDateBreaks)
    }
}

// MARK: - ConversationVC

// MARK: --MessageViewModel

public extension MessageViewModel {
    static func filterSQL(threadId: String) -> SQL {
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        
        return SQL("\(interaction[.threadId]) = \(threadId)")
    }
    
    static let groupSQL: SQL = {
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        
        return SQL("GROUP BY \(interaction[.id])")
    }()
    
    static let orderSQL: SQL = {
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        
        return SQL("\(interaction[.timestampMs].desc)")
    }()
    
    static func baseQuery(
        userPublicKey: String,
        orderSQL: SQL,
        groupSQL: SQL?
    ) -> (([Int64]) -> AdaptedFetchRequest<SQLRequest<MessageViewModel>>) {
        return { rowIds -> AdaptedFetchRequest<SQLRequest<ViewModel>> in
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
            let openGroup: TypedTableAlias<OpenGroup> = TypedTableAlias()
            let recipientState: TypedTableAlias<RecipientState> = TypedTableAlias()
            let contact: TypedTableAlias<Contact> = TypedTableAlias()
            let disappearingMessagesConfig: TypedTableAlias<DisappearingMessagesConfiguration> = TypedTableAlias()
            let profile: TypedTableAlias<Profile> = TypedTableAlias()
            let quote: TypedTableAlias<Quote> = TypedTableAlias()
            let linkPreview: TypedTableAlias<LinkPreview> = TypedTableAlias()
            
            let threadProfileTableLiteral: SQL = SQL(stringLiteral: "threadProfile")
            let profileIdColumnLiteral: SQL = SQL(stringLiteral: Profile.Columns.id.name)
            let profileNicknameColumnLiteral: SQL = SQL(stringLiteral: Profile.Columns.nickname.name)
            let profileNameColumnLiteral: SQL = SQL(stringLiteral: Profile.Columns.name.name)
            let interactionStateInteractionIdColumnLiteral: SQL = SQL(stringLiteral: RecipientState.Columns.interactionId.name)
            let readReceiptTableLiteral: SQL = SQL(stringLiteral: "readReceipt")
            let readReceiptReadTimestampMsColumnLiteral: SQL = SQL(stringLiteral: RecipientState.Columns.readTimestampMs.name)
            let attachmentIdColumnLiteral: SQL = SQL(stringLiteral: Attachment.Columns.id.name)
            let groupMemberModeratorTableLiteral: SQL = SQL(stringLiteral: "groupMemberModerator")
            let groupMemberAdminTableLiteral: SQL = SQL(stringLiteral: "groupMemberAdmin")
            let groupMemberGroupIdColumnLiteral: SQL = SQL(stringLiteral: GroupMember.Columns.groupId.name)
            let groupMemberProfileIdColumnLiteral: SQL = SQL(stringLiteral: GroupMember.Columns.profileId.name)
            let groupMemberRoleColumnLiteral: SQL = SQL(stringLiteral: GroupMember.Columns.role.name)
            
            let numColumnsBeforeLinkedRecords: Int = 20
            let request: SQLRequest<ViewModel> = """
                SELECT
                    \(thread[.id]) AS \(ViewModel.threadIdKey),
                    \(thread[.variant]) AS \(ViewModel.threadVariantKey),
                    -- Default to 'true' for non-contact threads
                    IFNULL(\(contact[.isTrusted]), true) AS \(ViewModel.threadIsTrustedKey),
                    -- Default to 'false' when no contact exists
                    IFNULL(\(disappearingMessagesConfig[.isEnabled]), false) AS \(ViewModel.threadHasDisappearingMessagesEnabledKey),
                    \(openGroup[.server]) AS \(ViewModel.threadOpenGroupServerKey),
                    \(openGroup[.publicKey]) AS \(ViewModel.threadOpenGroupPublicKeyKey),
                    IFNULL(\(threadProfileTableLiteral).\(profileNicknameColumnLiteral), \(threadProfileTableLiteral).\(profileNameColumnLiteral)) AS \(ViewModel.threadContactNameInternalKey),
            
                    \(interaction.alias[Column.rowID]) AS \(ViewModel.rowIdKey),
                    \(interaction[.id]),
                    \(interaction[.variant]),
                    \(interaction[.timestampMs]),
                    \(interaction[.authorId]),
                    IFNULL(\(profile[.nickname]), \(profile[.name])) AS \(ViewModel.authorNameInternalKey),
                    \(interaction[.body]),
                    \(interaction[.expiresStartedAtMs]),
                    \(interaction[.expiresInSeconds]),
            
                    -- Default to 'sending' assuming non-processed interaction when null
                    IFNULL(MIN(\(recipientState[.state])), \(SQL("\(RecipientState.State.sending)"))) AS \(ViewModel.stateKey),
                    (\(readReceiptTableLiteral).\(readReceiptReadTimestampMsColumnLiteral) IS NOT NULL) AS \(ViewModel.hasAtLeastOneReadReceiptKey),
                    \(recipientState[.mostRecentFailureText]) AS \(ViewModel.mostRecentFailureTextKey),
                    
                    (
                        \(groupMemberModeratorTableLiteral).\(groupMemberProfileIdColumnLiteral) IS NOT NULL OR
                        \(groupMemberAdminTableLiteral).\(groupMemberProfileIdColumnLiteral) IS NOT NULL
                    ) AS \(ViewModel.isSenderOpenGroupModeratorKey),
            
                    \(ViewModel.profileKey).*,
                    \(ViewModel.quoteKey).*,
                    \(ViewModel.quoteAttachmentKey).*,
                    \(ViewModel.linkPreviewKey).*,
                    \(ViewModel.linkPreviewAttachmentKey).*,
            
                    \(SQL("\(userPublicKey)")) AS \(ViewModel.currentUserPublicKeyKey),
            
                    -- All of the below properties are set in post-query processing but to prevent the
                    -- query from crashing when decoding we need to provide default values
                    \(CellType.textOnlyMessage) AS \(ViewModel.cellTypeKey),
                    '' AS \(ViewModel.authorNameKey),
                    false AS \(ViewModel.shouldShowProfileKey),
                    \(Position.middle) AS \(ViewModel.positionInClusterKey),
                    false AS \(ViewModel.isOnlyMessageInClusterKey),
                    false AS \(ViewModel.isLastKey)
                
                FROM \(Interaction.self)
                JOIN \(SessionThread.self) ON \(thread[.id]) = \(interaction[.threadId])
                LEFT JOIN \(Contact.self) ON \(contact[.id]) = \(interaction[.threadId])
                LEFT JOIN \(Profile.self) AS \(threadProfileTableLiteral) ON \(threadProfileTableLiteral).\(profileIdColumnLiteral) = \(interaction[.threadId])
                LEFT JOIN \(DisappearingMessagesConfiguration.self) ON \(disappearingMessagesConfig[.threadId]) = \(interaction[.threadId])
                LEFT JOIN \(OpenGroup.self) ON \(openGroup[.threadId]) = \(interaction[.threadId])
                LEFT JOIN \(Profile.self) ON \(profile[.id]) = \(interaction[.authorId])
                LEFT JOIN \(Quote.self) ON \(quote[.interactionId]) = \(interaction[.id])
                LEFT JOIN \(Attachment.self) AS \(ViewModel.quoteAttachmentKey) ON \(ViewModel.quoteAttachmentKey).\(attachmentIdColumnLiteral) = \(quote[.attachmentId])
                LEFT JOIN \(LinkPreview.self) ON (
                    \(linkPreview[.url]) = \(interaction[.linkPreviewUrl]) AND
                    \(Interaction.linkPreviewFilterLiteral())
                )
                LEFT JOIN \(Attachment.self) AS \(ViewModel.linkPreviewAttachmentKey) ON \(ViewModel.linkPreviewAttachmentKey).\(attachmentIdColumnLiteral) = \(linkPreview[.attachmentId])
                LEFT JOIN \(RecipientState.self) ON (
                    -- Ignore 'skipped' states
                    \(SQL("\(recipientState[.state]) != \(RecipientState.State.skipped)")) AND
                    \(recipientState[.interactionId]) = \(interaction[.id])
                )
                LEFT JOIN \(RecipientState.self) AS \(readReceiptTableLiteral) ON (
                    \(readReceiptTableLiteral).\(readReceiptReadTimestampMsColumnLiteral) IS NOT NULL AND
                    \(interaction[.id]) = \(readReceiptTableLiteral).\(interactionStateInteractionIdColumnLiteral)
                )
                LEFT JOIN \(GroupMember.self) AS \(groupMemberModeratorTableLiteral) ON (
                    \(SQL("\(thread[.variant]) = \(SessionThread.Variant.openGroup)")) AND
                    \(groupMemberModeratorTableLiteral).\(groupMemberGroupIdColumnLiteral) = \(interaction[.threadId]) AND
                    \(groupMemberModeratorTableLiteral).\(groupMemberProfileIdColumnLiteral) = \(interaction[.authorId]) AND
                    \(SQL("\(groupMemberModeratorTableLiteral).\(groupMemberRoleColumnLiteral) = \(GroupMember.Role.moderator)"))
                )
                LEFT JOIN \(GroupMember.self) AS \(groupMemberAdminTableLiteral) ON (
                    \(SQL("\(thread[.variant]) = \(SessionThread.Variant.openGroup)")) AND
                    \(groupMemberAdminTableLiteral).\(groupMemberGroupIdColumnLiteral) = \(interaction[.threadId]) AND
                    \(groupMemberAdminTableLiteral).\(groupMemberProfileIdColumnLiteral) = \(interaction[.authorId]) AND
                    \(SQL("\(groupMemberAdminTableLiteral).\(groupMemberRoleColumnLiteral) = \(GroupMember.Role.admin)"))
                )
                WHERE \(interaction.alias[Column.rowID]) IN \(rowIds)
                \(groupSQL ?? "")
                ORDER BY \(orderSQL)
            """
            
            return request.adapted { db in
                let adapters = try splittingRowAdapters(columnCounts: [
                    numColumnsBeforeLinkedRecords,
                    Profile.numberOfSelectedColumns(db),
                    Quote.numberOfSelectedColumns(db),
                    Attachment.numberOfSelectedColumns(db),
                    LinkPreview.numberOfSelectedColumns(db),
                    Attachment.numberOfSelectedColumns(db)
                ])
                
                return ScopeAdapter([
                    ViewModel.profileString: adapters[1],
                    ViewModel.quoteString: adapters[2],
                    ViewModel.quoteAttachmentString: adapters[3],
                    ViewModel.linkPreviewString: adapters[4],
                    ViewModel.linkPreviewAttachmentString: adapters[5]
                ])
            }
        }
    }
}

// MARK: --AttachmentInteractionInfo

public extension MessageViewModel.AttachmentInteractionInfo {
    static let baseQuery: ((SQL?) -> AdaptedFetchRequest<SQLRequest<MessageViewModel.AttachmentInteractionInfo>>) = {
        return { additionalFilters -> AdaptedFetchRequest<SQLRequest<AttachmentInteractionInfo>> in
            let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
            let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
            
            let finalFilterSQL: SQL = {
                guard let additionalFilters: SQL = additionalFilters else {
                    return SQL(stringLiteral: "")
                }
                
                return """
                    WHERE \(additionalFilters)
                """
            }()
            let numColumnsBeforeLinkedRecords: Int = 1
            let request: SQLRequest<AttachmentInteractionInfo> = """
                SELECT
                    \(attachment.alias[Column.rowID]) AS \(AttachmentInteractionInfo.rowIdKey),
                    \(AttachmentInteractionInfo.attachmentKey).*,
                    \(AttachmentInteractionInfo.interactionAttachmentKey).*
                FROM \(Attachment.self)
                JOIN \(InteractionAttachment.self) ON \(interactionAttachment[.attachmentId]) = \(attachment[.id])
                \(finalFilterSQL)
            """
            
            return request.adapted { db in
                let adapters = try splittingRowAdapters(columnCounts: [
                    numColumnsBeforeLinkedRecords,
                    Attachment.numberOfSelectedColumns(db),
                    InteractionAttachment.numberOfSelectedColumns(db)
                ])
                
                return ScopeAdapter([
                    AttachmentInteractionInfo.attachmentString: adapters[1],
                    AttachmentInteractionInfo.interactionAttachmentString: adapters[2]
                ])
            }
        }
    }()
    
    static var joinToViewModelQuerySQL: SQL = {
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
        let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
        
        return """
            JOIN \(InteractionAttachment.self) ON \(interactionAttachment[.interactionId]) = \(interaction[.id])
            JOIN \(Attachment.self) ON \(attachment[.id]) = \(interactionAttachment[.attachmentId])
        """
    }()
    
    static func createAssociateDataClosure() -> (DataCache<MessageViewModel.AttachmentInteractionInfo>, DataCache<MessageViewModel>) -> DataCache<MessageViewModel> {
        return { dataCache, pagedDataCache -> DataCache<MessageViewModel> in
            var updatedPagedDataCache: DataCache<MessageViewModel> = pagedDataCache
            
            dataCache
                .values
                .grouped(by: \.interactionAttachment.interactionId)
                .forEach { (interactionId: Int64, attachments: [MessageViewModel.AttachmentInteractionInfo]) in
                    guard
                        let interactionRowId: Int64 = updatedPagedDataCache.lookup[interactionId],
                        let dataToUpdate: ViewModel = updatedPagedDataCache.data[interactionRowId]
                    else { return }
                    
                    updatedPagedDataCache = updatedPagedDataCache.upserting(
                        dataToUpdate.with(
                            attachments: .update(
                                attachments
                                    .sorted()
                                    .map { $0.attachment }
                            )
                        )
                    )
                }
            
            return updatedPagedDataCache
        }
    }
}

// MARK: --ReactionInfo

public extension MessageViewModel.ReactionInfo {
    static let baseQuery: ((SQL?) -> AdaptedFetchRequest<SQLRequest<MessageViewModel.ReactionInfo>>) = {
        return { additionalFilters -> AdaptedFetchRequest<SQLRequest<ReactionInfo>> in
            let reaction: TypedTableAlias<Reaction> = TypedTableAlias()
            let profile: TypedTableAlias<Profile> = TypedTableAlias()
            
            let finalFilterSQL: SQL = {
                guard let additionalFilters: SQL = additionalFilters else {
                    return SQL(stringLiteral: "")
                }
                
                return """
                    WHERE \(additionalFilters)
                """
            }()
            let numColumnsBeforeLinkedRecords: Int = 1
            let request: SQLRequest<ReactionInfo> = """
                SELECT
                    \(reaction.alias[Column.rowID]) AS \(ReactionInfo.rowIdKey),
                    \(ReactionInfo.reactionKey).*,
                    \(ReactionInfo.profileKey).*
                FROM \(Reaction.self)
                LEFT JOIN \(Profile.self) ON \(profile[.id]) = \(reaction[.authorId])
                \(finalFilterSQL)
            """
            
            return request.adapted { db in
                let adapters = try splittingRowAdapters(columnCounts: [
                    numColumnsBeforeLinkedRecords,
                    Reaction.numberOfSelectedColumns(db),
                    Profile.numberOfSelectedColumns(db)
                ])
                
                return ScopeAdapter([
                    ReactionInfo.reactionString: adapters[1],
                    ReactionInfo.profileString: adapters[2]
                ])
            }
        }
    }()
    
    static var joinToViewModelQuerySQL: SQL = {
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        let reaction: TypedTableAlias<Reaction> = TypedTableAlias()
        
        return """
            JOIN \(Reaction.self) ON \(reaction[.interactionId]) = \(interaction[.id])
        """
    }()
    
    static func createAssociateDataClosure() -> (DataCache<MessageViewModel.ReactionInfo>, DataCache<MessageViewModel>) -> DataCache<MessageViewModel> {
        return { dataCache, pagedDataCache -> DataCache<MessageViewModel> in
            var updatedPagedDataCache: DataCache<MessageViewModel> = pagedDataCache
            var pagedRowIdsWithNoReactions: Set<Int64> = Set(pagedDataCache.data.keys)
            
            // Add any new reactions
            dataCache
                .values
                .grouped(by: \.reaction.interactionId)
                .forEach { (interactionId: Int64, reactionInfo: [MessageViewModel.ReactionInfo]) in
                    guard
                        let interactionRowId: Int64 = updatedPagedDataCache.lookup[interactionId],
                        let dataToUpdate: ViewModel = updatedPagedDataCache.data[interactionRowId]
                    else { return }
                    
                    updatedPagedDataCache = updatedPagedDataCache.upserting(
                        dataToUpdate.with(reactionInfo: .update(reactionInfo.sorted()))
                    )
                    pagedRowIdsWithNoReactions.remove(interactionRowId)
                }
            
            // Remove any removed reactions
            updatedPagedDataCache = updatedPagedDataCache.upserting(
                items: pagedRowIdsWithNoReactions
                    .compactMap { rowId -> ViewModel? in updatedPagedDataCache.data[rowId] }
                    .filter { viewModel -> Bool in (viewModel.reactionInfo?.isEmpty == false) }
                    .map { viewModel -> ViewModel in viewModel.with(reactionInfo: nil) }
            )
            
            return updatedPagedDataCache
        }
    }
}

// MARK: --TypingIndicatorInfo

public extension MessageViewModel.TypingIndicatorInfo {
    static let baseQuery: ((SQL?) -> SQLRequest<MessageViewModel.TypingIndicatorInfo>) = {
        return { additionalFilters -> SQLRequest<TypingIndicatorInfo> in
            let threadTypingIndicator: TypedTableAlias<ThreadTypingIndicator> = TypedTableAlias()
            let finalFilterSQL: SQL = {
                guard let additionalFilters: SQL = additionalFilters else {
                    return SQL(stringLiteral: "")
                }
                
                return """
                    WHERE \(additionalFilters)
                """
            }()
            let request: SQLRequest<MessageViewModel.TypingIndicatorInfo> = """
                SELECT
                    \(threadTypingIndicator.alias[Column.rowID]) AS \(MessageViewModel.TypingIndicatorInfo.rowIdKey),
                    \(threadTypingIndicator[.threadId]) AS \(MessageViewModel.TypingIndicatorInfo.threadIdKey)
                FROM \(ThreadTypingIndicator.self)
                \(finalFilterSQL)
            """
            
            return request
        }
    }()
    
    static var joinToViewModelQuerySQL: SQL = {
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        let threadTypingIndicator: TypedTableAlias<ThreadTypingIndicator> = TypedTableAlias()
        
        return """
            JOIN \(ThreadTypingIndicator.self) ON \(threadTypingIndicator[.threadId]) = \(interaction[.threadId])
        """
    }()
    
    static func createAssociateDataClosure() -> (DataCache<MessageViewModel.TypingIndicatorInfo>, DataCache<MessageViewModel>) -> DataCache<MessageViewModel> {
        return { dataCache, pagedDataCache -> DataCache<MessageViewModel> in
            guard !dataCache.data.isEmpty else {
                return pagedDataCache.deleting(rowIds: [MessageViewModel.typingIndicatorId])
            }
            
            return pagedDataCache
                .upserting(MessageViewModel(isTypingIndicator: true))
        }
    }
}
