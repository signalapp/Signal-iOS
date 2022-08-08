// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

@testable import SessionMessagingKit

class MockNonce24Generator: Mock<NonceGenerator24ByteType>, NonceGenerator24ByteType {
    var NonceBytes: Int = 24
    
    func nonce() -> Array<UInt8> { return accept() as! [UInt8] }
}
