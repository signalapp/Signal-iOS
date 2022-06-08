// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class MockGenericHash: Mock<GenericHashType>, GenericHashType {
    func hash(message: Bytes, key: Bytes?) -> Bytes? {
        return accept(args: [message, key]) as? Bytes
    }
    
    func hash(message: Bytes, outputLength: Int) -> Bytes? {
        return accept(args: [message, outputLength]) as? Bytes
    }
    
    func hashSaltPersonal(message: Bytes, outputLength: Int, key: Bytes?, salt: Bytes, personal: Bytes) -> Bytes? {
        return accept(args: [message, outputLength, key, salt, personal]) as? Bytes
    }
}
