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
        return TSAccountManager.sharedInstance()
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

    private var sessionManager: AFHTTPSessionManager {
        return OWSSignalService.sharedInstance().storageServiceSessionManager
    }

    private var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private var groupV2Updates: GroupV2UpdatesSwift {
        return SSKEnvironment.shared.groupV2Updates as! GroupV2UpdatesSwift
    }

    private var contactsUpdater: ContactsUpdater {
        return SSKEnvironment.shared.contactsUpdater
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
                RemoteConfig.versionedProfileUpdate,
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
            if RemoteConfig.versionedProfileUpdate,
                self.tsAccountManager.isRegisteredAndReady {
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

    @objc
    public func createNewGroupOnServiceObjc(groupModel: TSGroupModelV2) -> AnyPromise {
        return AnyPromise(createNewGroupOnService(groupModel: groupModel))
    }

    public func createNewGroupOnService(groupModel: TSGroupModelV2) -> Promise<Void> {
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise<Void>(error: OWSAssertionError("Missing localUuid."))
        }
        let groupV2Params: GroupV2Params
        do {
            groupV2Params = try groupModel.groupV2Params()
        } catch {
            return Promise<Void>(error: error)
        }

        let requestBuilder: RequestBuilder = { (authCredential, sessionManager) in
            return DispatchQueue.global().async(.promise) { () -> [UUID] in
                // Gather the UUIDs for all members.
                // We cannot gather profile key credentials for pending members, by definition.
                let uuids = self.uuids(for: groupModel.groupMembers)
                guard uuids.contains(localUuid) else {
                    throw OWSAssertionError("localUuid is not a member.")
                }
                return uuids
            }.then(on: DispatchQueue.global()) { (uuids: [UUID]) -> Promise<ProfileKeyCredentialMap> in
                // Gather the profile key credentials for all members.
                let allUuids = uuids + [localUuid]
                return self.loadProfileKeyCredentialData(for: allUuids)
            }.map(on: DispatchQueue.global()) { (profileKeyCredentialMap: ProfileKeyCredentialMap) -> NSURLRequest in
                let groupProto = try GroupsV2Protos.buildNewGroupProto(groupModel: groupModel,
                                                                       groupV2Params: groupV2Params,
                                                                       profileKeyCredentialMap: profileKeyCredentialMap,
                                                                       localUuid: localUuid)
                return try StorageService.buildNewGroupRequest(groupProto: groupProto,
                                                               groupV2Params: groupV2Params,
                                                               sessionManager: sessionManager,
                                                               authCredential: authCredential)
            }
        }

        return performServiceRequest(requestBuilder: requestBuilder,
                                     groupId: nil,
                                     behavior403: .fail).asVoid()
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
        guard RemoteConfig.groupsV2GoodCitizen else {
            return Promise(error: GroupsV2Error.gv2NotEnabled)
        }

        let groupId = changeSet.groupId
        let groupSecretParamsData = changeSet.groupSecretParamsData
        let groupV2Params: GroupV2Params
        do {
            groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
        } catch {
            return Promise(error: error)
        }

        var isFirstAttempt = true
        let requestBuilder: RequestBuilder = { (authCredential, sessionManager) in
            return firstly { () -> Promise<Void> in
                if isFirstAttempt {
                    isFirstAttempt = false
                    return Promise.value(())
                }
                return self.groupV2Updates.tryToRefreshV2GroupUpToCurrentRevisionImmediately(groupId: groupId,
                                                                                             groupSecretParamsData: groupSecretParamsData)
            }.map(on: DispatchQueue.global()) { _ throws -> (thread: TSGroupThread, disappearingMessageToken: DisappearingMessageToken) in
                return try self.databaseStorage.read { transaction in
                    guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                        throw OWSAssertionError("Thread does not exist.")
                    }
                    let dmConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: groupThread, transaction: transaction)
                    return (groupThread, dmConfiguration.asToken)
                }
            }.then(on: DispatchQueue.global()) { (groupThread: TSGroupThread, disappearingMessageToken: DisappearingMessageToken) -> Promise<GroupsProtoGroupChangeActions> in
                guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid group model.")
                }
                return changeSet.buildGroupChangeProto(currentGroupModel: groupModel,
                                                       currentDisappearingMessageToken: disappearingMessageToken)
            }.map(on: DispatchQueue.global()) { (groupChangeProto: GroupsProtoGroupChangeActions) -> NSURLRequest in
                return try StorageService.buildUpdateGroupRequest(groupChangeProto: groupChangeProto,
                                                                  groupV2Params: groupV2Params,
                                                                  sessionManager: sessionManager,
                                                                  authCredential: authCredential)
            }
        }

        return firstly {
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupId,
                                              behavior403: .fetchGroupUpdates)
        }.then(on: DispatchQueue.global()) { (response: ServiceResponse) -> Promise<UpdatedV2Group> in

            guard let changeActionsProtoData = response.responseObject as? Data else {
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
            }.map(on: DispatchQueue.global()) { (groupThread: TSGroupThread) -> UpdatedV2Group in
                return UpdatedV2Group(groupThread: groupThread, changeActionsProtoData: changeActionsProtoData)
            }
        }.then(on: DispatchQueue.global()) { (updatedV2Group: UpdatedV2Group) -> Promise<TSGroupThread> in

            GroupManager.updateProfileWhitelist(withGroupThread: updatedV2Group.groupThread)

            return GroupManager.sendGroupUpdateMessage(thread: updatedV2Group.groupThread,
                                                       changeActionsProtoData: updatedV2Group.changeActionsProtoData)
                .map(on: DispatchQueue.global()) { (_) -> TSGroupThread in
                    return updatedV2Group.groupThread
            }
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
        }.map(on: DispatchQueue.global()) { (downloadedAvatars: GroupV2DownloadedAvatars) -> TSGroupThread in
            return try self.databaseStorage.write { transaction in
                return try self.groupV2Updates.updateGroupWithChangeActions(groupId: groupId,
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

        guard !DebugFlags.groupsV2corruptAvatarUrlPaths else {
            return Promise.value("some/invalid/url/path")
        }

        let requestBuilder: RequestBuilder = { (authCredential, sessionManager) in
            return DispatchQueue.global().async(.promise) { () -> NSURLRequest in
                return try StorageService.buildGroupAvatarUploadFormRequest(groupV2Params: groupV2Params,
                                                                            sessionManager: sessionManager,
                                                                            authCredential: authCredential)
            }
        }

        return firstly { () -> Promise<ServiceResponse> in
            let groupId = try self.groupId(forGroupSecretParamsData: groupV2Params.groupSecretParamsData)
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupId,
                                              behavior403: .fetchGroupUpdates)
        }.map(on: DispatchQueue.global()) { (response: ServiceResponse) -> GroupsProtoAvatarUploadAttributes in

            guard let protoData = response.responseObject as? Data else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            return try GroupsProtoAvatarUploadAttributes.parseData(protoData)
        }.map(on: DispatchQueue.global()) { (avatarUploadAttributes: GroupsProtoAvatarUploadAttributes) throws -> OWSUploadForm in
            try OWSUploadForm.parse(proto: avatarUploadAttributes)
        }.then(on: DispatchQueue.global()) { (uploadForm: OWSUploadForm) -> Promise<String> in
            let encryptedData = try groupV2Params.encryptGroupAvatar(avatarData)
            return OWSUploadV2.upload(data: encryptedData, uploadForm: uploadForm, uploadUrlPath: "")
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
        return DispatchQueue.global().async(.promise) { () -> GroupV2Params in
            return try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
        }.then(on: DispatchQueue.global()) { (groupV2Params: GroupV2Params) -> Promise<GroupV2Snapshot> in
            return self.fetchCurrentGroupV2Snapshot(groupV2Params: groupV2Params,
                                                    localUuid: localUuid,
                                                    justUploadedAvatars: justUploadedAvatars)
        }
    }

    private func fetchCurrentGroupV2Snapshot(groupV2Params: GroupV2Params,
                                             localUuid: UUID,
                                             justUploadedAvatars: GroupV2DownloadedAvatars?) -> Promise<GroupV2Snapshot> {
        let requestBuilder: RequestBuilder = { (authCredential, sessionManager) in
            return DispatchQueue.global().async(.promise) { () -> NSURLRequest in
                return try StorageService.buildFetchCurrentGroupV2SnapshotRequest(groupV2Params: groupV2Params,
                                                                                  sessionManager: sessionManager,
                                                                                  authCredential: authCredential)
            }
        }

        return firstly { () -> Promise<ServiceResponse> in
            let groupId = try self.groupId(forGroupSecretParamsData: groupV2Params.groupSecretParamsData)
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupId,
                                              behavior403: .removeFromGroup)
        }.map(on: DispatchQueue.global()) { (response: ServiceResponse) -> GroupsProtoGroup in
            guard let groupProtoData = response.responseObject as? Data else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            return try GroupsProtoGroup.parseData(groupProtoData)
        }.then(on: DispatchQueue.global()) { (groupProto: GroupsProtoGroup) -> Promise<(GroupsProtoGroup, GroupV2DownloadedAvatars)> in
            return firstly {
                // We can ignoreSignature; these protos came from the service.
                self.fetchAllAvatarData(groupProto: groupProto,
                                        justUploadedAvatars: justUploadedAvatars,
                                        ignoreSignature: true,
                                        groupV2Params: groupV2Params)
            }.map(on: DispatchQueue.global()) { (downloadedAvatars: GroupV2DownloadedAvatars) -> (GroupsProtoGroup, GroupV2DownloadedAvatars) in
                return (groupProto, downloadedAvatars)
            }
        }.map(on: DispatchQueue.global()) { (groupProto: GroupsProtoGroup, downloadedAvatars: GroupV2DownloadedAvatars) -> GroupV2Snapshot in
            return try GroupsV2Protos.parse(groupProto: groupProto, downloadedAvatars: downloadedAvatars, groupV2Params: groupV2Params)
        }
    }

    // MARK: - Fetch Group Change Actions

    public func fetchGroupChangeActions(groupSecretParamsData: Data,
                                        firstKnownRevision: UInt32?) -> Promise<[GroupV2Change]> {

        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }
        return DispatchQueue.global().async(.promise) { () -> (Data, GroupV2Params) in
            let groupId = try self.groupId(forGroupSecretParamsData: groupSecretParamsData)
            let groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
            return (groupId, groupV2Params)
        }.then(on: DispatchQueue.global()) { (groupId: Data, groupV2Params: GroupV2Params) -> Promise<[GroupV2Change]> in
            return self.fetchGroupChangeActions(groupId: groupId,
                                                groupV2Params: groupV2Params,
                                                localUuid: localUuid,
                                                firstKnownRevision: firstKnownRevision)
        }
    }

    private func fetchGroupChangeActions(groupId: Data,
                                         groupV2Params: GroupV2Params,
                                         localUuid: UUID,
                                         firstKnownRevision: UInt32?) -> Promise<[GroupV2Change]> {

        let requestBuilder: RequestBuilder = { (authCredential, sessionManager) in
            return DispatchQueue.global().async(.promise) { () -> NSURLRequest in
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
                        if FeatureFlags.groupsV2reapplyCurrentRevision {
                            return (groupModel.revision, true)
                        } else {
                            return (groupModel.revision + 1, false)
                        }
                }

                return try StorageService.buildFetchGroupChangeActionsRequest(groupV2Params: groupV2Params,
                                                                              fromRevision: fromRevision,
                                                                              requireSnapshotForFirstChange: requireSnapshotForFirstChange,
                                                                              sessionManager: sessionManager,
                                                                              authCredential: authCredential)
            }
        }

        return firstly { () -> Promise<ServiceResponse> in
            // We can't remove the local user from the group on 403.
            // For example, user might just be joining the group
            // using an invite OR have just been re-added after leaving.
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupId,
                                              behavior403: .ignore)
        }.map(on: DispatchQueue.global()) { (response: ServiceResponse) -> GroupsProtoGroupChanges in
            guard let groupChangesProtoData = response.responseObject as? Data else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            return try GroupsProtoGroupChanges.parseData(groupChangesProtoData)
        }.then(on: DispatchQueue.global()) { (groupChangesProto: GroupsProtoGroupChanges) -> Promise<[GroupV2Change]> in
            return firstly {
                // We can ignoreSignature; these protos came from the service.
                self.fetchAllAvatarData(groupChangesProto: groupChangesProto,
                                        ignoreSignature: true,
                                        groupV2Params: groupV2Params)
            }.map(on: DispatchQueue.global()) { (downloadedAvatars: GroupV2DownloadedAvatars) -> [GroupV2Change] in
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

        return DispatchQueue.global().async(.promise) { () throws -> Void in
            // First step - try to skip downloading the current group avatar.
            let groupId = try self.groupId(forGroupSecretParamsData: groupV2Params.groupSecretParamsData)
            guard let groupThread = (self.databaseStorage.read { transaction in
                return TSGroupThread.fetch(groupId: groupId, transaction: transaction)
            }) else {
                // Thread doesn't exist in database yet.
                return
            }
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid groupModel.")
            }
            // Try to add avatar from group model, if any.
            downloadedAvatars.merge(GroupV2DownloadedAvatars.from(groupModel: groupModel))
        }.then(on: DispatchQueue.global()) { () -> Promise<[String]> in
            GroupsV2Protos.collectAvatarUrlPaths(groupProto: groupProto,
                                                 groupChangesProto: groupChangesProto,
                                                 changeActionsProto: changeActionsProto,
                                                 ignoreSignature: ignoreSignature,
                                                 groupV2Params: groupV2Params)
        }.then(on: DispatchQueue.global()) { (protoAvatarUrlPaths: [String]) -> Promise<GroupV2DownloadedAvatars> in

            let undownloadedAvatarUrlPaths = Set(protoAvatarUrlPaths).subtracting(downloadedAvatars.avatarUrlPaths)
            guard !undownloadedAvatarUrlPaths.isEmpty else {
                return Promise.value(downloadedAvatars)
            }

            // We need to "populate" any group changes that have a
            // avatar with the avatar data.
            var promises = [Promise<(String, Data)>]()
            for avatarUrlPath in undownloadedAvatarUrlPaths {
                let (downloadPromise, resolver) = Promise<Data>.pending()
                firstly { () -> Promise<Data> in
                    self.fetchAvatarData(avatarUrlPath: avatarUrlPath,
                                         groupV2Params: groupV2Params)
                }.done(on: DispatchQueue.global()) { avatarData in
                    resolver.fulfill(avatarData)
                }.catch(on: DispatchQueue.global()) { error in
                    if let statusCode = error.httpStatusCode,
                        statusCode == 404 {
                        // Fulfill with empty data if service returns 404 status code.
                        // We don't want the group to be left in an unrecoverable state
                        // if the the avatar is missing from the CDN.
                        resolver.fulfill(Data())
                    }

                    resolver.reject(error)
                }

                let promise = downloadPromise.map(on: DispatchQueue.global()) { (avatarData: Data) -> Data in
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
                }.map(on: DispatchQueue.global()) { (avatarData: Data) -> (String, Data) in
                    return (avatarUrlPath, avatarData)
                }
                promises.append(promise)
            }
            return firstly {
                when(fulfilled: promises)
            }.map(on: DispatchQueue.global()) { (avatars: [(String, Data)]) -> GroupV2DownloadedAvatars in
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
        return DispatchQueue.global().async(.promise) { () throws -> GroupsV2ChangeSet in
            let changeSet = GroupsV2ChangeSetImpl(groupId: groupModel.groupId,
                                                  groupSecretParamsData: groupModel.secretParamsData)
            changeSetBlock(changeSet)
            return changeSet
        }.then(on: DispatchQueue.global()) { (changeSet: GroupsV2ChangeSet) -> Promise<TSGroupThread> in
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

    private struct ServiceResponse {
        let task: URLSessionDataTask
        let response: URLResponse
        let responseObject: Any?
    }

    private typealias AuthCredentialMap = [UInt32: AuthCredential]
    private typealias RequestBuilder = (AuthCredential, AFHTTPSessionManager) -> Promise<NSURLRequest>

    // Represents how we should respond to 403 status codes.
    private enum Behavior403 {
        case fail
        case removeFromGroup
        case fetchGroupUpdates
        case ignore
    }

    private func performServiceRequest(requestBuilder: @escaping RequestBuilder,
                                       groupId: Data?,
                                       behavior403: Behavior403,
                                       remainingRetries: UInt = 3) -> Promise<ServiceResponse> {
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }
        let sessionManager = self.sessionManager

        return firstly {
            self.ensureTemporalCredentials(localUuid: localUuid)
        }.then(on: DispatchQueue.global()) { (authCredential: AuthCredential) -> Promise<NSURLRequest> in
            return requestBuilder(authCredential, sessionManager)
        }.then(on: DispatchQueue.global()) { (request: NSURLRequest) -> Promise<ServiceResponse> in
            let (promise, resolver) = Promise<ServiceResponse>.pending()
            firstly {
                self.performServiceRequestAttempt(request: request, sessionManager: sessionManager)
            }.done(on: DispatchQueue.global()) { (response: ServiceResponse) in
                resolver.fulfill(response)
            }.catch(on: DispatchQueue.global()) { (error: Error) in

                let retryIfPossible = {
                    if remainingRetries > 0 {
                        firstly {
                            self.performServiceRequest(requestBuilder: requestBuilder,
                                                       groupId: groupId,
                                                       behavior403: behavior403,
                                                       remainingRetries: remainingRetries - 1)
                        }.done(on: DispatchQueue.global()) { (response: ServiceResponse) in
                            resolver.fulfill(response)
                        }.catch(on: DispatchQueue.global()) { (error: Error) in
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
                            }
                        } else {
                            // We should only receive 403 when groupId is not nil.
                            owsFailDebug("Missing groupId.")
                        }

                        resolver.reject(GroupsV2Error.localUserNotInGroup)
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

    private func performServiceRequestAttempt(request: NSURLRequest,
                                              sessionManager: AFHTTPSessionManager) -> Promise<ServiceResponse> {

        Logger.info("Making group request: \(String(describing: request.httpMethod)) \(request)")

        return Promise { resolver in
            var blockTask: URLSessionDataTask?
            let task = sessionManager.dataTask(
                with: request as URLRequest,
                uploadProgress: nil,
                downloadProgress: nil
            ) { response, responseObject, error in

                guard let blockTask = blockTask else {
                    return resolver.reject(OWSAssertionError("Missing blockTask."))
                }

                if let error = error {
                    if error.isNetworkFailureOrTimeout {
                        Logger.warn("Request error: \(error)")
                        return resolver.reject(error)
                    }

                    if let statusCode = error.httpStatusCode {
                        if [401, 403, 409].contains(statusCode) {
                            // These status codes will be handled by performServiceRequest.
                            Logger.warn("Request error: \(error)")
                            #if TESTABLE_BUILD
                            TSNetworkManager.logCurl(for: blockTask)
                            #endif
                            return resolver.reject(error)
                        }
                    }

                    Logger.warn("Request failed: \(String(describing: request.httpMethod)) \(String(describing: request.url))")
                    owsFailDebug("Request error: \(error)")
                    #if TESTABLE_BUILD
                    TSNetworkManager.logCurl(for: blockTask)
                    #endif
                    return resolver.reject(error)
                }

                guard let response = response as? HTTPURLResponse else {
                    Logger.warn("Request failed: \(String(describing: request.httpMethod)) \(String(describing: request.url))")
                    owsFailDebug("Request missing response.")
                    #if TESTABLE_BUILD
                    TSNetworkManager.logCurl(for: blockTask)
                    #endif
                    return resolver.reject(OWSAssertionError("Unexpected response type."))
                }

                switch response.statusCode {
                case 200:
                    Logger.info("Request succeeded: \(String(describing: request.httpMethod)) \(String(describing: request.url))")
                    // NOTE: responseObject may be nil; not all group v2 responses have bodies.
                    let serviceResponse = ServiceResponse(task: blockTask, response: response, responseObject: responseObject)
                    resolver.fulfill(serviceResponse)
                default:
                    #if TESTABLE_BUILD
                    TSNetworkManager.logCurl(for: blockTask)
                    #endif
                    resolver.reject(OWSAssertionError("Invalid response: \(response.statusCode)"))
                }
            }
            blockTask = task
            task.resume()
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
            if IsNetworkConnectivityFailure(error) {
                Logger.warn("Error: \(error)")
            } else {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    // MARK: - ProfileKeyCredentials

    public func loadProfileKeyCredentialData(for uuids: [UUID]) -> Promise<ProfileKeyCredentialMap> {

        guard RemoteConfig.groupsV2GoodCitizen else {
            return Promise(error: GroupsV2Error.gv2NotEnabled)
        }

        guard FeatureFlags.groupsV2,
                RemoteConfig.versionedProfileFetches else {
                    return Promise(error: GroupsV2Error.gv2NotEnabled)
        }

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
                .map(on: DispatchQueue.global()) { (_: SignalServiceProfile) -> (UUID) in
                    // Ideally we'd pull the credential off of SignalServiceProfile here,
                    // but the credential response needs to be parsed and verified
                    // which requires the VersionedProfileRequest.
                    return uuid
            }
            promises.append(promise)
        }
        return when(fulfilled: promises)
            .map(on: DispatchQueue.global()) { _ in
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
        guard RemoteConfig.versionedProfileFetches else {
            return Promise.value(())
        }

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

        return DispatchQueue.global().async(.promise) { () -> AuthCredential? in
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
        }.then(on: DispatchQueue.global()) { (cachedAuthCredential: AuthCredential?) throws -> Promise<AuthCredential> in
            if let cachedAuthCredential = cachedAuthCredential {
                return Promise.value(cachedAuthCredential)
            }
            return firstly {
                self.retrieveTemporalCredentialsFromService(localUuid: localUuid)
            }.map(on: DispatchQueue.global()) { (authCredentialMap: AuthCredentialMap) throws -> AuthCredential in
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
        }.map(on: DispatchQueue.global()) { (_: URLSessionDataTask, responseObject: Any?) -> AuthCredentialMap in
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
        guard RemoteConfig.versionedProfileUpdate else {
            return Promise(error: OWSAssertionError("Versioned profiles are not enabled."))
        }
        return self.profileManager.reuploadLocalProfilePromise()
    }

    // MARK: - Restore Groups

    public func isGroupKnownToStorageService(groupModel: TSGroupModelV2,
                                             transaction: SDSAnyReadTransaction) -> Bool {
        return GroupsV2Impl.isGroupKnownToStorageService(groupModel: groupModel, transaction: transaction)
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

    public func groupV2ContextInfo(forMasterKeyData masterKeyData: Data?) throws -> GroupV2ContextInfo {
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
