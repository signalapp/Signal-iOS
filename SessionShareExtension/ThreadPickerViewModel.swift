// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SignalUtilitiesKit
import SessionMessagingKit

public class ThreadPickerViewModel {
    // MARK: - Initialization
    
    init() {
        viewData = ViewData(
            currentUserProfile: Profile.fetchOrCreateCurrentUser(),
            items: []
        )
    }
    
    public struct Item: FetchableRecord, Decodable, Equatable, Differentiable {
        public struct GroupMemberInfo: FetchableRecord, Decodable, Equatable {
            public let profile: Profile
        }
        
        fileprivate static let closedGroupNameKey = CodingKeys.closedGroupName.stringValue
        fileprivate static let openGroupNameKey = CodingKeys.openGroupName.stringValue
        fileprivate static let openGroupProfilePictureDataKey = CodingKeys.openGroupProfilePictureData.stringValue
        fileprivate static let contactProfileKey = CodingKeys.contactProfile.stringValue
        fileprivate static let closedGroupAvatarProfilesKey = CodingKeys.closedGroupAvatarProfiles.stringValue
        fileprivate static let contactIsBlockedKey = CodingKeys.contactIsBlocked.stringValue
        fileprivate static let isNoteToSelfKey = CodingKeys.isNoteToSelf.stringValue
        
        public var differenceIdentifier: String { id }
        
        public let id: String
        public let variant: SessionThread.Variant
        
        public let closedGroupName: String?
        public let openGroupName: String?
        public let openGroupProfilePictureData: Data?
        private let contactProfile: Profile?
        private let closedGroupAvatarProfiles: [GroupMemberInfo]?
        
        /// A flag indicating whether the contact is blocked (will be null for non-contact threads)
        private let contactIsBlocked: Bool?
        public let isNoteToSelf: Bool
        
        public func displayName(currentUserProfile: Profile) -> String {
            return SessionThread.displayName(
                threadId: id,
                variant: variant,
                closedGroupName: closedGroupName,
                openGroupName: openGroupName,
                isNoteToSelf: isNoteToSelf,
                profile: contactProfile
            )
        }
        
        public func profile(currentUserProfile: Profile) -> Profile? {
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
        
        /// A flag indicating whether the thread is blocked (only contact threads can be blocked)
        public var isBlocked: Bool {
            return (contactIsBlocked == true)
        }
        
        // MARK: - Query
        
        public static func query(userPublicKey: String) -> QueryInterfaceRequest<Item> {
            let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
            let contact: TypedTableAlias<Contact> = TypedTableAlias()
            let closedGroup: TypedTableAlias<ClosedGroup> = TypedTableAlias()
            let openGroup: TypedTableAlias<OpenGroup> = TypedTableAlias()
            let lastInteraction: TableAlias = TableAlias()
            
            let lastInteractionTimestampExpression: CommonTableExpression = Interaction.lastInteractionTimestamp(
                timestampMsKey: Interaction.Columns.timestampMs.stringValue
            )
            // FIXME: Exclude unwritable opengroups
            return SessionThread
                .select(
                    thread[.id],
                    thread[.variant],
                    thread[.creationDateTimestamp],

                    closedGroup[.name].forKey(Item.closedGroupNameKey),
                    openGroup[.name].forKey(Item.openGroupNameKey),
                    openGroup[.imageData].forKey(Item.openGroupProfilePictureDataKey),

                    contact[.isBlocked].forKey(Item.contactIsBlockedKey),
                    SessionThread.isNoteToSelf(userPublicKey: userPublicKey).forKey(Item.isNoteToSelfKey)
                )
                .filter(SessionThread.Columns.shouldBeVisible == true)
                .filter(SessionThread.isNotMessageRequest(userPublicKey: userPublicKey))
                .filter(
                    // Only show the Note to Self if it has an interaction
                    SessionThread.Columns.id != userPublicKey ||
                    lastInteraction[Interaction.Columns.timestampMs] != nil
                )
                .aliased(thread)
                .joining(
                    optional: SessionThread.contact
                        .aliased(contact)
                        .including(
                            optional: Contact.profile
                                .forKey(Item.contactProfileKey)
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
                                .forKey(Item.closedGroupAvatarProfilesKey)
                        )
                )
                .joining(optional: SessionThread.openGroup.aliased(openGroup))
                .with(lastInteractionTimestampExpression)
                .including(
                    optional: SessionThread
                        .association(
                            to: lastInteractionTimestampExpression,
                            on: { thread, lastInteraction in
                                thread[SessionThread.Columns.id] == lastInteraction[Interaction.Columns.threadId]
                            }
                        )
                        .aliased(lastInteraction)
                )
                .order(
                    (
                        lastInteraction[Interaction.Columns.timestampMs] ??
                        (thread[.creationDateTimestamp] * 1000)
                    ).desc
                )
                .asRequest(of: Item.self)
        }
    }
    
    public struct ViewData: Equatable {
        let currentUserProfile: Profile
        let items: [Item]
    }
    
    /// This value is the current state of the view
    public private(set) var viewData: ViewData
    
    /// This is all the data the screen needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    ///
    /// **Note:** The 'trackingConstantRegion' is optimised in such a way that the request needs to be static
    /// otherwise there may be situations where it doesn't get updates, this means we can't have conditional queries
    public lazy var observableViewData = ValueObservation
        .trackingConstantRegion { db -> ViewData in
            let currentUserProfile: Profile = Profile.fetchOrCreateCurrentUser(db)
            return ViewData(
                currentUserProfile: Profile.fetchOrCreateCurrentUser(db),
                items: try Item
                    .query(userPublicKey: currentUserProfile.id)
                    .fetchAll(db)
            )
        }
        .removeDuplicates()
    
    // MARK: - Functions
    
    public func updateData(_ updatedData: ViewData) {
        self.viewData = updatedData
    }
}
