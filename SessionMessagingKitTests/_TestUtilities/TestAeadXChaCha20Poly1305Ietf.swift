// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class TestAeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType, Mockable {
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case encrypt
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    
    // MARK: - SignType
    
    func encrypt(message: Bytes, secretKey: Aead.XChaCha20Poly1305Ietf.Key, additionalData: Bytes?) -> (authenticatedCipherText: Bytes, nonce: Aead.XChaCha20Poly1305Ietf.Nonce)? {
        return (mockData[.encrypt] as? (authenticatedCipherText: Bytes, nonce: Aead.XChaCha20Poly1305Ietf.Nonce))
    }
}
