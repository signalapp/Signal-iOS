// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

extension ConfigurationMessage {

    public static func getCurrent(_ db: Database) throws -> ConfigurationMessage {
        let profile: Profile = Profile.fetchOrCreateCurrentUser(db)
        
        let displayName: String = profile.name
        let profilePictureUrl: String? = profile.profilePictureUrl
        let profileKey: Data? = profile.profileEncryptionKey?.keyData
        var closedGroups: Set<CMClosedGroup> = []
        var openGroups: Set<String> = []
        
        Storage.read { transaction in
            TSGroupThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSGroupThread else { return }
                
                switch thread.groupModel.groupType {
                    case .closedGroup:
                        guard thread.isCurrentUserMemberInGroup() else { return }
                        
                        let groupID = thread.groupModel.groupId
                        let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
                        
                        guard
                            Storage.shared.isClosedGroup(groupPublicKey, using: transaction),
                            let encryptionKeyPair = Storage.shared.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey, using: transaction)
                        else {
                            return
                        }
                        
                        let closedGroup = ClosedGroup(
                            publicKey: groupPublicKey,
                            name: (thread.groupModel.groupName ?? ""),
                            encryptionKeyPair: encryptionKeyPair,
                            members: Set(thread.groupModel.groupMemberIds),
                            admins: Set(thread.groupModel.groupAdminIds),
                            expirationTimer: thread.disappearingMessagesDuration(with: transaction)
                        )
                        closedGroups.insert(closedGroup)
                        
                    case .openGroup:
                        if let threadId: String = thread.uniqueId, let v2OpenGroup = Storage.shared.getV2OpenGroup(for: threadId) {
                            openGroups.insert("\(v2OpenGroup.server)/\(v2OpenGroup.room)?public_key=\(v2OpenGroup.publicKey)")
                        }

                    default: break
                }
            }
        }
        
        let currentUserPublicKey: String = getUserHexEncodedPublicKey()
        
        let contacts: Set<CMContact> = try Contact.fetchAll(db)
            .compactMap { contact -> CMContact? in
                guard contact.id != currentUserPublicKey else { return nil }
                
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
