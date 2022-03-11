// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium

extension Box.KeyPair: Mocked {
    static var mockValue: Box.KeyPair = Box.KeyPair(
        publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
        secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
    )
}
