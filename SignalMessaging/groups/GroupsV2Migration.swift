//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import ZKGroup
import HKDFKit

public class GroupsV2Migration {

    // MARK: - Dependencies

    private static var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    private static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private static var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private static var groupsV2: GroupsV2Impl {
        return SSKEnvironment.shared.groupsV2 as! GroupsV2Impl
    }

    // MARK: -

    private init() {}

    // MARK: - Mapping

    public static func v2GroupId(forV1GroupId v1GroupId: Data) throws -> Data {
        try calculateMigrationMetadata(forV1GroupId: v1GroupId).v2GroupId
    }

    public static func v2MasterKey(forV1GroupId v1GroupId: Data) throws -> Data {
        try calculateMigrationMetadata(forV1GroupId: v1GroupId).v2MasterKey
    }

    // MARK: -

    // If there is a v1 group in the database that can be
    // migrated to a v2 group, try to migrate it to a v2
    // group. It might or might not already be migrated on
    // the service.
    public static func tryToMigrate(groupThread: TSGroupThread,
                                    migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {
        firstly(on: .global()) {
            Self.databaseStorage.read { transaction in
                Self.canGroupBeMigratedByLocalUser(groupThread: groupThread,
                                                   migrationMode: migrationMode,
                                                   transaction: transaction)
            }
        }.then(on: .global()) { (canGroupBeMigrated: Bool) -> Promise<TSGroupThread> in
            guard canGroupBeMigrated else {
                throw OWSGenericError("Group can not be migrated.")
            }
            return Self.localMigrationAttempt(groupId: groupThread.groupModel.groupId,
                                              migrationMode: migrationMode)
        }
    }

    // If there is a corresponding v1 group in the local database,
    // update it to reflect the v1 group already on the service.
    public static func updateAlreadyMigratedGroupIfNecessary(v2GroupId: Data) -> Promise<Void> {
        firstly(on: .global()) { () -> Promise<Void> in
            guard let groupThread = (Self.databaseStorage.read { transaction in
                TSGroupThread.fetch(groupId: v2GroupId, transaction: transaction)
            }) else {
                // No need to migrate; not in database.
                return Promise.value(())
            }
            guard groupThread.isGroupV1Thread else {
                // No need to migrate; not a v1 group.
                return Promise.value(())
            }

            return firstly(on: .global()) { () -> Promise<TSGroupThread> in
                Self.localMigrationAttempt(groupId: v2GroupId,
                                           migrationMode: .alreadyMigratedOnService)
            }.asVoid()
        }
    }
}

// MARK: -

fileprivate extension GroupsV2Migration {

    // groupId might be the v1 or v2 group id.
    static func localMigrationAttempt(groupId: Data,
                                      migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {

        return firstly(on: .global()) { () -> Promise<Void> in
            return GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
        }.map(on: .global()) { () -> UnmigratedState in
            try Self.loadUnmigratedState(groupId: groupId)
        }.then(on: .global()) { (unmigratedState: UnmigratedState) -> Promise<TSGroupThread> in
            addMigratingV2GroupId(unmigratedState.migrationMetadata.v1GroupId)
            addMigratingV2GroupId(unmigratedState.migrationMetadata.v2GroupId)

            return firstly(on: .global()) { () -> Promise<TSGroupThread> in
                attemptToMigrateByPullingFromService(unmigratedState: unmigratedState,
                                                     migrationMode: migrationMode)
            }.recover(on: .global()) { (error: Error) -> Promise<TSGroupThread> in
                if case GroupsV2Error.groupDoesNotExistOnService = error,
                migrationMode.canMigrateToService {
                    // If the group is not already on the service, try to
                    // migrate by creating on the service.
                    return attemptToMigrateByCreatingOnService(unmigratedState: unmigratedState,
                                                               migrationMode: migrationMode)
                } else {
                    throw error
                }
            }
        }
    }

    static func attemptToMigrateByPullingFromService(unmigratedState: UnmigratedState,
                                                     migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {

        return firstly(on: .global()) { () -> Promise<GroupV2Snapshot> in
            let groupSecretParamsData = unmigratedState.migrationMetadata.v2GroupSecretParams
            return self.groupsV2.fetchCurrentGroupV2Snapshot(groupSecretParamsData: groupSecretParamsData)
        }.recover(on: .global()) { (error: Error) -> Promise<GroupV2Snapshot> in
            if case GroupsV2Error.groupDoesNotExistOnService = error {
                // Convert error if the group is not already on the service.
                throw GroupsV2Error.groupDoesNotExistOnService
            } else {
                throw error
            }
        }.then(on: .global()) { (snapshot: GroupV2Snapshot) throws -> Promise<TSGroupThread> in
            self.migrateGroupUsingSnapshot(unmigratedState: unmigratedState,
                                           groupV2Snapshot: snapshot)
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                  description: "Migrate group from service") {
                    GroupsV2Error.timeout
        }
    }

    static func migrateGroupUsingSnapshot(unmigratedState: UnmigratedState,
                                          groupV2Snapshot: GroupV2Snapshot) -> Promise<TSGroupThread> {
        let localProfileKey = profileManager.localProfileKey()
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }

        return firstly(on: .global()) { () -> TSGroupModelV2 in
            try self.databaseStorage.read { transaction in
                let builder = try TSGroupModelBuilder(groupV2Snapshot: groupV2Snapshot)
                return try builder.buildAsV2(transaction: transaction)
            }
        }.then(on: .global()) { (newGroupModelV2: TSGroupModelV2) throws -> Promise<TSGroupThread> in
            let newDisappearingMessageToken = groupV2Snapshot.disappearingMessageToken
            // groupUpdateSourceAddress is nil because we don't know the
            // author(s) of changes reflected in the snapshot.
            let groupUpdateSourceAddress: SignalServiceAddress? = nil

            return GroupManager.replaceMigratedGroup(groupIdV1: unmigratedState.groupThread.groupModel.groupId,
                                                     groupModelV2: newGroupModelV2,
                                                     disappearingMessageToken: newDisappearingMessageToken,
                                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                     shouldSendMessage: false)
        }.map(on: .global()) { (groupThread: TSGroupThread) throws -> TSGroupThread in
            GroupManager.storeProfileKeysFromGroupProtos(groupV2Snapshot.profileKeys)

            // If the group state includes a stale profile key for the
            // local user, schedule an update to fix that.
            if let profileKey = groupV2Snapshot.profileKeys[localUuid],
                profileKey != localProfileKey.keyData {
                self.databaseStorage.write { transaction in
                    self.groupsV2.updateLocalProfileKeyInGroup(groupId: groupThread.groupModel.groupId,
                                                               transaction: transaction)
                }
            }

            return groupThread
        }
    }

    static func attemptToMigrateByCreatingOnService(unmigratedState: UnmigratedState,
                                                    migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {

        return firstly(on: .global()) { () -> Promise<TSGroupThread> in
            let groupThread = unmigratedState.groupThread
            guard groupThread.isLocalUserFullMember else {
                throw OWSAssertionError("Local user cannot migrate group; is not a full member.")
            }
            let memberSet = groupThread.groupMembership.allMembersOfAnyKind

            return firstly(on: .global()) { () -> Promise<Void> in
                GroupManager.tryToEnableGroupsV2(for: Array(memberSet), isBlocking: true, ignoreErrors: true)
            }.then(on: .global()) { () throws -> Promise<Void> in
                self.groupsV2.tryToEnsureProfileKeyCredentials(for: Array(memberSet))
            }.then(on: .global()) { () throws -> Promise<String?> in
                guard let avatarData = unmigratedState.groupThread.groupModel.groupAvatarData else {
                    // No avatar to upload.
                    return Promise.value(nil)
                }
                // Upload avatar.
                return firstly(on: .global()) { () -> Promise<String> in
                    return self.groupsV2.uploadGroupAvatar(avatarData: avatarData,
                                                           groupSecretParamsData: unmigratedState.migrationMetadata.v2GroupSecretParams)
                }.map(on: .global()) { (avatarUrlPath: String) -> String? in
                    return avatarUrlPath
                }
            }.map(on: .global()) { (avatarUrlPath: String?) throws -> TSGroupModelV2 in
                try databaseStorage.read { transaction in
                    try Self.deriveMigratedGroupModel(unmigratedState: unmigratedState,
                                                      avatarUrlPath: avatarUrlPath,
                                                      migrationMode: migrationMode,
                                                      transaction: transaction)
                }
            }.then(on: .global()) { (proposedGroupModel: TSGroupModelV2) -> Promise<TSGroupModelV2> in
                Self.migrateGroupOnService(proposedGroupModel: proposedGroupModel,
                                           disappearingMessageToken: unmigratedState.disappearingMessageToken)
            }.then(on: .global()) { (groupModelV2: TSGroupModelV2) -> Promise<TSGroupThread> in
                guard let localAddress = tsAccountManager.localAddress else {
                    throw OWSAssertionError("Missing localAddress.")
                }
                return GroupManager.replaceMigratedGroup(groupIdV1: unmigratedState.groupThread.groupModel.groupId,
                                                         groupModelV2: groupModelV2,
                                                         disappearingMessageToken: unmigratedState.disappearingMessageToken,
                                                         groupUpdateSourceAddress: localAddress,
                                                         shouldSendMessage: true)
            }.map(on: .global()) { (groupThread: TSGroupThread) -> TSGroupThread in
                self.profileManager.addThread(toProfileWhitelist: groupThread)
                return groupThread
            }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                      description: "Migrate group") {
                        GroupsV2Error.timeout
            }
        }
    }

    static func deriveMigratedGroupModel(unmigratedState: UnmigratedState,
                                         avatarUrlPath: String?,
                                         migrationMode: GroupsV2MigrationMode,
                                         transaction: SDSAnyReadTransaction) throws -> TSGroupModelV2 {

        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }
        guard let localUuid = localAddress.uuid else {
            throw OWSAssertionError("Missing localUuid.")
        }
        let v1GroupThread = unmigratedState.groupThread
        let v1GroupModel = v1GroupThread.groupModel
        guard v1GroupModel.groupsVersion == .V1 else {
            throw OWSAssertionError("Invalid group version: \(v1GroupModel.groupsVersion.rawValue).")
        }
        let migrationMetadata = unmigratedState.migrationMetadata
        let v2GroupId = migrationMetadata.v2GroupId
        let v2GroupSecretParams = migrationMetadata.v2GroupSecretParams

        var groupModelBuilder = v1GroupModel.asBuilder

        groupModelBuilder.groupId = v2GroupId
        groupModelBuilder.groupAccess = GroupAccess.defaultForV2
        groupModelBuilder.groupsVersion = .V2
        groupModelBuilder.groupV2Revision = 0
        groupModelBuilder.groupSecretParamsData = v2GroupSecretParams
        groupModelBuilder.newGroupSeed = nil
        groupModelBuilder.isPlaceholderModel = false

        // We should either have both avatarData and avatarUrlPath or neither.
        if let avatarData = v1GroupModel.groupAvatarData,
            let avatarUrlPath = avatarUrlPath {
            groupModelBuilder.avatarData = avatarData
            groupModelBuilder.avatarUrlPath = avatarUrlPath
        } else {
            owsAssertDebug(v1GroupModel.groupAvatarData == nil)
            owsAssertDebug(avatarUrlPath == nil)
            groupModelBuilder.avatarData = nil
            groupModelBuilder.avatarUrlPath = nil
        }

        // Build member list.
        //
        // The group creator is an administrator;
        // the other members are normal users.
        var v2MembershipBuilder = GroupMembership.Builder()
        for address in v1GroupModel.groupMembership.allMembersOfAnyKind {
            guard address.uuid != nil else {
                Logger.warn("Member missing uuid: \(address).")
                if migrationMode.skipMembersWithoutUuids {
                    Logger.warn("Discarding member: \(address).")
                    continue
                } else {
                    throw OWSAssertionError("Member does not support gv2.")
                }
            }

            if !GroupManager.doesUserHaveGroupsV2Capability(address: address,
                                                            transaction: transaction) {
                Logger.warn("Member without Groups v2 capability: \(address).")
                owsAssertDebug(migrationMode.allowMembersWithoutCapabilities)
            }
            if !GroupManager.doesUserHaveGroupsV2MigrationCapability(address: address,
                                                            transaction: transaction) {
                Logger.warn("Member without migration capability: \(address).")
                owsAssertDebug(migrationMode.allowMembersWithoutCapabilities)
            }

            var isInvited = false
            if !groupsV2.hasProfileKeyCredential(for: address, transaction: transaction) {
                Logger.warn("Inviting user with unknown profile key: \(address).")
                owsAssertDebug(migrationMode.allowMembersWithoutProfileKey)
                isInvited = true
            }

            // All migrated members become admins.
            let role: TSGroupMemberRole = .administrator

            if isInvited {
                v2MembershipBuilder.addInvitedMember(address, role: role, addedByUuid: localUuid)
            } else {
                v2MembershipBuilder.addFullMember(address, role: role)
            }
        }

        v2MembershipBuilder.remove(localAddress)
        v2MembershipBuilder.addFullMember(localAddress, role: .administrator)
        groupModelBuilder.groupMembership = v2MembershipBuilder.build()

        groupModelBuilder.addedByAddress = nil

        return try groupModelBuilder.buildAsV2(transaction: transaction)
    }

    static func migrateGroupOnService(proposedGroupModel: TSGroupModelV2,
                                      disappearingMessageToken: DisappearingMessageToken) -> Promise<TSGroupModelV2> {
        return firstly {
            self.groupsV2.createNewGroupOnService(groupModel: proposedGroupModel,
                                                  disappearingMessageToken: disappearingMessageToken)
        }.then(on: .global()) { _ in
            self.groupsV2.fetchCurrentGroupV2Snapshot(groupModel: proposedGroupModel)
        }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> TSGroupModelV2 in
            let createdGroupModel = try self.databaseStorage.read { (transaction) throws -> TSGroupModelV2 in
                let groupModelBuilder = try TSGroupModelBuilder(groupV2Snapshot: groupV2Snapshot)
                return try groupModelBuilder.buildAsV2(transaction: transaction)
            }
            if proposedGroupModel != createdGroupModel {
                Logger.verbose("proposedGroupModel: \(proposedGroupModel.debugDescription)")
                Logger.verbose("createdGroupModel: \(createdGroupModel.debugDescription)")
                if DebugFlags.groupsV2ignoreCorruptInvites {
                    Logger.warn("Proposed group model does not match created group model.")
                } else {
                    owsFailDebug("Proposed group model does not match created group model.")
                }
            }
            return createdGroupModel
        }
    }

    static func canGroupBeMigratedByLocalUser(groupThread: TSGroupThread,
                                              migrationMode: GroupsV2MigrationMode,
                                              transaction: SDSAnyReadTransaction) -> Bool {
        if migrationMode.onlyMigrateIfInProfileWhitelist {
            guard profileManager.isThread(inProfileWhitelist: groupThread,
                                          transaction: transaction) else {
                                            return false
            }
        }
        guard groupThread.isGroupV1Thread else {
            owsFailDebug("Not a v1 group.")
            return false
        }
        guard groupThread.isLocalUserFullMember else {
            return false
        }
        let groupMembership = groupThread.groupModel.groupMembership

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return false
        }

        // Build member list.
        //
        // The group creator is an administrator;
        // the other members are normal users.
        for address in groupMembership.allMembersOfAnyKind {
            if address.isEqualToAddress(localAddress) {
                continue
            }

            guard nil != address.uuid else {
                Logger.warn("Member missing uuid: \(address).")
                if migrationMode.skipMembersWithoutUuids {
                    continue
                } else {
                    return false
                }
            }

            if !GroupManager.doesUserHaveGroupsV2Capability(address: address,
                                                            transaction: transaction) {
                Logger.warn("Member without Groups v2 capability: \(address).")
                if !migrationMode.allowMembersWithoutCapabilities {
                    return false
                }
            }
            if !GroupManager.doesUserHaveGroupsV2MigrationCapability(address: address,
                                                                     transaction: transaction) {
                Logger.warn("Member without migration capability: \(address).")
                if !migrationMode.allowMembersWithoutCapabilities {
                    return false
                }
            }

            if !groupsV2.hasProfileKeyCredential(for: address, transaction: transaction) {
                Logger.warn("Member without profile key: \(address).")
                if !migrationMode.allowMembersWithoutProfileKey {
                    return false
                }
            }
        }

        return true
    }
}

// MARK: -

public enum GroupsV2MigrationMode {
    case migrateToServicePolite
    case migrateToServiceAggressive
    case alreadyMigratedOnService

    public var skipMembersWithoutUuids: Bool {
        self == .migrateToServiceAggressive
    }

    public var allowMembersWithoutCapabilities: Bool {
        self == .migrateToServiceAggressive
    }

    public var allowMembersWithoutProfileKey: Bool {
        self == .migrateToServiceAggressive
    }

    public var onlyMigrateIfInProfileWhitelist: Bool {
        self == .migrateToServiceAggressive
    }

    public var canMigrateToService: Bool {
        self != .alreadyMigratedOnService
    }
}

// MARK: -

extension GroupsV2Migration {

    // MARK: - Migrating Group Ids

    // We track migrating group ids for usage in asserts.
    private static let unfairLock = UnfairLock()
    private static var migratingV2GroupIds = Set<Data>()

    private static func addMigratingV2GroupId(_ groupId: Data) {
        _ = unfairLock.withLock {
            migratingV2GroupIds.insert(groupId)
        }
    }

    public static func isMigratingV2GroupId(_ groupId: Data) -> Bool {
        unfairLock.withLock {
            migratingV2GroupIds.contains(groupId)
        }
    }
}

// MARK: -

fileprivate extension GroupsV2Migration {

    // MARK: - Mapping

    static func gv2MasterKey(forV1GroupId v1GroupId: Data) throws -> Data {
        guard GroupManager.isValidGroupId(v1GroupId, groupsVersion: .V1) else {
            throw OWSAssertionError("Invalid v1 group id.")
        }
        guard let migrationInfo: Data = "GV2 Migration".data(using: .utf8) else {
            throw OWSAssertionError("Couldn't convert info data.")
        }
        let salt = Data(repeating: 0, count: 32)
        let masterKeyLength: Int32 = Int32(GroupMasterKey.SIZE)
        let masterKey =
            try HKDFKit.deriveKey(v1GroupId, info: migrationInfo, salt: salt, outputSize: masterKeyLength)
        guard masterKey.count == masterKeyLength else {
            throw OWSAssertionError("Invalid master key.")
        }
        return masterKey
    }

    // MARK: -

    struct MigrationMetadata {
        let v1GroupId: Data
        let v2GroupId: Data
        let v2MasterKey: Data
        let v2GroupSecretParams: Data
    }

    private static func calculateMigrationMetadata(forV1GroupId v1GroupId: Data) throws -> MigrationMetadata {
        guard GroupManager.isValidGroupId(v1GroupId, groupsVersion: .V1) else {
            throw OWSAssertionError("Invalid group id: \(v1GroupId.hexadecimalString).")
        }
        let masterKey = try gv2MasterKey(forV1GroupId: v1GroupId)
        let v2GroupSecretParams = try groupsV2.groupSecretParamsData(forMasterKeyData: masterKey)
        let v2GroupId = try groupsV2.groupId(forGroupSecretParamsData: v2GroupSecretParams)
        return MigrationMetadata(v1GroupId: v1GroupId,
                                 v2GroupId: v2GroupId,
                                 v2MasterKey: masterKey,
                                 v2GroupSecretParams: v2GroupSecretParams)
    }

    private static func calculateMigrationMetadata(for v1GroupModel: TSGroupModel) throws -> MigrationMetadata {
        guard v1GroupModel.groupsVersion == .V1 else {
            throw OWSAssertionError("Invalid group version: \(v1GroupModel.groupsVersion.rawValue).")
        }
        return try calculateMigrationMetadata(forV1GroupId: v1GroupModel.groupId)
    }

    struct UnmigratedState {
        let groupThread: TSGroupThread
        let disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration
        let migrationMetadata: MigrationMetadata

        var disappearingMessageToken: DisappearingMessageToken {
            disappearingMessagesConfiguration.asToken
        }
    }

    private static func loadUnmigratedState(groupId: Data) throws -> UnmigratedState {
        try databaseStorage.read { transaction in
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing group thread.")
            }
            guard groupThread.groupModel.groupsVersion == .V1 else {
                // This can happen due to races, but should be very rare.
                throw OWSAssertionError("Unexpected groupsVersion.")
            }
            let disappearingMessagesConfiguration = groupThread.disappearingMessagesConfiguration(with: transaction)
            let migrationMetadata = try Self.calculateMigrationMetadata(for: groupThread.groupModel)

            return UnmigratedState(groupThread: groupThread,
                                   disappearingMessagesConfiguration: disappearingMessagesConfiguration,
                                   migrationMetadata: migrationMetadata)
        }
    }
}
