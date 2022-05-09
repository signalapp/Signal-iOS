// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SignalUtilitiesKit

public class HomeViewModel {
    public enum Section: Differentiable {
        case messageRequests
        case threads
    }
    
    public struct ObservedInfo: Equatable {
        let unreadMessageRequestCount: Int
        let threadInfo: [ThreadInfo]
    }
    
    public struct ThreadInfo: FetchableRecord, Decodable, Equatable, Differentiable {
        public struct GroupMemberInfo: FetchableRecord, Decodable, Equatable {
            public let profile: Profile
        }
        public struct InteractionInfo: FetchableRecord, Decodable, Equatable {
            public struct AuthorInfo: FetchableRecord, Decodable, Equatable {
                public let id: String
                public let displayName: String
                public let nickname: String?
            }
            
            fileprivate static let timestampMsKey = CodingKeys.timestampMs.stringValue
            fileprivate static let threadVariantKey = CodingKeys.threadVariant.stringValue
            fileprivate static let authorInfoKey = CodingKeys.authorInfo.stringValue
            fileprivate static let isOpenGroupInvitationKey = CodingKeys.isOpenGroupInvitation.stringValue
            fileprivate static let recipientStatesKey = CodingKeys.recipientStates.stringValue
            
            public let id: Int64?
            public let variant: Interaction.Variant
            public let timestampMs: Double
            
            private let threadVariant: SessionThread.Variant
            private let body: String?
            private let attachments: [Attachment]?
            private let authorId: String
            private let authorInfo: AuthorInfo?
            private let isOpenGroupInvitation: Bool
            private let recipientStates: [RecipientState.State]?
            
            public var authorName: String {
                return Profile.displayName(
                    for: threadVariant,
                    id: (authorInfo?.id ?? authorId),
                    name: authorInfo?.displayName,
                    nickname: authorInfo?.nickname,
                    customFallback: (threadVariant == .contact && variant == .standardIncoming ?
                        "Anonymous" :
                        nil
                    )
                )
            }
            
            public var text: String {
                return Interaction.previewText(
                    variant: variant,
                    body: body,
                    authorDisplayName: authorName,
                    attachments: (attachments ?? []),
                    isOpenGroupInvitation: (isOpenGroupInvitation == true)
                )
            }
            
            public var state: RecipientState.State {
                return Interaction.state(for: (recipientStates ?? []))
            }
        }
        
        fileprivate static let closedGroupNameKey = CodingKeys.closedGroupName.stringValue
        fileprivate static let openGroupNameKey = CodingKeys.openGroupName.stringValue
        fileprivate static let openGroupProfilePictureDataKey = CodingKeys.openGroupProfilePictureData.stringValue
        fileprivate static let currentUserProfileKey = CodingKeys.currentUserProfile.stringValue
        fileprivate static let contactProfileKey = CodingKeys.contactProfile.stringValue
        fileprivate static let closedGroupAvatarProfilesKey = CodingKeys.closedGroupAvatarProfiles.stringValue
        fileprivate static let contactIsBlockedKey = CodingKeys.contactIsBlocked.stringValue
        fileprivate static let isNoteToSelfKey = CodingKeys.isNoteToSelf.stringValue
        fileprivate static let currentUserIsClosedGroupAdminKey = CodingKeys.currentUserIsClosedGroupAdmin.stringValue
        fileprivate static let threadUnreadCountKey = CodingKeys.threadUnreadCount.stringValue
        fileprivate static let threadUnreadMentionCountKey = CodingKeys.threadUnreadMentionCount.stringValue
        fileprivate static let lastInteractionInfoKey = CodingKeys.lastInteractionInfo.stringValue
        
        public var differenceIdentifier: String { id }
        
        public let id: String
        public let variant: SessionThread.Variant
        private let creationDateTimestamp: TimeInterval
        
        public let closedGroupName: String?
        public let openGroupName: String?
        public let openGroupProfilePictureData: Data?
        private let currentUserProfile: Profile
        private let contactProfile: Profile?
        private let closedGroupAvatarProfiles: [GroupMemberInfo]?
        
        public let mutedUntilTimestamp: TimeInterval?
        public let onlyNotifyForMentions: Bool
        public let isPinned: Bool
        
        /// A flag indicating whether the contact is blocked (will be null for non-contact threads)
        private let contactIsBlocked: Bool?
        
        public let isNoteToSelf: Bool
        private let currentUserIsClosedGroupAdmin: Bool?
        
        private let threadUnreadCount: UInt?
        private let threadUnreadMentionCount: UInt?
        
        public let lastInteractionInfo: InteractionInfo?
        
        public var displayName: String {
            return SessionThread.displayName(
                threadId: id,
                variant: variant,
                closedGroupName: closedGroupName,
                openGroupName: openGroupName,
                isNoteToSelf: isNoteToSelf,
                profile: contactProfile
            )
        }
        
        public var profile: Profile? {
            switch variant {
                case .contact: return contactProfile
                case .openGroup: return nil
                case .closedGroup:
                    // If there is only a single user in the group then we want to use the current user
                    // profile at the back
                    if closedGroupAvatarProfiles?.count == 1 {
                        return currentUserProfile
                    }
                    
                    return closedGroupAvatarProfiles?.first?.profile
            }
        }
        
        public var additionalProfile: Profile? {
            switch variant {
                case .closedGroup: return closedGroupAvatarProfiles?.last?.profile
                default: return nil
            }
        }
        
        public var lastInteractionDate: Date {
            guard let lastInteractionInfo: InteractionInfo = lastInteractionInfo else {
                return Date(timeIntervalSince1970: creationDateTimestamp)
            }
                            
            return Date(timeIntervalSince1970: (lastInteractionInfo.timestampMs / 1000))
        }
        
        /// A flag indicating whether the thread is blocked (only contact threads can be blocked)
        public var isBlocked: Bool {
            return (contactIsBlocked == true)
        }
        
        public var isGroupAdmin: Bool {
            return (currentUserIsClosedGroupAdmin == true)
        }
        
        public var unreadCount: UInt {
            return (threadUnreadCount ?? 0)
        }
        
        public var unreadMentionCount: UInt {
            return (threadUnreadMentionCount ?? 0)
        }
        
        fileprivate init() {
            self.id = "FALLBACK"
            self.variant = .contact
            self.creationDateTimestamp = 0
            self.closedGroupName = nil
            self.openGroupName = nil
            self.openGroupProfilePictureData = nil
            self.currentUserProfile = Profile(id: "", name: "")
            self.contactProfile = nil
            self.closedGroupAvatarProfiles = nil
            self.mutedUntilTimestamp = nil
            self.onlyNotifyForMentions = false
            self.isPinned = false
            self.contactIsBlocked = nil
            self.isNoteToSelf = false
            self.currentUserIsClosedGroupAdmin = nil
            self.threadUnreadCount = nil
            self.threadUnreadMentionCount = nil
            self.lastInteractionInfo = nil
        }
        
        // MARK: - Query
        
        public static func query(userPublicKey: String) -> QueryInterfaceRequest<ThreadInfo> {
            let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
            let contact: TypedTableAlias<Contact> = TypedTableAlias()
            let closedGroup: TypedTableAlias<ClosedGroup> = TypedTableAlias()
            let closedGroupMember: TypedTableAlias<GroupMember> = TypedTableAlias()
            let openGroup: TypedTableAlias<OpenGroup> = TypedTableAlias()
            let unreadInteractions: TableAlias = TableAlias()
            let unreadMentions: TableAlias = TableAlias()
            let lastInteraction: TableAlias = TableAlias()
            let lastInteractionThread: TypedTableAlias<SessionThread> = TypedTableAlias()
            let linkPreview: TypedTableAlias<LinkPreview> = TypedTableAlias()
            
            let currentUserProfileExpression: CommonTableExpression = CommonTableExpression(
                named: ThreadInfo.currentUserProfileKey,
                request: Profile.filter(id: userPublicKey)
            )
            let unreadInteractionExpression: CommonTableExpression = CommonTableExpression(
                named: ThreadInfo.threadUnreadCountKey,
                request: Interaction
                    .select(
                        count(Interaction.Columns.id).forKey(ThreadInfo.threadUnreadCountKey),
                        Interaction.Columns.threadId
                    )
                    .filter(Interaction.Columns.wasRead == false)
                    .group(Interaction.Columns.threadId)
            )
            let unreadMentionsExpression: CommonTableExpression = CommonTableExpression(
                named: ThreadInfo.threadUnreadMentionCountKey,
                request: Interaction
                    .select(
                        count(Interaction.Columns.id).forKey(ThreadInfo.threadUnreadMentionCountKey),
                        Interaction.Columns.threadId
                    )
                    .filter(Interaction.Columns.wasRead == false)
                    .filter(Interaction.Columns.hasMention == true)
                    .group(Interaction.Columns.threadId)
            )
            let lastInteractionExpression: CommonTableExpression = CommonTableExpression(
                named: ThreadInfo.lastInteractionInfoKey,
                request: Interaction
                    .select(
                        Interaction.Columns.id,
                        Interaction.Columns.threadId,
                        Interaction.Columns.variant,
                        
                        // 'max()' to get the latest
                        max(Interaction.Columns.timestampMs).forKey(ThreadInfo.InteractionInfo.timestampMsKey),
                        
                        lastInteractionThread[.variant].forKey(ThreadInfo.InteractionInfo.threadVariantKey),
                        Interaction.Columns.body,
                        Interaction.Columns.authorId,
                        (linkPreview[.url] != nil).forKey(ThreadInfo.InteractionInfo.isOpenGroupInvitationKey)
                    )
                    .joining(required: Interaction.thread.aliased(lastInteractionThread))
                    .joining(
                        optional: Interaction.linkPreview
                            .filter(literal: Interaction.linkPreviewFilterLiteral)
                            .filter(LinkPreview.Columns.variant == LinkPreview.Variant.openGroupInvitation)
                    )
                    .including(all: Interaction.attachments)
                    .including(
                        all: Interaction.recipientStates
                            .select(RecipientState.Columns.state)
                            .forKey(ThreadInfo.InteractionInfo.recipientStatesKey)
                    )
                    .group(Interaction.Columns.threadId)    // One interaction per thread
            )
            return SessionThread
                .select(
                    thread[.id],
                    thread[.variant],
                    thread[.creationDateTimestamp],

                    closedGroup[.name].forKey(ThreadInfo.closedGroupNameKey),
                    openGroup[.name].forKey(ThreadInfo.openGroupNameKey),
                    openGroup[.imageData].forKey(ThreadInfo.openGroupProfilePictureDataKey),

                    thread[.mutedUntilTimestamp],
                    thread[.onlyNotifyForMentions],
                    thread[.isPinned],
                    contact[.isBlocked].forKey(ThreadInfo.contactIsBlockedKey),
                    SessionThread.isNoteToSelf(userPublicKey: userPublicKey).forKey(ThreadInfo.isNoteToSelfKey),
                    (closedGroupMember[.profileId] != nil).forKey(ThreadInfo.currentUserIsClosedGroupAdminKey),
                    
                    unreadInteractions[ThreadInfo.threadUnreadCountKey],
                    unreadMentions[ThreadInfo.threadUnreadMentionCountKey]
                )
                .aliased(thread)
                .joining(
                    optional: SessionThread.contact
                        .aliased(contact)
                        .including(
                            optional: Contact.profile
                                .forKey(ThreadInfo.contactProfileKey)
                        )
                )
                .joining(
                    optional: SessionThread.closedGroup
                        .aliased(closedGroup)
                        .including(
                            all: ClosedGroup.members
                                .filter(GroupMember.Columns.role == GroupMember.Role.standard)
                                .filter(GroupMember.Columns.profileId != userPublicKey)
                                .order(GroupMember.Columns.profileId)   // Sort to provide a level of stability
                                .limit(2)
                                .including(required: GroupMember.profile)
                                .forKey(ThreadInfo.closedGroupAvatarProfilesKey)
                        )
                        .joining(
                            optional: ClosedGroup.members
                                .aliased(closedGroupMember)
                                .filter(GroupMember.Columns.role == GroupMember.Role.admin)
                                .filter(GroupMember.Columns.profileId == userPublicKey)
                        )
                )
                .joining(optional: SessionThread.openGroup.aliased(openGroup))
                .with(currentUserProfileExpression)
                .including(
                    required: SessionThread.association(to: currentUserProfileExpression)
                        .forKey(ThreadInfo.currentUserProfileKey)
                )
                .with(unreadInteractionExpression)
                .joining(
                    optional: SessionThread
                        .association(
                            to: unreadInteractionExpression,
                            on: { thread, unreadGroup in
                                thread[SessionThread.Columns.id] == unreadGroup[Interaction.Columns.threadId]
                            }
                        )
                        .aliased(unreadInteractions)
                )
                .with(unreadMentionsExpression)
                .joining(
                    optional: SessionThread
                        .association(
                            to: unreadMentionsExpression,
                            on: { thread, unreadMentions in
                                thread[SessionThread.Columns.id] == unreadMentions[Interaction.Columns.threadId]
                            }
                        )
                        .aliased(unreadMentions)
                )
                .with(lastInteractionExpression)
                .including(
                    optional: SessionThread
                        .association(
                            to: lastInteractionExpression,
                            on: { thread, lastInteraction in
                                thread[SessionThread.Columns.id] == lastInteraction[Interaction.Columns.threadId]
                            }
                        )
                        .aliased(lastInteraction)
                        .forKey(ThreadInfo.lastInteractionInfoKey)
                        .including(
                            optional: lastInteractionExpression
                                .association(
                                    to: CommonTableExpression(
                                        named: Profile.databaseTableName,
                                        request: Profile.select(.id, .name, .nickname)
                                    ),
                                    on: { lastInteraction, profile in
                                        lastInteraction[Interaction.Columns.authorId] == profile[Profile.Columns.id]
                                    }
                                )
                                .forKey(ThreadInfo.InteractionInfo.authorInfoKey)
                        )
                )
                .order(
                    lastInteraction[Interaction.Columns.timestampMs].desc,
                    thread[.creationDateTimestamp].desc
                )
                .asRequest(of: ThreadInfo.self)
        }
    }

    
    public struct Item: Equatable, Differentiable {
        public var differenceIdentifier: String {
            return threadInfo.id
        }
        
        let unreadCount: Int
        let threadInfo: ThreadInfo
    }
    
    /// This value is the current state of the view
    public private(set) var viewData: [ArraySection<Section, Item>] = []
    
    /// This is all the data the screen needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    ///
    /// **Note:** The 'trackingConstantRegion' is optimised in such a way that the request needs to be static
    /// otherwise there may be situations where it doesn't get updates, this means we can't have conditional queries
    public lazy var observableViewData = ValueObservation
        .trackingConstantRegion { db -> ObservedInfo in
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            let unreadMessageRequestCount: Int = try SessionThread
                .filter(SessionThread.isMessageRequest(userPublicKey: userPublicKey))
                .joining(optional: SessionThread.contact)
                .joining(
                    required: SessionThread.interactions
                        .filter(Interaction.Columns.wasRead == false)
                )
                .group(SessionThread.Columns.id)
                .fetchCount(db)
            
            return ObservedInfo(
                unreadMessageRequestCount: (db[.hasHiddenMessageRequests] ? 0 : unreadMessageRequestCount),
                threadInfo: try ThreadInfo
                    .query(userPublicKey: userPublicKey)
                    .filter(SessionThread.Columns.shouldBeVisible == true)
                    .filter(SessionThread.isNotMessageRequest(userPublicKey: userPublicKey))
                    .filter(
                        // Only show the Note to Self if it has a lastInteraction
                        SessionThread.Columns.id != userPublicKey ||
                        SQL(stringLiteral: "\(ThreadInfo.lastInteractionInfoKey).id IS NOT NULL")
                    )
                    .fetchAll(db)
            )
        }
        .removeDuplicates()
        .map { observedInfo -> [ArraySection<Section, Item>] in
            return [
                ArraySection(
                    model: .messageRequests,
                    elements: [
                        // If there are no unread message requests then hide the message request banner
                        (observedInfo.unreadMessageRequestCount == 0 ?
                            nil :
                            Item(
                                unreadCount: observedInfo.unreadMessageRequestCount,
                                threadInfo: ThreadInfo() // Won't be used
                            )
                        )
                    ].compactMap { $0 }
                ),
                ArraySection(
                    model: .threads,
                    elements: observedInfo.threadInfo
                        .map { info in
                            Item(
                                unreadCount: Int(info.unreadCount),
                                threadInfo: info
                            )
                        }
                ),
            ]
        }
    
    // MARK: - Functions
    
    public func updateData(_ updatedData: [ArraySection<Section, Item>]) {
        self.viewData = updatedData
    }
}
