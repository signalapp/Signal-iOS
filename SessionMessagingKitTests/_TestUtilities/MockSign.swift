// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class MockSign: Mock<SignType>, SignType {
    var Bytes: Int = 64
    var PublicKeyBytes: Int = 32
    
    func signature(message: Bytes, secretKey: Bytes) -> Bytes? {
        return accept(args: [message, secretKey]) as? Bytes
    }
    
    func verify(message: Bytes, publicKey: Bytes, signature: Bytes) -> Bool {
        return accept(args: [message, publicKey, signature]) as! Bool
    }
    
    func toX25519(ed25519PublicKey: Bytes) -> Bytes? {
        return accept(args: [ed25519PublicKey]) as? Bytes
    }
}
