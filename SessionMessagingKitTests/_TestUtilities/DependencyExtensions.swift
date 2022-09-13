// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionSnodeKit
import SessionUtilitiesKit

@testable import SessionMessagingKit

extension SMKDependencies {
    public func with(
        onionApi: OnionRequestAPIType.Type? = nil,
        generalCache: Atomic<GeneralCacheType>? = nil,
        storage: Storage? = nil,
        sodium: SodiumType? = nil,
        box: BoxType? = nil,
        genericHash: GenericHashType? = nil,
        sign: SignType? = nil,
        aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType? = nil,
        ed25519: Ed25519Type? = nil,
        nonceGenerator16: NonceGenerator16ByteType? = nil,
        nonceGenerator24: NonceGenerator24ByteType? = nil,
        standardUserDefaults: UserDefaultsType? = nil,
        date: Date? = nil
    ) -> SMKDependencies {
        return SMKDependencies(
            onionApi: (onionApi ?? self._onionApi.wrappedValue),
            generalCache: (generalCache ?? self._generalCache.wrappedValue),
            storage: (storage ?? self._storage.wrappedValue),
            sodium: (sodium ?? self._sodium.wrappedValue),
            box: (box ?? self._box.wrappedValue),
            genericHash: (genericHash ?? self._genericHash.wrappedValue),
            sign: (sign ?? self._sign.wrappedValue),
            aeadXChaCha20Poly1305Ietf: (aeadXChaCha20Poly1305Ietf ?? self._aeadXChaCha20Poly1305Ietf.wrappedValue),
            ed25519: (ed25519 ?? self._ed25519.wrappedValue),
            nonceGenerator16: (nonceGenerator16 ?? self._nonceGenerator16.wrappedValue),
            nonceGenerator24: (nonceGenerator24 ?? self._nonceGenerator24.wrappedValue),
            standardUserDefaults: (standardUserDefaults ?? self._standardUserDefaults.wrappedValue),
            date: (date ?? self._date.wrappedValue)
        )
    }
}
