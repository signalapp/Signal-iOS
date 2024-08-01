//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public final class Randomness: NSObject {

    /// Generates a given number of cryptographically secure bytes using `SecRandomCopyBytes`.
    ///
    /// - Parameters:
    ///   - numberBytes: the number of bytes to be generated; must be ≤ `Int.max`
    ///
    /// - Returns: random Data with count equal to `numberBytes`
    @objc
    public static func generateRandomBytes(_ numberBytes: UInt) -> Data {
        guard numberBytes > 0 else {
            // it would be silly to ask for 0 random bytes, but here you go; to prevent crashing at baseAddress! later on
            return Data()
        }

        // the Foundation APIs want Int, but negative values don't make sense so our API uses UInt and converts internally
        guard let numberBytes = Int(exactly: numberBytes) else {
            owsFail("number of random bytes requested \(numberBytes) does not fit in Int")
        }
        var result = Data(count: numberBytes)
        let err = result.withUnsafeMutableBytes { buffer in
            return SecRandomCopyBytes(kSecRandomDefault, numberBytes, buffer.baseAddress!)
        }
        guard err == errSecSuccess else {
            owsFail("failed to generate random bytes with result code \(err)")
        }
        return result
    }
}
