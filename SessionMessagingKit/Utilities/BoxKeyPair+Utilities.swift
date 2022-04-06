// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
extension Box.KeyPair: Equatable {
    public static func == (lhs: Box.KeyPair, rhs: Box.KeyPair) -> Bool {
        return (
            lhs.publicKey == rhs.publicKey &&
            lhs.secretKey == rhs.secretKey
        )
    }
}
