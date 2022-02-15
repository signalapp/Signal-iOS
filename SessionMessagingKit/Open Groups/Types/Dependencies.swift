// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import SessionSnodeKit

extension OpenGroupAPI {
    public struct Dependencies {
        let api: OnionRequestAPIType.Type
        let storage: SessionMessagingKitStorageProtocol
        let sodium: SodiumType
        let genericHash: GenericHashType
        let nonceGenerator: NonceGenerator16ByteType
        let date: Date
        
        public init(
            api: OnionRequestAPIType.Type = OnionRequestAPI.self,
            storage: SessionMessagingKitStorageProtocol = SNMessagingKitConfiguration.shared.storage,
            sodium: SodiumType = Sodium(),
            genericHash: GenericHashType? = nil,
            nonceGenerator: NonceGenerator16ByteType = NonceGenerator16Byte(),
            date: Date = Date()
        ) {
            self.api = api
            self.storage = storage
            self.sodium = sodium
            self.genericHash = (genericHash ?? sodium.getGenericHash())
            self.nonceGenerator = nonceGenerator
            self.date = date
        }
        
        // MARK: - Convenience
        
        public func with(
            api: OnionRequestAPIType.Type? = nil,
            storage: SessionMessagingKitStorageProtocol? = nil,
            sodium: SodiumType? = nil,
            genericHash: GenericHashType? = nil,
            nonceGenerator: NonceGenerator16ByteType? = nil,
            date: Date? = nil
        ) -> Dependencies {
            return Dependencies(
                api: (api ?? self.api),
                storage: (storage ?? self.storage),
                sodium: (sodium ?? self.sodium),
                genericHash: (genericHash ?? self.genericHash),
                nonceGenerator: (nonceGenerator ?? self.nonceGenerator),
                date: (date ?? self.date)
            )
        }
    }
}
