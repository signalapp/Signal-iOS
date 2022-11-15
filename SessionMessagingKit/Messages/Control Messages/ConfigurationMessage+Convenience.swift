// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

extension ConfigurationMessage {
    public static func getCurrent(_ db: Database) throws -> ConfigurationMessage {
        let currentUserProfile: Profile = Profile.fetchOrCreateCurrentUser(db)
        let displayName: String = currentUserProfile.name
        let profilePictureUrl: String? = currentUserProfile.profilePictureUrl
        let profileKey: Data? = currentUserProfile.profileEncryptionKey?.keyData
        let closedGroups: Set<CMClosedGroup> = try ClosedGroup.fetchAll(db)
            .compactMap { closedGroup -> CMClosedGroup? in
                guard let latestKeyPair: ClosedGroupKeyPair = try closedGroup.fetchLatestKeyPair(db) else {
                    return nil
                }
                
                return CMClosedGroup(
                    publicKey: closedGroup.publicKey,
                    name: closedGroup.name,
                    encryptionKeyPublicKey: latestKeyPair.publicKey,
                    encryptionKeySecretKey: latestKeyPair.secretKey,
                    members: try closedGroup.members
                        .select(GroupMember.Columns.profileId)
                        .asRequest(of: String.self)
                        .fetchSet(db),
                    admins: try closedGroup.admins
                        .select(GroupMember.Columns.profileId)
                        .asRequest(of: String.self)
                        .fetchSet(db),
                    expirationTimer: (try? DisappearingMessagesConfiguration
                        .fetchOne(db, id: closedGroup.threadId)
                        .map { ($0.isEnabled ? UInt32($0.durationSeconds) : 0) })
                        .defaulting(to: 0)
                )
            }
            .asSet()
        // The default room promise creates an OpenGroup with an empty `roomToken` value,
        // we don't want to start a poller for this as the user hasn't actually joined a room
        let openGroups: Set<String> = try OpenGroup
            .filter(OpenGroup.Columns.roomToken != "")
            .filter(OpenGroup.Columns.isActive)
            .fetchAll(db)
            .map { openGroup in
                OpenGroup.urlFor(
                    server: openGroup.server,
                    roomToken: openGroup.roomToken,
                    publicKey: openGroup.publicKey
                )
            }
            .asSet()
        let contacts: Set<CMContact> = try Contact
            .filter(Contact.Columns.id != currentUserProfile.id)
            .fetchAll(db)
            .map { contact -> CMContact in
                // Can just default the 'hasX' values to true as they will be set to this
                // when converting to proto anyway
                let profile: Profile? = try? Profile.fetchOne(db, id: contact.id)
                
                return CMContact(
                    publicKey: contact.id,
                    displayName: (profile?.name ?? contact.id),
                    profilePictureUrl: profile?.profilePictureUrl,
                    profileKey: profile?.profileEncryptionKey?.keyData,
                    hasIsApproved: true,
                    isApproved: contact.isApproved,
                    hasIsBlocked: true,
                    isBlocked: contact.isBlocked,
                    hasDidApproveMe: true,
                    didApproveMe: contact.didApproveMe
                )
            }
            .asSet()
        
        return ConfigurationMessage(
            displayName: displayName,
            profilePictureUrl: profilePictureUrl,
            profileKey: profileKey,
            closedGroups: closedGroups,
            openGroups: openGroups,
            contacts: contacts
        )
    }
}
