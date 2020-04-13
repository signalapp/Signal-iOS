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
    func encryptString(_ value: String) throws -> Data {
        guard let plaintext: Data = value.data(using: .utf8) else {
            throw OWSAssertionError("Could not encrypt value.")
        }
        return try encryptBlob(plaintext)
    }

    func decryptString(_ data: Data) throws -> String {
        let plaintext = try decryptBlob(data)
        guard let string = String(bytes: plaintext, encoding: .utf8) else {
            throw OWSAssertionError("Could not decrypt value.")
        }
        return string
    }

    func encryptBlob(_ plaintext: Data) throws -> Data {
        guard !DebugFlags.groupsV2corruptBlobEncryption else {
            return Randomness.generateRandomBytes(Int32(plaintext.count))
        }
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: groupSecretParams)
        let ciphertext = try clientZkGroupCipher.encryptBlob(plaintext: [UInt8](plaintext)).asData
        assert(ciphertext != plaintext)
        assert(ciphertext.count > 0)
        return ciphertext
    }

    func decryptBlob(_ ciphertext: Data) throws -> Data {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: groupSecretParams)
        let plaintext = try clientZkGroupCipher.decryptBlob(blobCiphertext: [UInt8](ciphertext)).asData
        assert(ciphertext != plaintext)
        return ciphertext
    }

    func uuid(forUserId userId: Data) throws -> UUID {
        let uuidCiphertext = try UuidCiphertext(contents: [UInt8](userId))
        return try uuid(forUuidCiphertext: uuidCiphertext)
    }

    func uuid(forUuidCiphertext uuidCiphertext: UuidCiphertext) throws -> UUID {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: self.groupSecretParams)
        let zkgUuid = try clientZkGroupCipher.decryptUuid(uuidCiphertext: uuidCiphertext)
        return zkgUuid.asUUID()
    }

    func userId(forUuid uuid: UUID) throws -> Data {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: self.groupSecretParams)
        let uuidCiphertext = try clientZkGroupCipher.encryptUuid(uuid: try uuid.asZKGUuid())
        return uuidCiphertext.serialize().asData
    }

    func profileKey(forProfileKeyCiphertext profileKeyCiphertext: ProfileKeyCiphertext,
                    uuid: UUID) throws -> Data {
        let zkgUuid = try uuid.asZKGUuid()
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: self.groupSecretParams)
        let profileKey = try clientZkGroupCipher.decryptProfileKey(profileKeyCiphertext: profileKeyCiphertext,
                                                                   uuid: zkgUuid)
        return profileKey.serialize().asData
    }
}
