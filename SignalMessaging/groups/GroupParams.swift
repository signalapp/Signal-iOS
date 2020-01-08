//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import ZKGroup

public struct GroupParams {
    let groupSecretParamsData: Data
    let groupSecretParams: GroupSecretParams
    let groupPublicParams: GroupPublicParams
    let groupPublicParamsData: Data

    public init(groupModel: TSGroupModel) throws {
        guard let groupSecretParamsData = groupModel.groupSecretParamsData else {
            throw OWSAssertionError("Missing groupSecretParamsData.")
        }
        try self.init(groupSecretParamsData: groupSecretParamsData)
    }

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

public extension GroupParams {
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
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: groupSecretParams)
        return try clientZkGroupCipher.encryptBlob(plaintext: [UInt8](plaintext)).asData
    }

    func decryptBlob(_ data: Data) throws -> Data {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: groupSecretParams)
        let plaintext = try clientZkGroupCipher.decryptBlob(blobCiphertext: [UInt8](data))
        return plaintext.asData
    }

    func uuid(forUserId userId: Data) throws -> UUID {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: self.groupSecretParams)

        let uuidCiphertext = try UuidCiphertext(contents: [UInt8](userId))
        let zkgUuid = try clientZkGroupCipher.decryptUuid(uuidCiphertext: uuidCiphertext)
        return try zkgUuid.asUUID()
    }

    func userId(forUuid uuid: UUID) throws -> Data {
        let clientZkGroupCipher = ClientZkGroupCipher(groupSecretParams: self.groupSecretParams)
        let uuidCiphertext = try clientZkGroupCipher.encryptUuid(uuid: try uuid.asZKGUuid())
        return uuidCiphertext.serialize().asData
    }
}
