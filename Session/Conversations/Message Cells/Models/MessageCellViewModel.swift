// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SessionUtilitiesKit
import SessionMessagingKit

fileprivate typealias ViewModel = MessageCell.ViewModel
fileprivate typealias AttachmentInteractionInfo = MessageCell.AttachmentInteractionInfo

extension MessageCell {
    public struct ViewModel: FetchableRecordWithRowId, Decodable, Equatable, Hashable, Identifiable, Differentiable {
        public static let threadVariantKey: SQL = SQL(stringLiteral: CodingKeys.threadVariant.stringValue)
        public static let threadIsTrustedKey: SQL = SQL(stringLiteral: CodingKeys.threadIsTrusted.stringValue)
        public static let threadHasDisappearingMessagesEnabledKey: SQL = SQL(stringLiteral: CodingKeys.threadHasDisappearingMessagesEnabled.stringValue)
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
        
        public var differenceIdentifier: ViewModel { self }
        
        // Thread Info
        
        let threadVariant: SessionThread.Variant
        let threadIsTrusted: Bool
        let threadHasDisappearingMessagesEnabled: Bool
        
        // Interaction Info
        
        public let rowId: Int64
        public let id: Int64
        let variant: Interaction.Variant
        let timestampMs: Int64
        let authorId: String
        private let authorNameInternal: String?
        let body: String?
        let expiresStartedAtMs: Double?
        let expiresInSeconds: TimeInterval?
        
        let state: RecipientState.State
        let hasAtLeastOneReadReceipt: Bool
        let mostRecentFailureText: String?
        let isTypingIndicator: Bool
        let isSenderOpenGroupModerator: Bool
        let profile: Profile?
        let quote: Quote?
        let quoteAttachment: Attachment?
        let linkPreview: LinkPreview?
        let linkPreviewAttachment: Attachment?
        
        // Post-Query Processing Data
        
        /// This value includes the associated attachments
        let attachments: [Attachment]?
        
        /// This value defines what type of cell should appear and is generated based on the interaction variant
        /// and associated attachment data
        let cellType: CellType
        
        /// This value includes the author name information
        let authorName: String

        /// This value will be used to populate the author label, if it's null then the label will be hidden
        let senderName: String?

        /// A flag indicating whether the profile view should be displayed
        let shouldShowProfile: Bool

        /// This value will be used to populate the date header, if it's null then the header will be hidden
        let dateForUI: Date?
        
        /// This value indicates the variant of the previous ViewModel item, if it's null then there is no previous item
        let previousVariant: Interaction.Variant?
        
        /// This value indicates the position of this message within a cluser of messages
        let positionInCluster: Position
        
        /// This value indicates whether this is the only message in a cluser of messages
        let isOnlyMessageInCluster: Bool
        
        /// This value indicates whether this is the last message in the thread
        let isLast: Bool

        // MARK: - Mutation
        
        public func with(attachments: [Attachment]) -> ViewModel {
            return ViewModel(
                threadVariant: self.threadVariant,
                threadIsTrusted: self.threadIsTrusted,
                threadHasDisappearingMessagesEnabled: self.threadHasDisappearingMessagesEnabled,
                rowId: self.rowId,
                id: self.id,
                variant: self.variant,
                timestampMs: self.timestampMs,
                authorId: self.authorId,
                authorNameInternal: self.authorNameInternal,
                body: self.body,
                expiresStartedAtMs: self.expiresStartedAtMs,
                expiresInSeconds: self.expiresInSeconds,
                state: self.state,
                hasAtLeastOneReadReceipt: self.hasAtLeastOneReadReceipt,
                mostRecentFailureText: self.mostRecentFailureText,
                isTypingIndicator: self.isTypingIndicator,
                isSenderOpenGroupModerator: self.isSenderOpenGroupModerator,
                profile: self.profile,
                quote: self.quote,
                quoteAttachment: self.quoteAttachment,
                linkPreview: self.linkPreview,
                linkPreviewAttachment: self.linkPreviewAttachment,
                attachments: attachments,
                cellType: self.cellType,
                authorName: self.authorName,
                senderName: self.senderName,
                shouldShowProfile: self.shouldShowProfile,
                dateForUI: self.dateForUI,
                previousVariant: self.previousVariant,
                positionInCluster: self.positionInCluster,
                isOnlyMessageInCluster: self.isOnlyMessageInCluster,
                isLast: self.isLast
            )
        }
        
        public func withClusteringChanges(
            prevModel: ViewModel?,
            nextModel: ViewModel?,
            isLast: Bool
        ) -> ViewModel {
            let cellType: CellType = {
                guard !self.isTypingIndicator else { return .typingIndicator }
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
                guard !self.isTypingIndicator else { return false }
                guard let prevModel: ViewModel = prevModel else { return true }
                
                return DateUtil.shouldShowDateBreak(
                    forTimestamp: UInt64(prevModel.timestampMs),
                    timestamp: UInt64(self.timestampMs)
                )
            }()
            let shouldShowDateOnNextModel: Bool = {
                // Should be nothing after a typing indicator
                guard !self.isTypingIndicator else { return false }
                guard let nextModel: ViewModel = nextModel else { return false }

                return DateUtil.shouldShowDateBreak(
                    forTimestamp: UInt64(self.timestampMs),
                    timestamp: UInt64(nextModel.timestampMs)
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
                threadVariant: self.threadVariant,
                threadIsTrusted: self.threadIsTrusted,
                threadHasDisappearingMessagesEnabled: self.threadHasDisappearingMessagesEnabled,
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
                expiresStartedAtMs: self.expiresStartedAtMs,
                expiresInSeconds: self.expiresInSeconds,
                state: self.state,
                hasAtLeastOneReadReceipt: self.hasAtLeastOneReadReceipt,
                mostRecentFailureText: self.mostRecentFailureText,
                isTypingIndicator: self.isTypingIndicator,
                isSenderOpenGroupModerator: self.isSenderOpenGroupModerator,
                profile: self.profile,
                quote: self.quote,
                quoteAttachment: self.quoteAttachment,
                linkPreview: self.linkPreview,
                linkPreviewAttachment: self.linkPreviewAttachment,
                attachments: self.attachments,
                cellType: cellType,
                authorName: authorDisplayName,
                senderName: {
                    // Only show for group threads
                    guard self.threadVariant == .openGroup || self.threadVariant == .closedGroup else {
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
                    
                    // Show if the next message has a different sender or has a "date break"
                    (
                        self.authorId != nextModel?.authorId ||
                        shouldShowDateOnNextModel
                    ) &&
                    
                    // Need a profile to be able to show it
                    self.profile != nil
                ),
                dateForUI: (shouldShowDateOnThisModel ?
                    Date(timeIntervalSince1970: (TimeInterval(self.timestampMs) / 1000)) :
                    nil
                ),
                previousVariant: prevModel?.variant,
                positionInCluster: positionInCluster,
                isOnlyMessageInCluster: isOnlyMessageInCluster,
                isLast: isLast
            )
        }
    }
    
    public struct AttachmentInteractionInfo: FetchableRecordWithRowId, Decodable, Identifiable, Equatable, Comparable {
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

// MARK: - Convenience Initialization

public extension MessageCell.ViewModel {
    // Note: This init method is only used system-created cells or empty states
    init(isTypingIndicator: Bool = false) {
        self.threadVariant = .contact
        self.threadIsTrusted = false
        self.threadHasDisappearingMessagesEnabled = false
        
        // Interaction Info
        
        self.rowId = -1
        self.id = -1
        self.variant = .standardOutgoing
        self.timestampMs = Int64.max
        self.authorId = ""
        self.authorNameInternal = nil
        self.body = nil
        self.expiresStartedAtMs = nil
        self.expiresInSeconds = nil
        
        self.state = .sent
        self.hasAtLeastOneReadReceipt = false
        self.mostRecentFailureText = nil
        self.isTypingIndicator = isTypingIndicator
        self.isSenderOpenGroupModerator = false
        self.profile = nil
        self.quote = nil
        self.quoteAttachment = nil
        self.linkPreview = nil
        self.linkPreviewAttachment = nil
        
        // Post-Query Processing Data
        
        self.attachments = nil
        self.cellType = .typingIndicator
        self.authorName = ""
        self.senderName = nil
        self.shouldShowProfile = false
        self.dateForUI = nil
        self.previousVariant = nil
        self.positionInCluster = .middle
        self.isOnlyMessageInCluster = true
        self.isLast = true
    }
}

// MARK: - ConversationVC

extension MessageCell.ViewModel {
    public static func filterSQL(threadId: String) -> SQL {
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        
        return SQL("\(interaction[.threadId]) = \(threadId)")
    }
    
    public static let orderSQL: SQL = {
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        
        return SQL("\(interaction[.timestampMs].desc)")
    }()
    
    public static func baseQuery(orderSQL: SQL, baseFilterSQL: SQL) -> ((SQL?, SQL?) -> AdaptedFetchRequest<SQLRequest<MessageCell.ViewModel>>) {
        return { additionalFilters, limitSQL -> AdaptedFetchRequest<SQLRequest<ViewModel>> in
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
            let contact: TypedTableAlias<Contact> = TypedTableAlias()
            let disappearingMessagesConfig: TypedTableAlias<DisappearingMessagesConfiguration> = TypedTableAlias()
            let profile: TypedTableAlias<Profile> = TypedTableAlias()
            let quote: TypedTableAlias<Quote> = TypedTableAlias()
            let linkPreview: TypedTableAlias<LinkPreview> = TypedTableAlias()
            
            let interactionStateTableLiteral: SQL = SQL(stringLiteral: "interactionState")
            let interactionStateInteractionIdColumnLiteral: SQL = SQL(stringLiteral: RecipientState.Columns.interactionId.name)
            let interactionStateStateColumnLiteral: SQL = SQL(stringLiteral: RecipientState.Columns.state.name)
            let interactionStateMostRecentFailureTextColumnLiteral: SQL = SQL(stringLiteral: RecipientState.Columns.mostRecentFailureText.name)
            let readReceiptTableLiteral: SQL = SQL(stringLiteral: "readReceipt")
            let readReceiptReadTimestampMsColumnLiteral: SQL = SQL(stringLiteral: RecipientState.Columns.readTimestampMs.name)
            let attachmentIdColumnLiteral: SQL = SQL(stringLiteral: Attachment.Columns.id.name)
            
            let finalFilterSQL: SQL = {
                guard let additionalFilters: SQL = additionalFilters else {
                    return """
                        WHERE \(baseFilterSQL)
                    """
                }
                
                return """
                    WHERE (
                        \(baseFilterSQL) AND
                        \(additionalFilters)
                    )
                """
            }()
            let finalLimitSQL: SQL = (limitSQL ?? SQL(stringLiteral: ""))
            let numColumnsBeforeLinkedRecords: Int = 17
            let request: SQLRequest<ViewModel> = """
                SELECT
                    \(thread[.variant]) AS \(ViewModel.threadVariantKey),
                    -- Default to 'true' for non-contact threads
                    IFNULL(\(contact[.isTrusted]), true) AS \(ViewModel.threadIsTrustedKey),
                    -- Default to 'false' when no contact exists
                    IFNULL(\(disappearingMessagesConfig[.isEnabled]), false) AS \(ViewModel.threadHasDisappearingMessagesEnabledKey),
            
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
                    IFNULL(\(interactionStateTableLiteral).\(interactionStateStateColumnLiteral), \(SQL("\(RecipientState.State.sending)"))) AS \(ViewModel.stateKey),
                    (\(readReceiptTableLiteral).\(readReceiptReadTimestampMsColumnLiteral) IS NOT NULL) AS \(ViewModel.hasAtLeastOneReadReceiptKey),
                    \(interactionStateTableLiteral).\(interactionStateMostRecentFailureTextColumnLiteral) AS \(ViewModel.mostRecentFailureTextKey),
                        
                    false AS \(ViewModel.isTypingIndicatorKey),
                    false AS \(ViewModel.isSenderOpenGroupModeratorKey),
            
                    \(ViewModel.profileKey).*,
                    \(ViewModel.quoteKey).*,
                    \(ViewModel.quoteAttachmentKey).*,
                    \(ViewModel.linkPreviewKey).*,
                    \(ViewModel.linkPreviewAttachmentKey).*,
            
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
                LEFT JOIN \(DisappearingMessagesConfiguration.self) ON \(disappearingMessagesConfig[.threadId]) = \(interaction[.threadId])
                LEFT JOIN \(Profile.self) ON \(profile[.id]) = \(interaction[.authorId])
                LEFT JOIN \(Quote.self) ON \(quote[.interactionId]) = \(interaction[.id])
                LEFT JOIN \(Attachment.self) AS \(ViewModel.quoteAttachmentKey) ON \(ViewModel.quoteAttachmentKey).\(attachmentIdColumnLiteral) = \(quote[.attachmentId])
                LEFT JOIN \(LinkPreview.self) ON (
                    \(linkPreview[.url]) = \(interaction[.linkPreviewUrl]) AND
                    \(Interaction.linkPreviewFilterLiteral)
                )
                LEFT JOIN \(Attachment.self) AS \(ViewModel.linkPreviewAttachmentKey) ON \(ViewModel.linkPreviewAttachmentKey).\(attachmentIdColumnLiteral) = \(linkPreview[.attachmentId])
                LEFT JOIN (
                    \(RecipientState.selectInteractionState(
                        tableLiteral: interactionStateTableLiteral,
                        idColumnLiteral: interactionStateInteractionIdColumnLiteral
                    ))
                ) AS \(interactionStateTableLiteral) ON \(interactionStateTableLiteral).\(interactionStateInteractionIdColumnLiteral) = \(interaction[.id])
                LEFT JOIN \(RecipientState.self) AS \(readReceiptTableLiteral) ON (
                    \(readReceiptTableLiteral).\(readReceiptReadTimestampMsColumnLiteral) IS NOT NULL AND
                    \(interaction[.id]) = \(readReceiptTableLiteral).\(interactionStateInteractionIdColumnLiteral)
                )
                \(finalFilterSQL)
                ORDER BY \(orderSQL)
                \(finalLimitSQL)
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

extension MessageCell.AttachmentInteractionInfo {
    public static let baseQuery: ((SQL?) -> AdaptedFetchRequest<SQLRequest<MessageCell.AttachmentInteractionInfo>>) = {
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
    
    public static var joinToViewModelQuerySQL: SQL = {
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
        let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
        
        return """
            JOIN \(InteractionAttachment.self) ON \(interactionAttachment[.attachmentId]) = \(attachment[.id])
            JOIN \(Interaction.self) ON
                \(interaction[.id]) = \(interactionAttachment[.interactionId])
        """
    }()
    
    public static func createAssociateDataClosure() -> (DataCache<MessageCell.AttachmentInteractionInfo>, DataCache<MessageCell.ViewModel>) -> DataCache<MessageCell.ViewModel> {
        return { dataCache, pagedDataCache -> DataCache<MessageCell.ViewModel> in
            var updatedPagedDataCache: DataCache<MessageCell.ViewModel> = pagedDataCache
            
            dataCache
                .values
                .grouped(by: \.interactionAttachment.interactionId)
                .forEach { (interactionId: Int64, attachments: [MessageCell.AttachmentInteractionInfo]) in
                    guard
                        let interactionRowId: Int64 = updatedPagedDataCache.lookup[interactionId],
                        let dataToUpdate: ViewModel = updatedPagedDataCache.data[interactionRowId]
                    else { return }
                    
                    updatedPagedDataCache = updatedPagedDataCache.upserting(
                        dataToUpdate.with(
                            attachments: attachments
                                .sorted()
                                .map { $0.attachment }
                        )
                    )
                }
            
            return updatedPagedDataCache
        }
    }
}
