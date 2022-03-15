// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import Curve25519Kit

extension Box.KeyPair: Mocked {
    static var mockValue: Box.KeyPair = Box.KeyPair(
        publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
        secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
    )
}

extension ECKeyPair: Mocked {
    static var mockValue: Self {
        try! Self.init(
            publicKeyData: Data.data(fromHex: TestConstants.publicKey)!,
            privateKeyData: Data.data(fromHex: TestConstants.privateKey)!
        )
    }
}
