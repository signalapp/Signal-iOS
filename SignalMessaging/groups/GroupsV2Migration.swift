//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import LibSignalClient

@objc
public class GroupsV2Migration: NSObject {

    private override init() {}

    // MARK: - Mapping

    public static func v2GroupId(forV1GroupId v1GroupId: Data) throws -> Data {
        try calculateMigrationMetadata(forV1GroupId: v1GroupId).v2GroupId
    }

    public static func v2MasterKey(forV1GroupId v1GroupId: Data) throws -> Data {
        try calculateMigrationMetadata(forV1GroupId: v1GroupId).v2MasterKey
    }
}

// MARK: -

public extension GroupsV2Migration {

    // MARK: -

    private static let groupMigrationTimeoutDuration: TimeInterval = 30

    static func tryManualMigration(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        Logger.info("request groupId: \(groupThread.groupId.hexadecimalString)")
        return firstly {
            self.tryToMigrate(groupThread: groupThread, migrationMode: manualMigrationMode)
        }.timeout(seconds: Self.groupMigrationTimeoutDuration,
                  description: "Manual migration") {
            GroupsV2Error.timeout
        }
    }

    // If there is a v1 group in the database that can be
    // migrated to a v2 group, try to migrate it to a v2
    // group. It might or might not already be migrated on
    // the service.
    static func tryToMigrate(groupThread: TSGroupThread,
                             migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {
        firstly(on: .global()) { () -> Bool in
            if migrationMode == .isAlreadyMigratedOnService {
                return true
            }

            return Self.databaseStorage.read { transaction in
                Self.canGroupBeMigratedByLocalUser(groupThread: groupThread,
                                                   migrationMode: migrationMode,
                                                   transaction: transaction)
            }
        }.then(on: .global()) { (canGroupBeMigrated: Bool) -> Promise<TSGroupThread> in
            guard canGroupBeMigrated else {
                throw GroupsV2Error.groupCannotBeMigrated
            }
            return Self.enqueueMigration(groupId: groupThread.groupModel.groupId,
                                         migrationMode: migrationMode)
        }
    }

    // If there is a corresponding v1 group in the local database,
    // update it to reflect the v1 group already on the service.
    static func updateAlreadyMigratedGroupIfNecessary(v2GroupId: Data) -> Promise<Void> {
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
                Self.enqueueMigration(groupId: v2GroupId,
                                      migrationMode: .isAlreadyMigratedOnService)
            }.asVoid()
        }
    }

    @objc
    static func migrationInfoForManualMigration(groupThread: TSGroupThread) -> GroupsV2MigrationInfo {
        databaseStorage.read { transaction in
            migrationInfoForManualMigration(groupThread: groupThread,
                                            transaction: transaction)
        }
    }

    // Will return nil if the group cannot be migrated by the local
    // user for any reason.
    static func migrationInfoForManualMigration(groupThread: TSGroupThread,
                                                transaction: SDSAnyReadTransaction) -> GroupsV2MigrationInfo {

        return migrationInfo(groupThread: groupThread,
                             migrationMode: manualMigrationMode,
                             transaction: transaction)
    }

    private static var manualMigrationMode: GroupsV2MigrationMode {
        return .manualMigrationAggressive
    }

    private static var autoMigrationMode: GroupsV2MigrationMode {
        return .autoMigrationPolite
    }

    @objc(autoMigrateThreadIfNecessary:)
    static func autoMigrateThreadIfNecessary(thread: TSThread) {
        AssertIsOnMainThread()

        guard let groupThread = thread as? TSGroupThread else {
            return
        }
        guard groupThread.isGroupV1Thread else {
            return
        }

        let migrationMode = self.autoMigrationMode
        firstly {
            return tryToMigrate(groupThread: groupThread, migrationMode: migrationMode)
        }.done(on: .global()) { (_: TSGroupThread) in
            Logger.verbose("")
        }.catch(on: .global()) { error in
            if case GroupsV2Error.groupDoesNotExistOnService = error {
                Logger.warn("Error: \(error)")
            } else if case GroupsV2Error.localUserNotInGroup = error {
                Logger.warn("Error: \(error)")
            } else if case GroupsV2Error.groupCannotBeMigrated = error {
                Logger.info("Error: \(error)")
            } else {
                owsFailDebug("Error: \(error)")
            }
        }
    }
}

// MARK: -

public extension GroupsV2Migration {
    static var verboseLogging: Bool { DebugFlags.internalLogging }
}

// MARK: -

fileprivate extension GroupsV2Migration {

    private static let migrationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "GroupsV2MigrationQueue"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    // Ensure only one migration is in flight at a time.
    static func enqueueMigration(groupId: Data,
                                 migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {
        if GroupsV2Migration.verboseLogging {
            Logger.info("enqueue groupId: \(groupId.hexadecimalString), migrationMode: \(migrationMode)")
        }
        let operation = MigrateGroupOperation(groupId: groupId, migrationMode: migrationMode)
        migrationQueue.addOperation(operation)
        return operation.promise
    }

    // groupId might be the v1 or v2 group id.
    static func attemptMigration(groupId: Data,
                                 migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {

        guard tsAccountManager.isRegisteredAndReady else {
            return Promise(error: OWSAssertionError("Not registered."))
        }

        return firstly(on: .global()) { () -> Promise<Void> in
            if Self.verboseLogging {
                Logger.info("Step 1: groupId: \(groupId.hexadecimalString), mode: \(migrationMode)")
            }
            return GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
        }.map(on: .global()) { () -> UnmigratedState in
            if Self.verboseLogging {
                Logger.info("Step 2: groupId: \(groupId.hexadecimalString), mode: \(migrationMode)")
            }
            return try Self.loadUnmigratedState(groupId: groupId)
        }.then(on: .global()) { (unmigratedState: UnmigratedState) -> Promise<UnmigratedState> in
            if Self.verboseLogging {
                Logger.info("Step 3: groupId: \(groupId.hexadecimalString), mode: \(migrationMode)")
                let groupName = unmigratedState.groupThread.groupModel.groupName ?? "Unnamed group"
                Logger.verbose("Migrating: \(groupName)")
            }

            return firstly {
                Self.tryToPrepareMembersForMigration(migrationMode: migrationMode,
                                                     unmigratedState: unmigratedState)
            }.map(on: .global()) {
                unmigratedState
            }
        }.then(on: .global()) { (unmigratedState: UnmigratedState) -> Promise<TSGroupThread> in
            if Self.verboseLogging {
                Logger.info("Step 4: groupId: \(groupId.hexadecimalString), mode: \(migrationMode)")
            }

            addMigratingGroupId(unmigratedState.migrationMetadata.v1GroupId)
            addMigratingGroupId(unmigratedState.migrationMetadata.v2GroupId)

            return firstly(on: .global()) { () -> Promise<TSGroupThread> in
                attemptToMigrateByPullingFromService(unmigratedState: unmigratedState,
                                                     migrationMode: migrationMode)
            }.recover(on: .global()) { (error: Error) -> Promise<TSGroupThread> in
                if case GroupsV2Error.groupDoesNotExistOnService = error,
                    migrationMode.canMigrateToService {
                    if Self.verboseLogging {
                        Logger.info("Step 4: groupId: \(groupId.hexadecimalString), mode: \(migrationMode)")
                    }
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

    // This method tries to fill in missing:
    //
    // * UUIDs.
    // * Capabilities (2).
    // * Profile key credentials.
    static func tryToPrepareMembersForMigration(migrationMode: GroupsV2MigrationMode,
                                                unmigratedState: UnmigratedState) -> Promise<Void> {
        guard !migrationMode.isOnlyUpdatingIfAlreadyMigrated else {
            // If we're only trying to update the local db to
            // reflect groups that are already migrated, we can
            // skip this step.
            return Promise.value(())
        }

        let groupMembership = unmigratedState.groupThread.groupModel.groupMembership
        let membersToMigrate = membersToTryToMigrate(groupMembership: groupMembership)

        return firstly(on: .global()) { () -> Promise<Void> in
            let phoneNumbersWithoutUuids = membersToMigrate.compactMap { (address: SignalServiceAddress) -> String? in
                if address.uuid != nil {
                    return nil
                }
                return address.phoneNumber
            }
            guard !phoneNumbersWithoutUuids.isEmpty else {
                return Promise.value(())
            }

            Logger.info("Trying to fill in missing uuids: \(phoneNumbersWithoutUuids.count)")

            let discoveryTask = ContactDiscoveryTask(phoneNumbers: Set(phoneNumbersWithoutUuids))
            return firstly {
                discoveryTask.perform().asVoid()
            }.recover(on: .global()) { error -> Promise<Void> in
                owsFailDebugUnlessNetworkFailure(error)
                return Promise.value(())
            }
        }.then(on: .global()) { () -> Promise<Void> in
            let membersToFetchProfiles = Self.databaseStorage.read { transaction in
                // Both the capability and a profile key are required to migrate
                // If a user doesn't have both, we need to refetch their profile
                membersToMigrate.filter { address in
                    let hasProfileKey = groupsV2.hasProfileKeyCredential(
                        for: address,
                        transaction: transaction)
                    guard hasProfileKey else { return true }

                    return false
                }
            }
            guard !membersToFetchProfiles.isEmpty else {
                return Promise.value(())
            }
            Logger.info("Fetching profiles: \(membersToFetchProfiles.count)")
            // Profile fetches are rate limited. We don't want to run afoul of those
            // rate limits especially while trying to auto-migrate groups in the
            // background. Therefore we throttle these requests for auto-migrations.
            let profileFetchMode: ProfileFetchMode = (migrationMode.isManualMigration
                                                        ? .parallel
                                                        : .serialWithThrottling)
            return fetchProfiles(addresses: Array(membersToFetchProfiles),
                                 profileFetchMode: profileFetchMode)
        }
    }

    private enum ProfileFetchMode {
        case serialWithThrottling
        case parallel
    }

    private static func fetchProfiles(addresses: [SignalServiceAddress],
                                      profileFetchMode: ProfileFetchMode) -> Promise<Void> {
        func fetchProfilePromise(address: SignalServiceAddress) -> Promise<Void> {
            firstly {
                ProfileFetcherJob.fetchProfilePromise(address: address, ignoreThrottling: false).asVoid()
            }.recover(on: .global()) { error -> Promise<Void> in
                if case ProfileFetchError.throttled = error {
                    // Ignore throttling errors.
                    return Promise.value(())
                }
                if case ProfileFetchError.missing = error {
                    // If a user has no profile, ignore.
                    return Promise.value(())
                }
                owsFailDebugUnlessNetworkFailure(error)
                return Promise.value(())
            }
        }

        switch profileFetchMode {
        case .parallel:
            let promises = addresses.map { fetchProfilePromise(address: $0) }
            return Promise.when(fulfilled: promises)
        case .serialWithThrottling:
            guard let firstAddress = addresses.first else {
                // No more profiles to fetch.
                return Promise.value(())
            }
            let remainder = Array(addresses.suffix(from: 1))
            return firstly {
                fetchProfilePromise(address: firstAddress)
            }.then(on: .global()) {
                // We need to throttle these jobs.
                //
                // The profile fetch rate limit is a bucket size of 4320, which
                // refills at a rate of 3 per minute.
                Guarantee.after(seconds: 1.0 / 3.0)
            }.then(on: .global()) {
                // Recurse.
                fetchProfiles(addresses: remainder, profileFetchMode: profileFetchMode)
            }
        }
    }

    static func attemptToMigrateByPullingFromService(unmigratedState: UnmigratedState,
                                                     migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {

        return firstly(on: .global()) { () -> Promise<GroupV2Snapshot> in
            let groupSecretParamsData = unmigratedState.migrationMetadata.v2GroupSecretParams
            return self.groupsV2Impl.fetchCurrentGroupV2Snapshot(groupSecretParamsData: groupSecretParamsData)
        }.recover(on: .global()) { (error: Error) -> Promise<GroupV2Snapshot> in
            if case GroupsV2Error.groupDoesNotExistOnService = error {
                // Convert error if the group is not already on the service.
                throw GroupsV2Error.groupDoesNotExistOnService
            } else if case GroupsV2Error.localUserNotInGroup = error {
                databaseStorage.write { transaction in
                    let groupId = unmigratedState.migrationMetadata.v1GroupId
                    GroupManager.handleNotInGroup(groupId: groupId, transaction: transaction)
                }
                throw error
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
            try self.databaseStorage.write { transaction in
                let builder = try TSGroupModelBuilder.builderForSnapshot(groupV2Snapshot: groupV2Snapshot,
                                                                         transaction: transaction)
                return try builder.buildAsV2()
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

            Logger.info("Group migrated using snapshot service")

            return groupThread
        }
    }

    static func attemptToMigrateByCreatingOnService(unmigratedState: UnmigratedState,
                                                    migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {

        Logger.info("migrationMode: \(migrationMode)")

        // This is only called from attemptMigration, also located in this file.
        // That method will fetch missing UUIDs and profile key credentials before
        // calling this one, so we don't need to fetch those as part of this flow.

        return firstly(on: .global()) { () throws -> Promise<String?> in
            // We should only migrate groups when we're a member.
            let groupThread = unmigratedState.groupThread
            guard groupThread.isLocalUserFullMember else {
                throw OWSAssertionError("Local user cannot migrate group; is not a full member.")
            }

            // If there's an avatar, upload it first; otherwise, just keep going.
            guard let avatarData = unmigratedState.groupThread.groupModel.avatarData else {
                // No avatar to upload.
                return Promise.value(nil)
            }

            // Upload avatar.
            return firstly(on: .global()) { () -> Promise<String> in
                return self.groupsV2Impl.uploadGroupAvatar(avatarData: avatarData,
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

            Logger.info("Group migrated to service")

            return groupThread
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                  description: "Migrate group") {
            GroupsV2Error.timeout
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
        if let avatarData = v1GroupModel.avatarData,
            let avatarUrlPath = avatarUrlPath {
            groupModelBuilder.avatarData = avatarData
            groupModelBuilder.avatarUrlPath = avatarUrlPath
        } else {
            owsAssertDebug(v1GroupModel.avatarData == nil)
            owsAssertDebug(avatarUrlPath == nil)
            groupModelBuilder.avatarData = nil
            groupModelBuilder.avatarUrlPath = nil
        }

        // Build member list.
        //
        // The group creator is an administrator;
        // the other members are normal users.
        var v2MembershipBuilder = GroupMembership.Builder()
        let membersToMigrate = membersToTryToMigrate(groupMembership: v1GroupModel.groupMembership)
        for address in membersToMigrate {
            if DebugFlags.groupsV2migrationsDropOtherMembers.get(),
                !address.isLocalAddress {
                Logger.warn("Dropping non-local user.")
                continue
            }

            guard address.uuid != nil else {
                Logger.warn("Member missing uuid: \(address).")
                owsAssertDebug(migrationMode.canSkipMembersWithoutUuids)
                Logger.warn("Discarding member: \(address).")
                continue
            }

            var isInvited = false
            if DebugFlags.groupsV2migrationsInviteOtherMembers.get() {
                Logger.warn("Inviting user with unknown profile key: \(address).")
                isInvited = true
            } else if !groupsV2.hasProfileKeyCredential(for: address, transaction: transaction) {
                Logger.warn("Inviting user with unknown profile key: \(address).")
                owsAssertDebug(migrationMode.canInviteMembersWithoutProfileKey)
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

        return try groupModelBuilder.buildAsV2()
    }

    static func migrateGroupOnService(proposedGroupModel: TSGroupModelV2,
                                      disappearingMessageToken: DisappearingMessageToken) -> Promise<TSGroupModelV2> {
        return firstly {
            self.groupsV2Impl.createNewGroupOnService(groupModel: proposedGroupModel,
                                                  disappearingMessageToken: disappearingMessageToken)
        }.then(on: .global()) { _ in
            self.groupsV2Impl.fetchCurrentGroupV2Snapshot(groupModel: proposedGroupModel)
        }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> TSGroupModelV2 in
            let createdGroupModel = try self.databaseStorage.write { (transaction) throws -> TSGroupModelV2 in
                let builder = try TSGroupModelBuilder.builderForSnapshot(groupV2Snapshot: groupV2Snapshot,
                                                                         transaction: transaction)
                return try builder.buildAsV2()
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
        migrationInfo(groupThread: groupThread,
                      migrationMode: migrationMode,
                      transaction: transaction).canGroupBeMigrated
    }

    // This method might be called for any group (v1 or v2).
    // It returns a description of whether the group can be
    // migrated, and if so under what conditions.
    //
    // Will return nil if the group cannot be migrated by the local
    // user for any reason.
    static func migrationInfo(groupThread: TSGroupThread,
                              migrationMode: GroupsV2MigrationMode,
                              transaction: SDSAnyReadTransaction) -> GroupsV2MigrationInfo {

        guard groupThread.isGroupV1Thread else {
            return .buildCannotBeMigrated(state: .cantBeMigrated_NotAV1Group)
        }
        let isLocalUserFullMember = groupThread.isLocalUserFullMember

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return .buildCannotBeMigrated(state: .cantBeMigrated_NotRegistered)
        }

        let isGroupInProfileWhitelist = profileManager.isThread(inProfileWhitelist: groupThread,
                                                                transaction: transaction)

        let groupMembership = groupThread.groupModel.groupMembership
        let membersToMigrate = membersToTryToMigrate(groupMembership: groupMembership)

        // Inspect member list.
        //
        // The group creator is an administrator;
        // the other members are normal users.
        var membersWithoutUuids = [SignalServiceAddress]()
        var membersWithoutProfileKeys = [SignalServiceAddress]()
        var membersMigrated = [SignalServiceAddress]()
        for address in membersToMigrate {
            if address.isEqualToAddress(localAddress) {
                continue
            }

            if DebugFlags.groupsV2migrationsDropOtherMembers.get() {
                Logger.warn("Dropping non-local user.")
                membersWithoutUuids.append(address)
                continue
            }

            guard nil != address.uuid else {
                Logger.warn("Member without uuid: \(address).")
                membersWithoutUuids.append(address)
                continue
            }

            membersMigrated.append(address)

            if DebugFlags.groupsV2migrationsInviteOtherMembers.get() ||
                !groupsV2.hasProfileKeyCredential(for: address, transaction: transaction) {
                Logger.warn("Member without profile key: \(address).")
                membersWithoutProfileKeys.append(address)
                continue
            }
        }

        let hasTooManyMembers = membersMigrated.count > GroupManager.groupsV2MaxGroupSizeHardLimit

        let state: GroupsV2MigrationState = {
            if !migrationMode.canMigrateIfNotMember,
                !isLocalUserFullMember {
                return .cantBeMigrated_LocalUserIsNotAMember
            }
            if !migrationMode.canMigrateIfNotInProfileWhitelist,
                !isGroupInProfileWhitelist {
                return .cantBeMigrated_NotInProfileWhitelist
            }
            if !migrationMode.canSkipMembersWithoutUuids,
                !membersWithoutUuids.isEmpty {
                return .cantBeMigrated_MembersWithoutUuids
            }
            if !migrationMode.canInviteMembersWithoutProfileKey,
                !membersWithoutProfileKeys.isEmpty {
                return .cantBeMigrated_MembersWithoutProfileKey
            }
            if !migrationMode.canMigrateWithTooManyMembers,
                hasTooManyMembers {
                return .cantBeMigrated_TooManyMembers
            }
            return .canBeMigrated
        }()

        Logger.info("Can the group be migrated?: \(state)")

        return GroupsV2MigrationInfo(isGroupInProfileWhitelist: isGroupInProfileWhitelist,
                                     membersWithoutUuids: membersWithoutUuids,
                                     membersWithoutProfileKeys: membersWithoutProfileKeys,
                                     state: state)
    }

    static func membersToTryToMigrate(groupMembership: GroupMembership) -> Set<SignalServiceAddress> {

        let allMembers = groupMembership.allMembersOfAnyKind
        let addressesWithoutUuids = Array(allMembers).filter { $0.uuid == nil }
        let knownUndiscoverable = Set(ContactDiscoveryTask.addressesRecentlyMarkedAsUndiscoverableForGroupMigrations(addressesWithoutUuids))

        var result = Set<SignalServiceAddress>()
        for address in allMembers {
            if nil == address.uuid, knownUndiscoverable.contains(address) {
                Logger.warn("Ignoring unregistered member without uuid: \(address).")
                continue
            }
            result.insert(address)
        }
        return result
    }
}

// MARK: -

public enum GroupsV2MigrationState {
    case canBeMigrated
    case cantBeMigrated_NotAV1Group
    case cantBeMigrated_NotRegistered
    case cantBeMigrated_LocalUserIsNotAMember
    case cantBeMigrated_NotInProfileWhitelist
    case cantBeMigrated_TooManyMembers
    case cantBeMigrated_MembersWithoutUuids
    case cantBeMigrated_MembersWithoutProfileKey
}

// MARK: -

@objc
public class GroupsV2MigrationInfo: NSObject {
    // These properties only have valid values if canGroupBeMigrated is true.
    public let isGroupInProfileWhitelist: Bool
    public let membersWithoutUuids: [SignalServiceAddress]
    public let membersWithoutProfileKeys: [SignalServiceAddress]

    // Always consult this property first.
    public let state: GroupsV2MigrationState

    fileprivate init(isGroupInProfileWhitelist: Bool,
                     membersWithoutUuids: [SignalServiceAddress],
                     membersWithoutProfileKeys: [SignalServiceAddress],
                     state: GroupsV2MigrationState) {
        self.isGroupInProfileWhitelist = isGroupInProfileWhitelist
        self.membersWithoutUuids = membersWithoutUuids
        self.membersWithoutProfileKeys = membersWithoutProfileKeys
        self.state = state
    }

    @objc
    public var canGroupBeMigrated: Bool {
        state == .canBeMigrated
    }

    fileprivate static func buildCannotBeMigrated(state: GroupsV2MigrationState) -> GroupsV2MigrationInfo {
        GroupsV2MigrationInfo(isGroupInProfileWhitelist: false,
                              membersWithoutUuids: [],
                              membersWithoutProfileKeys: [],
                              state: state)
    }
}

// MARK: -

public enum GroupsV2MigrationMode: String {
    // Manual migration; only available if all users can be
    // migrated.
    case manualMigrationAggressive
    // Auto migration; only available if all users can be
    // added.
    case autoMigrationPolite
    // When an incoming message (including sync messages)
    // or storage service update indicates that a group
    // has been migrated to the service, we should update
    // the local DB immediately to reflect the group state
    // on the service.
    case isAlreadyMigratedOnService

    fileprivate var isManualMigration: Bool {
        self == .manualMigrationAggressive
    }

    fileprivate var isAutoMigration: Bool {
        self == .autoMigrationPolite
    }

    fileprivate var isPolite: Bool {
        self == .autoMigrationPolite
    }

    fileprivate var isAggressive: Bool {
        self == .manualMigrationAggressive
    }

    fileprivate var isOnlyUpdatingIfAlreadyMigrated: Bool {
        switch self {
        case .isAlreadyMigratedOnService:
            return true
        case .manualMigrationAggressive,
             .autoMigrationPolite:
            return false
        }
    }

    public var canSkipMembersWithoutUuids: Bool {
        isAggressive || isOnlyUpdatingIfAlreadyMigrated
    }

    public var canInviteMembersWithoutProfileKey: Bool {
        isManualMigration || isAggressive || isOnlyUpdatingIfAlreadyMigrated
    }

    public var canMigrateIfNotInProfileWhitelist: Bool {
        isOnlyUpdatingIfAlreadyMigrated
    }

    public var canMigrateToService: Bool {
        !isOnlyUpdatingIfAlreadyMigrated
    }

    public var canMigrateIfNotMember: Bool {
        isOnlyUpdatingIfAlreadyMigrated
    }

    public var canMigrateWithTooManyMembers: Bool {
        isOnlyUpdatingIfAlreadyMigrated
    }

    fileprivate var queuePriority: Operation.QueuePriority {
        switch self {
        case .isAlreadyMigratedOnService:
            // These migrations block message processing and have high priority.
            return .high
        case .manualMigrationAggressive:
            // Manual migrations block the UI and have the highest priority.
            return .veryHigh
        case .autoMigrationPolite:
            return .low
        }
    }
}

// MARK: -

extension GroupsV2Migration {

    // MARK: - Migrating Group Ids

    // We track migrating group ids for usage in asserts.
    private static let unfairLock = UnfairLock()
    private static var migratingV2GroupIds = Set<Data>()

    private static func addMigratingGroupId(_ groupId: Data) {
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
        let migrationInfo = "GV2 Migration"
        let masterKey = try migrationInfo.utf8.withContiguousStorageIfAvailable {
            try hkdf(outputLength: GroupMasterKey.SIZE, inputKeyMaterial: v1GroupId, salt: [], info: $0)
        }!
        return Data(masterKey)
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
        let v2GroupSecretParams = try groupsV2Impl.groupSecretParamsData(forMasterKeyData: masterKey)
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
                throw OWSGenericError("Unexpected groupsVersion.")
            }
            let disappearingMessagesConfiguration = groupThread.disappearingMessagesConfiguration(with: transaction)
            let migrationMetadata = try Self.calculateMigrationMetadata(for: groupThread.groupModel)

            return UnmigratedState(groupThread: groupThread,
                                   disappearingMessagesConfiguration: disappearingMessagesConfiguration,
                                   migrationMetadata: migrationMetadata)
        }
    }
}

// MARK: -

private class MigrateGroupOperation: OWSOperation {

    private let groupId: Data
    private let migrationMode: GroupsV2MigrationMode

    fileprivate let promise: Promise<TSGroupThread>
    fileprivate let future: Future<TSGroupThread>

    fileprivate required init(groupId: Data,
                              migrationMode: GroupsV2MigrationMode) {
        self.groupId = groupId
        self.migrationMode = migrationMode

        let (promise, future) = Promise<TSGroupThread>.pending()
        self.promise = promise
        self.future = future

        super.init()

        self.queuePriority = migrationMode.queuePriority
    }

    public override func run() {
        let groupId = self.groupId
        let migrationMode = self.migrationMode
        if GroupsV2Migration.verboseLogging {
            Logger.info("start groupId: \(groupId.hexadecimalString), migrationMode: \(migrationMode)")
        }

        firstly(on: .global()) {
            GroupsV2Migration.attemptMigration(groupId: groupId,
                                               migrationMode: migrationMode)
        }.done(on: .global()) { groupThread in
            if GroupsV2Migration.verboseLogging {
                Logger.info("success groupId: \(groupId.hexadecimalString), migrationMode: \(migrationMode)")
            }
            self.reportSuccess()
            self.future.resolve(groupThread)
        }.catch(on: .global()) { error in
            if GroupsV2Migration.verboseLogging {
                Logger.info("failure groupId: \(groupId.hexadecimalString), migrationMode: \(migrationMode), error: \(error)")
            }
            self.reportError(error)
            self.future.reject(error)
        }
    }
}
