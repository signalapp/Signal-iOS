// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class MockEd25519: Mock<Ed25519Type>, Ed25519Type {
    func sign(data: Bytes, keyPair: Box.KeyPair) throws -> Bytes? {
        return accept(args: [data, keyPair]) as? Bytes
    }
    
    func verifySignature(_ signature: Data, publicKey: Data, data: Data) throws -> Bool {
        return accept(args: [signature, publicKey, data]) as! Bool
    }
}
