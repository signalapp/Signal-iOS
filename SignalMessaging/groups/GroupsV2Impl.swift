//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit
import ZKGroup

@objc
public class GroupsV2Impl: NSObject, GroupsV2, GroupsV2Swift {

    // MARK: - Dependencies

    fileprivate var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    fileprivate var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    fileprivate var socketManager: TSSocketManager {
        return TSSocketManager.shared
    }

    fileprivate var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    fileprivate var sessionManager: AFHTTPSessionManager {
        return OWSSignalService.sharedInstance().storageServiceSessionManager
    }

    fileprivate var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    // MARK: -

    public typealias ProfileKeyCredentialMap = [UUID: ProfileKeyCredential]

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Create Group

    @objc
    public func createNewGroupOnServiceObjc(groupModel: TSGroupModel) -> AnyPromise {
        return AnyPromise(createNewGroupOnService(groupModel: groupModel))
    }

    public func createNewGroupOnService(groupModel: TSGroupModel) -> Promise<Void> {
        // GroupsV2 TODO: Should we make sure we have a local profile credential?
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise<Void>(error: OWSAssertionError("Missing localUuid."))
        }
        let sessionManager = self.sessionManager
        let groupParams: GroupParams
        do {
            groupParams = try GroupParams(groupModel: groupModel)
        } catch {
            return Promise<Void>(error: error)
        }
        return DispatchQueue.global().async(.promise) { () -> [UUID] in
            // Gather the UUIDs for all members.
            let uuids = self.uuids(for: groupModel.groupMembers)
            guard uuids.contains(localUuid) else {
                throw OWSAssertionError("localUuid is not a member.")
            }
            return uuids
        }.then(on: DispatchQueue.global()) { (uuids: [UUID]) -> Promise<ProfileKeyCredentialMap> in
            // Gather the profile key credentials for all members.
            let allUuids = uuids + [localUuid]
            return self.loadProfileKeyCredentialData(for: allUuids)
        }.then(on: DispatchQueue.global()) { (profileKeyCredentialMap: ProfileKeyCredentialMap) -> Promise<NSURLRequest> in
            // Build the request.
            return self.buildNewGroupRequest(groupModel: groupModel,
                                             localUuid: localUuid,
                                             profileKeyCredentialMap: profileKeyCredentialMap,
                                             groupParams: groupParams,
                                             sessionManager: sessionManager)
        }.then(on: DispatchQueue.global()) { (request: NSURLRequest) -> Promise<Data> in
            Logger.info("Making create new group request: \(request)")

            return self.performServiceRequest(request: request, sessionManager: sessionManager)
        }.map(on: DispatchQueue.global()) { (_: Data) -> Void in
            // GroupsV2 TODO: We need to process the response data.
        }
    }

    // GroupsV2 TODO: Should we build the "update group" proto using this method
    // or a separate method?  There are real differences.
    private func buildNewGroupProto(groupModel: TSGroupModel,
                                    groupParams: GroupParams,
                                    profileKeyCredentialMap: ProfileKeyCredentialMap,
                                    localUuid: UUID) throws -> GroupsProtoGroup {
        // Collect credential for self.
        guard let localProfileKeyCredential = profileKeyCredentialMap[localUuid] else {
            throw OWSAssertionError("Missing localProfileKeyCredential.")
        }
        // Collect credentials for all members except self.

        let groupBuilder = GroupsProtoGroup.builder()
        // GroupsV2 TODO: Constant-ize, revisit.
        groupBuilder.setVersion(0)
        groupBuilder.setPublicKey(groupParams.groupPublicParamsData)
        groupBuilder.setTitle(try groupParams.encryptString(groupModel.groupName ?? ""))
        // GroupsV2 TODO: Avatar

        let accessControl = GroupsProtoAccessControl.builder()
        // GroupsV2 TODO: Pull these values from the group model.
        accessControl.setAttributes(.member)
        accessControl.setMembers(.member)
        groupBuilder.setAccessControl(try accessControl.build())

        // * You will be member 0 and the only admin.
        // * Other members will be non-admin members.
        //
        // Add local user first to ensure that they are user 0.
        assert(groupModel.isAdministrator(SignalServiceAddress(uuid: localUuid)))
        groupBuilder.addMembers(try GroupsV2Utils.buildMemberProto(profileKeyCredential: localProfileKeyCredential,
                                                                   role: .administrator,
                                                                   groupParams: groupParams))
        for (uuid, profileKeyCredential) in profileKeyCredentialMap {
            guard uuid != localUuid else {
                continue
            }
            let isAdministrator = groupModel.isAdministrator(SignalServiceAddress(uuid: uuid))
            let role: GroupsProtoMemberRole = isAdministrator ? .administrator : .`default`
            groupBuilder.addMembers(try GroupsV2Utils.buildMemberProto(profileKeyCredential: profileKeyCredential,
                                                                       role: role,
                                                                       groupParams: groupParams))
        }

        return try groupBuilder.build()
    }

    private func buildNewGroupRequest(groupModel: TSGroupModel,
                                      localUuid: UUID,
                                      profileKeyCredentialMap: ProfileKeyCredentialMap,
                                      groupParams: GroupParams,
                                      sessionManager: AFHTTPSessionManager) -> Promise<NSURLRequest> {

        return retrieveCredentials(localUuid: localUuid)
            .map(on: DispatchQueue.global()) { (authCredentialMap: [UInt32: AuthCredential]) -> NSURLRequest in

                let groupProto = try self.buildNewGroupProto(groupModel: groupModel,
                                                             groupParams: groupParams,
                                                             profileKeyCredentialMap: profileKeyCredentialMap,
                                                             localUuid: localUuid)
                let redemptionTime = self.daysSinceEpoch
                return try StorageService.buildNewGroupRequest(groupProto: groupProto,
                                                               groupParams: groupParams,
                                                               sessionManager: sessionManager,
                                                               authCredentialMap: authCredentialMap,
                                                               redemptionTime: redemptionTime)
        }
    }

    // MARK: - Update Group

    public func updateExistingGroupOnService(changeSet: GroupsV2ChangeSet) -> Promise<Void> {
        let groupId = changeSet.groupId

        // GroupsV2 TODO: Should we make sure we have a local profile credential?
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise<Void>(error: OWSAssertionError("Missing localUuid."))
        }
        let sessionManager = self.sessionManager
        let groupParams: GroupParams
        do {
            groupParams = try GroupParams(groupSecretParamsData: changeSet.groupSecretParamsData)
        } catch {
            return Promise<Void>(error: error)
        }
        return self.databaseStorage.read(.promise) { transaction in
            return TSGroupThread.fetch(groupId: groupId, transaction: transaction)
        }.then(on: DispatchQueue.global()) { (thread: TSGroupThread?) -> Promise<GroupsProtoGroupChangeActions> in
            guard let thread = thread else {
                throw OWSAssertionError("Thread does not exist.")
            }
            return changeSet.buildGroupChangeProto(currentGroupModel: thread.groupModel)
        }.then(on: DispatchQueue.global()) { (groupChangeProto: GroupsProtoGroupChangeActions) -> Promise<NSURLRequest> in
            // GroupsV2 TODO: We should implement retry for all request methods in this class.
            return self.buildUpdateGroupRequest(localUuid: localUuid,
                                                groupParams: groupParams,
                                                groupChangeProto: groupChangeProto,
                                                sessionManager: sessionManager)
        }.then(on: DispatchQueue.global()) { (request: NSURLRequest) -> Promise<Data> in
            Logger.info("Making update group request: \(request.httpMethod) \(request)")

            return self.performServiceRequest(request: request, sessionManager: sessionManager)
        }.then(on: DispatchQueue.global()) { (_: Data) -> Promise<Void> in
            // GroupsV2 TODO: Handle conflicts.
            // GroupsV2 TODO: Handle success.
            // GroupsV2 TODO: Propagate failure in a consumable way.
            /*
             If the group change is successfully applied, the service will respond:
             
             200 OK HTTP/2
             Content-Type: application/x-protobuf
             
             {encoded and signed GroupChange}
             
             The response body contains the fully signed and populated group change record, which clients can transmit to group members out of band.
             
             If the group change conflicts with a version that has already been applied (for example, the version in the supplied proto is not current version + 1) , the service will respond:
             
             409 Conflict HTTP/2
             Content-Type: application/x-protobuf
             
             {encoded_current_group_record}
             */
            return Promise.value(())
        }
    }

    private func buildUpdateGroupRequest(localUuid: UUID,
                                         groupParams: GroupParams,
                                         groupChangeProto: GroupsProtoGroupChangeActions,
                                         sessionManager: AFHTTPSessionManager) -> Promise<NSURLRequest> {

        return retrieveCredentials(localUuid: localUuid)
            .map(on: DispatchQueue.global()) { (authCredentialMap: [UInt32: AuthCredential]) -> NSURLRequest in
                let redemptionTime = self.daysSinceEpoch
                return try StorageService.buildUpdateGroupRequest(groupChangeProto: groupChangeProto,
                                                                  groupParams: groupParams,
                                                                  sessionManager: sessionManager,
                                                                  authCredentialMap: authCredentialMap,
                                                                  redemptionTime: redemptionTime)
        }
    }

    // MARK: - Fetch Group State

    @objc
    public func fetchGroupStateObjc(groupModel: TSGroupModel) -> AnyPromise {
        return AnyPromise(fetchGroupState(groupModel: groupModel))
    }

    public func fetchGroupState(groupModel: TSGroupModel) -> Promise<GroupV2State> {
        guard groupModel.groupsVersion == .V2 else {
            return Promise(error: OWSAssertionError("Invalid groupsVersion."))
        }
        guard let groupSecretParamsData = groupModel.groupSecretParamsData else {
            return Promise(error: OWSAssertionError("Missing groupSecretParamsData."))
        }

        return self.fetchGroupState(groupSecretParamsData: groupSecretParamsData)
    }

    public func fetchGroupState(groupSecretParamsData: Data) -> Promise<GroupV2State> {
        // GroupsV2 TODO: Should we make sure we have a local profile credential?
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise<GroupV2State>(error: OWSAssertionError("Missing localUuid."))
        }
        return DispatchQueue.global().async(.promise) { () -> GroupParams in
            return try GroupParams(groupSecretParamsData: groupSecretParamsData)
        }.then(on: DispatchQueue.global()) { (groupParams: GroupParams) -> Promise<GroupV2State> in
            return self.fetchGroupState(groupParams: groupParams,
                                        localUuid: localUuid)
        }.map(on: DispatchQueue.global()) { (groupState: GroupV2State) -> GroupV2State in
            // GroupsV2 TODO: Remove this logging.
            Logger.verbose("GroupV2State: \(groupState.debugDescription)")
            return groupState
        }
    }

    private func fetchGroupState(groupParams: GroupParams,
                                 localUuid: UUID) -> Promise<GroupV2State> {
        let sessionManager = self.sessionManager
        return self.buildFetchGroupStateRequest(localUuid: localUuid,
                                                groupParams: groupParams,
                                                sessionManager: sessionManager)
            .then(on: DispatchQueue.global()) { (request: NSURLRequest) -> Promise<Data> in
                Logger.info("Making fetch group state request: \(request)")

                return self.performServiceRequest(request: request, sessionManager: sessionManager)
        }.map(on: DispatchQueue.global()) { (groupProtoData: Data) -> GroupV2State in
            let groupProto = try GroupsProtoGroup.parseData(groupProtoData)
            return try self.parse(groupProto: groupProto, groupParams: groupParams)
        }
    }

    private func buildFetchGroupStateRequest(localUuid: UUID,
                                             groupParams: GroupParams,
                                             sessionManager: AFHTTPSessionManager) -> Promise<NSURLRequest> {

        return retrieveCredentials(localUuid: localUuid)
            .map(on: DispatchQueue.global()) { (authCredentialMap: [UInt32: AuthCredential]) -> NSURLRequest in

                let redemptionTime = self.daysSinceEpoch
                return try StorageService.buildFetchGroupStateRequest(groupParams: groupParams,
                                                                      sessionManager: sessionManager,
                                                                      authCredentialMap: authCredentialMap,
                                                                      redemptionTime: redemptionTime)
        }
    }

    // GroupsV2 TODO: How can we make this parsing less brittle?
    private func parse(groupProto: GroupsProtoGroup,
                       groupParams: GroupParams) throws -> GroupV2State {

        // GroupsV2 TODO: Is GroupsProtoAccessControl required?
        guard let accessControl = groupProto.accessControl else {
            throw OWSAssertionError("Missing accessControl.")
        }
        guard let accessControlForAttributes = accessControl.attributes else {
            throw OWSAssertionError("Missing accessControl.members.")
        }
        guard let accessControlForMembers = accessControl.members else {
            throw OWSAssertionError("Missing accessControl.members.")
        }

        var members = [GroupV2StateImpl.Member]()
        for memberProto in groupProto.members {
            guard let userID = memberProto.userID else {
                throw OWSAssertionError("Group member missing userID.")
            }
            guard let role = memberProto.role else {
                throw OWSAssertionError("Group member missing role.")
            }
            guard let profileKey = memberProto.profileKey else {
                throw OWSAssertionError("Group member missing profileKey.")
            }
            // NOTE: presentation is set when creating and updating groups, not
            //       when fetching group state.
            guard memberProto.hasJoinedAtVersion else {
                throw OWSAssertionError("Group member missing joinedAtVersion.")
            }
            let joinedAtVersion = memberProto.joinedAtVersion

            let uuid = try groupParams.uuid(forUserId: userID)
            let member = GroupV2StateImpl.Member(userID: userID,
                                                 uuid: uuid,
                                                 role: role,
                                                 profileKey: profileKey,
                                                 joinedAtVersion: joinedAtVersion)
            members.append(member)
        }

        var pendingMembers = [GroupV2StateImpl.PendingMember]()
        for pendingMemberProto in groupProto.pendingMembers {
            guard let userID = pendingMemberProto.addedByUserID else {
                throw OWSAssertionError("Group pending member missing userID.")
            }
            guard pendingMemberProto.hasTimestamp else {
                throw OWSAssertionError("Group pending member missing timestamp.")
            }
            let timestamp = pendingMemberProto.timestamp
            let uuid = try groupParams.uuid(forUserId: userID)
            let pendingMember = GroupV2StateImpl.PendingMember(userID: userID,
                                                               uuid: uuid,
                                                               timestamp: timestamp)
            pendingMembers.append(pendingMember)
        }

        // GroupsV2 TODO: Do we need the public key?

        var title = ""
        if let titleData = groupProto.title {
            do {
                title = try groupParams.decryptString(titleData)
            } catch {
                owsFailDebug("Could not decrypt title: \(error).")
            }
        }

        // GroupsV2 TODO: Avatar
        //        public var avatar: String? {

        // GroupsV2 TODO: disappearingMessagesTimer
        //        public var disappearingMessagesTimer: Data? {

        let version = groupProto.version
        let groupSecretParamsData = groupParams.groupSecretParamsData
        return GroupV2StateImpl(groupSecretParamsData: groupSecretParamsData,
                                groupProto: groupProto,
                                version: version,
                                title: title,
                                members: members,
                                pendingMembers: pendingMembers,
                                accessControlForAttributes: accessControlForAttributes,
                                accessControlForMembers: accessControlForMembers)
    }

    // MARK: - Updates

    public func fetchAndApplyGroupV2UpdatesFromServiceObjc(groupId: Data,
                                                           groupSecretParamsData: Data,
                                                           upToRevision: UInt32) -> AnyPromise {
        return AnyPromise(fetchAndApplyGroupV2UpdatesFromService(groupId: groupId,
                                                                 groupSecretParamsData: groupSecretParamsData,
                                                                 upToRevision: upToRevision))
    }

    // Fetch group state from service and apply.
    //
    // * Try to fetch and apply incremental "changes".
    // * Failover to fetching and applying latest state.
    // * We need to distinguish between retryable (network) errors
    //   and non-retryable errors.
    // * In the case of networking errors, we should do exponential
    //   backoff.
    // * If reachability changes, we should retry network errors
    //   immediately.
    //
    // GroupsV2 TODO: Implement properly.
    public func fetchAndApplyGroupV2UpdatesFromService(groupId: Data,
                                                       groupSecretParamsData: Data,
                                                       upToRevision: UInt32) -> Promise<Void> {
        return self.fetchGroupState(groupSecretParamsData: groupSecretParamsData)
            .done(on: DispatchQueue.global()) { (groupState: GroupV2State) throws in
                try self.databaseStorage.write { (transaction: SDSAnyWriteTransaction) throws in
                    // GroupsV2 TODO: We could make this a single GroupManager method.
                    let groupModel = try GroupManager.buildGroupModel(groupV2State: groupState,
                                                                      transaction: transaction)
                    _ = try GroupManager.upsertGroupV2Thread(groupModel: groupModel,
                                                             transaction: transaction)
                }
                // GroupsV2 TODO: Remove this logging.
                Logger.verbose("GroupV2State: \(groupState.debugDescription)")
        }
    }

    // MARK: - Perform Request

    // GroupsV2 TODO: We should implement retry for all request methods in this class.
    public func performServiceRequest(request: NSURLRequest,
                                      sessionManager: AFHTTPSessionManager) -> Promise<Data> {

        return Promise { resolver in
            let task = sessionManager.dataTask(
                with: request as URLRequest,
                uploadProgress: nil,
                downloadProgress: nil
            ) { response, responseObject, error in
                guard let response = response as? HTTPURLResponse else {
                    Logger.info("Request failed: \(String(describing: request.httpMethod)) \(String(describing: request.url))")

                    guard let error = error else {
                        return resolver.reject(OWSAssertionError("Unexpected response type."))
                    }

                    owsFailDebug("Response error: \(error)")
                    return resolver.reject(error)
                }

                switch response.statusCode {
                case 200:
                    Logger.info("Request succeeded: \(String(describing: request.httpMethod)) \(String(describing: request.url))")
                default:
                    return resolver.reject(OWSAssertionError("Invalid response: \(response.statusCode)"))
                }

                // GroupsV2 TODO: Some requests might not have a response body.
                guard let responseData = responseObject as? Data else {
                    return resolver.reject(OWSAssertionError("Missing response data."))
                }
                return resolver.fulfill(responseData)
            }
            task.resume()
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
                    if let credential = try VersionedProfiles.profileKeyCredential(for: address,
                                                                                   transaction: transaction) {
                        credentialMap[uuid] = credential
                        continue
                    }
                } catch {
                    // GroupsV2 TODO: Should we throw here?
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
            let promise = ProfileFetcherJob.fetchAndUpdateProfilePromise(address: address,
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
                        guard let credential = try VersionedProfiles.profileKeyCredential(for: address,
                                                                                          transaction: transaction) else {
                                                                                            throw OWSAssertionError("Could load credential.")
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
            return try VersionedProfiles.profileKeyCredential(for: address,
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
        guard FeatureFlags.versionedProfiledFetches else {
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
            promises.append(ProfileFetcherJob.fetchAndUpdateProfilePromise(address: address,
                                                                           mainAppOnly: false,
                                                                           ignoreThrottling: true,
                                                                           shouldUpdateProfile: true,
                                                                           fetchType: .versioned))
        }
        return when(fulfilled: promises).asVoid()
    }

    // MARK: - AuthCredentials

    // GroupsV2 TODO: Can we persist and reuse credentials?
    // GroupsV2 TODO: Reorganize this code.
    private func retrieveCredentials(localUuid: UUID) -> Promise<[UInt32: AuthCredential]> {

        let today = self.daysSinceEpoch
        let todayPlus7 = today + 7
        let request = OWSRequestFactory.groupAuthenticationCredentialRequest(fromRedemptionDays: today,
                                                                             toRedemptionDays: todayPlus7)
        return networkManager.makePromise(request: request)
            .map(on: DispatchQueue.global()) { (_: URLSessionDataTask, responseObject: Any?) -> [UInt32: AuthCredential] in
                let temporalCredentials = try self.parseCredentialResponse(responseObject: responseObject)
                let localZKGUuid = try localUuid.asZKGUuid()
                let serverPublicParams = try GroupsV2Utils.serverPublicParams()
                let clientZkAuthOperations = ClientZkAuthOperations(serverPublicParams: serverPublicParams)
                var credentialMap = [UInt32: AuthCredential]()
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

    public func buildChangeSet(from oldGroupModel: TSGroupModel,
                               to newGroupModel: TSGroupModel) throws -> GroupsV2ChangeSet {
        let changeSet = try GroupsV2ChangeSetImpl(for: oldGroupModel)
        try changeSet.buildChangeSet(from: oldGroupModel, to: newGroupModel)
        return changeSet
    }

    // MARK: - Protos

    public func buildGroupContextV2Proto(groupModel: TSGroupModel,
                                         groupChangeData: Data?) throws -> SSKProtoGroupContextV2 {

        guard let groupSecretParamsData = groupModel.groupSecretParamsData else {
            throw OWSAssertionError("Missing groupSecretParamsData.")
        }
        let groupSecretParams = try GroupSecretParams(contents: [UInt8](groupSecretParamsData))

        let builder = SSKProtoGroupContextV2.builder()
        builder.setMasterKey(try groupSecretParams.getMasterKey().serialize().asData)
        builder.setRevision(groupModel.groupV2Revision)

        if let groupChangeData = groupChangeData {
            assert(groupChangeData.count > 0)
            builder.setGroupChange(groupChangeData)
        }

        return try builder.build()
    }

    // MARK: - Profiles

    public func reuploadLocalProfilePromise() -> Promise<Void> {
        guard FeatureFlags.versionedProfiledUpdate else {
            return Promise(error: OWSAssertionError("Versioned profiles are not enabled."))
        }
        return self.profileManager.reuploadLocalProfilePromise()
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

// MARK: -

// GroupsV2 TODO: Convert this extension into tests.
@objc
public extension GroupsV2Impl {

    // MARK: - Dependencies

    private class var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private class var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    // MARK: -

    static func testGroupsV2Functionality() {
        guard !FeatureFlags.isUsingProductionService,
            FeatureFlags.tryToCreateNewGroupsV2,
            FeatureFlags.versionedProfiledFetches,
            FeatureFlags.versionedProfiledUpdate else {
                owsFailDebug("Incorrect feature flags.")
                return
        }
        let members = [SignalServiceAddress]()
        let title0 = "hello"
        let title1 = "goodbye"
        guard let localUuid = tsAccountManager.localUuid else {
            owsFailDebug("Missing localUuid.")
            return
        }
        guard let localNumber = tsAccountManager.localNumber else {
            owsFailDebug("Missing localNumber.")
            return
        }
        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            owsFailDebug("Missing groupsV2Swift.")
            return
        }
        GroupManager.createNewGroup(members: members,
                                    name: title0,
                                    shouldSendMessage: true)
            .then(on: .global()) { (groupThread: TSGroupThread) -> Promise<(TSGroupThread, GroupV2State)> in
                let groupModel = groupThread.groupModel
                guard groupModel.groupsVersion == .V2 else {
                    throw OWSAssertionError("Not a V2 group.")
                }
                return groupsV2Swift.fetchGroupState(groupModel: groupModel)
                    .map(on: .global()) { (groupV2State: GroupV2State) -> (TSGroupThread, GroupV2State) in
                        return (groupThread, groupV2State)
                }
            }.map(on: .global()) { (groupThread: TSGroupThread, groupV2State: GroupV2State) throws -> TSGroupThread in
                guard groupV2State.version == 0 else {
                    throw OWSAssertionError("Unexpected group version: \(groupV2State.version).")
                }
                guard groupV2State.title == title0 else {
                    throw OWSAssertionError("Unexpected group title: \(groupV2State.title).")
                }
                let expectedMembers = [SignalServiceAddress(uuid: localUuid)]
                guard groupV2State.activeMembers == expectedMembers else {
                    throw OWSAssertionError("Unexpected members: \(groupV2State.activeMembers).")
                }
                let expectedAdministrators = expectedMembers
                guard groupV2State.administrators == expectedAdministrators else {
                    throw OWSAssertionError("Unexpected administrators: \(groupV2State.administrators).")
                }
                guard groupV2State.accessControlForMembers == .member else {
                    throw OWSAssertionError("Unexpected accessControlForMembers: \(groupV2State.accessControlForMembers).")
                }
                guard groupV2State.accessControlForAttributes == .member else {
                    throw OWSAssertionError("Unexpected accessControlForAttributes: \(groupV2State.accessControlForAttributes).")
                }
                return groupThread
            }.then(on: .global()) { (groupThread: TSGroupThread) throws -> Promise<(TSGroupThread, GroupV2State)> in
                // GroupsV2 TODO: Add and remove members, change avatar, etc.
                let changeSet = try GroupsV2ChangeSetImpl(for: groupThread.groupModel)
                changeSet.setTitle(title1)

                return groupsV2Swift.updateExistingGroupOnService(changeSet: changeSet)
                    .then(on: .global()) { () -> Promise<GroupV2State> in
                        return groupsV2Swift.fetchGroupState(groupModel: groupThread.groupModel)
                }.map(on: .global()) { (groupV2State: GroupV2State) -> (TSGroupThread, GroupV2State) in
                    return (groupThread, groupV2State)
                }
            }.map(on: .global()) { (groupThread: TSGroupThread, groupV2State: GroupV2State) throws -> TSGroupThread in
                guard groupV2State.version == 1 else {
                    throw OWSAssertionError("Unexpected group version: \(groupV2State.version).")
                }
                guard groupV2State.title == title1 else {
                    throw OWSAssertionError("Unexpected group title: \(groupV2State.title).")
                }
                let expectedMembers = [SignalServiceAddress(uuid: localUuid)]
                guard groupV2State.activeMembers == expectedMembers else {
                    throw OWSAssertionError("Unexpected members: \(groupV2State.activeMembers).")
                }
                let expectedAdministrators = expectedMembers
                guard groupV2State.administrators == expectedAdministrators else {
                    throw OWSAssertionError("Unexpected administrators: \(groupV2State.administrators).")
                }
                guard groupV2State.accessControlForMembers == .member else {
                    throw OWSAssertionError("Unexpected accessControlForMembers: \(groupV2State.accessControlForMembers).")
                }
                guard groupV2State.accessControlForAttributes == .member else {
                    throw OWSAssertionError("Unexpected accessControlForAttributes: \(groupV2State.accessControlForAttributes).")
                }
                return groupThread
            }.done { (_: TSGroupThread) -> Void in
                Logger.info("---- Success.")
            }.catch { error in
                owsFailDebug("---- Error: \(error)")
            }.retainUntilComplete()
    }
}
