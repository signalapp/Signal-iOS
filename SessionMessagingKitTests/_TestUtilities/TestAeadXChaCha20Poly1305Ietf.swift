// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class TestAeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType, Mockable {
    var KeyBytes: Int = 32
    var ABytes: Int = 16
    
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case encrypt
        case decrypt
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    
    // MARK: - SignType
    
    func encrypt(message: Bytes, secretKey: Bytes, nonce: Bytes, additionalData: Bytes?) -> Bytes? {
        return (mockData[.encrypt] as? Bytes)
    }
    
    func decrypt(authenticatedCipherText: Bytes, secretKey: Bytes, nonce: Bytes, additionalData: Bytes?) -> Bytes? {
        return (mockData[.decrypt] as? Bytes)
    }
}
