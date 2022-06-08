// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

@testable import SessionMessagingKit

class MockNonce16Generator: Mock<NonceGenerator16ByteType>, NonceGenerator16ByteType {
    var NonceBytes: Int = 16
    
    func nonce() -> Array<UInt8> { return accept() as! [UInt8] }
}
