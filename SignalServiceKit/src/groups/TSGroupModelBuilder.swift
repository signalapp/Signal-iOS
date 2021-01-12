//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public struct TSGroupModelBuilder {

    // MARK: - Dependencies

    private var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    // MARK: -

    public var groupId: Data?
    public var name: String?
    public var avatarData: Data?
    public var groupMembership = GroupMembership()
    public var groupAccess: GroupAccess?
    public var groupsVersion: GroupsVersion?
    public var groupV2Revision: UInt32 = 0
    public var groupSecretParamsData: Data?
    public var newGroupSeed: NewGroupSeed?
    public var avatarUrlPath: String?
    public var inviteLinkPassword: Data?
    public var isPlaceholderModel: Bool = false
    public var addedByAddress: SignalServiceAddress?
    public var wasJustMigrated: Bool = false
    public var wasJustCreatedByLocalUser: Bool = false
    public var droppedMembers = [SignalServiceAddress]()

    public init() {}

    // Convert a group state proto received from the service
    // into a group model.
    private init(groupV2Snapshot: GroupV2Snapshot) throws {
        self.groupId = try groupsV2.groupId(forGroupSecretParamsData: groupV2Snapshot.groupSecretParamsData)
        self.name = groupV2Snapshot.title
        self.avatarData = groupV2Snapshot.avatarData
        self.groupMembership = groupV2Snapshot.groupMembership
        self.groupAccess = groupV2Snapshot.groupAccess
        self.groupsVersion = GroupsVersion.V2
        self.groupV2Revision = groupV2Snapshot.revision
        self.groupSecretParamsData = groupV2Snapshot.groupSecretParamsData
        self.avatarUrlPath = groupV2Snapshot.avatarUrlPath
        self.inviteLinkPassword = groupV2Snapshot.inviteLinkPassword
        self.isPlaceholderModel = false
        self.wasJustMigrated = false
        self.wasJustCreatedByLocalUser = false
    }

    public
    static func builderForSnapshot(groupV2Snapshot: GroupV2Snapshot,
                                   transaction: SDSAnyWriteTransaction) throws -> TSGroupModelBuilder {

        var builder = try TSGroupModelBuilder(groupV2Snapshot: groupV2Snapshot)

        guard let groupId = builder.groupId else {
            owsFailDebug("Missing groupId.")
            return builder
        }
        TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)
        guard let oldGroupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            // Group not uet in db.
            return builder
        }
        let oldGroupModel = oldGroupThread.groupModel
        builder.droppedMembers = oldGroupModel.asBuilder.droppedMembers
        return builder
    }

    private func checkUsers() throws {
        let allUsers = groupMembership.allMembersOfAnyKind
        for recipientAddress in allUsers {
            guard recipientAddress.isValid else {
                throw OWSAssertionError("Invalid address.")
            }
        }
    }

    public func buildForMinorChanges() throws -> TSGroupModel {

        try checkUsers()

        guard let groupsVersion = self.groupsVersion else {
            throw OWSAssertionError("Missing groupsVersion.")
        }
        guard let groupId = self.groupId else {
            throw OWSAssertionError("Missing groupId.")
        }

        var groupSecretParamsData: Data?
        if groupsVersion == .V2 {
            guard let secretParamsData = self.groupSecretParamsData else {
                throw OWSAssertionError("Missing groupSecretParamsData.")
            }
            groupSecretParamsData = secretParamsData
        }

        return try build(groupsVersion: groupsVersion,
                         groupId: groupId,
                         groupSecretParamsData: groupSecretParamsData)
    }

    public func build(transaction: SDSAnyReadTransaction) throws -> TSGroupModel {

        try checkUsers()

        let allUsers = groupMembership.allMembersOfAnyKind
        let groupsVersion = buildGroupsVersion(for: allUsers,
                                               transaction: transaction)

        let newGroupSeed = self.newGroupSeed ?? NewGroupSeed()

        let groupId = try buildGroupId(groupsVersion: groupsVersion,
                                       newGroupSeed: newGroupSeed)

        var groupSecretParamsData: Data?
        if groupsVersion == .V2 {
            groupSecretParamsData = try buildGroupSecretParamsData(newGroupSeed: newGroupSeed)
        }

        return try build(groupsVersion: groupsVersion,
                         groupId: groupId,
                         groupSecretParamsData: groupSecretParamsData)
    }

    private func build(groupsVersion: GroupsVersion,
                       groupId: Data,
                       groupSecretParamsData: Data?) throws -> TSGroupModel {

        let allUsers = groupMembership.allMembersOfAnyKind
        for recipientAddress in allUsers {
            guard recipientAddress.isValid else {
                throw OWSAssertionError("Invalid address.")
            }
        }

        var name: String?
        if let strippedName = self.name?.stripped,
            strippedName.count > 0 {
            name = strippedName
        }

        guard GroupManager.isValidGroupId(groupId, groupsVersion: groupsVersion) else {
            throw OWSAssertionError("Invalid groupId.")
        }

        switch groupsVersion {
        case .V1:
            if !groupMembership.invitedMembers.isEmpty {
                owsFailDebug("v1 group has pending profile key members.")
            }
            if !groupMembership.requestingMembers.isEmpty {
                owsFailDebug("v1 group has pending request members.")
            }
            owsAssertDebug(!isPlaceholderModel)
            return TSGroupModel(groupId: groupId,
                                name: name,
                                avatarData: avatarData,
                                members: Array(groupMembership.fullMembers),
                                addedBy: addedByAddress)
        case .V2:
            owsAssertDebug(addedByAddress == nil)

            let groupAccess = buildGroupAccess(groupsVersion: groupsVersion)
            guard let groupSecretParamsData = groupSecretParamsData else {
                throw OWSAssertionError("Missing groupSecretParamsData.")
            }
            // Don't set avatarUrlPath unless we have avatarData.
            let avatarUrlPath = avatarData != nil ? self.avatarUrlPath : nil

            // Update droppedMembers, removing any current members.
            let droppedMembers = Array(Set(self.droppedMembers).subtracting(groupMembership.allMembersOfAnyKind))
            return TSGroupModelV2(groupId: groupId,
                                  name: name,
                                  avatarData: avatarData,
                                  groupMembership: groupMembership,
                                  groupAccess: groupAccess,
                                  revision: groupV2Revision,
                                  secretParamsData: groupSecretParamsData,
                                  avatarUrlPath: avatarUrlPath,
                                  inviteLinkPassword: inviteLinkPassword,
                                  isPlaceholderModel: isPlaceholderModel,
                                  wasJustMigrated: wasJustMigrated,
                                  wasJustCreatedByLocalUser: wasJustCreatedByLocalUser,
                                  addedByAddress: addedByAddress,
                                  droppedMembers: droppedMembers)
        }
    }

    public func buildAsV2(transaction: SDSAnyReadTransaction) throws -> TSGroupModelV2 {
        guard let model = try build(transaction: transaction) as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group model.")
        }
        return model
    }

    private func buildGroupId(groupsVersion: GroupsVersion,
                              newGroupSeed: NewGroupSeed) throws -> Data {
        if let value = groupId {
            return value
        }

        switch groupsVersion {
        case .V1:
            return newGroupSeed.groupIdV1
        case .V2:
            guard let groupIdV2 = newGroupSeed.groupIdV2 else {
                throw OWSAssertionError("Missing groupIdV2.")
            }
            return groupIdV2
        }
    }

    private func buildGroupSecretParamsData(newGroupSeed: NewGroupSeed) throws -> Data {
        if let value = groupSecretParamsData {
            return value
        }

        guard let value = newGroupSeed.groupSecretParamsData else {
            throw OWSAssertionError("Missing groupSecretParamsData.")
        }
        return value
    }

    private func buildGroupAccess(groupsVersion: GroupsVersion) -> GroupAccess {
        if let value = groupAccess {
            return value
        }

        switch groupsVersion {
        case .V1:
            return GroupAccess.defaultForV1
        case .V2:
            return GroupAccess.defaultForV2
        }
    }

    private func buildGroupsVersion(for members: Set<SignalServiceAddress>,
                                    transaction: SDSAnyReadTransaction) -> GroupsVersion {
        if let value = groupsVersion {
            return value
        }

        if DebugFlags.groupsV2onlyCreateV1Groups.get() {
            Logger.info("Creating v1 group due to debug flag.")
            return .V1
        }
        let canUseV2 = GroupManager.canUseV2(for: members, transaction: transaction)
        if canUseV2 {
            Logger.info("Creating v2 group.")
            return GroupManager.defaultGroupsVersion
        } else {
            Logger.info("Creating v1 group due to members.")
            return .V1
        }
    }
}

// MARK: -

public extension TSGroupModel {
    var asBuilder: TSGroupModelBuilder {
        var builder = TSGroupModelBuilder()
        builder.groupId = self.groupId
        builder.name = self.groupName
        builder.avatarData = self.groupAvatarData
        builder.groupMembership = self.groupMembership
        builder.groupsVersion = self.groupsVersion
        builder.addedByAddress = self.addedByAddress

        if let v2 = self as? TSGroupModelV2 {
            builder.groupAccess = v2.access
            builder.groupV2Revision = v2.revision
            builder.groupSecretParamsData = v2.secretParamsData
            builder.avatarUrlPath = v2.avatarUrlPath
            builder.inviteLinkPassword = v2.inviteLinkPassword
            builder.droppedMembers = v2.droppedMembers

            // Do not copy isPlaceholderModel or wasJustMigrated or wasJustCreatedByLocalUser;
            // We want to discard these values when updating group models.
        }

        return builder
    }
}
