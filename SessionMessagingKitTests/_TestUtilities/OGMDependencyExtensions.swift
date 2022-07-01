// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionSnodeKit
import SessionUtilitiesKit

@testable import SessionMessagingKit

extension OpenGroupManager.OGMDependencies {
    public func with(
        cache: Atomic<OGMCacheType>? = nil,
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
    ) -> OpenGroupManager.OGMDependencies {
        return OpenGroupManager.OGMDependencies(
            cache: (cache ?? self._mutableCache),
            onionApi: (onionApi ?? self._onionApi),
            generalCache: (generalCache ?? self._generalCache),
            storage: (storage ?? self._storage),
            sodium: (sodium ?? self._sodium),
            box: (box ?? self._box),
            genericHash: (genericHash ?? self._genericHash),
            sign: (sign ?? self._sign),
            aeadXChaCha20Poly1305Ietf: (aeadXChaCha20Poly1305Ietf ?? self._aeadXChaCha20Poly1305Ietf),
            ed25519: (ed25519 ?? self._ed25519),
            nonceGenerator16: (nonceGenerator16 ?? self._nonceGenerator16),
            nonceGenerator24: (nonceGenerator24 ?? self._nonceGenerator24),
            standardUserDefaults: (standardUserDefaults ?? self._standardUserDefaults),
            date: (date ?? self._date)
        )
    }
}
