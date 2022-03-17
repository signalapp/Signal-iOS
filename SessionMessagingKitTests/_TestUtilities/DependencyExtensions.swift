// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionSnodeKit

@testable import SessionMessagingKit

extension Dependencies {
    public func with(
        onionApi: OnionRequestAPIType.Type? = nil,
        identityManager: IdentityManagerProtocol? = nil,
        storage: SessionMessagingKitStorageProtocol? = nil,
        sodium: SodiumType? = nil,
        aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType? = nil,
        sign: SignType? = nil,
        genericHash: GenericHashType? = nil,
        ed25519: Ed25519Type? = nil,
        nonceGenerator16: NonceGenerator16ByteType? = nil,
        nonceGenerator24: NonceGenerator24ByteType? = nil,
        standardUserDefaults: UserDefaultsType? = nil,
        date: Date? = nil
    ) -> Dependencies {
        return Dependencies(
            onionApi: (onionApi ?? self._onionApi),
            identityManager: (identityManager ?? self._identityManager),
            storage: (storage ?? self._storage),
            sodium: (sodium ?? self._sodium),
            aeadXChaCha20Poly1305Ietf: (aeadXChaCha20Poly1305Ietf ?? self._aeadXChaCha20Poly1305Ietf),
            sign: (sign ?? self._sign),
            genericHash: (genericHash ?? self._genericHash),
            ed25519: (ed25519 ?? self._ed25519),
            nonceGenerator16: (nonceGenerator16 ?? self._nonceGenerator16),
            nonceGenerator24: (nonceGenerator24 ?? self._nonceGenerator24),
            standardUserDefaults: (standardUserDefaults ?? self._standardUserDefaults),
            date: (date ?? self._date)
        )
    }
}
