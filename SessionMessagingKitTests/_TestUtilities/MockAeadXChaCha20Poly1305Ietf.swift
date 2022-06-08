// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class MockAeadXChaCha20Poly1305Ietf: Mock<AeadXChaCha20Poly1305IetfType>, AeadXChaCha20Poly1305IetfType {
    var KeyBytes: Int = 32
    var ABytes: Int = 16
    
    func encrypt(message: Bytes, secretKey: Bytes, nonce: Bytes, additionalData: Bytes?) -> Bytes? {
        return accept(args: [message, secretKey, nonce, additionalData]) as? Bytes
    }
    
    func decrypt(authenticatedCipherText: Bytes, secretKey: Bytes, nonce: Bytes, additionalData: Bytes?) -> Bytes? {
        return accept(args: [authenticatedCipherText, secretKey, nonce, additionalData]) as? Bytes
    }
}
