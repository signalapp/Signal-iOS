//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import LibSignalClient

public struct GroupV2Params {
    let groupSecretParamsData: Data
    let groupSecretParams: GroupSecretParams
    let groupPublicParams: GroupPublicParams
    let groupPublicParamsData: Data

    public init(groupSecretParamsData: Data) throws {
        self.groupSecretParamsData = groupSecretParamsData
        let groupSecretParams = try GroupSecretParams(contents: [UInt8](groupSecretParamsData))
        self.groupSecretParams = groupSecretParams
        let groupPublicParams = try groupSecretParams.getPublicParams()
        self.groupPublicParams = groupPublicParams
        self.groupPublicParamsData = groupPublicParams.serialize().asData
    }
}

// MARK: -

public extension TSGroupModelV2 {
    func groupV2Params() throws -> GroupV2Params {
        return try GroupV2Params(groupSecretParamsData: secretParamsData)
    }
}

// MARK: -

public extension GroupV2Params {

    fileprivate func encryptString(_ value: String) throws -> Data {
        guard let plaintext: Data = value.data(using: .utf8) else {
            throw OWSAssertionError("Could not encrypt value.")
        }
        return try encryptBlob(plaintext)
    }

    fileprivate func decryptString(_ data: Data) throws -> String {
        let plaintext = try decryptBlob(data)
        guard let string = String(bytes: plaintext, encoding: .utf8) else {
            throw OWSAssertionError("Could not decrypt value.")
        }
        return string
    }

    fileprivate func encryptBlob(_ plaintext: Data) throws -> Data {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: groupSecretParams)
        let ciphertext = try clientZkGroupCipher.encryptBlob(plaintext: [UInt8](plaintext)).asData
        assert(ciphertext != plaintext)
        assert(!ciphertext.isEmpty)

        if plaintext.count <= Self.decryptedBlobCacheMaxItemSize {
            let cacheKey = (ciphertext + groupSecretParamsData)
            Self.decryptedBlobCache.setObject(plaintext, forKey: cacheKey)
        }

        return ciphertext
    }

    private static let decryptedBlobCache = LRUCache<Data, Data>(maxSize: 16,
                                                                 shouldEvacuateInBackground: true)
    private static let decryptedBlobCacheMaxItemSize: UInt = 4 * 1024

    fileprivate func decryptBlob(_ ciphertext: Data) throws -> Data {
        let cacheKey = (ciphertext + groupSecretParamsData)
        if let plaintext = Self.decryptedBlobCache.object(forKey: cacheKey) {
            return plaintext
        }

        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: groupSecretParams)
        let plaintext = try clientZkGroupCipher.decryptBlob(blobCiphertext: [UInt8](ciphertext)).asData
        assert(ciphertext != plaintext)

        if plaintext.count <= Self.decryptedBlobCacheMaxItemSize {
            Self.decryptedBlobCache.setObject(plaintext, forKey: cacheKey)
        }
        return plaintext
    }

    func aci(for userId: Data) throws -> Aci {
        guard let aci = try serviceId(for: userId) as? Aci else {
            // PNI TODO: Update this to a more appropriate error.
            throw OWSGenericError("Wrong type of ServiceId.")
        }
        return aci
    }

    func serviceId(for userId: Data) throws -> ServiceId {
        let uuidCiphertext = try UuidCiphertext(contents: [UInt8](userId))
        return try serviceId(for: uuidCiphertext)
    }

    func aci(for uuidCiphertext: UuidCiphertext) throws -> Aci {
        guard let aci = try serviceId(for: uuidCiphertext) as? Aci else {
            // PNI TODO: Update this to a more appropriate error.
            throw OWSGenericError("Wrong type of ServiceId.")
        }
        return aci
    }

    private static var maxGroupSize: Int {
        return Int(RemoteConfig.groupsV2MaxGroupSizeHardLimit)
    }

    private static let decryptedServiceIdCache = LRUCache<Data, ServiceId>(
        maxSize: Self.maxGroupSize,
        nseMaxSize: Self.maxGroupSize
    )

    func serviceId(for uuidCiphertext: UuidCiphertext) throws -> ServiceId {
        let cacheKey = (uuidCiphertext.serialize().asData + groupSecretParamsData)
        if let plaintext = Self.decryptedServiceIdCache.object(forKey: cacheKey) {
            return plaintext
        }

        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: self.groupSecretParams)
        // PNI TODO: Support PNIs.
        let serviceId = Aci(fromUUID: try clientZkGroupCipher.decryptUuid(uuidCiphertext: uuidCiphertext))

        Self.decryptedServiceIdCache.setObject(serviceId, forKey: cacheKey)
        return serviceId
    }

    func userId(for serviceId: ServiceId) throws -> Data {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: self.groupSecretParams)
        // PNI TODO: Support PNIs.
        let uuidCiphertext = try clientZkGroupCipher.encryptUuid(uuid: serviceId.rawUUID)
        let userId = uuidCiphertext.serialize().asData

        let cacheKey = (userId + groupSecretParamsData)
        Self.decryptedServiceIdCache.setObject(serviceId, forKey: cacheKey)

        return userId
    }

    private static let decryptedProfileKeyCache = LRUCache<Data, Data>(maxSize: Self.maxGroupSize,
                                                                       nseMaxSize: Self.maxGroupSize)

    func profileKey(forProfileKeyCiphertext profileKeyCiphertext: ProfileKeyCiphertext, aci: Aci) throws -> Data {
        let cacheKey = (profileKeyCiphertext.serialize().asData + aci.serviceIdBinary + groupSecretParamsData)
        if let plaintext = Self.decryptedProfileKeyCache.object(forKey: cacheKey) {
            return plaintext
        }

        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: self.groupSecretParams)
        let profileKey = try clientZkGroupCipher.decryptProfileKey(profileKeyCiphertext: profileKeyCiphertext, uuid: aci.rawUUID)
        let plaintext = profileKey.serialize().asData

        Self.decryptedProfileKeyCache.setObject(plaintext, forKey: cacheKey)
        return plaintext
    }
}

// MARK: -

public extension GroupV2Params {
    func decryptDisappearingMessagesTimer(_ ciphertext: Data?) -> DisappearingMessageToken {
        guard let ciphertext = ciphertext else {
            // Treat a missing value as disabled.
            return DisappearingMessageToken.disabledToken
        }
        do {
            let blobProtoData = try decryptBlob(ciphertext)
            let blobProto = try GroupsProtoGroupAttributeBlob(serializedData: blobProtoData)
            if let blobContent = blobProto.content {
                switch blobContent {
                case .disappearingMessagesDuration(let value):
                    return DisappearingMessageToken.token(forProtoExpireTimer: value)
                default:
                    owsFailDebug("Invalid disappearing messages value.")
                }
            }
        } catch {
            owsFailDebug("Could not decrypt and parse disappearing messages state: \(error).")
        }
        return DisappearingMessageToken.disabledToken
    }

    func encryptDisappearingMessagesTimer(_ token: DisappearingMessageToken) throws -> Data {
        do {
            let duration = (token.isEnabled
                                ? token.durationSeconds
                                : 0)
            var blobBuilder = GroupsProtoGroupAttributeBlob.builder()
            blobBuilder.setContent(GroupsProtoGroupAttributeBlobOneOfContent.disappearingMessagesDuration(duration))
            let blobData = try blobBuilder.buildSerializedData()
            let encryptedTimerData = try encryptBlob(blobData)
            return encryptedTimerData
        } catch {
            owsFailDebug("Error: \(error)")
            throw error
        }
    }

    func decryptGroupName(_ ciphertext: Data?) -> String? {
        guard let ciphertext = ciphertext else {
            // Treat a missing value as no value.
            return nil
        }
        do {
            let blobProtoData = try decryptBlob(ciphertext)
            let blobProto = try GroupsProtoGroupAttributeBlob(serializedData: blobProtoData)
            if let blobContent = blobProto.content {
                switch blobContent {
                case .title(let value):
                    return value
                default:
                    owsFailDebug("Invalid group name value.")
                }
            }
        } catch {
            owsFailDebug("Could not decrypt group name: \(error).")
        }
        return nil
    }

    func encryptGroupName(_ value: String) throws -> Data {
        do {
            var blobBuilder = GroupsProtoGroupAttributeBlob.builder()
            blobBuilder.setContent(GroupsProtoGroupAttributeBlobOneOfContent.title(value))
            let blobData = try blobBuilder.buildSerializedData()
            let encryptedTimerData = try encryptBlob(blobData)
            return encryptedTimerData
        } catch {
            owsFailDebug("Error: \(error)")
            throw error
        }
    }

    func decryptGroupDescription(_ ciphertext: Data?) -> String? {
        guard let ciphertext = ciphertext else {
            // Treat a missing value as no value.
            return nil
        }
        do {
            let blobProtoData = try decryptBlob(ciphertext)
            let blobProto = try GroupsProtoGroupAttributeBlob(serializedData: blobProtoData)
            if let blobContent = blobProto.content {
                switch blobContent {
                case .descriptionText(let value):
                    return value
                default:
                    owsFailDebug("Invalid group description value.")
                }
            }
        } catch {
            owsFailDebug("Could not decrypt group name: \(error).")
        }
        return nil
    }

    func encryptGroupDescription(_ value: String) throws -> Data {
        do {
            var blobBuilder = GroupsProtoGroupAttributeBlob.builder()
            blobBuilder.setContent(GroupsProtoGroupAttributeBlobOneOfContent.descriptionText(value))
            let blobData = try blobBuilder.buildSerializedData()
            let ciphertext = try encryptBlob(blobData)
            return ciphertext
        } catch {
            owsFailDebug("Error: \(error)")
            throw error
        }
    }

    func decryptGroupAvatar(_ ciphertext: Data) throws -> Data? {
        do {
            let blobProtoData = try decryptBlob(ciphertext)
            let blobProto = try GroupsProtoGroupAttributeBlob(serializedData: blobProtoData)
            if let blobContent = blobProto.content {
                switch blobContent {
                case .avatar(let value):
                    return value
                default:
                    owsFailDebug("Invalid group avatar value.")
                }
            }
            return nil
        } catch {
            owsFailDebug("Error: \(error)")
            throw error
        }
}

    func encryptGroupAvatar(_ value: Data) throws -> Data {
        do {
            var blobBuilder = GroupsProtoGroupAttributeBlob.builder()
            blobBuilder.setContent(GroupsProtoGroupAttributeBlobOneOfContent.avatar(value))
            let blobData = try blobBuilder.buildSerializedData()
            let encryptedTimerData = try encryptBlob(blobData)
            return encryptedTimerData
        } catch {
            owsFailDebug("Error: \(error)")
            throw error
        }
    }
}
