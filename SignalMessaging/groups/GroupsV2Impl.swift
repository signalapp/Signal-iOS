//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit
import ZKGroup

@objc
public class GroupsV2Impl: NSObject, GroupsV2Swift {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var socketManager: TSSocketManager {
        return TSSocketManager.shared
    }

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    private var urlSession: OWSURLSession {
        return OWSSignalService.shared().urlSessionForStorageService()
    }

    private var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private var groupV2Updates: GroupV2UpdatesSwift {
        return SSKEnvironment.shared.groupV2Updates as! GroupV2UpdatesSwift
    }

    private var versionedProfiles: VersionedProfilesImpl {
        return SSKEnvironment.shared.versionedProfiles as! VersionedProfilesImpl
    }

    // MARK: -

    public typealias ProfileKeyCredentialMap = [UUID: ProfileKeyCredential]

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            let didReset = self.verifyServerPublicParams()

            // We don't need to ensure the local profile commitment
            // if we've just reset the zkgroup state, since that
            // have the same effect.
            guard !didReset,
                self.tsAccountManager.isRegisteredAndReady else {
                    return
            }

            firstly {
                GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
            }.catch { error in
                Logger.warn("Local profile update failed with error: \(error)")
            }

        }
        AppReadiness.runNowOrWhenAppDidBecomeReadyPolite {
            self.mergeUserProfiles()

            Self.enqueueRestoreGroupPass()

            GroupsV2Migration.tryToAutoMigrateAllGroups(shouldLimitBatchSize: true)
        }

        observeNotifications()
    }

    // MARK: -

    private let serviceStore = SDSKeyValueStore(collection: "GroupsV2Impl.serviceStore")

    // Returns true IFF zkgroups-related state is reset.
    private func verifyServerPublicParams() -> Bool {
        let serverPublicParamsBase64 = TSConstants.serverPublicParamsBase64
        let lastServerPublicParamsKey = "lastServerPublicParamsKey"
        let lastZKgroupVersionCounterKey = "lastZKgroupVersionCounterKey"
        // This _does not_ conform to the public version number of the
        // zkgroup library.  Instead it's a counter we should bump
        // every time there are breaking changes zkgroup library, e.g.
        // changes to data formats.
        let zkgroupVersionCounter: Int = 3

        let shouldReset = databaseStorage.read { transaction -> Bool in
            guard serverPublicParamsBase64 == self.serviceStore.getString(lastServerPublicParamsKey, transaction: transaction) else {
                Logger.info("Server public params have changed.")
                return true
            }
            guard zkgroupVersionCounter == self.serviceStore.getInt(lastZKgroupVersionCounterKey, transaction: transaction) else {
                Logger.info("ZKGroup library has changed.")
                return true
            }
            return false
        }
        guard shouldReset else {
            // Nothing to be done; server public params haven't changed.
            return false
        }

        Logger.info("Resetting zkgroup-related state.")

        databaseStorage.write { transaction in
            self.clearTemporalCredentials(transaction: transaction)
            self.versionedProfiles.clearProfileKeyCredentials(transaction: transaction)
            self.serviceStore.setString(serverPublicParamsBase64, key: lastServerPublicParamsKey, transaction: transaction)
            self.serviceStore.setInt(zkgroupVersionCounter, key: lastZKgroupVersionCounterKey, transaction: transaction)
        }
        AppReadiness.runNowOrWhenAppDidBecomeReadyPolite {
            if self.tsAccountManager.isRegisteredAndReady {
                firstly {
                    self.reuploadLocalProfilePromise()
                }.catch { error in
                    Logger.warn("Error: \(error)")
                }
            }
        }
        return true
    }

    // This will only be used for internal builds.
    private func mergeUserProfiles() {
        guard DebugFlags.shouldMergeUserProfiles else {
            return
        }

        databaseStorage.asyncWrite { transaction in
            SignalRecipient.anyEnumerate(transaction: transaction) { (recipient, _) in
                let address = recipient.address
                guard address.uuid != nil, address.phoneNumber != nil else {
                    return
                }
                OWSUserProfile.mergeUserProfilesIfNecessary(for: address, transaction: transaction)
            }
        }
    }

    // MARK: - Notifications

    private func observeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reachabilityChanged),
                                               name: SSKReachability.owsReachabilityDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)
    }

    @objc
    func didBecomeActive() {
        AssertIsOnMainThread()

        AppReadiness.runNowOrWhenAppDidBecomeReadyPolite {
            GroupsV2Impl.enqueueRestoreGroupPass()
        }
    }

    @objc
    func reachabilityChanged() {
        AssertIsOnMainThread()

        GroupsV2Impl.enqueueRestoreGroupPass()
    }

    // MARK: - Create Group

    public func createNewGroupOnService(groupModel: TSGroupModelV2,
                                        disappearingMessageToken: DisappearingMessageToken) -> Promise<Void> {
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise<Void>(error: OWSAssertionError("Missing localUuid."))
        }
        let groupV2Params: GroupV2Params
        do {
            groupV2Params = try groupModel.groupV2Params()
        } catch {
            return Promise<Void>(error: error)
        }

        let requestBuilder: RequestBuilder = { (authCredential) in
            return firstly(on: .global()) { () -> [UUID] in
                // Gather the UUIDs for all members.
                // We cannot gather profile key credentials for pending members, by definition.
                let uuids = self.uuids(for: groupModel.groupMembers)
                guard uuids.contains(localUuid) else {
                    throw OWSAssertionError("localUuid is not a member.")
                }
                return uuids
            }.then(on: .global()) { (uuids: [UUID]) -> Promise<ProfileKeyCredentialMap> in
                // Gather the profile key credentials for all members.
                let allUuids = uuids + [localUuid]
                return self.loadProfileKeyCredentialData(for: allUuids)
            }.map(on: .global()) { (profileKeyCredentialMap: ProfileKeyCredentialMap) -> GroupsV2Request in
                let groupProto = try GroupsV2Protos.buildNewGroupProto(groupModel: groupModel,
                                                                       disappearingMessageToken: disappearingMessageToken,
                                                                       groupV2Params: groupV2Params,
                                                                       profileKeyCredentialMap: profileKeyCredentialMap,
                                                                       localUuid: localUuid)
                return try StorageService.buildNewGroupRequest(groupProto: groupProto,
                                                               groupV2Params: groupV2Params,
                                                               authCredential: authCredential)
            }
        }

        return performServiceRequest(requestBuilder: requestBuilder,
                                     groupId: nil,
                                     behavior403: .fail,
                                     behavior404: .fail).asVoid()
    }

    // MARK: - Update Group

    private struct UpdatedV2Group {
        public let groupThread: TSGroupThread
        public let changeActionsProtoData: Data

        public init(groupThread: TSGroupThread,
                    changeActionsProtoData: Data) {
            self.groupThread = groupThread
            self.changeActionsProtoData = changeActionsProtoData
        }
    }

    // This method updates the group on the service.  This corresponds to:
    //
    // * The local user editing group state (e.g. adding a member).
    // * The local user accepting an invite.
    // * The local user reject an invite.
    // * The local user leaving the group.
    // * etc.
    //
    // Whenever we do this, there's a few follow-on actions that we always want to do (on success):
    //
    // * Update the group in the local database to reflect the update.
    // * Insert "group update info" messages in the conversation history.
    // * Send "group update" messages to other members &  linked devices.
    //
    // We do those things here as well, to DRY them up and to ensure they're always
    // done immediately and in a consistent way.
    public func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<TSGroupThread> {

        let groupId = changeSet.groupId
        let groupSecretParamsData = changeSet.groupSecretParamsData
        let groupV2Params: GroupV2Params
        do {
            groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
        } catch {
            return Promise(error: error)
        }

        let finalGroupChangeProto = AtomicOptional<GroupsProtoGroupChangeActions>(nil)
        var isFirstAttempt = true
        let requestBuilder: RequestBuilder = { (authCredential) in
            return firstly { () -> Promise<Void> in
                if isFirstAttempt {
                    isFirstAttempt = false
                    return Promise.value(())
                }
                return self.groupV2Updates.tryToRefreshV2GroupUpToCurrentRevisionImmediately(groupId: groupId,
                                                                                             groupSecretParamsData: groupSecretParamsData).asVoid()
            }.map(on: .global()) { _ throws -> (thread: TSGroupThread, disappearingMessageToken: DisappearingMessageToken) in
                return try self.databaseStorage.read { transaction in
                    guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                        throw OWSAssertionError("Thread does not exist.")
                    }
                    let dmConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: groupThread, transaction: transaction)
                    return (groupThread, dmConfiguration.asToken)
                }
            }.then(on: .global()) { (groupThread: TSGroupThread, disappearingMessageToken: DisappearingMessageToken) -> Promise<GroupsProtoGroupChangeActions> in
                guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid group model.")
                }
                return changeSet.buildGroupChangeProto(currentGroupModel: groupModel,
                                                       currentDisappearingMessageToken: disappearingMessageToken)
            }.map(on: .global()) { (groupChangeProto: GroupsProtoGroupChangeActions) -> GroupsV2Request in
                finalGroupChangeProto.set(groupChangeProto)
                return try StorageService.buildUpdateGroupRequest(groupChangeProto: groupChangeProto,
                                                                  groupV2Params: groupV2Params,
                                                                  authCredential: authCredential,
                                                                  groupInviteLinkPassword: nil)
            }
        }

        return firstly {
            self.performServiceRequest(requestBuilder: requestBuilder,
                                       groupId: groupId,
                                       behavior403: .fetchGroupUpdates,
                                       behavior404: .fail)
        }.then(on: .global()) { (response: OWSHTTPResponse) -> Promise<UpdatedV2Group> in

            guard let changeActionsProtoData = response.responseData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            let changeActionsProto = try GroupsV2Protos.parseAndVerifyChangeActionsProto(changeActionsProtoData,
                                                                                         ignoreSignature: true)

            // Collect avatar state from our change set so that we can
            // avoid downloading any avatars we just uploaded while
            // applying the change set locally.
            let downloadedAvatars = GroupV2DownloadedAvatars.from(changeSet: changeSet)

            return firstly {
                // We can ignoreSignature because these protos came from the service.
                return self.updateGroupWithChangeActions(groupId: groupId,
                                                         changeActionsProto: changeActionsProto,
                                                         justUploadedAvatars: downloadedAvatars,
                                                         ignoreSignature: true,
                                                         groupV2Params: groupV2Params)
            }.map(on: .global()) { (groupThread: TSGroupThread) -> UpdatedV2Group in
                return UpdatedV2Group(groupThread: groupThread, changeActionsProtoData: changeActionsProtoData)
            }
        }.then(on: .global()) { (updatedV2Group: UpdatedV2Group) -> Promise<TSGroupThread> in
            return firstly {
                GroupManager.sendGroupUpdateMessage(thread: updatedV2Group.groupThread,
                                                    changeActionsProtoData: updatedV2Group.changeActionsProtoData)
            }.map(on: .global()) { (_) -> Void in
                guard let groupChangeProto = finalGroupChangeProto.get() else {
                    owsFailDebug("Missing groupChangeProto.")
                    return
                }
                self.sendGroupUpdateMessageToRemovedUsers(groupThread: updatedV2Group.groupThread,
                                                          groupChangeProto: groupChangeProto,
                                                          changeActionsProtoData: updatedV2Group.changeActionsProtoData,
                                                          groupV2Params: groupV2Params)
            }.map(on: .global()) { (_) -> TSGroupThread in
                return updatedV2Group.groupThread
            }
        }
    }

    private func membersRemovedByChangeActions(groupChangeProto: GroupsProtoGroupChangeActions,
                                               groupV2Params: GroupV2Params) -> [UUID] {
        var userIds = [Data]()
        for action in groupChangeProto.deleteMembers {
            guard let userId = action.deletedUserID else {
                owsFailDebug("Missing userID.")
                continue
            }
            userIds.append(userId)
        }
        for action in groupChangeProto.deletePendingMembers {
            guard let userId = action.deletedUserID else {
                owsFailDebug("Missing userID.")
                continue
            }
            userIds.append(userId)
        }
        for action in groupChangeProto.deleteRequestingMembers {
            guard let userId = action.deletedUserID else {
                owsFailDebug("Missing userID.")
                continue
            }
            userIds.append(userId)
        }

        var uuids = [UUID]()
        for userId in userIds {
            do {
                let uuid = try groupV2Params.uuid(forUserId: userId)
                uuids.append(uuid)
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        return uuids
    }

    private func sendGroupUpdateMessageToRemovedUsers(groupThread: TSGroupThread,
                                                      groupChangeProto: GroupsProtoGroupChangeActions,
                                                      changeActionsProtoData: Data,
                                                      groupV2Params: GroupV2Params) {
        let shouldSendUpdate = !DebugFlags.groupsV2dontSendUpdates.get()
        guard shouldSendUpdate else {
            return
        }
        let uuids = membersRemovedByChangeActions(groupChangeProto: groupChangeProto,
                                                  groupV2Params: groupV2Params)

        guard !uuids.isEmpty else {
            return
        }

        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid groupModel.")
            return
        }

        let contactThreads = databaseStorage.write { transaction in
            uuids.map { uuid in
                TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(uuid: uuid),
                                                  transaction: transaction)
            }
        }
        for contactThread in contactThreads {
            let contentProtoData: Data
            do {
                let groupV2Context = try GroupsV2Protos.buildGroupContextV2Proto(groupModel: groupModel,
                                                                                 changeActionsProtoData: changeActionsProtoData)

                let dataBuilder = SSKProtoDataMessage.builder()
                dataBuilder.setGroupV2(groupV2Context)
                dataBuilder.setRequiredProtocolVersion(1)

                let dataProto = try dataBuilder.build()
                let contentBuilder = SSKProtoContent.builder()
                contentBuilder.setDataMessage(dataProto)
                contentProtoData = try contentBuilder.buildSerializedData()
            } catch {
                owsFailDebug("Error: \(error)")
                continue
            }
            let message = OWSDynamicOutgoingMessage(thread: contactThread) { (_: SignalServiceAddress) -> Data in
                contentProtoData
            }
            ThreadUtil.sendMessageNonDurably(message: message)
        }
    }

    public func updateGroupWithChangeActions(groupId: Data,
                                             changeActionsProto: GroupsProtoGroupChangeActions,
                                             ignoreSignature: Bool,
                                             groupSecretParamsData: Data) throws -> Promise<TSGroupThread> {
        let groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
        return updateGroupWithChangeActions(groupId: groupId,
                                            changeActionsProto: changeActionsProto,
                                            justUploadedAvatars: nil,
                                            ignoreSignature: ignoreSignature,
                                            groupV2Params: groupV2Params)
    }

    public func updateGroupWithChangeActions(groupId: Data,
                                             changeActionsProto: GroupsProtoGroupChangeActions,
                                             ignoreSignature: Bool,
                                             groupV2Params: GroupV2Params) -> Promise<TSGroupThread> {
        return updateGroupWithChangeActions(groupId: groupId,
                                            changeActionsProto: changeActionsProto,
                                            justUploadedAvatars: nil,
                                            ignoreSignature: ignoreSignature,
                                            groupV2Params: groupV2Params)
    }

    private func updateGroupWithChangeActions(groupId: Data,
                                              changeActionsProto: GroupsProtoGroupChangeActions,
                                              justUploadedAvatars: GroupV2DownloadedAvatars?,
                                              ignoreSignature: Bool,
                                              groupV2Params: GroupV2Params) -> Promise<TSGroupThread> {

        return firstly {
            self.fetchAllAvatarData(changeActionsProto: changeActionsProto,
                                    justUploadedAvatars: justUploadedAvatars,
                                    ignoreSignature: ignoreSignature,
                                    groupV2Params: groupV2Params)
        }.map(on: .global()) { (downloadedAvatars: GroupV2DownloadedAvatars) -> TSGroupThread in
            return try self.databaseStorage.write { transaction in
                try self.groupV2Updates.updateGroupWithChangeActions(groupId: groupId,
                                                                     changeActionsProto: changeActionsProto,
                                                                     downloadedAvatars: downloadedAvatars,
                                                                     transaction: transaction)
            }
        }
    }

    // MARK: - Upload Avatar

    public func uploadGroupAvatar(avatarData: Data,
                                  groupSecretParamsData: Data) -> Promise<String> {
        return firstly { () -> Promise<String> in
            let groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
            return self.uploadGroupAvatar(avatarData: avatarData, groupV2Params: groupV2Params)
        }
    }

    private func uploadGroupAvatar(avatarData: Data,
                                   groupV2Params: GroupV2Params) -> Promise<String> {

        guard !DebugFlags.groupsV2corruptAvatarUrlPaths.get() else {
            return Promise.value("some/invalid/url/path")
        }

        let requestBuilder: RequestBuilder = { (authCredential) in
            firstly(on: .global()) { () -> GroupsV2Request in
                try StorageService.buildGroupAvatarUploadFormRequest(groupV2Params: groupV2Params,
                                                                     authCredential: authCredential)
            }
        }

        return firstly { () -> Promise<OWSHTTPResponse> in
            let groupId = try self.groupId(forGroupSecretParamsData: groupV2Params.groupSecretParamsData)
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupId,
                                              behavior403: .fetchGroupUpdates,
                                              behavior404: .fail)
        }.map(on: .global()) { (response: OWSHTTPResponse) -> GroupsProtoAvatarUploadAttributes in

            guard let protoData = response.responseData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            return try GroupsProtoAvatarUploadAttributes(serializedData: protoData)
        }.map(on: .global()) { (avatarUploadAttributes: GroupsProtoAvatarUploadAttributes) throws -> OWSUploadFormV2 in
            try OWSUploadFormV2.parse(proto: avatarUploadAttributes)
        }.then(on: .global()) { (uploadForm: OWSUploadFormV2) -> Promise<String> in
            let encryptedData = try groupV2Params.encryptGroupAvatar(avatarData)
            return OWSUpload.uploadV2(data: encryptedData, uploadForm: uploadForm, uploadUrlPath: "")
        }
    }

    // MARK: - Fetch Current Group State

    public func fetchCurrentGroupV2Snapshot(groupModel: TSGroupModelV2) -> Promise<GroupV2Snapshot> {
        // Collect the avatar state to avoid an unnecessary download in the
        // case where we've just created this group but not yet inserted it
        // into the database.
        let justUploadedAvatars = GroupV2DownloadedAvatars.from(groupModel: groupModel)
        return self.fetchCurrentGroupV2Snapshot(groupSecretParamsData: groupModel.secretParamsData,
                                                justUploadedAvatars: justUploadedAvatars)
    }

    public func fetchCurrentGroupV2Snapshot(groupSecretParamsData: Data) -> Promise<GroupV2Snapshot> {
        return fetchCurrentGroupV2Snapshot(groupSecretParamsData: groupSecretParamsData,
                                           justUploadedAvatars: nil)
    }

    private func fetchCurrentGroupV2Snapshot(groupSecretParamsData: Data,
                                             justUploadedAvatars: GroupV2DownloadedAvatars?) -> Promise<GroupV2Snapshot> {
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise<GroupV2Snapshot>(error: OWSAssertionError("Missing localUuid."))
        }
        return firstly(on: .global()) { () -> GroupV2Params in
            return try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
        }.then(on: .global()) { (groupV2Params: GroupV2Params) -> Promise<GroupV2Snapshot> in
            return self.fetchCurrentGroupV2Snapshot(groupV2Params: groupV2Params,
                                                    localUuid: localUuid,
                                                    justUploadedAvatars: justUploadedAvatars)
        }
    }

    private func fetchCurrentGroupV2Snapshot(groupV2Params: GroupV2Params,
                                             localUuid: UUID,
                                             justUploadedAvatars: GroupV2DownloadedAvatars?) -> Promise<GroupV2Snapshot> {
        let requestBuilder: RequestBuilder = { (authCredential) in
            firstly(on: .global()) { () -> GroupsV2Request in
                try StorageService.buildFetchCurrentGroupV2SnapshotRequest(groupV2Params: groupV2Params,
                                                                           authCredential: authCredential)
            }
        }

        return firstly { () -> Promise<OWSHTTPResponse> in
            let groupId = try self.groupId(forGroupSecretParamsData: groupV2Params.groupSecretParamsData)
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupId,
                                              behavior403: .removeFromGroup,
                                              behavior404: .groupDoesNotExistOnService)
        }.map(on: .global()) { (response: OWSHTTPResponse) -> GroupsProtoGroup in
            guard let groupProtoData = response.responseData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            return try GroupsProtoGroup(serializedData: groupProtoData)
        }.then(on: .global()) { (groupProto: GroupsProtoGroup) -> Promise<(GroupsProtoGroup, GroupV2DownloadedAvatars)> in
            return firstly {
                // We can ignoreSignature; these protos came from the service.
                self.fetchAllAvatarData(groupProto: groupProto,
                                        justUploadedAvatars: justUploadedAvatars,
                                        ignoreSignature: true,
                                        groupV2Params: groupV2Params)
            }.map(on: .global()) { (downloadedAvatars: GroupV2DownloadedAvatars) -> (GroupsProtoGroup, GroupV2DownloadedAvatars) in
                return (groupProto, downloadedAvatars)
            }
        }.map(on: .global()) { (groupProto: GroupsProtoGroup, downloadedAvatars: GroupV2DownloadedAvatars) -> GroupV2Snapshot in
            return try GroupsV2Protos.parse(groupProto: groupProto, downloadedAvatars: downloadedAvatars, groupV2Params: groupV2Params)
        }
    }

    // MARK: - Fetch Group Change Actions

    public func fetchGroupChangeActions(groupSecretParamsData: Data,
                                        includeCurrentRevision: Bool,
                                        firstKnownRevision: UInt32?) -> Promise<[GroupV2Change]> {

        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }
        return firstly(on: .global()) { () -> (Data, GroupV2Params) in
            let groupId = try self.groupId(forGroupSecretParamsData: groupSecretParamsData)
            let groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
            return (groupId, groupV2Params)
        }.then(on: .global()) { (groupId: Data, groupV2Params: GroupV2Params) -> Promise<[GroupV2Change]> in
            return self.fetchGroupChangeActions(groupId: groupId,
                                                groupV2Params: groupV2Params,
                                                localUuid: localUuid,
                                                includeCurrentRevision: includeCurrentRevision,
                                                firstKnownRevision: firstKnownRevision)
        }
    }

    private func fetchGroupChangeActions(groupId: Data,
                                         groupV2Params: GroupV2Params,
                                         localUuid: UUID,
                                         includeCurrentRevision: Bool,
                                         firstKnownRevision: UInt32?) -> Promise<[GroupV2Change]> {

        let requestBuilder: RequestBuilder = { (authCredential) in
            return firstly(on: .global()) { () -> GroupsV2Request in
                let (fromRevision, requireSnapshotForFirstChange) =
                    try self.databaseStorage.read { (transaction) throws -> (UInt32, Bool) in
                        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                            if let firstKnownRevision = firstKnownRevision {
                                Logger.info("Group not in database, using first known revision.")
                                return (firstKnownRevision, true)
                            }
                            // This probably isn't an error and will be handled upstream.
                            throw GroupsV2Error.groupNotInDatabase
                        }
                        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                            throw OWSAssertionError("Invalid group model.")
                        }
                        if includeCurrentRevision {
                            return (groupModel.revision, true)
                        } else {
                            return (groupModel.revision + 1, false)
                        }
                }

                return try StorageService.buildFetchGroupChangeActionsRequest(groupV2Params: groupV2Params,
                                                                              fromRevision: fromRevision,
                                                                              requireSnapshotForFirstChange: requireSnapshotForFirstChange,
                                                                              authCredential: authCredential)
            }
        }

        return firstly { () -> Promise<OWSHTTPResponse> in
            // We can't remove the local user from the group on 403.
            // For example, user might just be joining the group
            // using an invite OR have just been re-added after leaving.
            self.performServiceRequest(requestBuilder: requestBuilder,
                                       groupId: groupId,
                                       behavior403: .ignore,
                                       behavior404: .fail)
        }.map(on: .global()) { (response: OWSHTTPResponse) -> GroupsProtoGroupChanges in
            guard let groupChangesProtoData = response.responseData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            return try GroupsProtoGroupChanges(serializedData: groupChangesProtoData)
        }.then(on: .global()) { (groupChangesProto: GroupsProtoGroupChanges) -> Promise<[GroupV2Change]> in
            return firstly {
                // We can ignoreSignature; these protos came from the service.
                self.fetchAllAvatarData(groupChangesProto: groupChangesProto,
                                        ignoreSignature: true,
                                        groupV2Params: groupV2Params)
            }.map(on: .global()) { (downloadedAvatars: GroupV2DownloadedAvatars) -> [GroupV2Change] in
                try GroupsV2Protos.parseChangesFromService(groupChangesProto: groupChangesProto,
                                                           downloadedAvatars: downloadedAvatars,
                                                           groupV2Params: groupV2Params)
            }
        }
    }

    // MARK: - Avatar Downloads

    // Before we can apply snapshots/changes from the service, we
    // need to download all avatars they use.  We can skip downloads
    // in a couple of cases:
    //
    // * We just created the group.
    // * We just updated the group and we're applying those changes.
    private func fetchAllAvatarData(groupProto: GroupsProtoGroup? = nil,
                                    groupChangesProto: GroupsProtoGroupChanges? = nil,
                                    changeActionsProto: GroupsProtoGroupChangeActions? = nil,
                                    justUploadedAvatars: GroupV2DownloadedAvatars? = nil,
                                    ignoreSignature: Bool,
                                    groupV2Params: GroupV2Params) -> Promise<GroupV2DownloadedAvatars> {

        var downloadedAvatars = GroupV2DownloadedAvatars()

        // Creating or updating a group is a multi-step process
        // that can involve uploading an avatar, updating the
        // group on the service, then updating the local database.
        // We can skip downloading an avatar that we just uploaded
        // using justUploadedAvatars.
        if let justUploadedAvatars = justUploadedAvatars {
            downloadedAvatars.merge(justUploadedAvatars)
        }

        return firstly(on: .global()) { () throws -> Void in
            // First step - try to skip downloading the current group avatar.
            let groupId = try self.groupId(forGroupSecretParamsData: groupV2Params.groupSecretParamsData)
            guard let groupThread = (self.databaseStorage.read { transaction in
                return TSGroupThread.fetch(groupId: groupId, transaction: transaction)
            }) else {
                // Thread doesn't exist in database yet.
                return
            }
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                Logger.warn("Unexpected v1 groupModel; possible migration in progress.")
                owsAssertDebug(GroupsV2Migration.isMigratingV2GroupId(groupId))
                return
            }
            // Try to add avatar from group model, if any.
            downloadedAvatars.merge(GroupV2DownloadedAvatars.from(groupModel: groupModel))
        }.then(on: .global()) { () -> Promise<[String]> in
            GroupsV2Protos.collectAvatarUrlPaths(groupProto: groupProto,
                                                 groupChangesProto: groupChangesProto,
                                                 changeActionsProto: changeActionsProto,
                                                 ignoreSignature: ignoreSignature,
                                                 groupV2Params: groupV2Params)
        }.then(on: .global()) { (protoAvatarUrlPaths: [String]) -> Promise<GroupV2DownloadedAvatars> in
            self.fetchAvatarData(avatarUrlPaths: protoAvatarUrlPaths,
                                 downloadedAvatars: downloadedAvatars,
                                 groupV2Params: groupV2Params)
        }
    }

    private func fetchAvatarData(avatarUrlPaths: [String],
                                 downloadedAvatars downloadedAvatarsParam: GroupV2DownloadedAvatars,
                                 groupV2Params: GroupV2Params) -> Promise<GroupV2DownloadedAvatars> {

        var downloadedAvatars = downloadedAvatarsParam

        return firstly(on: .global()) { () -> Promise<[(String, Data)]> in
            let undownloadedAvatarUrlPaths = Set(avatarUrlPaths).subtracting(downloadedAvatars.avatarUrlPaths)
            guard !undownloadedAvatarUrlPaths.isEmpty else {
                return Promise.value([])
            }

            // We need to "populate" any group changes that have a
            // avatar with the avatar data.
            var promises = [Promise<(String, Data)>]()
            for avatarUrlPath in undownloadedAvatarUrlPaths {
                let (downloadPromise, resolver) = Promise<Data>.pending()
                firstly { () -> Promise<Data> in
                    self.fetchAvatarData(avatarUrlPath: avatarUrlPath,
                                         groupV2Params: groupV2Params)
                }.done(on: .global()) { avatarData in
                    resolver.fulfill(avatarData)
                }.catch(on: .global()) { error in
                    if let statusCode = error.httpStatusCode,
                        statusCode == 404 {
                        // Fulfill with empty data if service returns 404 status code.
                        // We don't want the group to be left in an unrecoverable state
                        // if the the avatar is missing from the CDN.
                        resolver.fulfill(Data())
                    }

                    resolver.reject(error)
                }

                let promise = downloadPromise.map(on: .global()) { (avatarData: Data) -> Data in
                    guard avatarData.count > 0 else {
                        owsFailDebug("Empty avatarData.")
                        return avatarData
                    }
                    do {
                        return try groupV2Params.decryptGroupAvatar(avatarData) ?? Data()
                    } catch {
                        owsFailDebug("Invalid avatar data: \(error)")
                        // Empty avatar data will be discarded below.
                        return Data()
                    }
                }.map(on: .global()) { (avatarData: Data) -> (String, Data) in
                    return (avatarUrlPath, avatarData)
                }
                promises.append(promise)
            }
            return when(fulfilled: promises)
        }.map(on: .global()) { (avatars: [(String, Data)]) -> GroupV2DownloadedAvatars in
            for (avatarUrlPath, avatarData) in avatars {
                guard avatarData.count > 0 else {
                    owsFailDebug("Empty avatarData.")
                    continue
                }
                downloadedAvatars.set(avatarData: avatarData, avatarUrlPath: avatarUrlPath)
            }
            return downloadedAvatars
        }
    }

    let avatarDownloadQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "avatarDownloadQueue"
        operationQueue.maxConcurrentOperationCount = 3
        return operationQueue
    }()

    private func fetchAvatarData(avatarUrlPath: String,
                                 groupV2Params: GroupV2Params) -> Promise<Data> {
        let operation = GroupsV2AvatarDownloadOperation(urlPath: avatarUrlPath)
        let promise = operation.promise
        avatarDownloadQueue.addOperation(operation)
        return promise
    }

    // MARK: - Generic Group Change

    public func updateGroupV2(groupModel: TSGroupModelV2,
                              changeSetBlock: @escaping (GroupsV2ChangeSet) -> Void) -> Promise<TSGroupThread> {
        return firstly(on: .global()) { () throws -> GroupsV2ChangeSet in
            let changeSet = GroupsV2ChangeSetImpl(groupId: groupModel.groupId,
                                                  groupSecretParamsData: groupModel.secretParamsData)
            changeSetBlock(changeSet)
            return changeSet
        }.then(on: .global()) { (changeSet: GroupsV2ChangeSet) -> Promise<TSGroupThread> in
            return self.updateExistingGroupOnService(changeSet: changeSet)
        }
    }

    // MARK: - Rotate Profile Key

    private let profileKeyUpdater = GroupsV2ProfileKeyUpdater()

    @objc
    public func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: SDSAnyWriteTransaction) {
        profileKeyUpdater.scheduleAllGroupsV2ForProfileKeyUpdate(transaction: transaction)
    }

    @objc
    public func processProfileKeyUpdates() {
        profileKeyUpdater.processProfileKeyUpdates()
    }

    @objc
    public func updateLocalProfileKeyInGroup(groupId: Data, transaction: SDSAnyWriteTransaction) {
        profileKeyUpdater.updateLocalProfileKeyInGroup(groupId: groupId, transaction: transaction)
    }

    // MARK: - Perform Request

    private typealias AuthCredentialMap = [UInt32: AuthCredential]
    private typealias RequestBuilder = (AuthCredential) throws -> Promise<GroupsV2Request>

    // Represents how we should respond to 403 status codes.
    private enum Behavior403 {
        case fail
        case removeFromGroup
        case fetchGroupUpdates
        case ignore
        case expiredGroupInviteLink
        case localUserIsNotARequestingMember
    }

    // Represents how we should respond to 404 status codes.
    private enum Behavior404 {
        case fail
        case groupDoesNotExistOnService
    }

    private func performServiceRequest(requestBuilder: @escaping RequestBuilder,
                                       groupId: Data?,
                                       behavior403: Behavior403,
                                       behavior404: Behavior404,
                                       remainingRetries: UInt = 3) -> Promise<OWSHTTPResponse> {
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }

        return firstly {
            self.ensureTemporalCredentials(localUuid: localUuid)
        }.then(on: .global()) { (authCredential: AuthCredential) -> Promise<GroupsV2Request> in
            try requestBuilder(authCredential)
        }.then(on: .global()) { (request: GroupsV2Request) -> Promise<OWSHTTPResponse> in
            let (promise, resolver) = Promise<OWSHTTPResponse>.pending()
            firstly {
                self.performServiceRequestAttempt(request: request)
            }.done(on: .global()) { (response: OWSHTTPResponse) in
                resolver.fulfill(response)
            }.catch(on: .global()) { (error: Error) in

                let retryIfPossible = {
                    if remainingRetries > 0 {
                        firstly {
                            self.performServiceRequest(requestBuilder: requestBuilder,
                                                       groupId: groupId,
                                                       behavior403: behavior403,
                                                       behavior404: behavior404,
                                                       remainingRetries: remainingRetries - 1)
                        }.done(on: .global()) { (response: OWSHTTPResponse) in
                            resolver.fulfill(response)
                        }.catch(on: .global()) { (error: Error) in
                            resolver.reject(error)
                        }
                    } else {
                        resolver.reject(error)
                    }
                }

                // Fall through to retry if retry-able,
                // otherwise reject immediately.
                if let statusCode = error.httpStatusCode {
                    switch statusCode {
                    case 401:
                        // Retry auth errors after retrieving new temporal credentials.
                        self.databaseStorage.write { transaction in
                            self.clearTemporalCredentials(transaction: transaction)
                        }
                        retryIfPossible()
                    case 403:
                        // 403 indicates that we are no longer in the group for
                        // many (but not all) group v2 service requests.

                        if let groupId = groupId {
                            switch behavior403 {
                            case .fail:
                                // We should never receive 403 when creating groups.
                                owsFailDebug("Unexpected 403.")
                                break
                            case .ignore:
                                // We can't remove the local user from the group on 403
                                // when fetching change actions.
                                // For example, user might just be joining the group
                                // using an invite OR have just been re-added after leaving.
                                break
                            case .removeFromGroup:
                                // If we receive 403 when trying to fetch group state,
                                // we have left the group, been removed from the group
                                // or had our invite revoked and we should make sure
                                // group state in the database reflects that.
                                self.databaseStorage.write { transaction in
                                    GroupManager.handleNotInGroup(groupId: groupId,
                                                                  transaction: transaction)
                                }
                            case .fetchGroupUpdates:
                                // Service returns 403 if client tries to perform an
                                // update for which it is not authorized (e.g. add a
                                // new member if membership access is admin-only).
                                // The local client can't assume that 403 means they
                                // are not in the group. Therefore we "update group
                                // to latest" to check for and handle that case (see
                                // previous case).
                                self.tryToUpdateGroupToLatest(groupId: groupId)
                            case .expiredGroupInviteLink:
                                owsFailDebug("groupId should not be set in this code path.")
                                resolver.reject(GroupsV2Error.expiredGroupInviteLink)
                                break
                            case .localUserIsNotARequestingMember:
                                owsFailDebug("groupId should not be set in this code path.")
                                resolver.reject(GroupsV2Error.localUserIsNotARequestingMember)
                                break
                            }
                        } else {
                            // We should only receive 403 when groupId is not nil.
                            if behavior403 == .expiredGroupInviteLink {
                                resolver.reject(GroupsV2Error.expiredGroupInviteLink)
                                return
                            } else if behavior403 == .localUserIsNotARequestingMember {
                                resolver.reject(GroupsV2Error.localUserIsNotARequestingMember)
                                return
                            } else {
                                owsFailDebug("Missing groupId.")
                            }
                        }

                        resolver.reject(GroupsV2Error.localUserNotInGroup)
                    case 404:
                        // 404 indicates that the group does not exist on the
                        // service for some (but not all) group v2 service requests.

                        switch behavior404 {
                        case .fail:
                            resolver.reject(error)
                            break
                        case .groupDoesNotExistOnService:
                            Logger.warn("Error: \(error)")
                            resolver.reject(GroupsV2Error.groupDoesNotExistOnService)
                        }
                    case 409:
                        // Group update conflict, retry. When updating group state,
                        // we can often resolve conflicts using the change set.
                        retryIfPossible()
                    default:
                        // Unexpected status code.
                        resolver.reject(error)
                    }
                } else if error.isNetworkFailureOrTimeout {
                    // Retry on network failure.
                    retryIfPossible()
                } else {
                    // Unexpected error.
                    resolver.reject(error)
                }
            }
            return promise
        }
    }

    private func performServiceRequestAttempt(request: GroupsV2Request) -> Promise<OWSHTTPResponse> {

        let urlSession = self.urlSession
        urlSession.failOnError = false

        Logger.info("Making group request: \(request.method) \(request.urlString)")

        return firstly { () -> Promise<OWSHTTPResponse> in
            urlSession.dataTaskPromise(request.urlString,
                                       method: request.method,
                                       headers: request.headers.headers,
                                       body: request.bodyData)
        }.map(on: .global()) { (response: OWSHTTPResponse) -> OWSHTTPResponse in
            let hasValidStatusCode = [200, 206].contains(response.statusCode)
            guard hasValidStatusCode else {
                throw OWSAssertionError("Invalid status code: \(response.statusCode)")
            }

            // NOTE: responseObject may be nil; not all group v2 responses have bodies.
            Logger.info("Request succeeded: \(request.method) \(request.urlString)")

            return response
        }.recover(on: .global()) { (error: Error) -> Promise<OWSHTTPResponse> in
            if error.isNetworkFailureOrTimeout {
                throw error
            }

            if let statusCode = error.httpStatusCode {
                if [401, 403, 404, 409].contains(statusCode) {
                    // These status codes will be handled by performServiceRequest.
                    Logger.warn("Request error: \(error)")
                    throw error
                }
            }

            Logger.warn("Request failed: \(request.method) \(request.urlString)")
            owsFailDebug("Request error: \(error)")
            throw error
        }
    }

    private func tryToUpdateGroupToLatest(groupId: Data) {
        guard let groupThread = (databaseStorage.read { transaction in
            TSGroupThread.fetch(groupId: groupId, transaction: transaction)
        }) else {
            owsFailDebug("Missing group thread.")
            return
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return
        }
        let groupUpdateMode = GroupUpdateMode.upToCurrentRevisionAfterMessageProcessWithThrottling
        firstly {
            self.groupV2Updates.tryToRefreshV2GroupThread(groupId: groupId,
                                                          groupSecretParamsData: groupModelV2.secretParamsData,
                                                          groupUpdateMode: groupUpdateMode)
        }.done { _ in
            Logger.verbose("Update succeeded.")
        }.catch { error in
            if case GroupsV2Error.localUserNotInGroup = error {
                Logger.verbose("Error: \(error)")
            } else {
                owsFailDebugUnlessNetworkFailure(error)
            }
        }
    }

    // MARK: - ProfileKeyCredentials

    public func loadProfileKeyCredentialData(for uuids: [UUID]) -> Promise<ProfileKeyCredentialMap> {

        // 1. Use known credentials, where possible.
        var credentialMap = ProfileKeyCredentialMap()

        var uuidsWithoutCredentials = [UUID]()
        databaseStorage.read { transaction in
            // Skip duplicates.
            for uuid in Set(uuids) {
                do {
                    let address = SignalServiceAddress(uuid: uuid)
                    if let credential = try self.versionedProfiles.profileKeyCredential(for: address,
                                                                                        transaction: transaction) {
                        credentialMap[uuid] = credential
                        continue
                    }
                } catch {
                    owsFailDebug("Error: \(error)")
                }
                uuidsWithoutCredentials.append(uuid)
            }
        }

        // If we already have credentials for all members, no need to fetch.
        guard uuidsWithoutCredentials.count > 0 else {
            return Promise.value(credentialMap)
        }

        // 2. Fetch missing credentials.
        var promises = [Promise<UUID>]()
        for uuid in uuidsWithoutCredentials {
            let address = SignalServiceAddress(uuid: uuid)
            let promise = ProfileFetcherJob.fetchProfilePromise(address: address,
                                                                mainAppOnly: false,
                                                                ignoreThrottling: true,
                                                                fetchType: .versioned)
                .map(on: .global()) { (_: SignalServiceProfile) -> (UUID) in
                    // Ideally we'd pull the credential off of SignalServiceProfile here,
                    // but the credential response needs to be parsed and verified
                    // which requires the VersionedProfileRequest.
                    return uuid
            }
            promises.append(promise)
        }
        return when(fulfilled: promises)
            .map(on: .global()) { _ in
                // Since we've just successfully fetched versioned profiles
                // for all of the UUIDs without credentials, we _should_ be
                // able to load a credential.
                //
                // If we change how credentials are cleared, we'll need to
                // revisit this to avoid races.
                try self.databaseStorage.read { transaction in
                    for uuid in uuids {
                        let address = SignalServiceAddress(uuid: uuid)
                        guard let credential = try self.versionedProfiles.profileKeyCredential(for: address,
                                                                                               transaction: transaction) else {
                                                                                                throw OWSAssertionError("Could not load credential.")
                        }
                        credentialMap[uuid] = credential
                    }
                }

                return credentialMap
        }
    }

    public func hasProfileKeyCredential(for address: SignalServiceAddress,
                                        transaction: SDSAnyReadTransaction) -> Bool {
        do {
            return try self.versionedProfiles.profileKeyCredential(for: address,
                                                                   transaction: transaction) != nil
        } catch {
            owsFailDebug("Error: \(error)")
            return false
        }
    }

    @objc
    public func tryToEnsureProfileKeyCredentialsObjc(for addresses: [SignalServiceAddress]) -> AnyPromise {
        return AnyPromise(tryToEnsureProfileKeyCredentials(for: addresses))
    }

    // When creating (or modifying) a v2 group, we need profile key
    // credentials for all members.  This method tries to find members
    // with known UUIDs who are missing profile key credentials and
    // then tries to get those credentials if possible.
    //
    // This is particularly important when we create a new group, since
    // one of the first things we do is decide whether to create a v1
    // or v2 group.  We have to create a v1 group unless we know the
    // uuid and profile key credential for all members.
    public func tryToEnsureProfileKeyCredentials(for addresses: [SignalServiceAddress]) -> Promise<Void> {

        var uuidsWithoutProfileKeyCredentials = [UUID]()
        databaseStorage.read { transaction in
            for address in addresses {
                guard let uuid = address.uuid else {
                    // If we don't know the user's UUID, there's no point in
                    // trying to get their credential.
                    continue
                }
                guard !self.hasProfileKeyCredential(for: address, transaction: transaction) else {
                    // If we already have the credential, there's no work to do.
                    continue
                }
                uuidsWithoutProfileKeyCredentials.append(uuid)
            }
        }
        guard uuidsWithoutProfileKeyCredentials.count > 0 else {
            return Promise.value(())
        }

        var promises = [Promise<SignalServiceProfile>]()
        for uuid in uuidsWithoutProfileKeyCredentials {
            let address = SignalServiceAddress(uuid: uuid)
            promises.append(ProfileFetcherJob.fetchProfilePromise(address: address,
                                                                  mainAppOnly: false,
                                                                  ignoreThrottling: true,
                                                                  fetchType: .versioned))
        }
        return when(fulfilled: promises).asVoid()
    }

    // MARK: - Auth Credentials

    private let authCredentialStore = SDSKeyValueStore(collection: "GroupsV2Impl.authCredentialStoreStore")

    private func ensureTemporalCredentials(localUuid: UUID) -> Promise<AuthCredential> {
        let redemptionTime = self.daysSinceEpoch

        let authCredentialCacheKey = { (redemptionTime: UInt32) -> String in
            return "\(redemptionTime)"
        }

        return firstly(on: .global()) { () -> AuthCredential? in
            do {
                let data = self.databaseStorage.read { (transaction) -> Data? in
                    let key = authCredentialCacheKey(redemptionTime)
                    return self.authCredentialStore.getData(key, transaction: transaction)
                }
                guard let authCredentialData = data else {
                    return nil
                }
                return try AuthCredential(contents: [UInt8](authCredentialData))
            } catch {
                owsFailDebug("Error retrieving cached auth credential: \(error)")
                return nil
            }
        }.then(on: .global()) { (cachedAuthCredential: AuthCredential?) throws -> Promise<AuthCredential> in
            if let cachedAuthCredential = cachedAuthCredential {
                return Promise.value(cachedAuthCredential)
            }
            return firstly {
                self.retrieveTemporalCredentialsFromService(localUuid: localUuid)
            }.map(on: .global()) { (authCredentialMap: AuthCredentialMap) throws -> AuthCredential in
                self.databaseStorage.write { transaction in
                    // Remove stale auth credentials.
                    self.authCredentialStore.removeAll(transaction: transaction)
                    // Store new auth credentials.
                    for (authTime, authCredential) in authCredentialMap {
                        let key = authCredentialCacheKey(authTime)
                        let value = authCredential.serialize().asData
                        self.authCredentialStore.setData(value, key: key, transaction: transaction)
                    }
                }
                guard let authCredential = authCredentialMap[redemptionTime] else {
                    throw OWSAssertionError("No auth credential for redemption time.")
                }
                return authCredential
            }
        }
    }

    private func clearTemporalCredentials(transaction: SDSAnyWriteTransaction) {
        // Remove stale auth credentials.
        self.authCredentialStore.removeAll(transaction: transaction)
    }

    private func retrieveTemporalCredentialsFromService(localUuid: UUID) -> Promise<AuthCredentialMap> {

        let today = self.daysSinceEpoch
        let todayPlus7 = today + 7
        let request = OWSRequestFactory.groupAuthenticationCredentialRequest(fromRedemptionDays: today,
                                                                             toRedemptionDays: todayPlus7)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { (_: URLSessionDataTask, responseObject: Any?) -> AuthCredentialMap in
            let temporalCredentials = try self.parseCredentialResponse(responseObject: responseObject)
            let localZKGUuid = try localUuid.asZKGUuid()
            let serverPublicParams = try GroupsV2Protos.serverPublicParams()
            let clientZkAuthOperations = ClientZkAuthOperations(serverPublicParams: serverPublicParams)
            var credentialMap = AuthCredentialMap()
            for temporalCredential in temporalCredentials {
                // Verify the credentials.
                let authCredential: AuthCredential = try clientZkAuthOperations.receiveAuthCredential(uuid: localZKGUuid,
                                                                                                      redemptionTime: temporalCredential.redemptionTime,
                                                                                                      authCredentialResponse: temporalCredential.authCredentialResponse)
                credentialMap[temporalCredential.redemptionTime] = authCredential
            }
            return credentialMap
        }
    }

    private struct TemporalCredential {
        let redemptionTime: UInt32
        let authCredentialResponse: AuthCredentialResponse
    }

    private func parseCredentialResponse(responseObject: Any?) throws -> [TemporalCredential] {
        guard let responseObject = responseObject else {
            throw OWSAssertionError("Missing response.")
        }

        guard let params = ParamParser(responseObject: responseObject) else {
            throw OWSAssertionError("invalid response: \(String(describing: responseObject))")
        }
        guard let credentials: [Any] = try params.required(key: "credentials") else {
            throw OWSAssertionError("Missing or invalid credentials.")
        }
        var temporalCredentials = [TemporalCredential]()
        for credential in credentials {
            guard let credentialParser = ParamParser(responseObject: credential) else {
                throw OWSAssertionError("invalid credential: \(String(describing: credential))")
            }
            guard let redemptionTime: UInt32 = try credentialParser.required(key: "redemptionTime") else {
                throw OWSAssertionError("Missing or invalid redemptionTime.")
            }
            let responseData: Data = try credentialParser.requiredBase64EncodedData(key: "credential")
            let response = try AuthCredentialResponse(contents: [UInt8](responseData))

            temporalCredentials.append(TemporalCredential(redemptionTime: redemptionTime, authCredentialResponse: response))
        }
        return temporalCredentials
    }

    // MARK: - Change Set

    public func buildChangeSet(oldGroupModel: TSGroupModelV2,
                               newGroupModel: TSGroupModelV2,
                               oldDMConfiguration: OWSDisappearingMessagesConfiguration,
                               newDMConfiguration: OWSDisappearingMessagesConfiguration,
                               transaction: SDSAnyReadTransaction) throws -> GroupsV2ChangeSet {
        let changeSet = try GroupsV2ChangeSetImpl(for: oldGroupModel)
        try changeSet.buildChangeSet(oldGroupModel: oldGroupModel,
                                     newGroupModel: newGroupModel,
                                     oldDMConfiguration: oldDMConfiguration,
                                     newDMConfiguration: newDMConfiguration,
                                     transaction: transaction)
        return changeSet
    }

    // MARK: - Protos

    public func masterKeyData(forGroupModel groupModel: TSGroupModelV2) throws -> Data {
        return try GroupsV2Protos.masterKeyData(forGroupModel: groupModel)
    }

    public func buildGroupContextV2Proto(groupModel: TSGroupModelV2,
                                         changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2 {
        return try GroupsV2Protos.buildGroupContextV2Proto(groupModel: groupModel, changeActionsProtoData: changeActionsProtoData)
    }

    public func parseAndVerifyChangeActionsProto(_ changeProtoData: Data,
                                                 ignoreSignature: Bool) throws -> GroupsProtoGroupChangeActions {
        return try GroupsV2Protos.parseAndVerifyChangeActionsProto(changeProtoData,
                                                                   ignoreSignature: ignoreSignature)
    }

    // MARK: - Profiles

    public func reuploadLocalProfilePromise() -> Promise<Void> {
        profileManager.reuploadLocalProfilePromise()
    }

    // MARK: - Restore Groups

    public func isGroupKnownToStorageService(groupModel: TSGroupModelV2,
                                             transaction: SDSAnyReadTransaction) -> Bool {
        GroupsV2Impl.isGroupKnownToStorageService(groupModel: groupModel, transaction: transaction)
    }

    public func restoreGroupFromStorageServiceIfNecessary(masterKeyData: Data, transaction: SDSAnyWriteTransaction) {
        GroupsV2Impl.enqueueGroupRestore(masterKeyData: masterKeyData, transaction: transaction)
    }

    // MARK: - Groups Secrets

    public func generateGroupSecretParamsData() throws -> Data {
        let groupSecretParams = try GroupSecretParams.generate()
        let bytes = groupSecretParams.serialize()
        return bytes.asData
    }

    public func groupSecretParamsData(forMasterKeyData masterKeyData: Data) throws -> Data {
        let groupMasterKey = try GroupMasterKey(contents: [UInt8](masterKeyData))
        let groupSecretParams = try GroupSecretParams.deriveFromMasterKey(groupMasterKey: groupMasterKey)
        return groupSecretParams.serialize().asData
    }

    public func groupId(forGroupSecretParamsData groupSecretParamsData: Data) throws -> Data {
        let groupSecretParams = try GroupSecretParams(contents: [UInt8](groupSecretParamsData))
        return try groupSecretParams.getPublicParams().getGroupIdentifier().serialize().asData
    }

    public func v2GroupId(forV1GroupId v1GroupId: Data) -> Data? {
        do {
            return try GroupsV2Migration.v2GroupId(forV1GroupId: v1GroupId)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    public func
        groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo {
        guard let masterKeyData = masterKeyData else {
            throw OWSAssertionError("Missing masterKeyData.")
        }
        let groupSecretParamsData = try self.groupSecretParamsData(forMasterKeyData: masterKeyData)
        let groupId = try self.groupId(forGroupSecretParamsData: groupSecretParamsData)
        guard GroupManager.isValidGroupId(groupId, groupsVersion: .V2) else {
            throw OWSAssertionError("Invalid groupId.")
        }
        return GroupV2ContextInfo(masterKeyData: masterKeyData,
                                  groupSecretParamsData: groupSecretParamsData,
                                  groupId: groupId)
    }

    public func isValidGroupV2MasterKey(_ masterKeyData: Data) -> Bool {
        return masterKeyData.count == GroupMasterKey.SIZE
    }

    // MARK: - Group Links

    public func groupInviteLink(forGroupModelV2 groupModelV2: TSGroupModelV2) throws -> URL {
        guard let inviteLinkPassword = groupModelV2.inviteLinkPassword,
            !inviteLinkPassword.isEmpty else {
                throw OWSAssertionError("Missing password.")
        }
        let masterKey = try GroupsV2Protos.masterKeyData(forGroupModel: groupModelV2)

        var contentsV1Builder = GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1.builder()
        contentsV1Builder.setGroupMasterKey(masterKey)
        contentsV1Builder.setInviteLinkPassword(inviteLinkPassword)

        var builder = GroupsProtoGroupInviteLink.builder()
        builder.setContents(GroupsProtoGroupInviteLinkOneOfContents.contentsV1(try contentsV1Builder.build()))
        let protoData = try builder.buildSerializedData()

        let protoBase64Url = protoData.asBase64Url

        let urlString = "https://signal.group/#\(protoBase64Url)"
        guard let url = URL(string: urlString) else {
            throw OWSAssertionError("Could not construct url.")
        }
        return url
    }

    public func isPossibleGroupInviteLink(_ url: URL) -> Bool {
        let possibleHosts: [String]
        if url.scheme == "https" {
            possibleHosts = ["signal.group"]
        } else if url.scheme == "sgnl" {
            possibleHosts = ["signal.group", "joingroup"]
        } else {
            return false
        }
        guard let host = url.host else {
            return false
        }
        return possibleHosts.contains(host)
    }

    public func parseGroupInviteLink(_ url: URL) -> GroupInviteLinkInfo? {
        guard isPossibleGroupInviteLink(url) else {
            return nil
        }
        guard let protoBase64Url = url.fragment,
            !protoBase64Url.isEmpty else {
            owsFailDebug("Missing encoded data.")
            return nil
        }
        do {
            let protoData = try Data.data(fromBase64Url: protoBase64Url)
            let proto = try GroupsProtoGroupInviteLink(serializedData: protoData)
            guard let protoContents = proto.contents else {
                owsFailDebug("Missing proto contents.")
                return nil
            }
            switch protoContents {
            case .contentsV1(let contentsV1):
                guard let masterKey = contentsV1.groupMasterKey,
                    !masterKey.isEmpty else {
                        owsFailDebug("Invalid masterKey.")
                        return nil
                }
                guard let inviteLinkPassword = contentsV1.inviteLinkPassword,
                    !inviteLinkPassword.isEmpty else {
                        owsFailDebug("Invalid inviteLinkPassword.")
                        return nil
                }
                return GroupInviteLinkInfo(masterKey: masterKey, inviteLinkPassword: inviteLinkPassword)
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private let groupInviteLinkPreviewCache = NSCache<NSData, GroupInviteLinkPreview>()

    private func groupInviteLinkPreviewCacheKey(groupSecretParamsData: Data) -> NSData {
        groupSecretParamsData as NSData
    }

    public func cachedGroupInviteLinkPreview(groupSecretParamsData: Data) -> GroupInviteLinkPreview? {
        let cacheKey = groupInviteLinkPreviewCacheKey(groupSecretParamsData: groupSecretParamsData)
        return groupInviteLinkPreviewCache.object(forKey: cacheKey)
    }

    // inviteLinkPassword is not necessary if we're already a member or have a pending request.
    public func fetchGroupInviteLinkPreview(inviteLinkPassword: Data?,
                                            groupSecretParamsData: Data,
                                            allowCached: Bool) -> Promise<GroupInviteLinkPreview> {
        let cacheKey = groupInviteLinkPreviewCacheKey(groupSecretParamsData: groupSecretParamsData)

        if allowCached,
            let groupInviteLinkPreview = groupInviteLinkPreviewCache.object(forKey: cacheKey) {
            return Promise.value(groupInviteLinkPreview)
        }

        let groupV2Params: GroupV2Params
        do {
            groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
        } catch {
            return Promise(error: error)
        }

        let requestBuilder: RequestBuilder = { (authCredential) in
            firstly(on: .global()) { () -> GroupsV2Request in
                try StorageService.buildFetchGroupInviteLinkPreviewRequest(inviteLinkPassword: inviteLinkPassword,
                                                                           groupV2Params: groupV2Params,
                                                                           authCredential: authCredential)
            }
        }

        return firstly(on: .global()) { () -> Promise<OWSHTTPResponse> in
            let behavior403: Behavior403 = (inviteLinkPassword != nil
                ? .expiredGroupInviteLink
                : .localUserIsNotARequestingMember)
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: nil,
                                              behavior403: behavior403,
                                              behavior404: .fail)
        }.map(on: .global()) { (response: OWSHTTPResponse) -> GroupInviteLinkPreview in
            guard let protoData = response.responseData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            let groupInviteLinkPreview = try GroupsV2Protos.parseGroupInviteLinkPreview(protoData, groupV2Params: groupV2Params)

            self.groupInviteLinkPreviewCache.setObject(groupInviteLinkPreview, forKey: cacheKey)

            self.updatePlaceholderGroupModelUsingInviteLinkPreview(groupSecretParamsData: groupSecretParamsData,
                                                                   isLocalUserRequestingMember: groupInviteLinkPreview.isLocalUserRequestingMember)

            return groupInviteLinkPreview
        }.recover { (error: Error) -> Promise<GroupInviteLinkPreview> in
            if case GroupsV2Error.localUserIsNotARequestingMember = error {
                self.updatePlaceholderGroupModelUsingInviteLinkPreview(groupSecretParamsData: groupSecretParamsData,
                                                                       isLocalUserRequestingMember: false)
            }
            throw error
        }
    }

    public func fetchGroupInviteLinkAvatar(avatarUrlPath: String,
                                           groupSecretParamsData: Data) -> Promise<Data> {
        let groupV2Params: GroupV2Params
        do {
            groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
        } catch {
            return Promise(error: error)
        }

        return firstly(on: .global()) { () -> Promise<GroupV2DownloadedAvatars> in
            self.fetchAvatarData(avatarUrlPaths: [avatarUrlPath],
                                 downloadedAvatars: GroupV2DownloadedAvatars(),
                                 groupV2Params: groupV2Params)
        }.map(on: .global()) { (downloadedAvatars: GroupV2DownloadedAvatars) -> Data in
            try downloadedAvatars.avatarData(for: avatarUrlPath)
        }
    }

    public func joinGroupViaInviteLink(groupId: Data,
                                       groupSecretParamsData: Data,
                                       inviteLinkPassword: Data,
                                       groupInviteLinkPreview: GroupInviteLinkPreview,
                                       avatarData: Data?) -> Promise<TSGroupThread> {

        let groupV2Params: GroupV2Params
        do {
            groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
        } catch {
            return Promise(error: error)
        }

        return Promises.performWithImmediateRetry { () -> Promise<TSGroupThread> in
            self.joinGroupViaInviteLinkAttempt(groupId: groupId,
                                               inviteLinkPassword: inviteLinkPassword,
                                               groupV2Params: groupV2Params,
                                               groupInviteLinkPreview: groupInviteLinkPreview,
                                               avatarData: avatarData)
        }
    }

    private func joinGroupViaInviteLinkAttempt(groupId: Data,
                                               inviteLinkPassword: Data,
                                               groupV2Params: GroupV2Params,
                                               groupInviteLinkPreview: GroupInviteLinkPreview,
                                               avatarData: Data?) -> Promise<TSGroupThread> {

        // There are many edge cases around joining groups via invite links.
        //
        // * We might have previously been a member or not.
        // * We might previously have requested to join and been denied.
        // * The group might or might not already exist in the database.
        // * We might already be a full member.
        // * We might already have a pending invite (in which case we should
        //   accept that invite rather than request to join).
        // * The invite link may have been rescinded.
        return firstly(on: .global()) { () -> Promise<TSGroupThread> in
            // Check if...
            //
            // * We're already in the group.
            // * We already have a pending invite. If so, use it.
            //
            // Note: this will typically fail.
            self.joinGroupViaInviteLinkUsingAlternateMeans(groupId: groupId,
                                                           inviteLinkPassword: inviteLinkPassword,
                                                           groupV2Params: groupV2Params)
        }.recover(on: .global()) { (error: Error) -> Promise<TSGroupThread> in
            guard !IsNetworkConnectivityFailure(error) else {
                throw error
            }
            Logger.warn("Error: \(error)")
            return self.joinGroupViaInviteLinkUsingPatch(groupId: groupId,
                                                         inviteLinkPassword: inviteLinkPassword,
                                                         groupV2Params: groupV2Params,
                                                         groupInviteLinkPreview: groupInviteLinkPreview,
                                                         avatarData: avatarData)
        }
    }

    private func joinGroupViaInviteLinkUsingAlternateMeans(groupId: Data,
                                                           inviteLinkPassword: Data,
                                                           groupV2Params: GroupV2Params) -> Promise<TSGroupThread> {

        return firstly(on: .global()) { () -> Promise<TSGroupThread> in
            // First try to fetch latest group state from service.
            // This will fail for users trying to join via group link
            // who are not yet in the group.
            self.groupV2Updates.tryToRefreshV2GroupUpToCurrentRevisionImmediately(groupId: groupId,
                                                                                  groupSecretParamsData: groupV2Params.groupSecretParamsData)
        }.then(on: .global()) { (groupThread: TSGroupThread) -> Promise<TSGroupThread> in
            guard let localUuid = self.tsAccountManager.localUuid else {
                throw OWSAssertionError("Missing localUuid.")
            }
            guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid group model.")
            }
            let groupMembership = groupModelV2.groupMembership
            if groupMembership.isFullMember(localUuid) ||
                groupMembership.isRequestingMember(localUuid) {
                // We're already in the group.
                return Promise.value(groupThread)
            } else if groupMembership.isInvitedMember(localUuid) {
                // We're already an invited member; try to join by accepting the invite.
                // That will make us a full member; requesting to join via
                // the invite link might make us a requesting member.
                return self.updateGroupV2(groupModel: groupModelV2) { groupChangeSet in
                    groupChangeSet.promoteInvitedMember(localUuid)
                }
            } else {
                throw GroupsV2Error.localUserNotInGroup
            }
        }
    }

    private func joinGroupViaInviteLinkUsingPatch(groupId: Data,
                                                  inviteLinkPassword: Data,
                                                  groupV2Params: GroupV2Params,
                                                  groupInviteLinkPreview: GroupInviteLinkPreview,
                                                  avatarData: Data?) -> Promise<TSGroupThread> {

        let revisionForPlaceholderModel = AtomicOptional<UInt32>(nil)

        return firstly(on: .global()) { () -> Promise<OWSHTTPResponse> in
            let requestBuilder: RequestBuilder = { (authCredential) in
                return firstly { () -> Promise<GroupsProtoGroupChangeActions> in
                    self.buildChangeActionsProtoToJoinGroupLink(groupId: groupId,
                                                                inviteLinkPassword: inviteLinkPassword,
                                                                groupV2Params: groupV2Params,
                                                                revisionForPlaceholderModel: revisionForPlaceholderModel)
                }.map(on: .global()) { (groupChangeProto: GroupsProtoGroupChangeActions) -> GroupsV2Request in
                    try StorageService.buildUpdateGroupRequest(groupChangeProto: groupChangeProto,
                                                               groupV2Params: groupV2Params,
                                                               authCredential: authCredential,
                                                               groupInviteLinkPassword: inviteLinkPassword)
                }
            }

            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupId,
                                              behavior403: .expiredGroupInviteLink,
                                              behavior404: .fail)
        }.then(on: .global()) { (response: OWSHTTPResponse) -> Promise<TSGroupThread> in
            guard let changeActionsProtoData = response.responseData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            // The PATCH request that adds us to the group (as a full or requesting member)
            // only return the "change actions" proto data, but not a full snapshot
            // so we need to seperately GET the latest group state and update the database.
            //
            // Download and update database with the group state.
            return firstly {
                self.groupV2Updates.tryToRefreshV2GroupUpToCurrentRevisionImmediately(groupId: groupId,
                                                                                      groupSecretParamsData: groupV2Params.groupSecretParamsData)
            }.recover(on: .global()) { (_: Error) -> Promise<TSGroupThread> in
                throw GroupsV2Error.requestingMemberCantLoadGroupState
            }.then(on: .global()) { _ -> Promise<TSGroupThread> in
                guard let groupThread = (self.databaseStorage.read { transaction in
                    TSGroupThread.fetch(groupId: groupId, transaction: transaction)
                }) else {
                    throw OWSAssertionError("Missing group thread.")
                }

                return firstly {
                    GroupManager.sendGroupUpdateMessage(thread: groupThread,
                                                        changeActionsProtoData: changeActionsProtoData)
                }.map(on: .global()) { (_) -> TSGroupThread in
                    return groupThread
                }
            }
        }.recover(on: .global()) { (error: Error) -> Promise<TSGroupThread> in
            // We create a placeholder in a couple of different scenarios:
            //
            // * We successfully request to join a group via group invite link.
            //   Afterward we do not have access to group state on the service.
            // * The GroupInviteLinkPreview indicates that we are already a
            //   requesting member of the group but the group does not yet exist
            //   in the database.
            var shouldCreatePlaceholder = false
            if case GroupsV2Error.localUserIsAlreadyRequestingMember = error {
                shouldCreatePlaceholder = true
            } else if case GroupsV2Error.requestingMemberCantLoadGroupState = error {
                shouldCreatePlaceholder = true
            }
            guard shouldCreatePlaceholder else {
                throw error
            }
            return firstly(on: .global()) { () throws -> TSGroupThread in
                try self.createPlaceholderGroupForJoinRequest(groupId: groupId,
                                                              inviteLinkPassword: inviteLinkPassword,
                                                              groupV2Params: groupV2Params,
                                                              groupInviteLinkPreview: groupInviteLinkPreview,
                                                              avatarData: avatarData,
                                                              revisionForPlaceholderModel: revisionForPlaceholderModel)
            }.then(on: .global()) { (groupThread: TSGroupThread) -> Promise<TSGroupThread> in
                let isPlaceholderModel: Bool
                if let groupModel = groupThread.groupModel as? TSGroupModelV2 {
                    isPlaceholderModel = groupModel.isPlaceholderModel
                } else {
                    isPlaceholderModel = false
                }
                guard !isPlaceholderModel else {
                    // There's no point in sending a group update for a placeholder
                    // group, since we don't know who to send it to.
                    return Promise.value(groupThread)
                }

                return firstly {
                    GroupManager.sendGroupUpdateMessage(thread: groupThread, changeActionsProtoData: nil)
                }.map(on: .global()) { (_) -> TSGroupThread in
                    return groupThread
                }
            }
        }
    }

    private func createPlaceholderGroupForJoinRequest(groupId: Data,
                                                      inviteLinkPassword: Data,
                                                      groupV2Params: GroupV2Params,
                                                      groupInviteLinkPreview: GroupInviteLinkPreview,
                                                      avatarData: Data?,
                                                      revisionForPlaceholderModel: AtomicOptional<UInt32>) throws -> TSGroupThread {
        // We might be creating a placeholder for a revision that we just
        // created or for one we learned about from a GroupInviteLinkPreview.
        guard let revision = revisionForPlaceholderModel.get() else {
            throw OWSAssertionError("Missing revisionForPlaceholderModel.")
        }
        guard let localUuid = self.tsAccountManager.localUuid else {
            throw OWSAssertionError("Missing localUuid.")
        }
        return try databaseStorage.write { (transaction) throws -> TSGroupThread in

            TSGroupThread.ensureGroupIdMapping(forGroupId: groupId,
                                               transaction: transaction)

            if let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
                // The group already existing in the database; make sure
                // that we are a requesting member.
                guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid groupModel.")
                }
                let oldGroupMembership = oldGroupModel.groupMembership
                if oldGroupModel.revision >= revision &&
                    oldGroupMembership.isRequestingMember(localUuid) {
                    // No need to update database, group state is already acceptable.
                    return groupThread
                }
                var builder = oldGroupModel.asBuilder
                builder.isPlaceholderModel = true
                builder.groupV2Revision = max(revision, oldGroupModel.revision)
                var membershipBuilder = oldGroupMembership.asBuilder
                membershipBuilder.remove(localUuid)
                membershipBuilder.addRequestingMember(localUuid)
                builder.groupMembership = membershipBuilder.build()
                let newGroupModel = try builder.build(transaction: transaction)

                groupThread.update(with: newGroupModel, transaction: transaction)

                let dmConfiguration = groupThread.disappearingMessagesConfiguration(with: transaction)
                let disappearingMessageToken = dmConfiguration.asToken
                let localAddress = SignalServiceAddress(uuid: localUuid)
                GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                          oldGroupModel: oldGroupModel,
                                                          newGroupModel: newGroupModel,
                                                          oldDisappearingMessageToken: disappearingMessageToken,
                                                          newDisappearingMessageToken: disappearingMessageToken,
                                                          groupUpdateSourceAddress: localAddress,
                                                          transaction: transaction)

                return groupThread
            } else {
                // Create a placeholder group.
                var builder = TSGroupModelBuilder()
                builder.groupId = groupId
                builder.name = groupInviteLinkPreview.title
                builder.groupAccess = GroupAccess(members: GroupAccess.defaultForV2.members,
                                                  attributes: GroupAccess.defaultForV2.attributes,
                                                  addFromInviteLink: groupInviteLinkPreview.addFromInviteLinkAccess)
                builder.groupsVersion = .V2
                builder.groupV2Revision = revision
                builder.groupSecretParamsData = groupV2Params.groupSecretParamsData
                builder.inviteLinkPassword = inviteLinkPassword
                builder.isPlaceholderModel = true

                // The "group invite link" UI might not have downloaded
                // the avatar. That's fine; this is just a placeholder
                // model.
                if let avatarData = avatarData,
                    let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath {
                    builder.avatarData = avatarData
                    builder.avatarUrlPath = avatarUrlPath
                }

                var membershipBuilder = GroupMembership.Builder()
                membershipBuilder.addRequestingMember(localUuid)
                builder.groupMembership = membershipBuilder.build()

                let groupModel = try builder.build(transaction: transaction)
                let groupThread = TSGroupThread(groupModelPrivate: groupModel,
                                                transaction: transaction)
                groupThread.anyInsert(transaction: transaction)

                let dmConfiguration = groupThread.disappearingMessagesConfiguration(with: transaction)
                let disappearingMessageToken = dmConfiguration.asToken
                let localAddress = SignalServiceAddress(uuid: localUuid)
                GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                          oldGroupModel: nil,
                                                          newGroupModel: groupModel,
                                                          oldDisappearingMessageToken: nil,
                                                          newDisappearingMessageToken: disappearingMessageToken,
                                                          groupUpdateSourceAddress: localAddress,
                                                          transaction: transaction)

                return groupThread
            }
        }
    }

    private func buildChangeActionsProtoToJoinGroupLink(groupId: Data,
                                                        inviteLinkPassword: Data,
                                                        groupV2Params: GroupV2Params,
                                                        revisionForPlaceholderModel: AtomicOptional<UInt32>) -> Promise<GroupsProtoGroupChangeActions> {

        guard let localUuid = self.tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }

        return firstly(on: .global()) { () -> Promise<GroupInviteLinkPreview> in
            // We re-fetch the GroupInviteLinkPreview with every attempt in order to get the latest:
            //
            // * revision
            // * addFromInviteLinkAccess
            // * local user's request status.
            self.fetchGroupInviteLinkPreview(inviteLinkPassword: inviteLinkPassword,
                                             groupSecretParamsData: groupV2Params.groupSecretParamsData,
                                             allowCached: false)
        }.then(on: .global()) { (groupInviteLinkPreview: GroupInviteLinkPreview) -> Promise<(GroupInviteLinkPreview, ProfileKeyCredential)> in

            guard !groupInviteLinkPreview.isLocalUserRequestingMember else {
                // Use the current revision when creating a placeholder group.
                revisionForPlaceholderModel.set(groupInviteLinkPreview.revision)
                throw GroupsV2Error.localUserIsAlreadyRequestingMember
            }

            return firstly(on: .global()) { () -> Promise<ProfileKeyCredentialMap> in
                self.loadProfileKeyCredentialData(for: [localUuid])
            }.map(on: .global()) { (profileKeyCredentialMap: ProfileKeyCredentialMap) -> (GroupInviteLinkPreview, ProfileKeyCredential) in
                guard let localProfileKeyCredential = profileKeyCredentialMap[localUuid] else {
                    throw OWSAssertionError("Missing localProfileKeyCredential.")
                }
                return (groupInviteLinkPreview, localProfileKeyCredential)
            }
        }.map(on: .global()) { (groupInviteLinkPreview: GroupInviteLinkPreview, localProfileKeyCredential: ProfileKeyCredential) -> GroupsProtoGroupChangeActions in
            var actionsBuilder = GroupsProtoGroupChangeActions.builder()

            let oldRevision = groupInviteLinkPreview.revision
            let newRevision = oldRevision + 1
            Logger.verbose("Revision: \(oldRevision) -> \(newRevision)")
            actionsBuilder.setRevision(newRevision)

            // Use the new revision when creating a placeholder group.
            revisionForPlaceholderModel.set(newRevision)

            switch groupInviteLinkPreview.addFromInviteLinkAccess {
            case .any:
                let role = TSGroupMemberRole.`normal`
                var actionBuilder = GroupsProtoGroupChangeActionsAddMemberAction.builder()
                actionBuilder.setAdded(try GroupsV2Protos.buildMemberProto(profileKeyCredential: localProfileKeyCredential,
                                                                           role: role.asProtoRole,
                                                                           groupV2Params: groupV2Params))
                actionsBuilder.addAddMembers(try actionBuilder.build())
            case .administrator:
                var actionBuilder = GroupsProtoGroupChangeActionsAddRequestingMemberAction.builder()
                actionBuilder.setAdded(try GroupsV2Protos.buildRequestingMemberProto(profileKeyCredential: localProfileKeyCredential,
                                                                                     groupV2Params: groupV2Params))
                actionsBuilder.addAddRequestingMembers(try actionBuilder.build())
            default:
                throw OWSAssertionError("Invalid addFromInviteLinkAccess.")
            }

            return try actionsBuilder.build()
        }
    }

    public func cancelMemberRequests(groupModel: TSGroupModelV2) -> Promise<TSGroupThread> {
        let groupV2Params: GroupV2Params
        do {
            groupV2Params = try groupModel.groupV2Params()
        } catch {
            return Promise<TSGroupThread>(error: error)
        }

        return firstly(on: .global()) { () -> Promise<UInt32> in
            self.cancelMemberRequestsUsingPatch(groupId: groupModel.groupId, groupV2Params: groupV2Params)
        }.map(on: .global()) { (newRevision: UInt32) -> TSGroupThread in
            try self.updateGroupRemovingMemberRequest(groupId: groupModel.groupId, newRevision: newRevision)
        }.recover(on: .global()) { (error: Error) -> Promise<TSGroupThread> in
            if case GroupsV2Error.localUserIsNotARequestingMember = error {
                // We don't need to cancel our pending member request; there is none.
                // Update the model to reflect that.
                let groupThread = try self.updateGroupRemovingMemberRequest(groupId: groupModel.groupId,
                                                                            newRevision: nil)
                return Promise.value(groupThread)
            } else {
                throw error
            }
        }
    }

    private func updateGroupRemovingMemberRequest(groupId: Data,
                                                  newRevision proposedRevision: UInt32?) throws -> TSGroupThread {

        guard let localUuid = self.tsAccountManager.localUuid else {
            throw OWSAssertionError("Missing localUuid.")
        }

        return try databaseStorage.write { transaction -> TSGroupThread in
            TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing groupThread.")
            }
            // The group already existing in the database; make sure
            // that we are a requesting member.
            guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid groupModel.")
            }
            let oldGroupMembership = oldGroupModel.groupMembership
            var newRevision = oldGroupModel.revision + 1
            if let proposedRevision = proposedRevision {
                if oldGroupModel.revision >= proposedRevision {
                    // No need to update database, group state is already acceptable.
                    owsAssertDebug(!oldGroupMembership.isMemberOfAnyKind(localUuid))
                    return groupThread
                }
                newRevision = max(newRevision, proposedRevision)
            }

            var builder = oldGroupModel.asBuilder
            builder.isPlaceholderModel = true
            builder.groupV2Revision = newRevision

            var membershipBuilder = oldGroupMembership.asBuilder
            membershipBuilder.remove(localUuid)
            builder.groupMembership = membershipBuilder.build()
            let newGroupModel = try builder.build(transaction: transaction)

            groupThread.update(with: newGroupModel, transaction: transaction)

            let dmConfiguration = groupThread.disappearingMessagesConfiguration(with: transaction)
            let disappearingMessageToken = dmConfiguration.asToken
            let localAddress = SignalServiceAddress(uuid: localUuid)
            GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                      oldGroupModel: oldGroupModel,
                                                      newGroupModel: newGroupModel,
                                                      oldDisappearingMessageToken: disappearingMessageToken,
                                                      newDisappearingMessageToken: disappearingMessageToken,
                                                      groupUpdateSourceAddress: localAddress,
                                                      transaction: transaction)

            return groupThread
        }
    }

    private func cancelMemberRequestsUsingPatch(groupId: Data, groupV2Params: GroupV2Params) -> Promise<UInt32> {

        let revisionForPlaceholderModel = AtomicOptional<UInt32>(nil)

        // We re-fetch the GroupInviteLinkPreview with every attempt in order to get the latest:
        //
        // * revision
        // * addFromInviteLinkAccess
        // * local user's request status.
        return firstly {
            self.fetchGroupInviteLinkPreview(inviteLinkPassword: nil,
                                             groupSecretParamsData: groupV2Params.groupSecretParamsData,
                                             allowCached: false)
        }.then(on: .global()) { (groupInviteLinkPreview: GroupInviteLinkPreview) -> Promise<OWSHTTPResponse> in
            let requestBuilder: RequestBuilder = { (authCredential) in
                return firstly { () -> Promise<GroupsProtoGroupChangeActions> in
                    self.buildChangeActionsProtoToCancelMemberRequest(groupInviteLinkPreview: groupInviteLinkPreview,
                                                                      groupV2Params: groupV2Params,
                                                                      revisionForPlaceholderModel: revisionForPlaceholderModel)
                }.map(on: .global()) { (groupChangeProto: GroupsProtoGroupChangeActions) -> GroupsV2Request in
                    try StorageService.buildUpdateGroupRequest(groupChangeProto: groupChangeProto,
                                                               groupV2Params: groupV2Params,
                                                               authCredential: authCredential,
                                                               groupInviteLinkPassword: nil)
                }
            }

            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupId,
                                              behavior403: .fail,
                                              behavior404: .fail)
        }.map(on: .global()) { _ -> UInt32 in
            guard let revision = revisionForPlaceholderModel.get() else {
                throw OWSAssertionError("Missing revisionForPlaceholderModel.")
            }
            return revision
        }
    }

    private func buildChangeActionsProtoToCancelMemberRequest(groupInviteLinkPreview: GroupInviteLinkPreview,
                                                              groupV2Params: GroupV2Params,
                                                              revisionForPlaceholderModel: AtomicOptional<UInt32>) -> Promise<GroupsProtoGroupChangeActions> {

        return firstly(on: .global()) { () -> GroupsProtoGroupChangeActions in
            guard let localUuid = self.tsAccountManager.localUuid else {
                throw OWSAssertionError("Missing localUuid.")
            }
            let oldRevision = groupInviteLinkPreview.revision
            let newRevision = oldRevision + 1
            revisionForPlaceholderModel.set(newRevision)

            var actionsBuilder = GroupsProtoGroupChangeActions.builder()
            actionsBuilder.setRevision(newRevision)

            var actionBuilder = GroupsProtoGroupChangeActionsDeleteRequestingMemberAction.builder()
            let userId = try groupV2Params.userId(forUuid: localUuid)
            actionBuilder.setDeletedUserID(userId)
            actionsBuilder.addDeleteRequestingMembers(try actionBuilder.build())

            return try actionsBuilder.build()
        }
    }

    public func tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(groupModel: TSGroupModelV2) {
        guard groupModel.isPlaceholderModel else {
            owsFailDebug("Invalid group model.")
            return
        }

        firstly { () -> Promise<GroupInviteLinkPreview> in
            let groupV2Params = try groupModel.groupV2Params()
            return self.fetchGroupInviteLinkPreview(inviteLinkPassword: nil,
                                                    groupSecretParamsData: groupV2Params.groupSecretParamsData,
                                                    allowCached: false)
        }.catch { (error: Error) -> Void in
            if case GroupsV2Error.localUserIsNotARequestingMember = error {
                // Expected if our request has been cancelled.
                Logger.verbose("Error: \(error)")
                return
            }
            owsFailDebug("Error: \(error)")
        }
    }

    private func updatePlaceholderGroupModelUsingInviteLinkPreview(groupSecretParamsData: Data,
                                                                   isLocalUserRequestingMember: Bool) {

        firstly(on: .global()) {
            let groupId = try self.groupId(forGroupSecretParamsData: groupSecretParamsData)
            try self.databaseStorage.write { transaction in
                guard let localUuid = self.tsAccountManager.localUuid else {
                    throw OWSAssertionError("Missing localUuid.")
                }
                TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)
                guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                    // Thread not yet in database.
                    return
                }
                guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid groupModel.")
                }
                guard oldGroupModel.isPlaceholderModel else {
                    // Not a placeholder model; no need to update.
                    return
                }
                guard isLocalUserRequestingMember != groupThread.isLocalUserRequestingMember else {
                    // Nothing to change.
                    return
                }
                let oldGroupMembership = oldGroupModel.groupMembership
                var builder = oldGroupModel.asBuilder

                var membershipBuilder = oldGroupMembership.asBuilder
                membershipBuilder.remove(localUuid)
                if isLocalUserRequestingMember {
                    membershipBuilder.addRequestingMember(localUuid)
                }
                builder.groupMembership = membershipBuilder.build()
                let newGroupModel = try builder.build(transaction: transaction)

                groupThread.update(with: newGroupModel, transaction: transaction)

                let dmConfiguration = groupThread.disappearingMessagesConfiguration(with: transaction)
                let disappearingMessageToken = dmConfiguration.asToken
                // groupUpdateSourceAddress is nil; we don't know who did the update.
                GroupManager.insertGroupUpdateInfoMessage(groupThread: groupThread,
                                                          oldGroupModel: oldGroupModel,
                                                          newGroupModel: newGroupModel,
                                                          oldDisappearingMessageToken: disappearingMessageToken,
                                                          newDisappearingMessageToken: disappearingMessageToken,
                                                          groupUpdateSourceAddress: nil,
                                                          transaction: transaction)
            }
        }.catch { (error: Error) in
            owsFailDebug("Error: \(error)")
        }
    }

    public func fetchGroupExternalCredentials(groupModel: TSGroupModelV2) throws -> Promise<GroupsProtoGroupExternalCredential> {
        let requestBuilder: RequestBuilder = { authCredential in
            firstly(on: .global()) { () -> GroupsV2Request in
                try StorageService.buildFetchGroupExternalCredentials(groupV2Params: try groupModel.groupV2Params(),
                                                                      authCredential: authCredential)
            }
        }

        return firstly { () -> Promise<OWSHTTPResponse> in
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupModel.groupId,
                                              behavior403: .fetchGroupUpdates,
                                              behavior404: .fail)
        }.map(on: .global()) { (response: OWSHTTPResponse) -> GroupsProtoGroupExternalCredential in
            guard let groupProtoData = response.responseData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            return try GroupsProtoGroupExternalCredential(serializedData: groupProtoData)
        }
    }

    // MARK: - Migration

    public func updateAlreadyMigratedGroupIfNecessary(v2GroupId: Data) -> Promise<Void> {
        GroupsV2Migration.updateAlreadyMigratedGroupIfNecessary(v2GroupId: v2GroupId)
    }

    // MARK: - Utils

    private var daysSinceEpoch: UInt32 {
        let msSinceEpoch = NSDate.ows_millisecondTimeStamp()
        let daysSinceEpoch = UInt32(msSinceEpoch / kDayInMs)
        return daysSinceEpoch
    }

    private func uuids(for addresses: [SignalServiceAddress]) -> [UUID] {
        var uuids = [UUID]()
        for address in addresses {
            guard let uuid = address.uuid else {
                owsFailDebug("Missing UUID.")
                continue
            }
            uuids.append(uuid)
        }
        return uuids
    }
}
