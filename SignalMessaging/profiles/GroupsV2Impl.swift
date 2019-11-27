//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit
import ZKGroup

@objc
public class GroupsV2Impl: NSObject, GroupsV2 {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: - Create Group v2

    public func createNewGroupV2OnService(groupModel: TSGroupModel) -> Promise<Void> {
        // TODO: Should we make sure we have a local profile credential?
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSErrorMakeAssertionError("Missing localUuid."))
        }
        return DispatchQueue.global().async(.promise) { () -> [UUID] in
            let uuids = try self.uuids(for: groupModel.groupMembers)
            return uuids
        }.map(on: DispatchQueue.global()) { uuids in
            let allUuids = uuids + [localUuid]
            let uuidmap = self.loadProfileKeyCredentialData(for: allUuids)
            Logger.verbose("uuidmap: \(uuidmap)")
            // TODO: Finish creating group on service.
        }
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

    private func loadProfileKeyCredentialData(for uuids: [UUID]) -> Promise<[UUID: ProfileKeyCredential]> {

        // 1. Use known credentials, where possible.
        var credentialMap = [UUID: ProfileKeyCredential]()
        var uuidsWithoutCredentials = [UUID]()
        databaseStorage.read { transaction in
            for uuid in uuids {
                do {
                    let address = SignalServiceAddress(uuid: uuid, phoneNumber: nil)
                    if let credential = try VersionedProfiles.profileKeyCredential(for: address,
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
        var promises = [Promise<(UUID, ProfileKeyCredential)>]()
        for uuid in uuidsWithoutCredentials {
            let address = SignalServiceAddress(uuid: uuid, phoneNumber: nil)
            let promise = ProfileFetcherJob.fetchAndUpdateProfilePromise(address: address,
                                                                         mainAppOnly: false,
                                                                         ignoreThrottling: true,
                                                                         fetchType: .versioned)
                .map(on: DispatchQueue.global()) { (serviceProfile: SignalServiceProfile) -> (UUID, ProfileKeyCredential) in
                    guard let data: Data = serviceProfile.credential else {
                        throw OWSErrorMakeAssertionError("Missing credential.")
                    }
                    let bytes: [UInt8] = [UInt8](data)
                    let credential = try ProfileKeyCredential(contents: bytes)
                    return (uuid, credential)
            }
            promises.append(promise)
        }
        return when(fulfilled: promises)
            .map(on: DispatchQueue.global()) { tuples in
                for (uuid, credential) in tuples {
                    credentialMap[uuid] = credential
                }
                return credentialMap
        }
    }

    public func generateGroupSecretParamsData() throws -> Data {
        let sroupSecretParams = try GroupSecretParams.generate()
        let bytes = sroupSecretParams.serialize()
        return bytes.asData
    }
}
