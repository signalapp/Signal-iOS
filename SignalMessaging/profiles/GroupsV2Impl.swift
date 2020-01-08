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

    // MARK: -

    private typealias ProfileKeyCredentialMap = [UUID: ProfileKeyCredential]

    // MARK: - Create Group

    public func createNewGroupOnServiceObjc(groupModel: TSGroupModel) -> AnyPromise {
        return AnyPromise(createNewGroupOnService(groupModel: groupModel))
    }

    public func createNewGroupOnService(groupModel: TSGroupModel) -> Promise<Void> {
        // GroupsV2 TODO: Should we make sure we have a local profile credential?
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise<Void>(error: OWSErrorMakeAssertionError("Missing localUuid."))
        }
        let sessionManager = self.sessionManager
        let groupParams: GroupParams
        do {
            groupParams = try GroupParams(groupModel: groupModel)
        } catch {
            return Promise<Void>(error: error)
        }
        var profileKeyCredentialMap: ProfileKeyCredentialMap?
        return DispatchQueue.global().async(.promise) { () -> [UUID] in
            // Gather the UUIDs for all members.
            let uuids = try self.uuids(for: groupModel.groupMembers)
            guard uuids.contains(localUuid) else {
                throw OWSErrorMakeAssertionError("localUuid is not a member.")
            }
            return uuids
        }.then(on: DispatchQueue.global()) { (uuids: [UUID]) -> Promise<Void> in
            // Gather the profile key credentials for all members.
            let allUuids = uuids + [localUuid]
            return self.loadProfileKeyCredentialData(for: allUuids)
                .map(on: DispatchQueue.global()) { (value: ProfileKeyCredentialMap) -> Void in
                    profileKeyCredentialMap = value
                    return ()
            }
        }.then(on: DispatchQueue.global()) { (_) -> Promise<NSURLRequest> in
            // Build the request.
            guard let profileKeyCredentialMap = profileKeyCredentialMap else {
                throw OWSErrorMakeAssertionError("Missing profileKeyCredentialMap.")
            }
            return self.buildNewGroupRequest(groupModel: groupModel,
                                             localUuid: localUuid,
                                             profileKeyCredentialMap: profileKeyCredentialMap,
                                             groupParams: groupParams,
                                             sessionManager: sessionManager)

        }.then(on: DispatchQueue.global()) { (request: NSURLRequest) -> Promise<Data> in
            Logger.info("Making new group request: \(request)")

            return Promise { resolver in
                let task = sessionManager.dataTask(
                    with: request as URLRequest,
                    uploadProgress: nil,
                    downloadProgress: nil
                ) { response, responseObject, error in

                    guard let response = response as? HTTPURLResponse else {
                        Logger.info("Request failed: \(String(describing: request.httpMethod)) \(String(describing: request.url))")

                        guard let error = error else {
                            return resolver.reject(OWSErrorMakeAssertionError("Unexpected response type."))
                        }

                        owsFailDebug("Response error: \(error)")
                        return resolver.reject(error)
                    }

                    switch response.statusCode {
                    case 200:
                        Logger.info("Request succeeded: \(String(describing: request.httpMethod)) \(String(describing: request.url))")
                    default:
                        return resolver.reject(OWSErrorMakeAssertionError("Invalid response: \(response.statusCode)"))
                    }

                    guard let responseData = responseObject as? Data else {
                        return resolver.reject(OWSErrorMakeAssertionError("Missing response data."))
                    }
                    return resolver.fulfill(responseData)
                }
                task.resume()
            }
        }.then(on: DispatchQueue.global()) { (_: Data) -> Promise<GroupV2State> in
            guard let profileKeyCredentialMap = profileKeyCredentialMap else {
                throw OWSErrorMakeAssertionError("Missing profileKeyCredentialMap.")
            }
            return self.fetchGroupState(groupModel: groupModel,
                                        groupParams: groupParams,
                                        localUuid: localUuid,
                                        sessionManager: sessionManager,
                                        profileKeyCredentialMap: profileKeyCredentialMap)
        }.done(on: DispatchQueue.global()) { (groupState: GroupV2State) -> Void in
            // Do nothing, for now.
            Logger.verbose("GroupV2State: \(groupState.debugDescription)")
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
            throw OWSErrorMakeAssertionError("Missing localProfileKeyCredential.")
        }
        // Collect credentials for all members except self.

        let groupBuilder = GroupsProtoGroup.builder()
        // GroupsV2 TODO: Constant-ize, revisit.
        groupBuilder.setVersion(0)
        groupBuilder.setPublicKey(groupParams.groupPublicParamsData)
        groupBuilder.setTitle(try encryptTitle(title: groupModel.groupName,
                                               groupParams: groupParams))
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
        groupBuilder.addMembers(try buildMemberProto(profileKeyCredential: localProfileKeyCredential,
                                                     role: .administrator,
                                                     groupParams: groupParams))
        for (uuid, profileKeyCredential) in profileKeyCredentialMap {
            guard uuid != localUuid else {
                continue
            }
            groupBuilder.addMembers(try buildMemberProto(profileKeyCredential: profileKeyCredential,
                                                         role: .default,
                                                         groupParams: groupParams))
        }

        return try groupBuilder.build()
    }

    // GroupsV2 TODO: Can we build protos for the "create group" and "update group" scenarios here?
    // There might be real differences.
    private func buildMemberProto(profileKeyCredential: ProfileKeyCredential,
                                  role: GroupsProtoMemberRole,
                                  groupParams: GroupParams) throws -> GroupsProtoMember {
        let builder = GroupsProtoMember.builder()
        builder.setRole(role)

        let serverPublicParams = try VersionedProfiles.serverPublicParams()
        let profileOperations = ClientZkProfileOperations(serverPublicParams: serverPublicParams)
        let presentation = try profileOperations.createProfileKeyCredentialPresentation(groupSecretParams: groupParams.groupSecretParams,
                                                                                        profileKeyCredential: profileKeyCredential)
        builder.setPresentation(presentation.serialize().asData)

        return try builder.build()
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
                let groupProtoData = try groupProto.serializedData()

                let urlPath = "/v1/groups/"
                guard let url = URL(string: urlPath, relativeTo: sessionManager.baseURL) else {
                    throw OWSErrorMakeAssertionError("Invalid URL.")
                }
                let request = NSMutableURLRequest(url: url)
                let method = "PUT"
                request.httpMethod = method
                request.httpBody = groupProtoData

                request.setValue(OWSMimeTypeProtobuf, forHTTPHeaderField: "Content-Type")

                try self.addAuthorizationHeader(to: request,
                                                groupModel: groupModel,
                                                groupParams: groupParams,
                                                authCredentialMap: authCredentialMap)

                return request
        }
    }

    // MARK: - Fetch Group State

    public func fetchGroupStateObjc(groupModel: TSGroupModel) -> AnyPromise {
        return AnyPromise(fetchGroupState(groupModel: groupModel))
    }

    public func fetchGroupState(groupModel: TSGroupModel) -> Promise<GroupV2State> {
        // GroupsV2 TODO: Should we make sure we have a local profile credential?
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise<GroupV2State>(error: OWSErrorMakeAssertionError("Missing localUuid."))
        }
        let sessionManager = self.sessionManager
        return DispatchQueue.global().async(.promise) { () -> [UUID] in
            let uuids = try self.uuids(for: groupModel.groupMembers)
            guard uuids.contains(localUuid) else {
                throw OWSErrorMakeAssertionError("localUuid is not a member.")
            }
            return uuids
        }.then(on: DispatchQueue.global()) { (uuids: [UUID]) -> Promise<ProfileKeyCredentialMap> in
            let allUuids = uuids + [localUuid]
            return self.loadProfileKeyCredentialData(for: allUuids)
        }.then(on: DispatchQueue.global()) { (profileKeyCredentialMap: ProfileKeyCredentialMap) -> Promise<GroupV2State> in

            let groupParams = try GroupParams(groupModel: groupModel)

            return self.fetchGroupState(groupModel: groupModel,
                                        groupParams: groupParams,
                                        localUuid: localUuid,
                                        sessionManager: sessionManager,
                                        profileKeyCredentialMap: profileKeyCredentialMap)
        }.map(on: DispatchQueue.global()) { (groupState: GroupV2State) -> GroupV2State in
            // Do nothing, for now.
            Logger.verbose("GroupV2State: \(groupState.debugDescription)")
            return groupState
        }
    }

    private func fetchGroupState(groupModel: TSGroupModel,
                                 groupParams: GroupParams,
                                 localUuid: UUID,
                                 sessionManager: AFHTTPSessionManager,
                                 profileKeyCredentialMap: ProfileKeyCredentialMap) -> Promise<GroupV2State> {
        return self.buildFetchGroupStateRequest(groupModel: groupModel,
                                                localUuid: localUuid,
                                                profileKeyCredentialMap: profileKeyCredentialMap,
                                                groupParams: groupParams,
                                                sessionManager: sessionManager)
            .then(on: DispatchQueue.global()) { (request: NSURLRequest) -> Promise<Data> in
                Logger.info("Making fetch group state request: \(request)")

                return Promise { resolver in
                    let task = sessionManager.dataTask(
                        with: request as URLRequest,
                        uploadProgress: nil,
                        downloadProgress: nil
                    ) { response, responseObject, error in

                        guard let response = response as? HTTPURLResponse else {
                            Logger.info("Request failed: \(String(describing: request.httpMethod)) \(String(describing: request.url))")

                            guard let error = error else {
                                return resolver.reject(OWSErrorMakeAssertionError("Unexpected response type."))
                            }

                            owsFailDebug("Response error: \(error)")
                            return resolver.reject(error)
                        }

                        switch response.statusCode {
                        case 200:
                            Logger.info("Request succeeded: \(String(describing: request.httpMethod)) \(String(describing: request.url))")
                        default:
                            return resolver.reject(OWSErrorMakeAssertionError("Invalid response: \(response.statusCode)"))
                        }

                        guard let responseData = responseObject as? Data else {
                            return resolver.reject(OWSErrorMakeAssertionError("Missing response data."))
                        }
                        return resolver.fulfill(responseData)
                    }
                    task.resume()
                }
            }.map(on: DispatchQueue.global()) { (groupProtoData: Data) -> GroupV2State in
                let groupProto = try GroupsProtoGroup.parseData(groupProtoData)
                return try self.parse(groupProto: groupProto, groupParams: groupParams)
        }
    }

    private func buildFetchGroupStateRequest(groupModel: TSGroupModel,
                                             localUuid: UUID,
                                             profileKeyCredentialMap: ProfileKeyCredentialMap,
                                             groupParams: GroupParams,
                                             sessionManager: AFHTTPSessionManager) -> Promise<NSURLRequest> {

        return retrieveCredentials(localUuid: localUuid)
            .map(on: DispatchQueue.global()) { (authCredentialMap: [UInt32: AuthCredential]) -> NSURLRequest in

                let urlPath = "/v1/groups/"
                guard let url = URL(string: urlPath, relativeTo: sessionManager.baseURL) else {
                    throw OWSErrorMakeAssertionError("Invalid URL.")
                }
                let request = NSMutableURLRequest(url: url)
                let method = "GET"
                request.httpMethod = method

                try self.addAuthorizationHeader(to: request,
                                                groupModel: groupModel,
                                                groupParams: groupParams,
                                                authCredentialMap: authCredentialMap)

                return request
        }
    }

    // GroupsV2 TODO: How can we make this parsing less brittle?
    private func parse(groupProto: GroupsProtoGroup,
                       groupParams: GroupParams) throws -> GroupV2State {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: groupParams.groupSecretParams)

        // GroupsV2 TODO: Is GroupsProtoAccessControl required?
        guard let accessControl = groupProto.accessControl else {
            throw OWSErrorMakeAssertionError("Missing accessControl.")
        }
        guard let accessControlForAttributes = accessControl.attributes else {
            throw OWSErrorMakeAssertionError("Missing accessControl.members.")
        }
        guard let accessControlForMembers = accessControl.members else {
            throw OWSErrorMakeAssertionError("Missing accessControl.members.")
        }

        var members = [GroupV2StateImpl.Member]()
        for memberProto in groupProto.members {
            guard let userID = memberProto.userID else {
                throw OWSErrorMakeAssertionError("Group member missing userID.")
            }
            guard let role = memberProto.role else {
                throw OWSErrorMakeAssertionError("Group member missing role.")
            }
            guard let profileKey = memberProto.profileKey else {
                throw OWSErrorMakeAssertionError("Group member missing profileKey.")
            }
            // NOTE: presentation is set when creating and updating groups, not
            //       when fetching group state.
            guard memberProto.hasJoinedAtVersion else {
                throw OWSErrorMakeAssertionError("Group member missing joinedAtVersion.")
            }
            let joinedAtVersion = memberProto.joinedAtVersion

            let uuidCiphertext = try UuidCiphertext(contents: [UInt8](userID))
            let zkgUuid = try clientZkGroupCipher.decryptUuid(uuidCiphertext: uuidCiphertext)
            let uuidData = zkgUuid.serialize().asData
            let uuid = uuidData.withUnsafeBytes {
                UUID(uuid: $0.bindMemory(to: uuid_t.self).first!)
            }
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
                throw OWSErrorMakeAssertionError("Group pending member missing userID.")
            }
            guard pendingMemberProto.hasTimestamp else {
                throw OWSErrorMakeAssertionError("Group pending member missing timestamp.")
            }
            let timestamp = pendingMemberProto.timestamp
            let uuidCiphertext = try UuidCiphertext(contents: [UInt8](userID))
            let zkgUuid = try clientZkGroupCipher.decryptUuid(uuidCiphertext: uuidCiphertext)
            let uuidData = zkgUuid.serialize().asData
            let uuid = uuidData.withUnsafeBytes {
                UUID(uuid: $0.bindMemory(to: uuid_t.self).first!)
            }
            let pendingMember = GroupV2StateImpl.PendingMember(userID: userID,
                                                               uuid: uuid,
                                                               timestamp: timestamp)
            pendingMembers.append(pendingMember)
        }

        // GroupsV2 TODO: Do we need the public key?

        var title = ""
        if let titleData = groupProto.title {
            do {
                title = try decryptTitle(data: titleData,
                                         groupParams: groupParams)
            } catch {
                owsFailDebug("Could not decrypt title: \(error).")
            }
        }

        // GroupsV2 TODO: Avatar
        //        public var avatar: String? {

        // GroupsV2 TODO: disappearingMessagesTimer
        //        public var disappearingMessagesTimer: Data? {

        let version = groupProto.version

        return GroupV2StateImpl(groupProto: groupProto,
                                version: version,
                                title: title,
                                members: members,
                                pendingMembers: pendingMembers,
                                accessControlForAttributes: accessControlForAttributes,
                                accessControlForMembers: accessControlForMembers)
    }

    // MARK: - Authorization Headers

    private func addAuthorizationHeader(to request: NSMutableURLRequest,
                                        groupModel: TSGroupModel,
                                        groupParams: GroupParams,
                                        authCredentialMap: [UInt32: AuthCredential]) throws {

        let redemptionTime = self.daysSinceEpoch
        guard let authCredential = authCredentialMap[redemptionTime] else {
            throw OWSErrorMakeAssertionError("No auth credential for redemption time.")
        }

        let serverPublicParams = try VersionedProfiles.serverPublicParams()
        let clientZkAuthOperations = ClientZkAuthOperations(serverPublicParams: serverPublicParams)
        let authCredentialPresentation = try clientZkAuthOperations.createAuthCredentialPresentation(groupSecretParams: groupParams.groupSecretParams, authCredential: authCredential)
        let authCredentialPresentationData = authCredentialPresentation.serialize().asData

        let username: String = groupParams.groupPublicParamsData.hexadecimalString
        let password: String = authCredentialPresentationData.hexadecimalString
        guard let data = "\(username):\(password)".data(using: .utf8) else {
            throw OWSErrorMakeAssertionError("Could not construct authorization.")
        }
        let authHeader = "Basic " + data.base64EncodedString()
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }

    // MARK: - Encryption

    private func encryptTitle(title: String?,
                              groupParams: GroupParams) throws -> Data {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: groupParams.groupSecretParams)
        guard let plaintext: Data = (title ?? "").data(using: .utf8) else {
            throw OWSErrorMakeAssertionError("Could not encrypt value.")
        }
        return try clientZkGroupCipher.encryptBlob(plaintext: [UInt8](plaintext)).asData
    }

    private func decryptTitle(data: Data,
                              groupParams: GroupParams) throws -> String {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: groupParams.groupSecretParams)
        let plaintext = try clientZkGroupCipher.decryptBlob(blobCiphertext: [UInt8](data))
        guard let string = String(bytes: plaintext, encoding: .utf8) else {
            throw OWSErrorMakeAssertionError("Could not decrypt value.")
        }
        return string
    }

    // MARK: - ProfileKeyCredentials

    private func loadProfileKeyCredentialData(for uuids: [UUID]) -> Promise<ProfileKeyCredentialMap> {

        // 1. Use known credentials, where possible.
        var credentialMap = ProfileKeyCredentialMap()

        // GroupsV2 TODO: Persist the ProfileKeyCredential?
        var uuidsWithoutCredentials = [UUID]()
        databaseStorage.read { transaction in
            // Skip duplicates.
            for uuid in Set(uuids) {
                do {
                    let address = SignalServiceAddress(uuid: uuid, phoneNumber: nil)
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
            let address = SignalServiceAddress(uuid: uuid, phoneNumber: nil)
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
                        let address = SignalServiceAddress(uuid: uuid, phoneNumber: nil)
                        guard let credential = try VersionedProfiles.profileKeyCredential(for: address,
                                                                                          transaction: transaction) else {
                                                                                            throw OWSErrorMakeAssertionError("Could load credential.")
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
            let address = SignalServiceAddress(uuid: uuid, phoneNumber: nil)
            promises.append(ProfileFetcherJob.fetchAndUpdateProfilePromise(address: address,
                                                                           mainAppOnly: false,
                                                                           ignoreThrottling: true,
                                                                           shouldUpdateProfile: true,
                                                                           fetchType: .versioned))
        }
        return when(fulfilled: promises).map { ([SignalServiceProfile]) -> Void in
            // Do nothing.
        }
    }

    // MARK: - AuthCredentials

    // GroupsV2 TODO: Reorganize this code.
    private func retrieveCredentials(localUuid: UUID) -> Promise<[UInt32: AuthCredential]> {

        let today = self.daysSinceEpoch
        let todayPlus7 = today + 7
        let request = OWSRequestFactory.groupAuthenticationCredentialRequest(fromRedemptionTime: today,
                                                                             toRedemptionTime: todayPlus7)
        return networkManager.makePromise(request: request)
            .map(on: DispatchQueue.global()) { (response: TSNetworkManager.Response) -> [TemporalCredential] in
                let responseObject = response.responseObject
                return try self.parseCredentialResponse(responseObject: responseObject)
            }.map(on: DispatchQueue.global()) { (temporalCredentials: [TemporalCredential]) in
                let localUuidData: Data = withUnsafeBytes(of: localUuid.uuid) { Data($0) }
                let localZKGUuid = try ZKGUuid(contents: [UInt8](localUuidData))

                let serverPublicParams = try VersionedProfiles.serverPublicParams()
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
            throw OWSErrorMakeAssertionError("Missing response.")
        }

        guard let params = ParamParser(responseObject: responseObject) else {
            throw OWSErrorMakeAssertionError("invalid response: \(String(describing: responseObject))")
        }
        guard let credentials: [Any] = try params.required(key: "credentials") else {
            throw OWSErrorMakeAssertionError("Missing or invalid credentials.")
        }
        var temporalCredentials = [TemporalCredential]()
        for credential in credentials {
            guard let credentialParser = ParamParser(responseObject: credential) else {
                throw OWSErrorMakeAssertionError("invalid credential: \(String(describing: credential))")
            }
            guard let redemptionTime: UInt32 = try credentialParser.required(key: "redemptionTime") else {
                throw OWSErrorMakeAssertionError("Missing or invalid redemptionTime.")
            }
            let responseData: Data = try credentialParser.requiredBase64EncodedData(key: "credential")
            let response = try AuthCredentialResponse(contents: [UInt8](responseData))

            temporalCredentials.append(TemporalCredential(redemptionTime: redemptionTime, authCredentialResponse: response))
        }
        return temporalCredentials
    }

    // MARK: - Utils

    private var daysSinceEpoch: UInt32 {
        let msSinceEpoch = NSDate.ows_millisecondTimeStamp()
        let daysSinceEpoch = UInt32(msSinceEpoch / kDayInMs)
        return daysSinceEpoch
    }

    public func generateGroupSecretParamsData() throws -> Data {
        let groupSecretParams = try GroupSecretParams.generate()
        let bytes = groupSecretParams.serialize()
        return bytes.asData
    }

    private func uuids(for addresses: [SignalServiceAddress]) throws -> [UUID] {
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

// MARK: - GroupsV2Swift

private struct GroupParams {
    let groupSecretParamsData: Data
    let groupSecretParams: GroupSecretParams
    let groupPublicParams: GroupPublicParams
    let groupPublicParamsData: Data

    init(groupModel: TSGroupModel) throws {
        guard let groupSecretParamsData = groupModel.groupSecretParamsData else {
            throw OWSErrorMakeAssertionError("Missing groupSecretParamsData.")
        }
        self.groupSecretParamsData = groupSecretParamsData
        let groupSecretParams = try GroupSecretParams(contents: [UInt8](groupSecretParamsData))
        self.groupSecretParams = groupSecretParams
        let groupPublicParams = try groupSecretParams.getPublicParams()
        self.groupPublicParams = groupPublicParams
        self.groupPublicParamsData = groupPublicParams.serialize().asData
    }
}

// MARK: -

// GroupsV2 TODO: This class is likely to be reworked heavily as we
// start to apply it.
public struct GroupV2StateImpl: GroupV2State {

    struct Member {
        let userID: Data
        let uuid: UUID
        var address: SignalServiceAddress {
            return SignalServiceAddress(uuid: uuid, phoneNumber: nil)
        }
        let role: GroupsProtoMemberRole
        let profileKey: Data
        let joinedAtVersion: UInt32
    }

    struct PendingMember {
        let userID: Data
        let uuid: UUID
        let timestamp: UInt64
    }

    public let groupProto: GroupsProtoGroup

    public let version: UInt32

    public let title: String

    let members: [Member]
    let pendingMembers: [PendingMember]

    public let accessControlForAttributes: GroupsProtoAccessControlAccessRequired
    public let accessControlForMembers: GroupsProtoAccessControlAccessRequired

    public var debugDescription: String {
        return groupProto.debugDescription
    }

    public var activeMembers: [SignalServiceAddress] {
        return members.map { $0.address }
    }

    public var administrators: [SignalServiceAddress] {
        return members.compactMap { member in
            guard member.role == .administrator else {
                return nil
            }
            return member.address
        }
    }
}
