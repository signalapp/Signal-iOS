//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import LibSignalClient

@objc
public class GroupsV2Impl: NSObject, GroupsV2Swift, GroupsV2 {

    private var urlSession: OWSURLSessionProtocol {
        return self.signalService.urlSessionForStorageService()
    }

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
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
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
        let zkgroupVersionCounter: Int = 4

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
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            if self.tsAccountManager.isRegisteredAndReady {
                Logger.info("Re-uploading local profile due to zkgroup update.")
                firstly {
                    self.reuploadLocalProfilePromise()
                }.catch { error in
                    Logger.warn("Error: \(error)")
                }
            }
        }
        return true
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

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
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
        let groupV2Params: GroupV2Params
        do {
            groupV2Params = try groupModel.groupV2Params()
        } catch {
            return Promise<Void>(error: error)
        }

        return firstly(on: .global()) { () throws -> Promise<GroupsProtoGroup> in
            self.buildProtoToCreateNewGroupOnService(
                groupModel: groupModel,
                disappearingMessageToken: disappearingMessageToken,
                groupV2Params: groupV2Params
            )
        }.then(on: .global()) { groupProto -> Promise<Void> in
            let requestBuilder: RequestBuilder = { authCredential -> Promise<GroupsV2Request> in
                return .value(try StorageService.buildNewGroupRequest(
                    groupProto: groupProto,
                    groupV2Params: groupV2Params,
                    authCredential: authCredential
                ))
            }

            // New-group protos contain a profile key credential for each
            // member. If the proto we're submitting contains a profile key
            // credential that's expired, we'll get back a generic 400.
            // Consequently, if we get a 400 we should attempt to recover
            // (see below).

            return self.performServiceRequest(
                requestBuilder: requestBuilder,
                groupId: nil,
                behavior400: .reportForRecovery,
                behavior403: .fail,
                behavior404: .fail
            ).asVoid()
        }.recover(on: .global()) { error throws -> Promise<Void> in
            guard case GroupsV2Error.serviceRequestHitRecoverable400 = error else {
                throw error
            }

            // We likely failed to create the group because one of the profile
            // key credentials we submitted was expired, possibly due to drift
            // between our local clock and the service. We should try again
            // exactly once, forcing a refresh of all the credentials first.

            return self.buildProtoToCreateNewGroupOnService(
                groupModel: groupModel,
                disappearingMessageToken: disappearingMessageToken,
                groupV2Params: groupV2Params,
                shouldForceRefreshProfileKeyCredentials: true
            ).then(on: .global()) { groupProto -> Promise<Void> in
                let requestBuilder: RequestBuilder = { authCredential -> Promise<GroupsV2Request> in
                    return .value(try StorageService.buildNewGroupRequest(
                        groupProto: groupProto,
                        groupV2Params: groupV2Params,
                        authCredential: authCredential
                    ))
                }

                return self.performServiceRequest(
                    requestBuilder: requestBuilder,
                    groupId: nil,
                    behavior400: .fail,
                    behavior403: .fail,
                    behavior404: .fail
                ).asVoid()
            }
        }
    }

    /// Construct the proto to create a new group on the service.
    /// - Parameters:
    ///   - shouldForceRefreshProfileKeyCredentials: Whether we should force-refresh PKCs for the group members.
    private func buildProtoToCreateNewGroupOnService(
        groupModel: TSGroupModelV2,
        disappearingMessageToken: DisappearingMessageToken,
        groupV2Params: GroupV2Params,
        shouldForceRefreshProfileKeyCredentials: Bool = false
    ) -> Promise<GroupsProtoGroup> {
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }

        return firstly(on: .global()) { () throws -> Promise<ProfileKeyCredentialMap> in
            // Gather the UUIDs for all full (not invited) members, and get
            // profile key credentials for them. By definition, we cannot get
            // a PKC for the invited members.
            let uuids: [UUID] = groupModel.groupMembers.compactMap { address in
                guard let uuid = address.uuid else {
                    owsFailDebug("Address of full member in new group missing UUID.")
                    return nil
                }

                return uuid
            }

            guard uuids.contains(localUuid) else {
                throw OWSAssertionError("localUuid is not a member.")
            }

            return self.loadProfileKeyCredentials(
                for: uuids,
                forceRefresh: shouldForceRefreshProfileKeyCredentials
            )
        }.map(on: .global()) { profileKeyCredentialMap -> GroupsProtoGroup in
            return try GroupsV2Protos.buildNewGroupProto(
                groupModel: groupModel,
                disappearingMessageToken: disappearingMessageToken,
                groupV2Params: groupV2Params,
                profileKeyCredentialMap: profileKeyCredentialMap,
                localUuid: localUuid
            )
        }
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
    private func updateExistingGroupOnService(changes: GroupsV2OutgoingChanges) -> Promise<TSGroupThread> {

        let groupId = changes.groupId
        let groupSecretParamsData = changes.groupSecretParamsData
        let groupV2Params: GroupV2Params
        do {
            groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
        } catch {
            return Promise(error: error)
        }

        return firstly { () -> Promise<(GroupsProtoGroupChangeActions, HTTPResponse)> in
            self.buildGroupChangeProtoAndTryToUpdateGroupOnService(
                groupId: groupId,
                groupV2Params: groupV2Params,
                changes: changes
            )
        }.recover(on: .global()) { error throws -> Promise<(GroupsProtoGroupChangeActions, HTTPResponse)> in
            switch error {
            case GroupsV2Error.conflictingChangeOnService:
                // If we failed because a conflicting change has already been
                // committed to the service, we should refresh our local state
                // for the group and try again to apply our changes.

                return self.groupV2Updates.tryToRefreshV2GroupUpToCurrentRevisionImmediately(
                    groupId: groupId,
                    groupSecretParamsData: groupSecretParamsData
                ).then(on: .global()) { _ in
                    self.buildGroupChangeProtoAndTryToUpdateGroupOnService(
                        groupId: groupId,
                        groupV2Params: groupV2Params,
                        changes: changes
                    )
                }
            case GroupsV2Error.serviceRequestHitRecoverable400:
                // We likely got the 400 because we submitted a proto with
                // profile key credentials and one of them was expired, possibly
                // due to drift between our local clock and the service. We
                // should try again exactly once, forcing a refresh of all the
                // credentials first.

                return self.buildGroupChangeProtoAndTryToUpdateGroupOnService(
                    groupId: groupId,
                    groupV2Params: groupV2Params,
                    changes: changes,
                    shouldForceRefreshProfileKeyCredentials: true,
                    forceFailOn400: true
                )
            default:
                throw error
            }
        }.then(on: .global()) { (groupChangeProto, response) throws -> Promise<TSGroupThread> in
            return self.handleGroupUpdatedOnService(
                response: response,
                changes: changes,
                groupChangeProto: groupChangeProto,
                groupId: groupId,
                groupV2Params: groupV2Params
            )
        }
    }

    /// Construct a group change proto from the given `changes` for the given
    /// `groupId`, and attempt to commit the group change to the service.
    /// - Parameters:
    ///   - shouldForceRefreshProfileKeyCredentials: Whether we should force-refresh PKCs for any new members while building the proto.
    ///   - forceFailOn400: Whether we should force failure when receiving a 400. If `false`, may instead report expired PKCs.
    private func buildGroupChangeProtoAndTryToUpdateGroupOnService(
        groupId: Data,
        groupV2Params: GroupV2Params,
        changes: GroupsV2OutgoingChanges,
        shouldForceRefreshProfileKeyCredentials: Bool = false,
        forceFailOn400: Bool = false
    ) -> Promise<(GroupsProtoGroupChangeActions, HTTPResponse)> {
        self.databaseStorage.read(.promise) { transaction throws -> (TSGroupThread, DisappearingMessageToken) in
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Thread does not exist.")
            }

            let dmConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: groupThread, transaction: transaction)

            return (groupThread, dmConfiguration.asToken)
        }.then(on: .global()) { (groupThread, dmToken) throws -> Promise<GroupsProtoGroupChangeActions> in
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid group model.")
            }

            return changes.buildGroupChangeProto(
                currentGroupModel: groupModel,
                currentDisappearingMessageToken: dmToken,
                forceRefreshProfileKeyCredentials: shouldForceRefreshProfileKeyCredentials
            )
        }.then(on: .global()) { groupChangeProto -> Promise<(GroupsProtoGroupChangeActions, HTTPResponse)> in
            var behavior400: Behavior400 = .fail
            if
                !forceFailOn400,
                groupChangeProto.containsProfileKeyCredentials
            {
                // If the proto we're submitting contains a profile key credential
                // that's expired, we'll get back a generic 400. Consequently, if
                // we're submitting a proto with PKCs, and we get a 400, we should
                // attempt to recover.

                behavior400 = .reportForRecovery
            }

            let requestBuilder: RequestBuilder = { authCredential in
                return .value(try StorageService.buildUpdateGroupRequest(
                    groupChangeProto: groupChangeProto,
                    groupV2Params: groupV2Params,
                    authCredential: authCredential,
                    groupInviteLinkPassword: nil
                ))
            }

            return self.performServiceRequest(
                requestBuilder: requestBuilder,
                groupId: groupId,
                behavior400: behavior400,
                behavior403: .fetchGroupUpdates,
                behavior404: .fail
            ).map(on: .global()) { response -> (GroupsProtoGroupChangeActions, HTTPResponse) in
                return (groupChangeProto, response)
            }
        }
    }

    private func handleGroupUpdatedOnService(
        response: HTTPResponse,
        changes: GroupsV2OutgoingChanges,
        groupChangeProto: GroupsProtoGroupChangeActions,
        groupId: Data,
        groupV2Params: GroupV2Params
    ) -> Promise<TSGroupThread> {
        firstly { () -> Promise<UpdatedV2Group> in
            guard let changeActionsProtoData = response.responseBodyData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            let changeActionsProto = try GroupsV2Protos.parseAndVerifyChangeActionsProto(changeActionsProtoData,
                                                                                         ignoreSignature: true)

            // Collect avatar state from our change set so that we can
            // avoid downloading any avatars we just uploaded while
            // applying the change set locally.
            let downloadedAvatars = GroupV2DownloadedAvatars.from(changes: changes)

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

            databaseStorage.write { transaction in
                let message = OWSStaticOutgoingMessage(thread: contactThread,
                                                       plaintextData: contentProtoData,
                                                       transaction: transaction)

                Self.sskJobQueues.messageSenderJobQueue.add(
                    message: message.asPreparer,
                    limitToCurrentProcessLifetime: true,
                    transaction: transaction
                )
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

        return firstly { () -> Promise<HTTPResponse> in
            let groupId = try self.groupId(forGroupSecretParamsData: groupV2Params.groupSecretParamsData)
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupId,
                                              behavior400: .fail,
                                              behavior403: .fetchGroupUpdates,
                                              behavior404: .fail)
        }.map(on: .global()) { (response: HTTPResponse) -> GroupsProtoAvatarUploadAttributes in

            guard let protoData = response.responseBodyData else {
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

        return firstly { () -> Promise<HTTPResponse> in
            let groupId = try self.groupId(forGroupSecretParamsData: groupV2Params.groupSecretParamsData)
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupId,
                                              behavior400: .fail,
                                              behavior403: .removeFromGroup,
                                              behavior404: .groupDoesNotExistOnService)
        }.map(on: .global()) { (response: HTTPResponse) -> GroupsProtoGroup in
            guard let groupProtoData = response.responseBodyData else {
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

    func fetchGroupChangeActions(
        groupSecretParamsData: Data,
        includeCurrentRevision: Bool
    ) -> Promise<GroupChangePage> {
        return firstly(on: .global()) { () -> (Data, GroupV2Params) in
            let groupId = try self.groupId(forGroupSecretParamsData: groupSecretParamsData)
            let groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)
            return (groupId, groupV2Params)
        }.then(on: .global()) { (groupId: Data, groupV2Params: GroupV2Params) -> Promise<GroupChangePage> in
            return self.fetchGroupChangeActions(
                groupId: groupId,
                groupV2Params: groupV2Params,
                includeCurrentRevision: includeCurrentRevision
            )
        }
    }

    struct GroupChangePage {
        let changes: [GroupV2Change]
        let earlyEnd: UInt32?

        fileprivate static func parseEarlyEnd(fromGroupRangeHeader header: String?) -> UInt32? {
            guard let header = header else {
                OWSLogger.warn("Missing Content-Range for group update request with 206 response")
                return nil
            }

            let pattern = try! NSRegularExpression(pattern: #"^versions (\d+)-(\d+)/(\d+)$"#)
            guard let match = pattern.firstMatch(in: header, range: header.entireRange) else {
                OWSLogger.warn("Unparsable Content-Range for group update request: \(header)")
                return nil
            }

            guard let earlyEndRange = Range(match.range(at: 1), in: header) else {
                owsFailDebug("Could not translate NSRange to Range<String.Index>")
                return nil
            }

            guard let earlyEndValue = UInt32(header[earlyEndRange]) else {
                OWSLogger.warn("Invalid early-end in Content-Range for group update request: \(header)")
                return nil
            }

            return earlyEndValue
        }
    }

    private func fetchGroupChangeActions(
        groupId: Data,
        groupV2Params: GroupV2Params,
        includeCurrentRevision: Bool
    ) -> Promise<GroupChangePage> {
        return firstly(on: .global()) { () -> Promise<(fromRevision: UInt32, requireSnapshotForFirstChange: Bool)> in
            let groupThread = self.databaseStorage.read { transaction in
                TSGroupThread.fetch(groupId: groupId, transaction: transaction)
            }

            if
                let groupThread = groupThread,
                let groupModel = groupThread.groupModel as? TSGroupModelV2,
                groupModel.groupMembership.isLocalUserFullOrInvitedMember
            {
                // We're being told about a group we are aware of and are
                // already a member of. In this case, we can figure out which
                // revision we want to start with from local data.

                let fromRevision: UInt32
                let requireSnapshotForFirstChange: Bool

                if includeCurrentRevision {
                    fromRevision = groupModel.revision
                    requireSnapshotForFirstChange = true
                } else {
                    fromRevision = groupModel.revision + 1
                    requireSnapshotForFirstChange = false
                }

                return Promise.value((
                    fromRevision: fromRevision,
                    requireSnapshotForFirstChange: requireSnapshotForFirstChange
                ))
            } else {
                // We're being told about a thread we either have never heard
                // of, or don't yet know we're a member of. In this case, we
                // need to ask the service which revision we joined at, and
                // request revisions from there. We should also get the
                // snapshot, since there may be revisions we were not in the
                // group to witness, and we want to make sure that state is
                // reflected.

                return self.getRevisionLocalUserWasAddedToGroup(
                    groupId: groupId,
                    groupV2Params: groupV2Params
                ).map { fromRevision in
                    (
                        fromRevision: fromRevision,
                        requireSnapshotForFirstChange: true
                    )
                }
            }
        }.then { (fromRevision: UInt32, requireSnapshotForFirstChange: Bool) -> Promise<HTTPResponse> in
            let fetchGroupChangesRequestBuilder: RequestBuilder = { authCredential in
                firstly(on: .global()) { () -> GroupsV2Request in
                    return try StorageService.buildFetchGroupChangeActionsRequest(
                        groupV2Params: groupV2Params,
                        fromRevision: fromRevision,
                        requireSnapshotForFirstChange: requireSnapshotForFirstChange,
                        authCredential: authCredential
                    )
                }
            }

            // At this stage, we know we are requesting for a revision at which
            // we are a member. Therefore, 403s should be treated as failure.
            return self.performServiceRequest(
                requestBuilder: fetchGroupChangesRequestBuilder,
                groupId: groupId,
                behavior400: .fail,
                behavior403: .fail,
                behavior404: .fail
            )
        }.map(on: .global()) { (response: HTTPResponse) -> (GroupsProtoGroupChanges, UInt32?) in
            guard let groupChangesProtoData = response.responseBodyData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            let earlyEnd: UInt32?
            if response.responseStatusCode == 206 {
                let groupRangeHeader = response.responseHeaders.first {
                    $0.key.caseInsensitiveCompare("content-range") == .orderedSame
                }?.value
                earlyEnd = GroupChangePage.parseEarlyEnd(fromGroupRangeHeader: groupRangeHeader)
            } else {
                earlyEnd = nil
            }
            return (try GroupsProtoGroupChanges(serializedData: groupChangesProtoData), earlyEnd)
        }.then(on: .global()) { (groupChangesProto: GroupsProtoGroupChanges, earlyEnd: UInt32?) -> Promise<GroupChangePage> in
            return firstly {
                // We can ignoreSignature; these protos came from the service.
                self.fetchAllAvatarData(groupChangesProto: groupChangesProto,
                                        ignoreSignature: true,
                                        groupV2Params: groupV2Params)
            }.map(on: .global()) { (downloadedAvatars: GroupV2DownloadedAvatars) -> GroupChangePage in
                let changes = try GroupsV2Protos.parseChangesFromService(groupChangesProto: groupChangesProto,
                                                                         downloadedAvatars: downloadedAvatars,
                                                                         groupV2Params: groupV2Params)
                return GroupChangePage(changes: changes, earlyEnd: earlyEnd)
            }
        }
    }

    private func getRevisionLocalUserWasAddedToGroup(
        groupId: Data,
        groupV2Params: GroupV2Params
    ) -> Promise<UInt32> {
        firstly(on: .global()) { () -> Promise<HTTPResponse> in
            let getJoinedAtRevisionRequestBuilder: RequestBuilder = { authCredential in
                firstly(on: .global()) {
                    try StorageService.buildGetJoinedAtRevisionRequest(
                        groupV2Params: groupV2Params,
                        authCredential: authCredential
                    )
                }
            }

            // We might get a 403 if we are not a member of the group, e.g. if
            // we are joining via invite link. Passing .ignore means we won't
            // retry, and will allow the "not a member" error to be thrown and
            // propagated upwards.
            return self.performServiceRequest(
                requestBuilder: getJoinedAtRevisionRequestBuilder,
                groupId: groupId,
                behavior400: .fail,
                behavior403: .ignore,
                behavior404: .fail
            )
        }.then { (response: HTTPResponse) throws -> Promise<UInt32> in
            guard let memberData = response.responseBodyData else {
                throw OWSAssertionError("Response missing body data")
            }

            let memberProto = try GroupsProtoMember(serializedData: memberData)

            guard memberProto.hasJoinedAtRevision else {
                throw OWSAssertionError("Member proto missing joinedAtRevision")
            }

            return Promise.value(memberProto.joinedAtRevision)
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
                let promise = firstly { () -> Promise<Data> in
                    self.fetchAvatarData(avatarUrlPath: avatarUrlPath,
                                         groupV2Params: groupV2Params)
                }.recover(on: .global()) { error -> Promise<Data> in
                    if let statusCode = error.httpStatusCode,
                       statusCode == 404 {
                        // Fulfill with empty data if service returns 404 status code.
                        // We don't want the group to be left in an unrecoverable state
                        // if the avatar is missing from the CDN.
                        return .value(Data())
                    }

                    throw error
                }.map(on: .global()) { (avatarData: Data) -> Data in
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
            return Promise.when(fulfilled: promises)
        }.map(on: .global()) { (avatars: [(String, Data)]) -> GroupV2DownloadedAvatars in
            for (avatarUrlPath, avatarData) in avatars {
                guard avatarData.count > 0 else {
                    owsFailDebug("Empty avatarData.")
                    continue
                }
                guard TSGroupModel.isValidGroupAvatarData(avatarData) else {
                    owsFailDebug("Invalid group avatar")
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

    public func updateGroupV2(
        groupId: Data,
        groupSecretParamsData: Data,
        changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void
    ) -> Promise<TSGroupThread> {
        return firstly(on: .global()) { () throws -> GroupsV2OutgoingChanges in
            let changes = GroupsV2OutgoingChangesImpl(
                groupId: groupId,
                groupSecretParamsData: groupSecretParamsData
            )
            changesBlock(changes)
            return changes
        }.then(on: .global()) { (changes: GroupsV2OutgoingChanges) -> Promise<TSGroupThread> in
            return self.updateExistingGroupOnService(changes: changes)
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

    private typealias AuthCredentialWithPniMap = [UInt64: AuthCredentialWithPni]
    private typealias RequestBuilder = (AuthCredentialWithPni) throws -> Promise<GroupsV2Request>

    /// Represents how we should respond to 400 status codes.
    enum Behavior400 {
        case fail
        case reportForRecovery
    }

    /// Represents how we should respond to 403 status codes.
    private enum Behavior403 {
        case fail
        case removeFromGroup
        case fetchGroupUpdates
        case ignore
        case reportInvalidOrBlockedGroupLink
        case localUserIsNotARequestingMember
    }

    /// Represents how we should respond to 404 status codes.
    private enum Behavior404 {
        case fail
        case groupDoesNotExistOnService
    }

    /// Make a request to the GV2 service, produced by the given
    /// `requestBuilder`. Specifies how to respond if the request results in
    /// certain errors.
    private func performServiceRequest(
        requestBuilder: @escaping RequestBuilder,
        groupId: Data?,
        behavior400: Behavior400,
        behavior403: Behavior403,
        behavior404: Behavior404,
        remainingRetries: UInt = 3
    ) -> Promise<HTTPResponse> {
        guard
            let localAci = tsAccountManager.localUuid,
            let localPni = tsAccountManager.localPni
        else {
            return Promise(error: OWSAssertionError("Missing local ACI/PNI."))
        }

        return firstly {
            self.ensureTemporalCredentials(localAci: localAci, localPni: localPni)
        }.then(on: .global()) { (authCredential: AuthCredentialWithPni) -> Promise<GroupsV2Request> in
            try requestBuilder(authCredential)
        }.then(on: .global()) { (request: GroupsV2Request) -> Promise<HTTPResponse> in
            self.performServiceRequestAttempt(request: request)
                .recover(on: .global()) { (error: Error) throws -> Promise<HTTPResponse> in
                    let retryIfPossible = { (error: Error) throws -> Promise<HTTPResponse> in
                        if remainingRetries > 0 {
                            return self.performServiceRequest(
                                requestBuilder: requestBuilder,
                                groupId: groupId,
                                behavior400: behavior400,
                                behavior403: behavior403,
                                behavior404: behavior404,
                                remainingRetries: remainingRetries - 1
                            )
                        } else {
                            throw error
                        }
                    }

                    return try self.tryRecoveryFromServiceRequestFailure(
                        error: error,
                        retryBlock: retryIfPossible,
                        groupId: groupId,
                        behavior400: behavior400,
                        behavior403: behavior403,
                        behavior404: behavior404
                    )
                }
        }
    }

    /// Upon error from performing a service request, attempt to recover based
    /// on the error and our 4XX behaviors.
    private func tryRecoveryFromServiceRequestFailure(
        error: Error,
        retryBlock: (Error) throws -> Promise<HTTPResponse>,
        groupId: Data?,
        behavior400: Behavior400,
        behavior403: Behavior403,
        behavior404: Behavior404
    ) throws -> Promise<HTTPResponse> {
        // Fall through to retry if retry-able,
        // otherwise reject immediately.
        if let statusCode = error.httpStatusCode {
            switch statusCode {
            case 400:
                switch behavior400 {
                case .fail:
                    owsFailDebug("Unexpected 400.")
                case .reportForRecovery:
                    throw GroupsV2Error.serviceRequestHitRecoverable400
                }

                throw error
            case 401:
                // Retry auth errors after retrieving new temporal credentials.
                self.databaseStorage.write { transaction in
                    self.clearTemporalCredentials(transaction: transaction)
                }
                return try retryBlock(error)
            case 403:
                // 403 indicates that we are no longer in the group for
                // many (but not all) group v2 service requests.
                switch behavior403 {
                case .fail:
                    // We should never receive 403 when creating groups.
                    owsFailDebug("Unexpected 403.")
                case .ignore:
                    // We may get a 403 when fetching change actions if
                    // they are not yet a member - for example, if they are
                    // joining via an invite link.
                    owsAssertDebug(groupId != nil, "Expecting a groupId for this path")
                case .removeFromGroup:
                    guard let groupId = groupId else {
                        owsFailDebug("GroupId must be set to remove from group")
                        break
                    }
                    // If we receive 403 when trying to fetch group state,
                    // we have left the group, been removed from the group
                    // or had our invite revoked and we should make sure
                    // group state in the database reflects that.
                    self.databaseStorage.write { transaction in
                        GroupManager.handleNotInGroup(groupId: groupId, transaction: transaction)
                    }

                case .fetchGroupUpdates:
                    guard let groupId = groupId else {
                        owsFailDebug("GroupId must be set to fetch group updates")
                        break
                    }
                    // Service returns 403 if client tries to perform an
                    // update for which it is not authorized (e.g. add a
                    // new member if membership access is admin-only).
                    // The local client can't assume that 403 means they
                    // are not in the group. Therefore we "update group
                    // to latest" to check for and handle that case (see
                    // previous case).
                    self.tryToUpdateGroupToLatest(groupId: groupId)

                case .reportInvalidOrBlockedGroupLink:
                    owsAssertDebug(groupId == nil, "groupId should not be set in this code path.")

                    if error.httpResponseHeaders?.containsBan == true {
                        throw GroupsV2Error.localUserBlockedFromJoining
                    } else {
                        throw GroupsV2Error.expiredGroupInviteLink
                    }

                case .localUserIsNotARequestingMember:
                    owsAssertDebug(groupId == nil, "groupId should not be set in this code path.")
                    throw GroupsV2Error.localUserIsNotARequestingMember
                }

                throw GroupsV2Error.localUserNotInGroup
            case 404:
                // 404 indicates that the group does not exist on the
                // service for some (but not all) group v2 service requests.

                switch behavior404 {
                case .fail:
                    throw error
                case .groupDoesNotExistOnService:
                    Logger.warn("Error: \(error)")
                    throw GroupsV2Error.groupDoesNotExistOnService
                }
            case 409:
                // Group update conflict. The caller may be able to recover by
                // retrying, using the change set and the most recent state
                // from the service.
                throw GroupsV2Error.conflictingChangeOnService
            default:
                // Unexpected status code.
                throw error
            }
        } else if error.isNetworkFailureOrTimeout {
            // Retry on network failure.
            return try retryBlock(error)
        } else {
            // Unexpected error.
            throw error
        }
    }

    private func performServiceRequestAttempt(request: GroupsV2Request) -> Promise<HTTPResponse> {

        let urlSession = self.urlSession
        urlSession.failOnError = false

        Logger.info("Making group request: \(request.method) \(request.urlString)")

        return firstly { () -> Promise<HTTPResponse> in
            urlSession.dataTaskPromise(request.urlString,
                                       method: request.method,
                                       headers: request.headers.headers,
                                       body: request.bodyData)
        }.map(on: .global()) { (response: HTTPResponse) -> HTTPResponse in
            let statusCode = response.responseStatusCode
            let hasValidStatusCode = [200, 206].contains(statusCode)
            guard hasValidStatusCode else {
                throw OWSAssertionError("Invalid status code: \(statusCode)")
            }

            // NOTE: responseObject may be nil; not all group v2 responses have bodies.
            Logger.info("Request succeeded: \(request.method) \(request.urlString)")

            return response
        }.recover(on: .global()) { (error: Error) -> Promise<HTTPResponse> in
            if error.isNetworkFailureOrTimeout {
                throw error
            }

            if let statusCode = error.httpStatusCode {
                if [400, 401, 403, 404, 409].contains(statusCode) {
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
                Logger.warn("Error: \(error)")
            } else {
                owsFailDebugUnlessNetworkFailure(error)
            }
        }
    }

    // MARK: - ProfileKeyCredentials

    /// Fetches and returnes the profile key credential for each passed UUID. If
    /// any are missing, returns an error.
    public func loadProfileKeyCredentials(
        for uuids: [UUID],
        forceRefresh: Bool
    ) -> Promise<ProfileKeyCredentialMap> {
        tryToFetchProfileKeyCredentials(
            for: uuids,
            ignoreMissingProfiles: false,
            forceRefresh: forceRefresh
        ).map(on: .global()) { () -> ProfileKeyCredentialMap in
            let uuids = Set(uuids)

            let credentialMap = self.loadPresentProfileKeyCredentials(for: uuids)

            guard uuids.symmetricDifference(credentialMap.keys).isEmpty else {
                throw OWSAssertionError("Missing requested keys from credential map!")
            }

            return credentialMap
        }
    }

    /// Makes a best-effort to fetch the profile key credential for each passed
    /// UUID. If a profile exists for the user but the credential cannot be
    /// fetched (e.g., the UUID is not a contact of ours), skips it. Optionally
    /// ignores "missing profile" errors during fetch.
    public func tryToFetchProfileKeyCredentials(
        for uuids: [UUID],
        ignoreMissingProfiles: Bool,
        forceRefresh: Bool
    ) -> Promise<Void> {
        let uuids = Set(uuids)

        let uuidsToFetch: Set<UUID>
        if forceRefresh {
            uuidsToFetch = uuids
        } else {
            uuidsToFetch = uuids.subtracting(loadPresentProfileKeyCredentials(for: uuids).keys)
        }

        var promises = [Promise<Void>]()
        for uuidToFetch in uuidsToFetch {
            let address = SignalServiceAddress(uuid: uuidToFetch)

            let promise = ProfileFetcherJob.fetchProfilePromise(
                address: address,
                mainAppOnly: false,
                ignoreThrottling: true,
                fetchType: .versioned
            ).asVoid().recover(on: .global()) { error throws -> Promise<Void> in
                if
                    case ProfileFetchError.missing = error,
                    ignoreMissingProfiles
                {
                    Logger.info("Ignoring missing profile: \(error)")
                    return Promise.value(())
                }

                throw error
            }

            promises.append(promise)
        }

        return Promise.when(fulfilled: promises)
    }

    private func loadPresentProfileKeyCredentials(for uuids: Set<UUID>) -> ProfileKeyCredentialMap {
        databaseStorage.read { transaction in
            var credentialMap = ProfileKeyCredentialMap()

            for uuid in uuids {
                do {
                    let address = SignalServiceAddress(uuid: uuid)
                    if let credential = try self.versionedProfilesSwift.validProfileKeyCredential(
                        for: address,
                        transaction: transaction
                    ) {
                        credentialMap[uuid] = credential
                    }
                } catch {
                    owsFailDebug("Error loading profile key credential: \(error)")
                }
            }

            return credentialMap
        }
    }

    public func hasProfileKeyCredential(
        for address: SignalServiceAddress,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        do {
            return try self.versionedProfilesSwift.validProfileKeyCredential(
                for: address,
                transaction: transaction
            ) != nil
        } catch let error {
            owsFailDebug("Error getting profile key credential: \(error)")
            return false
        }
    }

    // MARK: - Auth Credentials

    private enum AuthCredentialStore {
        private static let store = SDSKeyValueStore(collection: "GroupsV2Impl.authCredentialStoreStore")

        private static func cacheKey(forRedemptionTime redemptionTime: UInt64) -> String {
            return "ACWP_\(redemptionTime)"
        }

        static func credential(
            forRedemptionTime redemptionTime: UInt64,
            transaction: SDSAnyReadTransaction
        ) throws -> AuthCredentialWithPni? {
            let key = cacheKey(forRedemptionTime: redemptionTime)

            guard let data = store.getData(key, transaction: transaction) else {
                return nil
            }

            return try AuthCredentialWithPni(contents: [UInt8](data))
        }

        static func set(
            credential: AuthCredentialWithPni,
            forRedemptionTime redemptionTime: UInt64,
            transaction: SDSAnyWriteTransaction
        ) {
            let key = cacheKey(forRedemptionTime: redemptionTime)
            let value = credential.serialize().asData

            store.setData(value, key: key, transaction: transaction)
        }

        static func removeAll(transaction: SDSAnyWriteTransaction) {
            store.removeAll(transaction: transaction)
        }
    }

    private func ensureTemporalCredentials(
        localAci: UUID,
        localPni: UUID
    ) -> Promise<AuthCredentialWithPni> {
        let redemptionTime = Self.todaySecondsSinceEpoch

        return firstly(on: .global()) { () -> AuthCredentialWithPni? in
            do {
                return try self.databaseStorage.read { (transaction) throws -> AuthCredentialWithPni? in
                    try AuthCredentialStore.credential(forRedemptionTime: redemptionTime, transaction: transaction)
                }
            } catch {
                owsFailDebug("Error retrieving cached auth credential: \(error)")
                return nil
            }
        }.then(on: .global()) { (cachedAuthCredential: AuthCredentialWithPni?) throws -> Promise<AuthCredentialWithPni> in
            if let cachedAuthCredential = cachedAuthCredential {
                return Promise.value(cachedAuthCredential)
            }

            return self.retrieveTemporalCredentialsFromService(
                localAci: localAci,
                localPni: localPni
            ).map(on: .global()) { (authCredentialMap: AuthCredentialWithPniMap) throws -> AuthCredentialWithPni in
                self.databaseStorage.write { transaction in
                    // Remove stale auth credentials.
                    AuthCredentialStore.removeAll(transaction: transaction)

                    // Store new auth credentials.
                    for (authTime, authCredential) in authCredentialMap {
                        AuthCredentialStore.set(
                            credential: authCredential,
                            forRedemptionTime: authTime,
                            transaction: transaction
                        )
                    }
                }

                guard let authCredential = authCredentialMap[redemptionTime] else {
                    throw OWSAssertionError("No auth credential for redemption time.")
                }

                return authCredential
            }
        }
    }

    public func clearTemporalCredentials(transaction: SDSAnyWriteTransaction) {
        // Remove stale auth credentials.
        AuthCredentialStore.removeAll(transaction: transaction)
    }

    private func retrieveTemporalCredentialsFromService(
        localAci: UUID,
        localPni: UUID
    ) -> Promise<AuthCredentialWithPniMap> {
        let sevenDaysSeconds = 7 * Self.dayInSeconds
        let todaySeconds = Self.todaySecondsSinceEpoch
        let todaySecondsPlus7Days = todaySeconds + sevenDaysSeconds

        let request = OWSRequestFactory.groupAuthenticationCredentialRequest(
            fromRedemptionSeconds: todaySeconds,
            toRedemptionSeconds: todaySecondsPlus7Days
        )

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response -> AuthCredentialWithPniMap in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON")
            }

            let (temporalCredentials, pni) = try self.parseCredentialResponse(responseObject: json)

            if pni != localPni {
                Logger.error("PNI from fetching auth credentials (\(pni)) did not match local PNI \(localPni)! Did the phone number change?")
            }

            let serverPublicParams = try GroupsV2Protos.serverPublicParams()
            let clientZkAuthOperations = ClientZkAuthOperations(serverPublicParams: serverPublicParams)
            var credentialMap = AuthCredentialWithPniMap()
            for temporalCredential in temporalCredentials {
                // Verify the credentials.
                let authCredential: AuthCredentialWithPni = try clientZkAuthOperations.receiveAuthCredentialWithPni(
                    aci: localAci,
                    pni: pni,
                    redemptionTime: temporalCredential.redemptionTime,
                    authCredentialResponse: temporalCredential.authCredentialWithPniResponse
                )
                credentialMap[temporalCredential.redemptionTime] = authCredential
            }
            return credentialMap
        }
    }

    /// The "start of today", i.e. midnight at the beginning of today, in epoch
    /// seconds.
    private static var todaySecondsSinceEpoch: UInt64 {
        let msSinceEpoch = NSDate.ows_millisecondTimeStamp()
        let daysSinceEpoch = msSinceEpoch / kDayInMs
        return daysSinceEpoch * dayInSeconds
    }

    private static let dayInSeconds = kDayInMs / kSecondInMs

    private struct TemporalCredential {
        let redemptionTime: UInt64
        let authCredentialWithPniResponse: AuthCredentialWithPniResponse
    }

    private func parseCredentialResponse(
        responseObject: Any?
    ) throws -> (credentials: [TemporalCredential], pni: UUID) {
        guard let responseObject = responseObject else {
            throw OWSAssertionError("Missing response.")
        }

        guard let params = ParamParser(responseObject: responseObject) else {
            throw OWSAssertionError("invalid response: \(String(describing: responseObject))")
        }

        let pni: UUID = try params.required(key: "pni")
        let credentials: [Any] = try params.required(key: "credentials")

        var temporalCredentials = [TemporalCredential]()
        for credential in credentials {
            guard let credentialParser = ParamParser(responseObject: credential) else {
                throw OWSAssertionError("invalid credential: \(String(describing: credential))")
            }

            let redemptionTime: UInt64 = try credentialParser.required(key: "redemptionTime")
            let responseData: Data = try credentialParser.requiredBase64EncodedData(key: "credential")

            let response = try AuthCredentialWithPniResponse(contents: [UInt8](responseData))

            temporalCredentials.append(TemporalCredential(
                redemptionTime: redemptionTime,
                authCredentialWithPniResponse: response
            ))
        }

        return (credentials: temporalCredentials, pni: pni)
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
        OWSProfileManager.shared.reuploadLocalProfilePromise()
    }

    // MARK: - Restore Groups

    public func isGroupKnownToStorageService(
        groupModel: TSGroupModelV2,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        GroupsV2Impl.isGroupKnownToStorageService(groupModel: groupModel, transaction: transaction)
    }

    public func groupRecordPendingStorageServiceRestore(
        masterKeyData: Data,
        transaction: SDSAnyReadTransaction
    ) -> StorageServiceProtoGroupV2Record? {
        GroupsV2Impl.enqueuedGroupRecordForRestore(masterKeyData: masterKeyData, transaction: transaction)
    }

    public func restoreGroupFromStorageServiceIfNecessary(
        groupRecord: StorageServiceProtoGroupV2Record,
        transaction: SDSAnyWriteTransaction
    ) {
        GroupsV2Impl.enqueueGroupRestore(groupRecord: groupRecord, transaction: transaction)
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

    private let groupInviteLinkPreviewCache = LRUCache<Data, GroupInviteLinkPreview>(maxSize: 5,
                                                                                     shouldEvacuateInBackground: true)

    private func groupInviteLinkPreviewCacheKey(groupSecretParamsData: Data) -> Data {
        groupSecretParamsData
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

        return firstly(on: .global()) { () -> Promise<HTTPResponse> in
            let behavior403: Behavior403 = (inviteLinkPassword != nil
                                                ? .reportInvalidOrBlockedGroupLink
                                                : .localUserIsNotARequestingMember)
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: nil,
                                              behavior400: .fail,
                                              behavior403: behavior403,
                                              behavior404: .fail)
        }.map(on: .global()) { (response: HTTPResponse) -> GroupInviteLinkPreview in
            guard let protoData = response.responseBodyData else {
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
            guard !error.isNetworkConnectivityFailure else {
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
                return self.updateGroupV2(
                    groupId: groupModelV2.groupId,
                    groupSecretParamsData: groupModelV2.secretParamsData
                ) { groupChangeSet in
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

        return firstly(on: .global()) { () -> Promise<HTTPResponse> in
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
                                              behavior400: .fail,
                                              behavior403: .reportInvalidOrBlockedGroupLink,
                                              behavior404: .fail)
        }.then(on: .global()) { (response: HTTPResponse) -> Promise<TSGroupThread> in
            guard let changeActionsProtoData = response.responseBodyData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            // The PATCH request that adds us to the group (as a full or requesting member)
            // only return the "change actions" proto data, but not a full snapshot
            // so we need to separately GET the latest group state and update the database.
            //
            // Download and update database with the group state.
            return firstly {
                self.groupV2UpdatesImpl.tryToRefreshV2GroupUpToCurrentRevisionImmediately(groupId: groupId,
                                                                                          groupSecretParamsData: groupV2Params.groupSecretParamsData,
                                                                                          groupModelOptions: .didJustAddSelfViaGroupLink)
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
                let newGroupModel = try builder.build()

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
                builder.descriptionText = groupInviteLinkPreview.descriptionText
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

                let groupModel = try builder.build()
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
        }.then(on: .global()) { (groupInviteLinkPreview: GroupInviteLinkPreview) -> Promise<(GroupInviteLinkPreview, ExpiringProfileKeyCredential)> in

            guard !groupInviteLinkPreview.isLocalUserRequestingMember else {
                // Use the current revision when creating a placeholder group.
                revisionForPlaceholderModel.set(groupInviteLinkPreview.revision)
                throw GroupsV2Error.localUserIsAlreadyRequestingMember
            }

            return firstly(on: .global()) { () -> Promise<ProfileKeyCredentialMap> in
                self.loadProfileKeyCredentials(for: [localUuid], forceRefresh: false)
            }.map(on: .global()) { (profileKeyCredentialMap: ProfileKeyCredentialMap) -> (GroupInviteLinkPreview, ExpiringProfileKeyCredential) in
                guard let localProfileKeyCredential = profileKeyCredentialMap[localUuid] else {
                    throw OWSAssertionError("Missing localProfileKeyCredential.")
                }
                return (groupInviteLinkPreview, localProfileKeyCredential)
            }
        }.map(on: .global()) { (groupInviteLinkPreview: GroupInviteLinkPreview, localProfileKeyCredential: ExpiringProfileKeyCredential) -> GroupsProtoGroupChangeActions in
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

        return firstly(on: .global()) { () -> Promise<UInt32?> in
            self.cancelMemberRequestsUsingPatch(
                groupId: groupModel.groupId,
                groupV2Params: groupV2Params,
                inviteLinkPassword: groupModel.inviteLinkPassword).map { Optional($0) }
        }.recover(on: .global()) { (error: Error) -> Promise<UInt32?> in
            switch error {
            case GroupsV2Error.localUserBlockedFromJoining, GroupsV2Error.localUserIsNotARequestingMember:
                // In both of these cases, our request has already been removed. We can proceed with updating the model.
                return .value(nil)
            default:
                // Otherwise, we don't recover and let the error propogate
                throw error
            }
        }.map(on: .global()) { (newRevision: UInt32?) -> TSGroupThread in
            try self.updateGroupRemovingMemberRequest(groupId: groupModel.groupId, newRevision: newRevision)
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
            let newGroupModel = try builder.build()

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

    private func cancelMemberRequestsUsingPatch(
        groupId: Data,
        groupV2Params: GroupV2Params,
        inviteLinkPassword: Data?
    ) -> Promise<UInt32> {

        let revisionForPlaceholderModel = AtomicOptional<UInt32>(nil)

        // We re-fetch the GroupInviteLinkPreview with every attempt in order to get the latest:
        //
        // * revision
        // * addFromInviteLinkAccess
        // * local user's request status.
        return firstly {
            self.fetchGroupInviteLinkPreview(inviteLinkPassword: inviteLinkPassword,
                                             groupSecretParamsData: groupV2Params.groupSecretParamsData,
                                             allowCached: false)
        }.then(on: .global()) { (groupInviteLinkPreview: GroupInviteLinkPreview) -> Promise<HTTPResponse> in
            let requestBuilder: RequestBuilder = { (authCredential) in
                return firstly { () -> Promise<GroupsProtoGroupChangeActions> in
                    self.buildChangeActionsProtoToCancelMemberRequest(groupInviteLinkPreview: groupInviteLinkPreview,
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
                                              behavior400: .fail,
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

    public func tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(
        groupModel: TSGroupModelV2,
        removeLocalUserBlock: @escaping (SDSAnyWriteTransaction) -> Void
    ) {
        guard groupModel.isPlaceholderModel else {
            owsFailDebug("Invalid group model.")
            return
        }

        firstly { () -> Promise<GroupInviteLinkPreview> in
            let groupV2Params = try groupModel.groupV2Params()
            return self.fetchGroupInviteLinkPreview(inviteLinkPassword: groupModel.inviteLinkPassword,
                                                    groupSecretParamsData: groupV2Params.groupSecretParamsData,
                                                    allowCached: false)
        }.catch { (error: Error) -> Void in
            switch error {
            case GroupsV2Error.localUserIsNotARequestingMember, GroupsV2Error.localUserBlockedFromJoining:
                // Expected if our request has been cancelled or we're banned. In this
                // scenario, we should remove ourselves from the local group (in which
                // we will be stored as a requesting member).
                Logger.verbose("Error: \(error)")
                self.databaseStorage.write { transaction in
                    removeLocalUserBlock(transaction)
                }
            default:
                owsFailDebug("Error: \(error)")
            }
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
                let newGroupModel = try builder.build()

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

        return firstly { () -> Promise<HTTPResponse> in
            return self.performServiceRequest(requestBuilder: requestBuilder,
                                              groupId: groupModel.groupId,
                                              behavior400: .fail,
                                              behavior403: .fetchGroupUpdates,
                                              behavior404: .fail)
        }.map(on: .global()) { (response: HTTPResponse) -> GroupsProtoGroupExternalCredential in
            guard let groupProtoData = response.responseBodyData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            return try GroupsProtoGroupExternalCredential(serializedData: groupProtoData)
        }
    }

    // MARK: - Migration

    public func updateAlreadyMigratedGroupIfNecessary(v2GroupId: Data) -> Promise<Void> {
        GroupsV2Migration.updateAlreadyMigratedGroupIfNecessary(v2GroupId: v2GroupId)
    }
}

fileprivate extension OWSHttpHeaders {
    private static let forbiddenKey: String = "X-Signal-Forbidden-Reason"
    private static let forbiddenValue: String = "banned"

    var containsBan: Bool {
        value(forHeader: Self.forbiddenKey) == Self.forbiddenValue
    }
}

// MARK: - What's in the change actions?

private extension GroupsProtoGroupChangeActions {
    var containsProfileKeyCredentials: Bool {
        !addMembers.isEmpty
    }
}
