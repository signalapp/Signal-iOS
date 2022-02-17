// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import SessionSnodeKit

extension OpenGroupAPI {
    public struct Dependencies {
        let api: OnionRequestAPIType.Type
        let storage: SessionMessagingKitStorageProtocol
        let sodium: SodiumType
        let aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType
        let genericHash: GenericHashType
        let nonceGenerator: NonceGenerator16ByteType
        let date: Date
        
        public init(
            api: OnionRequestAPIType.Type = OnionRequestAPI.self,
            storage: SessionMessagingKitStorageProtocol = SNMessagingKitConfiguration.shared.storage,
            sodium: SodiumType = Sodium(),
            aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType? = nil,
            genericHash: GenericHashType? = nil,
            nonceGenerator: NonceGenerator16ByteType = NonceGenerator16Byte(),
            date: Date = Date()
        ) {
            self.api = api
            self.storage = storage
            self.sodium = sodium
            self.aeadXChaCha20Poly1305Ietf = (aeadXChaCha20Poly1305Ietf ?? sodium.getAeadXChaCha20Poly1305Ietf())
            self.genericHash = (genericHash ?? sodium.getGenericHash())
            self.nonceGenerator = nonceGenerator
            self.date = date
        }
        
        // MARK: - Convenience
        
        public func with(
            api: OnionRequestAPIType.Type? = nil,
            storage: SessionMessagingKitStorageProtocol? = nil,
            sodium: SodiumType? = nil,
            aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType? = nil,
            genericHash: GenericHashType? = nil,
            nonceGenerator: NonceGenerator16ByteType? = nil,
            date: Date? = nil
        ) -> Dependencies {
            return Dependencies(
                api: (api ?? self.api),
                storage: (storage ?? self.storage),
                sodium: (sodium ?? self.sodium),
                aeadXChaCha20Poly1305Ietf: (aeadXChaCha20Poly1305Ietf ?? self.aeadXChaCha20Poly1305Ietf),
                genericHash: (genericHash ?? self.genericHash),
                nonceGenerator: (nonceGenerator ?? self.nonceGenerator),
                date: (date ?? self.date)
            )
        }
    }
}
