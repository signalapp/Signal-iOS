//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import ZKGroup

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
        guard !DebugFlags.groupsV2corruptBlobEncryption.get() else {
            return Randomness.generateRandomBytes(Int32(plaintext.count))
        }
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: groupSecretParams)
        let ciphertext = try clientZkGroupCipher.encryptBlob(plaintext: [UInt8](plaintext)).asData
        assert(ciphertext != plaintext)
        assert(ciphertext.count > 0)

        if plaintext.count <= Self.decryptedBlobCacheMaxItemSize {
            let cacheKey = (groupSecretParamsData + ciphertext) as NSData
            Self.decryptedBlobCache.setObject(plaintext as NSData, forKey: cacheKey)
        }

        return ciphertext
    }

    private static let decryptedBlobCache = NSCache<NSData, NSData>()
    private static let decryptedBlobCacheMaxItemSize: UInt = 4 * 1024

    fileprivate func decryptBlob(_ ciphertext: Data) throws -> Data {
        let cacheKey = (groupSecretParamsData + ciphertext) as NSData
        if let plaintext = Self.decryptedBlobCache.object(forKey: cacheKey) {
            return plaintext as Data
        }

        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: groupSecretParams)
        let plaintext = try clientZkGroupCipher.decryptBlob(blobCiphertext: [UInt8](ciphertext)).asData
        assert(ciphertext != plaintext)

        if plaintext.count <= Self.decryptedBlobCacheMaxItemSize {
            Self.decryptedBlobCache.setObject(plaintext as NSData, forKey: cacheKey)
        }
        return plaintext
    }

    func uuid(forUserId userId: Data) throws -> UUID {
        let uuidCiphertext = try UuidCiphertext(contents: [UInt8](userId))
        return try uuid(forUuidCiphertext: uuidCiphertext)
    }

    private static let decryptedUuidCache = NSCache<NSData, NSUUID>()

    func uuid(forUuidCiphertext uuidCiphertext: UuidCiphertext) throws -> UUID {
        let cacheKey = (groupSecretParamsData + uuidCiphertext.serialize().asData) as NSData
        if let plaintext = Self.decryptedUuidCache.object(forKey: cacheKey) {
            return plaintext as UUID
        }

        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: self.groupSecretParams)
        let zkgUuid = try clientZkGroupCipher.decryptUuid(uuidCiphertext: uuidCiphertext)
        let uuid = zkgUuid.asUUID()

        Self.decryptedUuidCache.setObject(uuid as NSUUID, forKey: cacheKey)
        return uuid
    }

    func userId(forUuid uuid: UUID) throws -> Data {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: self.groupSecretParams)
        let uuidCiphertext = try clientZkGroupCipher.encryptUuid(uuid: try uuid.asZKGUuid())
        let userId = uuidCiphertext.serialize().asData

        let cacheKey = (groupSecretParamsData + userId) as NSData
        Self.decryptedUuidCache.setObject(uuid as NSUUID, forKey: cacheKey)

        return userId
    }

    private static let decryptedProfileKeyCache = NSCache<NSData, NSData>()

    func profileKey(forProfileKeyCiphertext profileKeyCiphertext: ProfileKeyCiphertext,
                    uuid: UUID) throws -> Data {
        let zkgUuid = try uuid.asZKGUuid()

        let cacheKey = (groupSecretParamsData + profileKeyCiphertext.serialize().asData + zkgUuid.serialize().asData) as NSData
        if let plaintext = Self.decryptedProfileKeyCache.object(forKey: cacheKey) {
            return plaintext as Data
        }

        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: self.groupSecretParams)
        let profileKey = try clientZkGroupCipher.decryptProfileKey(profileKeyCiphertext: profileKeyCiphertext,
                                                                   uuid: zkgUuid)
        let plaintext = profileKey.serialize().asData

        Self.decryptedProfileKeyCache.setObject(plaintext as NSData, forKey: cacheKey)
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
        let duration = (token.isEnabled
            ? token.durationSeconds
            : 0)
        var blobBuilder = GroupsProtoGroupAttributeBlob.builder()
        blobBuilder.setContent(GroupsProtoGroupAttributeBlobOneOfContent.disappearingMessagesDuration(duration))
        let blobData = try blobBuilder.buildSerializedData()
        let encryptedTimerData = try encryptBlob(blobData)
        return encryptedTimerData
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
        var blobBuilder = GroupsProtoGroupAttributeBlob.builder()
        blobBuilder.setContent(GroupsProtoGroupAttributeBlobOneOfContent.title(value))
        let blobData = try blobBuilder.buildSerializedData()
        let encryptedTimerData = try encryptBlob(blobData)
        return encryptedTimerData
    }

    func decryptGroupAvatar(_ ciphertext: Data) throws -> Data? {
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
    }

    func encryptGroupAvatar(_ value: Data) throws -> Data {
        var blobBuilder = GroupsProtoGroupAttributeBlob.builder()
        blobBuilder.setContent(GroupsProtoGroupAttributeBlobOneOfContent.avatar(value))
        let blobData = try blobBuilder.buildSerializedData()
        let encryptedTimerData = try encryptBlob(blobData)
        return encryptedTimerData
    }
}
