//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

struct PreKeyBundle: Decodable {
    let identityKey: IdentityKey
    let devices: [PreKeyDeviceBundle]

    enum CodingKeys: CodingKey {
        case identityKey
        case devices
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identityKeyString = try container.decode(String.self, forKey: .identityKey)
        guard
            let identityKeyData = Data(base64EncodedWithoutPadding: identityKeyString),
            identityKeyData.count == 33
        else {
            throw DecodingError.dataCorruptedError(forKey: CodingKeys.identityKey, in: container, debugDescription: "")
        }
        self.identityKey = try IdentityKey(bytes: identityKeyData)
        self.devices = try container.decode([PreKeyDeviceBundle].self, forKey: .devices)
    }

    struct PreKeyDeviceBundle: Decodable {
        let deviceId: Int8
        let registrationId: UInt32
        let signedPreKey: SignedPreKey
        let preKey: OneTimePreKey?
        let pqPreKey: PQPreKey?

        struct OneTimePreKey: Decodable {
            let keyId: UInt32
            let publicKey: PublicKey

            enum CodingKeys: CodingKey {
                case keyId
                case publicKey
            }

            init(from decoder: any Decoder) throws {
                let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
                self.keyId = try container.decode(UInt32.self, forKey: CodingKeys.keyId)
                let publicKeyString = try container.decode(String.self, forKey: CodingKeys.publicKey)
                guard
                    let publicKeyData = Data(base64EncodedWithoutPadding: publicKeyString),
                    publicKeyData.count == 33
                else {
                    throw DecodingError.dataCorruptedError(forKey: CodingKeys.publicKey, in: container, debugDescription: "")
                }
                self.publicKey = try PublicKey(publicKeyData)
            }
        }

        struct SignedPreKey: Decodable {
            let keyId: UInt32
            let signature: Data
            let publicKey: PublicKey

            enum CodingKeys: CodingKey {
                case keyId
                case signature
                case publicKey
            }

            init(from decoder: any Decoder) throws {
                let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
                self.keyId = try container.decode(UInt32.self, forKey: CodingKeys.keyId)
                let signatureString = try container.decode(String.self, forKey: CodingKeys.signature)
                guard let signatureData = Data(base64EncodedWithoutPadding: signatureString) else {
                    throw DecodingError.dataCorruptedError(forKey: CodingKeys.signature, in: container, debugDescription: "")
                }
                self.signature = signatureData
                let publicKeyString = try container.decode(String.self, forKey: CodingKeys.publicKey)
                guard
                    let publicKeyData = Data(base64EncodedWithoutPadding: publicKeyString),
                    publicKeyData.count == 33
                else {
                    throw DecodingError.dataCorruptedError(forKey: CodingKeys.publicKey, in: container, debugDescription: "")
                }
                self.publicKey = try PublicKey(publicKeyData)
            }
        }

        struct PQPreKey: Decodable {
            let keyId: UInt32
            let signature: Data
            let publicKey: KEMPublicKey

            enum CodingKeys: CodingKey {
                case keyId
                case signature
                case publicKey
            }

            init(from decoder: any Decoder) throws {
                let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
                self.keyId = try container.decode(UInt32.self, forKey: CodingKeys.keyId)
                let signatureString = try container.decode(String.self, forKey: CodingKeys.signature)
                guard let signatureData = Data(base64EncodedWithoutPadding: signatureString) else {
                    throw DecodingError.dataCorruptedError(forKey: CodingKeys.signature, in: container, debugDescription: "")
                }
                self.signature = signatureData
                let publicKeyString = try container.decode(String.self, forKey: CodingKeys.publicKey)
                guard let publicKeyData = Data(base64EncodedWithoutPadding: publicKeyString) else {
                    throw DecodingError.dataCorruptedError(forKey: CodingKeys.publicKey, in: container, debugDescription: "")
                }
                self.publicKey = try KEMPublicKey(publicKeyData)
            }
        }
    }
}
