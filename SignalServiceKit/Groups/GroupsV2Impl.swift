//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class GroupsV2Impl: GroupsV2, Dependencies {
    private var urlSession: OWSURLSessionProtocol {
        return self.signalService.urlSessionForStorageService()
    }

    private let authCredentialStore: AuthCredentialStore
    private let authCredentialManager: any AuthCredentialManager

    init(
        authCredentialStore: AuthCredentialStore,
        authCredentialManager: any AuthCredentialManager
    ) {
        self.authCredentialStore = authCredentialStore
        self.authCredentialManager = authCredentialManager

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                return
            }

            Task {
                do {
                    try await GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
                } catch {
                    Logger.warn("Local profile update failed with error: \(error)")
                }
            }
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Self.enqueueRestoreGroupPass(authedAccount: .implicit())
        }

        observeNotifications()
    }

    // MARK: - Notifications

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reachabilityChanged),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
    }

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()

        Self.enqueueRestoreGroupPass(authedAccount: .implicit())
    }

    @objc
    private func reachabilityChanged() {
        AssertIsOnMainThread()

        Self.enqueueRestoreGroupPass(authedAccount: .implicit())
    }

    // MARK: - Create Group

    public func createNewGroupOnService(
        groupModel: TSGroupModelV2,
        disappearingMessageToken: DisappearingMessageToken
    ) async throws {
        let groupV2Params = try groupModel.groupV2Params()

        do {
            let groupProto = try await self.buildProtoToCreateNewGroupOnService(
                groupModel: groupModel,
                disappearingMessageToken: disappearingMessageToken,
                groupV2Params: groupV2Params
            )
            let requestBuilder: RequestBuilder = { authCredential -> GroupsV2Request in
                return try StorageService.buildNewGroupRequest(
                    groupProto: groupProto,
                    groupV2Params: groupV2Params,
                    authCredential: authCredential
                )
            }

            // New-group protos contain a profile key credential for each
            // member. If the proto we're submitting contains a profile key
            // credential that's expired, we'll get back a generic 400.
            // Consequently, if we get a 400 we should attempt to recover
            // (see below).

            _ = try await performServiceRequest(
                requestBuilder: requestBuilder,
                groupId: nil,
                behavior400: .reportForRecovery,
                behavior403: .fail,
                behavior404: .fail
            )
        } catch {
            guard case GroupsV2Error.serviceRequestHitRecoverable400 = error else {
                throw error
            }

            // We likely failed to create the group because one of the profile
            // key credentials we submitted was expired, possibly due to drift
            // between our local clock and the service. We should try again
            // exactly once, forcing a refresh of all the credentials first.

            let groupProto = try await buildProtoToCreateNewGroupOnService(
                groupModel: groupModel,
                disappearingMessageToken: disappearingMessageToken,
                groupV2Params: groupV2Params,
                shouldForceRefreshProfileKeyCredentials: true
            )

            let requestBuilder: RequestBuilder = { authCredential -> GroupsV2Request in
                return try StorageService.buildNewGroupRequest(
                    groupProto: groupProto,
                    groupV2Params: groupV2Params,
                    authCredential: authCredential
                )
            }

            _ = try await performServiceRequest(
                requestBuilder: requestBuilder,
                groupId: nil,
                behavior400: .fail,
                behavior403: .fail,
                behavior404: .fail
            )
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
    ) async throws -> GroupsProtoGroup {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            throw OWSAssertionError("Missing localAci.")
        }

        // Gather the ACIs for all full (not invited) members, and get profile key
        // credentials for them. By definition, we cannot get a PKC for the invited
        // members.
        let acis: [Aci] = groupModel.groupMembers.compactMap { address in
            guard let aci = address.aci else {
                owsFailDebug("Address of full member in new group missing ACI.")
                return nil
            }
            return aci
        }

        guard acis.contains(localAci) else {
            throw OWSAssertionError("localUuid is not a member.")
        }

        let profileKeyCredentialMap = try await loadProfileKeyCredentials(
            for: acis,
            forceRefresh: shouldForceRefreshProfileKeyCredentials
        )
        return try GroupsV2Protos.buildNewGroupProto(
            groupModel: groupModel,
            disappearingMessageToken: disappearingMessageToken,
            groupV2Params: groupV2Params,
            profileKeyCredentialMap: profileKeyCredentialMap,
            localAci: localAci
        )
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
    private func updateExistingGroupOnService(changes: GroupsV2OutgoingChanges) async throws -> TSGroupThread {

        let groupId = changes.groupId
        let groupV2Params = try GroupV2Params(groupSecretParams: changes.groupSecretParams)

        var builtGroupChange: GroupsV2BuiltGroupChange
        let httpResponse: HTTPResponse
        do {
            (builtGroupChange, httpResponse) = try await buildGroupChangeProtoAndTryToUpdateGroupOnService(
                groupId: groupId,
                groupV2Params: groupV2Params,
                changes: changes
            )
        } catch {
            switch error {
            case GroupsV2Error.conflictingChangeOnService:
                // If we failed because a conflicting change has already been
                // committed to the service, we should refresh our local state
                // for the group and try again to apply our changes.

                _ = try await groupV2Updates.tryToRefreshV2GroupUpToCurrentRevisionImmediately(
                    groupId: groupId,
                    groupSecretParams: groupV2Params.groupSecretParams
                )

                (builtGroupChange, httpResponse) = try await buildGroupChangeProtoAndTryToUpdateGroupOnService(
                    groupId: groupId,
                    groupV2Params: groupV2Params,
                    changes: changes
                )
            case GroupsV2Error.serviceRequestHitRecoverable400:
                // We likely got the 400 because we submitted a proto with
                // profile key credentials and one of them was expired, possibly
                // due to drift between our local clock and the service. We
                // should try again exactly once, forcing a refresh of all the
                // credentials first.

                (builtGroupChange, httpResponse) = try await buildGroupChangeProtoAndTryToUpdateGroupOnService(
                    groupId: groupId,
                    groupV2Params: groupV2Params,
                    changes: changes,
                    shouldForceRefreshProfileKeyCredentials: true,
                    forceFailOn400: true
                )
            default:
                throw error
            }
        }

        guard let responseBodyData = httpResponse.responseBodyData else {
            throw OWSAssertionError("Missing data in response body!")
        }

        return try await handleGroupUpdatedOnService(
            responseBodyData: responseBodyData,
            builtGroupChange: builtGroupChange,
            changes: changes,
            groupId: groupId,
            groupV2Params: groupV2Params
        )
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
    ) async throws -> (GroupsV2BuiltGroupChange, HTTPResponse) {
        let (groupThread, dmToken) = try NSObject.databaseStorage.read { tx in
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: tx) else {
                throw OWSAssertionError("Thread does not exist.")
            }

            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let dmConfiguration = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: tx.asV2Read)

            return (groupThread, dmConfiguration.asToken)
        }

        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group model.")
        }

        let builtGroupChange = try await changes.buildGroupChangeProto(
            currentGroupModel: groupModel,
            currentDisappearingMessageToken: dmToken,
            forceRefreshProfileKeyCredentials: shouldForceRefreshProfileKeyCredentials
        ).awaitable()

        var behavior400: Behavior400 = .fail
        if
            !forceFailOn400,
            builtGroupChange.proto.containsProfileKeyCredentials
        {
            // If the proto we're submitting contains a profile key credential
            // that's expired, we'll get back a generic 400. Consequently, if
            // we're submitting a proto with PKCs, and we get a 400, we should
            // attempt to recover.

            behavior400 = .reportForRecovery
        }

        let requestBuilder: RequestBuilder = { authCredential in
            return try StorageService.buildUpdateGroupRequest(
                groupChangeProto: builtGroupChange.proto,
                groupV2Params: groupV2Params,
                authCredential: authCredential,
                groupInviteLinkPassword: nil
            )
        }

        let response = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: groupId,
            behavior400: behavior400,
            behavior403: .fetchGroupUpdates,
            behavior404: .fail
        )

        return (builtGroupChange, response)
    }

    private func handleGroupUpdatedOnService(
        responseBodyData: Data,
        builtGroupChange: GroupsV2BuiltGroupChange,
        changes: GroupsV2OutgoingChanges,
        groupId: Data,
        groupV2Params: GroupV2Params
    ) async throws -> TSGroupThread {
        let changeActionsProto = try GroupsV2Protos.parseAndVerifyChangeActionsProto(
            responseBodyData,
            ignoreSignature: true
        )

        // Collect avatar state from our change set so that we can
        // avoid downloading any avatars we just uploaded while
        // applying the change set locally.
        let downloadedAvatars = GroupV2DownloadedAvatars.from(changes: changes)

        // We can ignoreSignature because these protos came from the service.
        let groupThread = try await updateGroupWithChangeActions(
            groupId: groupId,
            spamReportingMetadata: .learnedByLocallyInitatedRefresh,
            changeActionsProto: changeActionsProto,
            justUploadedAvatars: downloadedAvatars,
            ignoreSignature: true,
            groupV2Params: groupV2Params
        )
        let updatedV2Group = UpdatedV2Group(groupThread: groupThread, changeActionsProtoData: responseBodyData)

        switch builtGroupChange.groupUpdateMessageBehavior {
        case .sendNothing:
            return updatedV2Group.groupThread
        case .sendUpdateToOtherGroupMembers:
            break
        }

        await GroupManager.sendGroupUpdateMessage(
            thread: updatedV2Group.groupThread,
            changeActionsProtoData: updatedV2Group.changeActionsProtoData
        )

        await sendGroupUpdateMessageToRemovedUsers(
            groupThread: updatedV2Group.groupThread,
            groupChangeProto: builtGroupChange.proto,
            changeActionsProtoData: updatedV2Group.changeActionsProtoData,
            groupV2Params: groupV2Params
        )

        return updatedV2Group.groupThread
    }

    private func membersRemovedByChangeActions(
        groupChangeProto: GroupsProtoGroupChangeActions,
        groupV2Params: GroupV2Params
    ) -> [ServiceId] {
        var serviceIds = [ServiceId]()
        for action in groupChangeProto.deleteMembers {
            guard let userId = action.deletedUserID else {
                owsFailDebug("Missing userID.")
                continue
            }
            do {
                serviceIds.append(try groupV2Params.aci(for: userId))
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        for action in groupChangeProto.deletePendingMembers {
            guard let userId = action.deletedUserID else {
                owsFailDebug("Missing userID.")
                continue
            }
            do {
                serviceIds.append(try groupV2Params.serviceId(for: userId))
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        for action in groupChangeProto.deleteRequestingMembers {
            guard let userId = action.deletedUserID else {
                owsFailDebug("Missing userID.")
                continue
            }
            do {
                serviceIds.append(try groupV2Params.aci(for: userId))
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        return serviceIds
    }

    private func sendGroupUpdateMessageToRemovedUsers(
        groupThread: TSGroupThread,
        groupChangeProto: GroupsProtoGroupChangeActions,
        changeActionsProtoData: Data,
        groupV2Params: GroupV2Params
    ) async {
        let serviceIds = membersRemovedByChangeActions(groupChangeProto: groupChangeProto, groupV2Params: groupV2Params)

        guard !serviceIds.isEmpty else {
            return
        }

        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid groupModel.")
            return
        }

        let plaintextData: Data
        do {
            let groupV2Context = try GroupsV2Protos.buildGroupContextV2Proto(
                groupModel: groupModel,
                changeActionsProtoData: changeActionsProtoData
            )

            let dataBuilder = SSKProtoDataMessage.builder()
            dataBuilder.setGroupV2(groupV2Context)
            dataBuilder.setRequiredProtocolVersion(1)

            let dataProto = try dataBuilder.build()
            let contentBuilder = SSKProtoContent.builder()
            contentBuilder.setDataMessage(dataProto)
            plaintextData = try contentBuilder.buildSerializedData()
        } catch {
            owsFailDebug("Error: \(error)")
            return
        }

        await databaseStorage.awaitableWrite { tx in
            for serviceId in serviceIds {
                let address = SignalServiceAddress(serviceId)
                let contactThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: tx)
                let message = OWSStaticOutgoingMessage(thread: contactThread, plaintextData: plaintextData, transaction: tx)
                let preparedMessage = PreparedOutgoingMessage.preprepared(
                    transientMessageWithoutAttachments: message
                )
                SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
            }
        }
    }

    // This method can process protos from another client, so there's a possibility
    // the serverGuid may be present and can be passed along to record with the update.
    public func updateGroupWithChangeActions(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        ignoreSignature: Bool,
        groupSecretParams: GroupSecretParams
    ) async throws -> TSGroupThread {
        let groupV2Params = try GroupV2Params(groupSecretParams: groupSecretParams)
        return try await _updateGroupWithChangeActions(
            groupId: groupId,
            spamReportingMetadata: spamReportingMetadata,
            changeActionsProto: changeActionsProto,
            justUploadedAvatars: nil,
            ignoreSignature: ignoreSignature,
            groupV2Params: groupV2Params
        )
    }

    private func updateGroupWithChangeActions(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        justUploadedAvatars: GroupV2DownloadedAvatars?,
        ignoreSignature: Bool,
        groupV2Params: GroupV2Params
    ) async throws -> TSGroupThread {
        return try await _updateGroupWithChangeActions(
            groupId: groupId,
            spamReportingMetadata: spamReportingMetadata,
            changeActionsProto: changeActionsProto,
            justUploadedAvatars: justUploadedAvatars,
            ignoreSignature: ignoreSignature,
            groupV2Params: groupV2Params
        )
    }

    private func _updateGroupWithChangeActions(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        justUploadedAvatars: GroupV2DownloadedAvatars?,
        ignoreSignature: Bool,
        groupV2Params: GroupV2Params
    ) async throws -> TSGroupThread {
        let downloadedAvatars = try await fetchAllAvatarData(
            changeActionsProto: changeActionsProto,
            justUploadedAvatars: justUploadedAvatars,
            ignoreSignature: ignoreSignature,
            groupV2Params: groupV2Params
        )
        return try await NSObject.databaseStorage.awaitableWrite { tx in
            try self.groupV2Updates.updateGroupWithChangeActions(
                groupId: groupId,
                spamReportingMetadata: spamReportingMetadata,
                changeActionsProto: changeActionsProto,
                downloadedAvatars: downloadedAvatars,
                transaction: tx
            )
        }
    }

    // MARK: - Upload Avatar

    public func uploadGroupAvatar(
        avatarData: Data,
        groupSecretParams: GroupSecretParams
    ) async throws -> String {
        let groupV2Params = try GroupV2Params(groupSecretParams: groupSecretParams)
        return try await uploadGroupAvatar(avatarData: avatarData, groupV2Params: groupV2Params)
    }

    private func uploadGroupAvatar(
        avatarData: Data,
        groupV2Params: GroupV2Params
    ) async throws -> String {

        let requestBuilder: RequestBuilder = { (authCredential) in
            try StorageService.buildGroupAvatarUploadFormRequest(
                groupV2Params: groupV2Params,
                authCredential: authCredential
            )
        }

        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier().serialize().asData
        let response = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: groupId,
            behavior400: .fail,
            behavior403: .fetchGroupUpdates,
            behavior404: .fail
        )

        guard let protoData = response.responseBodyData else {
            throw OWSAssertionError("Invalid responseObject.")
        }
        let avatarUploadAttributes = try GroupsProtoAvatarUploadAttributes(serializedData: protoData)
        let uploadForm = try Upload.CDN0.Form.parse(proto: avatarUploadAttributes)
        let encryptedData = try groupV2Params.encryptGroupAvatar(avatarData)
        return try await Upload.CDN0.upload(data: encryptedData, uploadForm: uploadForm)
    }

    // MARK: - Fetch Current Group State

    public func fetchCurrentGroupV2Snapshot(groupModel: TSGroupModelV2) async throws -> GroupV2Snapshot {
        // Collect the avatar state to avoid an unnecessary download in the
        // case where we've just created this group but not yet inserted it
        // into the database.
        let justUploadedAvatars = GroupV2DownloadedAvatars.from(groupModel: groupModel)
        return try await fetchCurrentGroupV2Snapshot(
            groupSecretParams: try groupModel.secretParams(),
            justUploadedAvatars: justUploadedAvatars
        )
    }

    public func fetchCurrentGroupV2Snapshot(groupSecretParams: GroupSecretParams) async throws -> GroupV2Snapshot {
        return try await fetchCurrentGroupV2Snapshot(
            groupSecretParams: groupSecretParams,
            justUploadedAvatars: nil
        )
    }

    private func fetchCurrentGroupV2Snapshot(
        groupSecretParams: GroupSecretParams,
        justUploadedAvatars: GroupV2DownloadedAvatars?
    ) async throws -> GroupV2Snapshot {
        let groupV2Params = try GroupV2Params(groupSecretParams: groupSecretParams)
        return try await fetchCurrentGroupV2Snapshot(groupV2Params: groupV2Params, justUploadedAvatars: justUploadedAvatars)
    }

    private func fetchCurrentGroupV2Snapshot(
        groupV2Params: GroupV2Params,
        justUploadedAvatars: GroupV2DownloadedAvatars?
    ) async throws -> GroupV2Snapshot {
        let requestBuilder: RequestBuilder = { (authCredential) in
            try StorageService.buildFetchCurrentGroupV2SnapshotRequest(
                groupV2Params: groupV2Params,
                authCredential: authCredential
            )
        }

        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier().serialize().asData
        let response = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: groupId,
            behavior400: .fail,
            behavior403: .removeFromGroup,
            behavior404: .groupDoesNotExistOnService
        )

        guard let groupProtoData = response.responseBodyData else {
            throw OWSAssertionError("Invalid responseObject.")
        }

        let groupProto = try GroupsProtoGroup(serializedData: groupProtoData)

        // We can ignoreSignature; these protos came from the service.
        let downloadedAvatars = try await fetchAllAvatarData(
            groupProto: groupProto,
            justUploadedAvatars: justUploadedAvatars,
            ignoreSignature: true,
            groupV2Params: groupV2Params
        )

        return try GroupsV2Protos.parse(groupProto: groupProto, downloadedAvatars: downloadedAvatars, groupV2Params: groupV2Params)
    }

    // MARK: - Fetch Group Change Actions

    func fetchGroupChangeActions(
        groupSecretParams: GroupSecretParams,
        includeCurrentRevision: Bool
    ) async throws -> GroupChangePage {
        let groupV2Params = try GroupV2Params(groupSecretParams: groupSecretParams)
        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier().serialize().asData
        return try await fetchGroupChangeActions(
            groupId: groupId,
            groupV2Params: groupV2Params,
            includeCurrentRevision: includeCurrentRevision
        )
    }

    struct GroupChangePage {
        let changes: [GroupV2Change]
        let earlyEnd: UInt32?

        fileprivate static func parseEarlyEnd(fromGroupRangeHeader header: String?) -> UInt32? {
            guard let header = header else {
                Logger.warn("Missing Content-Range for group update request with 206 response")
                return nil
            }

            let pattern = try! NSRegularExpression(pattern: #"^versions (\d+)-(\d+)/(\d+)$"#)
            guard let match = pattern.firstMatch(in: header, range: header.entireRange) else {
                Logger.warn("Unparsable Content-Range for group update request: \(header)")
                return nil
            }

            guard let earlyEndRange = Range(match.range(at: 1), in: header) else {
                owsFailDebug("Could not translate NSRange to Range<String.Index>")
                return nil
            }

            guard let earlyEndValue = UInt32(header[earlyEndRange]) else {
                Logger.warn("Invalid early-end in Content-Range for group update request: \(header)")
                return nil
            }

            return earlyEndValue
        }
    }

    private func fetchGroupChangeActions(
        groupId: Data,
        groupV2Params: GroupV2Params,
        includeCurrentRevision: Bool
    ) async throws -> GroupChangePage {
        let groupThread = NSObject.databaseStorage.read { transaction in
            TSGroupThread.fetch(groupId: groupId, transaction: transaction)
        }

        let fromRevision: UInt32
        let requireSnapshotForFirstChange: Bool

        if
            let groupThread = groupThread,
            let groupModel = groupThread.groupModel as? TSGroupModelV2,
            groupModel.groupMembership.isLocalUserFullOrInvitedMember
        {
            // We're being told about a group we are aware of and are
            // already a member of. In this case, we can figure out which
            // revision we want to start with from local data.

            if includeCurrentRevision {
                fromRevision = groupModel.revision
                requireSnapshotForFirstChange = true
            } else {
                fromRevision = groupModel.revision + 1
                requireSnapshotForFirstChange = false
            }
        } else {
            // We're being told about a thread we either have never heard
            // of, or don't yet know we're a member of. In this case, we
            // need to ask the service which revision we joined at, and
            // request revisions from there. We should also get the
            // snapshot, since there may be revisions we were not in the
            // group to witness, and we want to make sure that state is
            // reflected.

            fromRevision = try await getRevisionLocalUserWasAddedToGroup(groupId: groupId, groupV2Params: groupV2Params)
            requireSnapshotForFirstChange = true
        }

        let fetchGroupChangesRequestBuilder: RequestBuilder = { authCredential in
            return try StorageService.buildFetchGroupChangeActionsRequest(
                groupV2Params: groupV2Params,
                fromRevision: fromRevision,
                requireSnapshotForFirstChange: requireSnapshotForFirstChange,
                authCredential: authCredential
            )
        }

        // At this stage, we know we are requesting for a revision at which
        // we are a member. Therefore, 403s should be treated as failure.
        let response = try await performServiceRequest(
            requestBuilder: fetchGroupChangesRequestBuilder,
            groupId: groupId,
            behavior400: .fail,
            behavior403: .fail,
            behavior404: .fail
        )
        guard let groupChangesProtoData = response.responseBodyData else {
            throw OWSAssertionError("Invalid responseObject.")
        }
        let earlyEnd: UInt32?
        if response.responseStatusCode == 206 {
            let groupRangeHeader = response.responseHeaders["content-range"]
            earlyEnd = GroupChangePage.parseEarlyEnd(fromGroupRangeHeader: groupRangeHeader)
        } else {
            earlyEnd = nil
        }
        let groupChangesProto = try GroupsProtoGroupChanges(serializedData: groupChangesProtoData)

        // We can ignoreSignature; these protos came from the service.
        let downloadedAvatars = try await fetchAllAvatarData(
            groupChangesProto: groupChangesProto,
            ignoreSignature: true,
            groupV2Params: groupV2Params
        )
        let changes = try GroupsV2Protos.parseChangesFromService(
            groupChangesProto: groupChangesProto,
            downloadedAvatars: downloadedAvatars,
            groupV2Params: groupV2Params
        )
        return GroupChangePage(changes: changes, earlyEnd: earlyEnd)
    }

    private func getRevisionLocalUserWasAddedToGroup(
        groupId: Data,
        groupV2Params: GroupV2Params
    ) async throws -> UInt32 {
        let getJoinedAtRevisionRequestBuilder: RequestBuilder = { authCredential in
            try StorageService.buildGetJoinedAtRevisionRequest(
                groupV2Params: groupV2Params,
                authCredential: authCredential
            )
        }

        // We might get a 403 if we are not a member of the group, e.g. if
        // we are joining via invite link. Passing .ignore means we won't
        // retry, and will allow the "not a member" error to be thrown and
        // propagated upwards.
        let response = try await performServiceRequest(
            requestBuilder: getJoinedAtRevisionRequestBuilder,
            groupId: groupId,
            behavior400: .fail,
            behavior403: .ignore,
            behavior404: .fail
        )

        guard let memberData = response.responseBodyData else {
            throw OWSAssertionError("Response missing body data")
        }

        let memberProto = try GroupsProtoMember(serializedData: memberData)

        return memberProto.joinedAtRevision
    }

    // MARK: - Avatar Downloads

    // Before we can apply snapshots/changes from the service, we
    // need to download all avatars they use.  We can skip downloads
    // in a couple of cases:
    //
    // * We just created the group.
    // * We just updated the group and we're applying those changes.
    private func fetchAllAvatarData(
        groupProto: GroupsProtoGroup? = nil,
        groupChangesProto: GroupsProtoGroupChanges? = nil,
        changeActionsProto: GroupsProtoGroupChangeActions? = nil,
        justUploadedAvatars: GroupV2DownloadedAvatars? = nil,
        ignoreSignature: Bool,
        groupV2Params: GroupV2Params
    ) async throws -> GroupV2DownloadedAvatars {

        var downloadedAvatars = GroupV2DownloadedAvatars()

        // Creating or updating a group is a multi-step process
        // that can involve uploading an avatar, updating the
        // group on the service, then updating the local database.
        // We can skip downloading an avatar that we just uploaded
        // using justUploadedAvatars.
        if let justUploadedAvatars = justUploadedAvatars {
            downloadedAvatars.merge(justUploadedAvatars)
        }

        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier().serialize().asData

        // First step - try to skip downloading the current group avatar.
        if
            let groupThread = (NSObject.databaseStorage.read { transaction in
                return TSGroupThread.fetch(groupId: groupId, transaction: transaction)
            }),
            let groupModel = groupThread.groupModel as? TSGroupModelV2
        {
            // Try to add avatar from group model, if any.
            downloadedAvatars.merge(GroupV2DownloadedAvatars.from(groupModel: groupModel))
        }

        let protoAvatarUrlPaths = try await GroupsV2Protos.collectAvatarUrlPaths(
            groupProto: groupProto,
            groupChangesProto: groupChangesProto,
            changeActionsProto: changeActionsProto,
            ignoreSignature: ignoreSignature,
            groupV2Params: groupV2Params
        ).awaitable()

        return try await fetchAvatarData(
            avatarUrlPaths: protoAvatarUrlPaths,
            downloadedAvatars: downloadedAvatars,
            groupV2Params: groupV2Params
        )
    }

    private func fetchAvatarData(
        avatarUrlPaths: [String],
        downloadedAvatars: GroupV2DownloadedAvatars,
        groupV2Params: GroupV2Params
    ) async throws -> GroupV2DownloadedAvatars {
        var downloadedAvatars = downloadedAvatars

        let undownloadedAvatarUrlPaths = Set(avatarUrlPaths).subtracting(downloadedAvatars.avatarUrlPaths)

        try await withThrowingTaskGroup(of: (String, Data).self) { taskGroup in
            // We need to "populate" any group changes that have a
            // avatar with the avatar data.
            for avatarUrlPath in undownloadedAvatarUrlPaths {
                taskGroup.addTask {
                    var avatarData: Data
                    do {
                        avatarData = try await self.fetchAvatarData(
                            avatarUrlPath: avatarUrlPath,
                            groupV2Params: groupV2Params
                        )
                    } catch OWSURLSessionError.responseTooLarge {
                        avatarData = Data()
                    } catch where error.httpStatusCode == 404 {
                        // Fulfill with empty data if service returns 404 status code.
                        // We don't want the group to be left in an unrecoverable state
                        // if the avatar is missing from the CDN.
                        avatarData = Data()
                    }
                    if !avatarData.isEmpty {
                        avatarData = (try? groupV2Params.decryptGroupAvatar(avatarData)) ?? Data()
                    }
                    return (avatarUrlPath, avatarData)
                }
            }
            while let (avatarUrlPath, avatarData) = try await taskGroup.next() {
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
        }

        return downloadedAvatars
    }

    let avatarDownloadQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "AvatarDownload"
        operationQueue.maxConcurrentOperationCount = 3
        return operationQueue
    }()

    private func fetchAvatarData(
        avatarUrlPath: String,
        groupV2Params: GroupV2Params
    ) async throws -> Data {
        // We throw away decrypted avatars larger than `kMaxEncryptedAvatarSize`.
        let operation = GroupsV2AvatarDownloadOperation(
            urlPath: avatarUrlPath,
            maxDownloadSize: kMaxEncryptedAvatarSize
        )
        let promise = operation.promise
        avatarDownloadQueue.addOperation(operation)
        return try await promise.awaitable()
    }

    // MARK: - Generic Group Change

    public func updateGroupV2(
        groupId: Data,
        groupSecretParams: GroupSecretParams,
        changesBlock: (GroupsV2OutgoingChanges) -> Void
    ) async throws -> TSGroupThread {
        let changes = GroupsV2OutgoingChangesImpl(
            groupId: groupId,
            groupSecretParams: groupSecretParams
        )
        changesBlock(changes)
        return try await updateExistingGroupOnService(changes: changes)
    }

    // MARK: - Rotate Profile Key

    private let profileKeyUpdater = GroupsV2ProfileKeyUpdater()

    public func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: SDSAnyWriteTransaction) {
        profileKeyUpdater.scheduleAllGroupsV2ForProfileKeyUpdate(transaction: transaction)
    }

    public func processProfileKeyUpdates() {
        profileKeyUpdater.processProfileKeyUpdates()
    }

    public func updateLocalProfileKeyInGroup(groupId: Data, transaction: SDSAnyWriteTransaction) {
        profileKeyUpdater.updateLocalProfileKeyInGroup(groupId: groupId, transaction: transaction)
    }

    // MARK: - Perform Request

    private typealias RequestBuilder = (AuthCredentialWithPni) async throws -> GroupsV2Request

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
    ) async throws -> HTTPResponse {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            throw OWSAssertionError("Missing localIdentifiers.")
        }

        let authCredential = try await authCredentialManager.fetchGroupAuthCredential(localIdentifiers: localIdentifiers)
        let request = try await requestBuilder(authCredential)

        do {
            return try await performServiceRequestAttempt(request: request)
        } catch {
            let retryIfPossible = { (error: Error) async throws -> HTTPResponse in
                if remainingRetries > 0 {
                    return try await self.performServiceRequest(
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

            return try await self.tryRecoveryFromServiceRequestFailure(
                error: error,
                retryBlock: retryIfPossible,
                groupId: groupId,
                behavior400: behavior400,
                behavior403: behavior403,
                behavior404: behavior404
            )
        }
    }

    /// Upon error from performing a service request, attempt to recover based
    /// on the error and our 4XX behaviors.
    private func tryRecoveryFromServiceRequestFailure(
        error: Error,
        retryBlock: (Error) async throws -> HTTPResponse,
        groupId: Data?,
        behavior400: Behavior400,
        behavior403: Behavior403,
        behavior404: Behavior404
    ) async throws -> HTTPResponse {
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
                await self.databaseStorage.awaitableWrite { tx in
                    self.authCredentialStore.removeAllGroupAuthCredentials(tx: tx.asV2Write)
                }
                return try await retryBlock(error)
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
                    await self.databaseStorage.awaitableWrite { transaction in
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
            return try await retryBlock(error)
        } else {
            // Unexpected error.
            throw error
        }
    }

    private func performServiceRequestAttempt(request: GroupsV2Request) async throws -> HTTPResponse {

        let urlSession = self.urlSession
        urlSession.failOnError = false

        Logger.info("Making group request: \(request.method) \(request.urlString)")

        do {
            let response = try await urlSession.dataTaskPromise(
                request.urlString,
                method: request.method,
                headers: request.headers.headers,
                body: request.bodyData
            ).awaitable()

            let statusCode = response.responseStatusCode
            let hasValidStatusCode = [200, 206].contains(statusCode)
            guard hasValidStatusCode else {
                throw OWSAssertionError("Invalid status code: \(statusCode)")
            }

            // NOTE: responseObject may be nil; not all group v2 responses have bodies.
            Logger.info("Request succeeded: \(request.method) \(request.urlString)")

            return response
        } catch {
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
        let groupSecretParamsData = groupModelV2.secretParamsData
        Task {
            do {
                _ = try await self.groupV2Updates.tryToRefreshV2GroupThread(
                    groupId: groupId,
                    spamReportingMetadata: .learnedByLocallyInitatedRefresh,
                    groupSecretParams: try GroupSecretParams(contents: [UInt8](groupSecretParamsData)),
                    groupUpdateMode: groupUpdateMode
                )
            } catch {
                if case GroupsV2Error.localUserNotInGroup = error {
                    Logger.warn("Error: \(error)")
                } else {
                    owsFailDebugUnlessNetworkFailure(error)
                }
            }
        }
    }

    // MARK: - ProfileKeyCredentials

    /// Fetches and returnes the profile key credential for each passed ACI. If
    /// any are missing, returns an error.
    public func loadProfileKeyCredentials(
        for acis: [Aci],
        forceRefresh: Bool
    ) async throws -> ProfileKeyCredentialMap {
        try await tryToFetchProfileKeyCredentials(
            for: acis,
            ignoreMissingProfiles: false,
            forceRefresh: forceRefresh
        )

        let acis = Set(acis)

        let credentialMap = self.loadPresentProfileKeyCredentials(for: acis)

        guard acis.symmetricDifference(credentialMap.keys).isEmpty else {
            throw OWSAssertionError("Missing requested keys from credential map!")
        }

        return credentialMap
    }

    /// Makes a best-effort to fetch the profile key credential for each passed
    /// ACI. If a profile exists for the user but the credential cannot be
    /// fetched (e.g., the ACI is not a contact of ours), skips it. Optionally
    /// ignores "missing profile" errors during fetch.
    public func tryToFetchProfileKeyCredentials(
        for acis: [Aci],
        ignoreMissingProfiles: Bool,
        forceRefresh: Bool
    ) async throws {
        let acis = Set(acis)

        let acisToFetch: Set<Aci>
        if forceRefresh {
            acisToFetch = acis
        } else {
            acisToFetch = acis.subtracting(loadPresentProfileKeyCredentials(for: acis).keys)
        }

        let profileFetcher = SSKEnvironment.shared.profileFetcherRef

        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for aciToFetch in acisToFetch {
                taskGroup.addTask {
                    do {
                        _ = try await profileFetcher.fetchProfile(for: aciToFetch)
                    } catch ProfileRequestError.notFound where ignoreMissingProfiles {
                        // this is fine
                    }
                }
            }
            try await taskGroup.waitForAll()
        }
    }

    private func loadPresentProfileKeyCredentials(for acis: Set<Aci>) -> ProfileKeyCredentialMap {
        databaseStorage.read { transaction in
            var credentialMap = ProfileKeyCredentialMap()

            for aci in acis {
                do {
                    if let credential = try self.versionedProfilesSwift.validProfileKeyCredential(
                        for: aci,
                        transaction: transaction
                    ) {
                        credentialMap[aci] = credential
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
            guard let serviceId = address.serviceId else {
                throw OWSAssertionError("Missing ACI.")
            }
            guard let aci = serviceId as? Aci else {
                return false
            }
            return try self.versionedProfilesSwift.validProfileKeyCredential(
                for: aci,
                transaction: transaction
            ) != nil
        } catch let error {
            owsFailDebug("Error getting profile key credential: \(error)")
            return false
        }
    }

    // MARK: - Protos

    public func buildGroupContextV2Proto(groupModel: TSGroupModelV2,
                                         changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2 {
        return try GroupsV2Protos.buildGroupContextV2Proto(groupModel: groupModel, changeActionsProtoData: changeActionsProtoData)
    }

    public func parseAndVerifyChangeActionsProto(_ changeProtoData: Data,
                                                 ignoreSignature: Bool) throws -> GroupsProtoGroupChangeActions {
        return try GroupsV2Protos.parseAndVerifyChangeActionsProto(changeProtoData,
                                                                   ignoreSignature: ignoreSignature)
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
        account: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        GroupsV2Impl.enqueueGroupRestore(groupRecord: groupRecord, account: account, transaction: transaction)
    }

    // MARK: - Group Links

    private let groupInviteLinkPreviewCache = LRUCache<Data, GroupInviteLinkPreview>(maxSize: 5,
                                                                                     shouldEvacuateInBackground: true)

    private func groupInviteLinkPreviewCacheKey(groupSecretParams: GroupSecretParams) -> Data {
        return groupSecretParams.serialize().asData
    }

    public func cachedGroupInviteLinkPreview(groupSecretParams: GroupSecretParams) -> GroupInviteLinkPreview? {
        let cacheKey = groupInviteLinkPreviewCacheKey(groupSecretParams: groupSecretParams)
        return groupInviteLinkPreviewCache.object(forKey: cacheKey)
    }

    // inviteLinkPassword is not necessary if we're already a member or have a pending request.
    public func fetchGroupInviteLinkPreview(
        inviteLinkPassword: Data?,
        groupSecretParams: GroupSecretParams,
        allowCached: Bool
    ) async throws -> GroupInviteLinkPreview {
        let cacheKey = groupInviteLinkPreviewCacheKey(groupSecretParams: groupSecretParams)

        if
            allowCached,
            let groupInviteLinkPreview = groupInviteLinkPreviewCache.object(forKey: cacheKey)
        {
            return groupInviteLinkPreview
        }

        let groupV2Params = try GroupV2Params(groupSecretParams: groupSecretParams)

        let requestBuilder: RequestBuilder = { (authCredential) in
            try StorageService.buildFetchGroupInviteLinkPreviewRequest(
                inviteLinkPassword: inviteLinkPassword,
                groupV2Params: groupV2Params,
                authCredential: authCredential
            )
        }

        do {
            let behavior403: Behavior403 = (
                inviteLinkPassword != nil
                ? .reportInvalidOrBlockedGroupLink
                : .localUserIsNotARequestingMember
            )
            let response = try await performServiceRequest(
                requestBuilder: requestBuilder,
                groupId: nil,
                behavior400: .fail,
                behavior403: behavior403,
                behavior404: .fail
            )
            guard let protoData = response.responseBodyData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            let groupInviteLinkPreview = try GroupsV2Protos.parseGroupInviteLinkPreview(protoData, groupV2Params: groupV2Params)

            groupInviteLinkPreviewCache.setObject(groupInviteLinkPreview, forKey: cacheKey)

            await updatePlaceholderGroupModelUsingInviteLinkPreview(
                groupSecretParams: groupSecretParams,
                isLocalUserRequestingMember: groupInviteLinkPreview.isLocalUserRequestingMember
            )

            return groupInviteLinkPreview
        } catch {
            if case GroupsV2Error.localUserIsNotARequestingMember = error {
                await self.updatePlaceholderGroupModelUsingInviteLinkPreview(
                    groupSecretParams: groupSecretParams,
                    isLocalUserRequestingMember: false
                )
            }
            throw error
        }
    }

    public func fetchGroupInviteLinkAvatar(
        avatarUrlPath: String,
        groupSecretParams: GroupSecretParams
    ) async throws -> Data {
        let groupV2Params = try GroupV2Params(groupSecretParams: groupSecretParams)
        let downloadedAvatars = try await fetchAvatarData(
            avatarUrlPaths: [avatarUrlPath],
            downloadedAvatars: GroupV2DownloadedAvatars(),
            groupV2Params: groupV2Params
        )
        return try downloadedAvatars.avatarData(for: avatarUrlPath)
    }

    public func joinGroupViaInviteLink(
        groupId: Data,
        groupSecretParams: GroupSecretParams,
        inviteLinkPassword: Data,
        groupInviteLinkPreview: GroupInviteLinkPreview,
        avatarData: Data?
    ) async throws -> TSGroupThread {
        let groupV2Params = try GroupV2Params(groupSecretParams: groupSecretParams)
        var remainingRetries = 3
        while true {
            do {
                return try await self.joinGroupViaInviteLinkAttempt(
                    groupId: groupId,
                    inviteLinkPassword: inviteLinkPassword,
                    groupV2Params: groupV2Params,
                    groupInviteLinkPreview: groupInviteLinkPreview,
                    avatarData: avatarData
                )
            } catch where remainingRetries > 0 && error.isNetworkFailureOrTimeout {
                Logger.warn("Retryable after error: \(error)")
                remainingRetries -= 1
            }
        }
    }

    private func joinGroupViaInviteLinkAttempt(
        groupId: Data,
        inviteLinkPassword: Data,
        groupV2Params: GroupV2Params,
        groupInviteLinkPreview: GroupInviteLinkPreview,
        avatarData: Data?
    ) async throws -> TSGroupThread {

        // There are many edge cases around joining groups via invite links.
        //
        // * We might have previously been a member or not.
        // * We might previously have requested to join and been denied.
        // * The group might or might not already exist in the database.
        // * We might already be a full member.
        // * We might already have a pending invite (in which case we should
        //   accept that invite rather than request to join).
        // * The invite link may have been rescinded.

        do {
            // Check if...
            //
            // * We're already in the group.
            // * We already have a pending invite. If so, use it.
            //
            // Note: this will typically fail.
            return try await joinGroupViaInviteLinkUsingAlternateMeans(
                groupId: groupId,
                inviteLinkPassword: inviteLinkPassword,
                groupV2Params: groupV2Params
            )
        } catch {
            guard !error.isNetworkFailureOrTimeout else {
                throw error
            }
            Logger.warn("Error: \(error)")
            return try await self.joinGroupViaInviteLinkUsingPatch(
                groupId: groupId,
                inviteLinkPassword: inviteLinkPassword,
                groupV2Params: groupV2Params,
                groupInviteLinkPreview: groupInviteLinkPreview,
                avatarData: avatarData
            )
        }
    }

    private func joinGroupViaInviteLinkUsingAlternateMeans(
        groupId: Data,
        inviteLinkPassword: Data,
        groupV2Params: GroupV2Params
    ) async throws -> TSGroupThread {

        // First try to fetch latest group state from service.
        // This will fail for users trying to join via group link
        // who are not yet in the group.
        let groupThread = try await groupV2Updates.tryToRefreshV2GroupUpToCurrentRevisionImmediately(
            groupId: groupId,
            groupSecretParams: groupV2Params.groupSecretParams
        )

        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            throw OWSAssertionError("Missing localAci.")
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group model.")
        }
        let groupMembership = groupModelV2.groupMembership
        if groupMembership.isFullMember(localIdentifiers.aci) ||
            groupMembership.isRequestingMember(localIdentifiers.aci) {
            // We're already in the group.
            return groupThread
        } else if groupMembership.isInvitedMember(localIdentifiers.aci) {
            // We're already invited by ACI; try to join by accepting the invite.
            // That will make us a full member; requesting to join via
            // the invite link might make us a requesting member.
            return try await GroupManager.localAcceptInviteToGroupV2(groupModel: groupModelV2)
        } else if
            let pni = localIdentifiers.pni,
            groupMembership.isInvitedMember(pni)
        {
            // We're already invited by PNI; try to join by accepting the invite.
            // That will make us a full member; requesting to join via
            // the invite link might make us a requesting member.
            return try await GroupManager.localAcceptInviteToGroupV2(groupModel: groupModelV2)
        } else {
            throw GroupsV2Error.localUserNotInGroup
        }
    }

    private func joinGroupViaInviteLinkUsingPatch(
        groupId: Data,
        inviteLinkPassword: Data,
        groupV2Params: GroupV2Params,
        groupInviteLinkPreview: GroupInviteLinkPreview,
        avatarData: Data?
    ) async throws -> TSGroupThread {

        let revisionForPlaceholderModel = AtomicOptional<UInt32>(nil, lock: .sharedGlobal)

        let requestBuilder: RequestBuilder = { (authCredential) in
            let groupChangeProto = try await self.buildChangeActionsProtoToJoinGroupLink(
                groupId: groupId,
                inviteLinkPassword: inviteLinkPassword,
                groupV2Params: groupV2Params,
                revisionForPlaceholderModel: revisionForPlaceholderModel
            )
            return try StorageService.buildUpdateGroupRequest(
                groupChangeProto: groupChangeProto,
                groupV2Params: groupV2Params,
                authCredential: authCredential,
                groupInviteLinkPassword: inviteLinkPassword
            )
        }

        do {
            let response = try await performServiceRequest(
                requestBuilder: requestBuilder,
                groupId: groupId,
                behavior400: .fail,
                behavior403: .reportInvalidOrBlockedGroupLink,
                behavior404: .fail
            )

            guard let changeActionsProtoData = response.responseBodyData else {
                throw OWSAssertionError("Invalid responseObject.")
            }
            // The PATCH request that adds us to the group (as a full or requesting member)
            // only return the "change actions" proto data, but not a full snapshot
            // so we need to separately GET the latest group state and update the database.
            //
            // Download and update database with the group state.
            do {
                _ = try await groupV2UpdatesImpl.tryToRefreshV2GroupUpToCurrentRevisionImmediately(
                    groupId: groupId,
                    groupSecretParams: groupV2Params.groupSecretParams,
                    groupModelOptions: .didJustAddSelfViaGroupLink
                )
            } catch {
                throw GroupsV2Error.requestingMemberCantLoadGroupState
            }

            guard let groupThread = NSObject.databaseStorage.read(block: { tx in
                TSGroupThread.fetch(groupId: groupId, transaction: tx)
            }) else {
                throw OWSAssertionError("Missing group thread.")
            }

            await GroupManager.sendGroupUpdateMessage(
                thread: groupThread,
                changeActionsProtoData: changeActionsProtoData
            )
            return groupThread
        } catch {
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

            let groupThread = try await createPlaceholderGroupForJoinRequest(
                groupId: groupId,
                inviteLinkPassword: inviteLinkPassword,
                groupV2Params: groupV2Params,
                groupInviteLinkPreview: groupInviteLinkPreview,
                avatarData: avatarData,
                revisionForPlaceholderModel: revisionForPlaceholderModel
            )

            let isJoinRequestPlaceholder: Bool
            if let groupModel = groupThread.groupModel as? TSGroupModelV2 {
                isJoinRequestPlaceholder = groupModel.isJoinRequestPlaceholder
            } else {
                isJoinRequestPlaceholder = false
            }
            guard !isJoinRequestPlaceholder else {
                // There's no point in sending a group update for a placeholder
                // group, since we don't know who to send it to.
                return groupThread
            }

            await GroupManager.sendGroupUpdateMessage(thread: groupThread, changeActionsProtoData: nil)
            return groupThread
        }
    }

    private func createPlaceholderGroupForJoinRequest(
        groupId: Data,
        inviteLinkPassword: Data,
        groupV2Params: GroupV2Params,
        groupInviteLinkPreview: GroupInviteLinkPreview,
        avatarData: Data?,
        revisionForPlaceholderModel: AtomicOptional<UInt32>
    ) async throws -> TSGroupThread {
        // We might be creating a placeholder for a revision that we just
        // created or for one we learned about from a GroupInviteLinkPreview.
        guard let revision = revisionForPlaceholderModel.get() else {
            throw OWSAssertionError("Missing revisionForPlaceholderModel.")
        }
        return try await databaseStorage.awaitableWrite { (transaction) throws -> TSGroupThread in
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }

            if let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
                // The group already existing in the database; make sure
                // that we are a requesting member.
                guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid groupModel.")
                }
                let oldGroupMembership = oldGroupModel.groupMembership
                if oldGroupModel.revision >= revision && oldGroupMembership.isRequestingMember(localIdentifiers.aci) {
                    // No need to update database, group state is already acceptable.
                    return groupThread
                }
                var builder = oldGroupModel.asBuilder
                builder.isJoinRequestPlaceholder = true
                builder.groupV2Revision = max(revision, oldGroupModel.revision)
                var membershipBuilder = oldGroupMembership.asBuilder
                membershipBuilder.remove(localIdentifiers.aci)
                membershipBuilder.addRequestingMember(localIdentifiers.aci)
                builder.groupMembership = membershipBuilder.build()
                let newGroupModel = try builder.build()

                groupThread.update(with: newGroupModel, transaction: transaction)

                let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                let dmToken = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: transaction.asV2Read).asToken
                GroupManager.insertGroupUpdateInfoMessage(
                    groupThread: groupThread,
                    oldGroupModel: oldGroupModel,
                    newGroupModel: newGroupModel,
                    oldDisappearingMessageToken: dmToken,
                    newDisappearingMessageToken: dmToken,
                    newlyLearnedPniToAciAssociations: [:],
                    groupUpdateSource: .localUser(originalSource: .aci(localIdentifiers.aci)),
                    localIdentifiers: localIdentifiers,
                    spamReportingMetadata: .createdByLocalAction,
                    transaction: transaction
                )

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
                builder.isJoinRequestPlaceholder = true

                // The "group invite link" UI might not have downloaded
                // the avatar. That's fine; this is just a placeholder
                // model.
                if let avatarData = avatarData,
                   let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath {
                    builder.avatarData = avatarData
                    builder.avatarUrlPath = avatarUrlPath
                }

                var membershipBuilder = GroupMembership.Builder()
                membershipBuilder.addRequestingMember(localIdentifiers.aci)
                builder.groupMembership = membershipBuilder.build()

                let groupModel = try builder.buildAsV2()
                let groupThread = DependenciesBridge.shared.threadStore.createGroupThread(
                    groupModel: groupModel, tx: transaction.asV2Write
                )

                let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                let dmToken = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: transaction.asV2Read).asToken
                GroupManager.insertGroupUpdateInfoMessageForNewGroup(
                    localIdentifiers: localIdentifiers,
                    spamReportingMetadata: .createdByLocalAction,
                    groupThread: groupThread,
                    groupModel: groupModel,
                    disappearingMessageToken: dmToken,
                    groupUpdateSource: .localUser(originalSource: .aci(localIdentifiers.aci)),
                    transaction: transaction
                )

                return groupThread
            }
        }
    }

    private func buildChangeActionsProtoToJoinGroupLink(
        groupId: Data,
        inviteLinkPassword: Data,
        groupV2Params: GroupV2Params,
        revisionForPlaceholderModel: AtomicOptional<UInt32>
    ) async throws -> GroupsProtoGroupChangeActions {

        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            throw OWSAssertionError("Missing localAci.")
        }

        // We re-fetch the GroupInviteLinkPreview with every attempt in order to get the latest:
        //
        // * revision
        // * addFromInviteLinkAccess
        // * local user's request status.
        let groupInviteLinkPreview = try await fetchGroupInviteLinkPreview(
            inviteLinkPassword: inviteLinkPassword,
            groupSecretParams: groupV2Params.groupSecretParams,
            allowCached: false
        )

        guard !groupInviteLinkPreview.isLocalUserRequestingMember else {
            // Use the current revision when creating a placeholder group.
            revisionForPlaceholderModel.set(groupInviteLinkPreview.revision)
            throw GroupsV2Error.localUserIsAlreadyRequestingMember
        }

        let profileKeyCredentialMap = try await loadProfileKeyCredentials(for: [localAci], forceRefresh: false)

        guard let localProfileKeyCredential = profileKeyCredentialMap[localAci] else {
            throw OWSAssertionError("Missing localProfileKeyCredential.")
        }

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
            actionBuilder.setAdded(
                try GroupsV2Protos.buildMemberProto(
                    profileKeyCredential: localProfileKeyCredential,
                    role: role.asProtoRole,
                    groupV2Params: groupV2Params
                ))
            actionsBuilder.addAddMembers(actionBuilder.buildInfallibly())
        case .administrator:
            var actionBuilder = GroupsProtoGroupChangeActionsAddRequestingMemberAction.builder()
            actionBuilder.setAdded(
                try GroupsV2Protos.buildRequestingMemberProto(
                    profileKeyCredential: localProfileKeyCredential,
                    groupV2Params: groupV2Params
                ))
            actionsBuilder.addAddRequestingMembers(actionBuilder.buildInfallibly())
        default:
            throw OWSAssertionError("Invalid addFromInviteLinkAccess.")
        }

        return actionsBuilder.buildInfallibly()
    }

    public func cancelMemberRequests(groupModel: TSGroupModelV2) async throws -> TSGroupThread {
        let groupV2Params = try groupModel.groupV2Params()

        var newRevision: UInt32?
        do {
            newRevision = try await cancelMemberRequestsUsingPatch(
                groupId: groupModel.groupId,
                groupV2Params: groupV2Params,
                inviteLinkPassword: groupModel.inviteLinkPassword
            )
        } catch {
            switch error {
            case GroupsV2Error.localUserBlockedFromJoining, GroupsV2Error.localUserIsNotARequestingMember:
                // In both of these cases, our request has already been removed. We can proceed with updating the model.
                break
            default:
                // Otherwise, we don't recover and let the error propogate
                throw error
            }
        }

        return try await updateGroupRemovingMemberRequest(groupId: groupModel.groupId, newRevision: newRevision)
    }

    private func updateGroupRemovingMemberRequest(
        groupId: Data,
        newRevision proposedRevision: UInt32?
    ) async throws -> TSGroupThread {
        return try await NSObject.databaseStorage.awaitableWrite { transaction -> TSGroupThread in
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }
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
                    owsAssertDebug(!oldGroupMembership.isMemberOfAnyKind(localIdentifiers.aci))
                    return groupThread
                }
                newRevision = max(newRevision, proposedRevision)
            }

            var builder = oldGroupModel.asBuilder
            builder.isJoinRequestPlaceholder = true
            builder.groupV2Revision = newRevision

            var membershipBuilder = oldGroupMembership.asBuilder
            membershipBuilder.remove(localIdentifiers.aci)
            builder.groupMembership = membershipBuilder.build()
            let newGroupModel = try builder.build()

            groupThread.update(with: newGroupModel, transaction: transaction)

            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let dmToken = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: transaction.asV2Read).asToken
            GroupManager.insertGroupUpdateInfoMessage(
                groupThread: groupThread,
                oldGroupModel: oldGroupModel,
                newGroupModel: newGroupModel,
                oldDisappearingMessageToken: dmToken,
                newDisappearingMessageToken: dmToken,
                newlyLearnedPniToAciAssociations: [:],
                groupUpdateSource: .localUser(originalSource: .aci(localIdentifiers.aci)),
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: .createdByLocalAction,
                transaction: transaction
            )

            return groupThread
        }
    }

    private func cancelMemberRequestsUsingPatch(
        groupId: Data,
        groupV2Params: GroupV2Params,
        inviteLinkPassword: Data?
    ) async throws -> UInt32 {

        let revisionForPlaceholderModel = AtomicOptional<UInt32>(nil, lock: .sharedGlobal)

        // We re-fetch the GroupInviteLinkPreview with every attempt in order to get the latest:
        //
        // * revision
        // * addFromInviteLinkAccess
        // * local user's request status.
        let groupInviteLinkPreview = try await fetchGroupInviteLinkPreview(
            inviteLinkPassword: inviteLinkPassword,
            groupSecretParams: groupV2Params.groupSecretParams,
            allowCached: false
        )

        let requestBuilder: RequestBuilder = { (authCredential) in
            let groupChangeProto = try self.buildChangeActionsProtoToCancelMemberRequest(
                groupInviteLinkPreview: groupInviteLinkPreview,
                groupV2Params: groupV2Params,
                revisionForPlaceholderModel: revisionForPlaceholderModel
            )
            return try StorageService.buildUpdateGroupRequest(
                groupChangeProto: groupChangeProto,
                groupV2Params: groupV2Params,
                authCredential: authCredential,
                groupInviteLinkPassword: inviteLinkPassword
            )
        }

        _ = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: groupId,
            behavior400: .fail,
            behavior403: .fail,
            behavior404: .fail
        )

        guard let revision = revisionForPlaceholderModel.get() else {
            throw OWSAssertionError("Missing revisionForPlaceholderModel.")
        }
        return revision
    }

    private func buildChangeActionsProtoToCancelMemberRequest(
        groupInviteLinkPreview: GroupInviteLinkPreview,
        groupV2Params: GroupV2Params,
        revisionForPlaceholderModel: AtomicOptional<UInt32>
    ) throws -> GroupsProtoGroupChangeActions {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            throw OWSAssertionError("Missing localAci.")
        }
        let oldRevision = groupInviteLinkPreview.revision
        let newRevision = oldRevision + 1
        revisionForPlaceholderModel.set(newRevision)

        var actionsBuilder = GroupsProtoGroupChangeActions.builder()
        actionsBuilder.setRevision(newRevision)

        var actionBuilder = GroupsProtoGroupChangeActionsDeleteRequestingMemberAction.builder()
        let userId = try groupV2Params.userId(for: localAci)
        actionBuilder.setDeletedUserID(userId)
        actionsBuilder.addDeleteRequestingMembers(actionBuilder.buildInfallibly())

        return actionsBuilder.buildInfallibly()
    }

    public func tryToUpdatePlaceholderGroupModelUsingInviteLinkPreview(
        groupModel: TSGroupModelV2,
        removeLocalUserBlock: @escaping (SDSAnyWriteTransaction) -> Void
    ) async throws {
        guard groupModel.isJoinRequestPlaceholder else {
            owsFailDebug("Invalid group model.")
            return
        }

        do {
            let groupV2Params = try groupModel.groupV2Params()
            _ = try await fetchGroupInviteLinkPreview(
                inviteLinkPassword: groupModel.inviteLinkPassword,
                groupSecretParams: groupV2Params.groupSecretParams,
                allowCached: false
            )
        } catch {
            switch error {
            case GroupsV2Error.localUserIsNotARequestingMember, GroupsV2Error.localUserBlockedFromJoining:
                // Expected if our request has been cancelled or we're banned. In this
                // scenario, we should remove ourselves from the local group (in which
                // we will be stored as a requesting member).
                await NSObject.databaseStorage.awaitableWrite { transaction in
                    removeLocalUserBlock(transaction)
                }
            default:
                owsFailDebug("Error: \(error)")
            }
        }
    }

    private func updatePlaceholderGroupModelUsingInviteLinkPreview(
        groupSecretParams: GroupSecretParams,
        isLocalUserRequestingMember: Bool
    ) async {
        do {
            let groupId = try groupSecretParams.getPublicParams().getGroupIdentifier().serialize().asData
            try await NSObject.databaseStorage.awaitableWrite { transaction in
                guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
                    throw OWSAssertionError("Missing localIdentifiers.")
                }
                guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                    // Thread not yet in database.
                    return
                }
                guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid groupModel.")
                }
                guard oldGroupModel.isJoinRequestPlaceholder else {
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
                membershipBuilder.remove(localIdentifiers.aci)
                if isLocalUserRequestingMember {
                    membershipBuilder.addRequestingMember(localIdentifiers.aci)
                }
                builder.groupMembership = membershipBuilder.build()
                let newGroupModel = try builder.build()

                groupThread.update(with: newGroupModel, transaction: transaction)

                let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                let dmToken = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: transaction.asV2Read).asToken
                // groupUpdateSource is unknown; we don't know who did the update.
                GroupManager.insertGroupUpdateInfoMessage(
                    groupThread: groupThread,
                    oldGroupModel: oldGroupModel,
                    newGroupModel: newGroupModel,
                    oldDisappearingMessageToken: dmToken,
                    newDisappearingMessageToken: dmToken,
                    newlyLearnedPniToAciAssociations: [:],
                    groupUpdateSource: .unknown,
                    localIdentifiers: localIdentifiers,
                    spamReportingMetadata: .createdByLocalAction,
                    transaction: transaction
                )
            }
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    public func fetchGroupExternalCredentials(groupModel: TSGroupModelV2) async throws -> GroupsProtoGroupExternalCredential {
        let requestBuilder: RequestBuilder = { authCredential in
            try StorageService.buildFetchGroupExternalCredentials(
                groupV2Params: try groupModel.groupV2Params(),
                authCredential: authCredential
            )
        }

        let response = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: groupModel.groupId,
            behavior400: .fail,
            behavior403: .fetchGroupUpdates,
            behavior404: .fail
        )

        guard let groupProtoData = response.responseBodyData else {
            throw OWSAssertionError("Invalid responseObject.")
        }
        return try GroupsProtoGroupExternalCredential(serializedData: groupProtoData)
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
        // When adding a member, we include their profile key credential.
        let isAddingMembers = !addMembers.isEmpty

        // When promoting an invited member, we include the profile key for
        // their ACI.
        // Note: in practice the only user we'll promote is ourself, when
        // accepting an invite.
        let isPromotingPni = !promotePniPendingMembers.isEmpty
        let isPromotingAci = !promotePendingMembers.isEmpty

        return isAddingMembers || isPromotingPni || isPromotingAci
    }
}
