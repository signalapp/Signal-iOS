// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class MockBox: Mock<BoxType>, BoxType {
    func seal(message: Bytes, recipientPublicKey: Bytes) -> Bytes? {
        return accept(args: [message, recipientPublicKey]) as? Bytes
    }
    
    func open(anonymousCipherText: Bytes, recipientPublicKey: Bytes, recipientSecretKey: Bytes) -> Bytes? {
        return accept(args: [anonymousCipherText, recipientPublicKey, recipientSecretKey]) as? Bytes
    }
}
