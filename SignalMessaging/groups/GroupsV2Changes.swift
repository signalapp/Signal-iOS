//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import ZKGroup

public struct ChangedGroupModel {
    public let oldGroupModel: TSGroupModel
    public let newGroupModel: TSGroupModel
    // newDisappearingMessageToken is only set of DM state changed.
    public let newDisappearingMessageToken: DisappearingMessageToken?
    public let changeAuthorUuid: UUID
    public let profileKeys: [UUID: Data]

    public init(oldGroupModel: TSGroupModel,
                newGroupModel: TSGroupModel,
                newDisappearingMessageToken: DisappearingMessageToken?,
                changeAuthorUuid: UUID,
                profileKeys: [UUID: Data]) {
        self.oldGroupModel = oldGroupModel
        self.newGroupModel = newGroupModel
        self.newDisappearingMessageToken = newDisappearingMessageToken
        self.changeAuthorUuid = changeAuthorUuid
        self.profileKeys = profileKeys
    }
}

// MARK: -

public class GroupsV2Changes {

    // GroupsV2Changes has one responsibility: applying incremental
    // changes to group models. It should exactly mimic the behavior
    // of the service. Applying these "diffs" allow us to do two things:
    //
    // * Update groups without the burden of contacting the service.
    // * Stay aligned with service state... mostly.
    //
    // We can always deviate due to a bug or due to new "change actions"
    // that the local client doesn't know about. We're not versioning
    // the changes so if we introduce a breaking changes to the "change
    // actions" we'll need to roll out support for the new actions
    // before they go live.
    //
    // This method applies a single set of "change actions" to a group
    // model, thereby deriving a new group model whose revision is
    // exactly 1 higher.
    class func applyChangesToGroupModel(groupThread: TSGroupThread,
                                        changeActionsProto: GroupsProtoGroupChangeActions,
                                        transaction: SDSAnyReadTransaction) throws -> ChangedGroupModel {
        let oldGroupModel = groupThread.groupModel
        let groupId = oldGroupModel.groupId
        let groupsVersion = oldGroupModel.groupsVersion
        guard groupsVersion == .V2 else {
            throw OWSAssertionError("Invalid groupsVersion: \(groupsVersion).")
        }
        guard let groupSecretParamsData = groupThread.groupModel.groupSecretParamsData else {
            throw OWSAssertionError("Missing groupSecretParamsData.")
        }
        let groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
        // Many change actions have author info, e.g. addedByUserID. But we can
        // safely assume that all actions in the "change actions" have the same author.
        guard let changeAuthorUuidData = changeActionsProto.sourceUuid else {
            throw OWSAssertionError("Missing changeAuthorUuid.")
        }
        let changeAuthorUuid = try groupV2Params.uuid(forUserId: changeAuthorUuidData)

        guard changeActionsProto.hasVersion else {
            throw OWSAssertionError("Missing revision.")
        }
        let newRevision = changeActionsProto.version
        guard newRevision == oldGroupModel.groupV2Revision + 1 else {
            throw OWSAssertionError("Unexpected revision: \(newRevision) != \(oldGroupModel.groupV2Revision + 1).")
        }

        var newGroupName: String? = oldGroupModel.groupName
        let oldGroupMembership = oldGroupModel.groupMembership
        var groupMembershipBuilder = oldGroupMembership.asBuilder

        let oldGroupAccess = oldGroupModel.groupAccess
        var newMembersAccess = oldGroupAccess.members
        var newAttributesAccess = oldGroupAccess.attributes

        // This client can learn of profile keys from parsing group state protos.
        // After parsing, we should fill in profileKeys in the profile manager.
        var profileKeys = [UUID: Data]()

        for action in changeActionsProto.addMembers {
            guard let member = action.added else {
                throw OWSAssertionError("Missing member.")
            }
            guard let userId = member.userID else {
                throw OWSAssertionError("Missing userID.")
            }
            guard let protoRole = member.role else {
                throw OWSAssertionError("Missing role.")
            }
            guard let role = TSGroupMemberRole.role(for: protoRole) else {
                throw OWSAssertionError("Invalid role: \(protoRole.rawValue)")
            }
            guard let profileKeyCiphertextData = member.profileKey else {
                throw OWSAssertionError("Missing profileKeyCiphertext.")
            }
            let uuid = try groupV2Params.uuid(forUserId: userId)
            let address = SignalServiceAddress(uuid: uuid)

            guard !oldGroupMembership.allUsers.contains(address) else {
                throw OWSAssertionError("Invalid membership.")
            }
            groupMembershipBuilder.remove(address)
            groupMembershipBuilder.addNonPendingMember(address, role: role)

            let profileKeyCiphertext = try ProfileKeyCiphertext(contents: [UInt8](profileKeyCiphertextData))
            let profileKey = try groupV2Params.profileKey(forProfileKeyCiphertext: profileKeyCiphertext)

            profileKeys[uuid] = profileKey
        }

        for action in changeActionsProto.deleteMembers {
            guard let userId = action.deletedUserID else {
                throw OWSAssertionError("Missing userID.")
            }
            let uuid = try groupV2Params.uuid(forUserId: userId)
            let address = SignalServiceAddress(uuid: uuid)

            guard oldGroupMembership.nonPendingMembers.contains(address) else {
                throw OWSAssertionError("Invalid membership.")
            }
            groupMembershipBuilder.remove(address)
        }

        for action in changeActionsProto.modifyMemberRoles {
            guard let userId = action.userID else {
                throw OWSAssertionError("Missing userID.")
            }
            guard let protoRole = action.role else {
                throw OWSAssertionError("Missing role.")
            }
            guard let role = TSGroupMemberRole.role(for: protoRole) else {
                throw OWSAssertionError("Invalid role: \(protoRole.rawValue)")
            }

            let uuid = try groupV2Params.uuid(forUserId: userId)
            let address = SignalServiceAddress(uuid: uuid)

            guard oldGroupMembership.nonPendingMembers.contains(address) else {
                throw OWSAssertionError("Invalid membership.")
            }
            groupMembershipBuilder.remove(address)
            groupMembershipBuilder.addNonPendingMember(address, role: role)
        }

        for action in changeActionsProto.modifyMemberProfileKeys {
            guard let presentationData = action.presentation else {
                throw OWSAssertionError("Missing presentation.")
            }
            let presentation = try ProfileKeyCredentialPresentation(contents: [UInt8](presentationData))
            let uuidCiphertext = try presentation.getUuidCiphertext()
            let profileKeyCiphertext = try presentation.getProfileKeyCiphertext()
            let uuid = try groupV2Params.uuid(forUuidCiphertext: uuidCiphertext)
            let profileKey = try groupV2Params.profileKey(forProfileKeyCiphertext: profileKeyCiphertext)

            let address = SignalServiceAddress(uuid: uuid)
            guard oldGroupMembership.nonPendingMembers.contains(address) else {
                throw OWSAssertionError("Invalid membership.")
            }
            profileKeys[uuid] = profileKey
        }

        for action in changeActionsProto.addPendingMembers {
            guard let pendingMember = action.added else {
                throw OWSAssertionError("Missing pendingMember.")
            }
            guard let member = pendingMember.member else {
                throw OWSAssertionError("Missing member.")
            }
            guard let userId = member.userID else {
                throw OWSAssertionError("Missing userID.")
            }
            guard let protoRole = member.role else {
                throw OWSAssertionError("Missing role.")
            }
            guard let role = TSGroupMemberRole.role(for: protoRole) else {
                throw OWSAssertionError("Invalid role: \(protoRole.rawValue)")
            }
            let uuid = try groupV2Params.uuid(forUserId: userId)
            let address = SignalServiceAddress(uuid: uuid)
            guard let addedByUserID = pendingMember.addedByUserID else {
                throw OWSAssertionError("Group pending member missing addedByUserID.")
            }
            let addedByUuid = try groupV2Params.uuid(forUserId: addedByUserID)

            guard !oldGroupMembership.allUsers.contains(address) else {
                throw OWSAssertionError("Invalid membership.")
            }
            groupMembershipBuilder.remove(address)
            groupMembershipBuilder.addPendingMember(address, role: role, addedByUuid: addedByUuid)
        }

        for action in changeActionsProto.deletePendingMembers {
            guard let userId = action.deletedUserID else {
                throw OWSAssertionError("Missing userID.")
            }
            let uuid = try groupV2Params.uuid(forUserId: userId)
            let address = SignalServiceAddress(uuid: uuid)

            guard oldGroupMembership.pendingMembers.contains(address) else {
                throw OWSAssertionError("Invalid membership.")
            }
            groupMembershipBuilder.remove(address)
        }

        for action in changeActionsProto.promotePendingMembers {
            guard let presentationData = action.presentation else {
                throw OWSAssertionError("Missing presentation.")
            }
            let presentation = try ProfileKeyCredentialPresentation(contents: [UInt8](presentationData))
            let uuidCiphertext = try presentation.getUuidCiphertext()
            let profileKeyCiphertext = try presentation.getProfileKeyCiphertext()
            let uuid = try groupV2Params.uuid(forUuidCiphertext: uuidCiphertext)
            let profileKey = try groupV2Params.profileKey(forProfileKeyCiphertext: profileKeyCiphertext)

            let address = SignalServiceAddress(uuid: uuid)
            guard oldGroupMembership.pendingMembers.contains(address) else {
                throw OWSAssertionError("Invalid membership.")
            }
            guard !oldGroupMembership.nonPendingMembers.contains(address) else {
                throw OWSAssertionError("Invalid membership.")
            }
            guard let role = oldGroupMembership.role(for: address) else {
                throw OWSAssertionError("Missing role.")
            }
            groupMembershipBuilder.remove(address)
            groupMembershipBuilder.addNonPendingMember(address, role: role)

            profileKeys[uuid] = profileKey
        }

        if let action = changeActionsProto.modifyTitle {
            if let titleData = action.title {
                newGroupName = try groupV2Params.decryptString(titleData)
            } else {
                // Other client cleared the group title.
                newGroupName = nil
            }
        }

        if let action = changeActionsProto.modifyAvatar {
            // GroupsV2 TODO: Handle avatars.
            // GroupsProtoGroupChangeActionsModifyAvatarAction
        }

        var newDisappearingMessageToken: DisappearingMessageToken?
        if let action = changeActionsProto.modifyDisappearingMessagesTimer {
            // If the timer blob is not populated or has zero duration,
            // disappearing messages should be disabled.
            newDisappearingMessageToken = DisappearingMessageToken.disabledToken

            if let disappearingMessagesTimerEncrypted = action.timer {
                let disappearingMessagesTimerDecrypted = try groupV2Params.decryptBlob(disappearingMessagesTimerEncrypted)
                let disappearingMessagesProto = try GroupsProtoDisappearingMessagesTimer.parseData(disappearingMessagesTimerDecrypted)
                let durationSeconds = disappearingMessagesProto.duration
                newDisappearingMessageToken = DisappearingMessageToken.token(forProtoExpireTimer: disappearingMessagesProto.duration)
            }
        }

        if let action = changeActionsProto.modifyAttributesAccess {
            guard let protoAccess = action.attributesAccess else {
                throw OWSAssertionError("Missing access.")
            }
            newAttributesAccess = GroupAccess.groupV2Access(forProtoAccess: protoAccess)
        }

        if let action = changeActionsProto.modifyMemberAccess {
            guard let protoAccess = action.membersAccess else {
                throw OWSAssertionError("Missing access.")
            }
            newMembersAccess = GroupAccess.groupV2Access(forProtoAccess: protoAccess)
        }

        let newGroupMembership = groupMembershipBuilder.build()
        let newGroupAccess = GroupAccess(members: newMembersAccess, attributes: newAttributesAccess)
        // GroupsV2 TODO: Avatar.
        let avatarData: Data? = oldGroupModel.groupAvatarData

        let newGroupModel = try GroupManager.buildGroupModel(groupId: groupId,
                                                             name: newGroupName,
                                                             avatarData: avatarData,
                                                             groupMembership: newGroupMembership,
                                                             groupAccess: newGroupAccess,
                                                             groupsVersion: groupsVersion,
                                                             groupV2Revision: newRevision,
                                                             groupSecretParamsData: groupSecretParamsData,
                                                             transaction: transaction)
        return ChangedGroupModel(oldGroupModel: oldGroupModel,
                                 newGroupModel: newGroupModel,
                                 newDisappearingMessageToken: newDisappearingMessageToken,
                                 changeAuthorUuid: changeAuthorUuid,
                                 profileKeys: profileKeys)
    }
}
