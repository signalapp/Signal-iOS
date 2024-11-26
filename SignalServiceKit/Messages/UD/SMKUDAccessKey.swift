//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public struct SMKUDAccessKey {

    public static let kUDAccessKeyLength: Int = 16

    public let keyData: Data

    public init(profileKey: Data) throws {
        self.keyData = try Data(ProfileKey(contents: [UInt8](profileKey)).deriveAccessKey())
    }

    private init(keyData: Data) {
        self.keyData = keyData
    }

    /// Used to compose multiple Unidentified-Access-Keys for the multiRecipient endpoint
    public static func ^ (lhs: SMKUDAccessKey, rhs: SMKUDAccessKey) -> SMKUDAccessKey {
        owsPrecondition(lhs.keyData.count == SMKUDAccessKey.kUDAccessKeyLength)
        owsPrecondition(rhs.keyData.count == SMKUDAccessKey.kUDAccessKeyLength)

        let xoredBytes = zip(lhs.keyData, rhs.keyData).map(^)
        return .init(keyData: Data(xoredBytes))
    }

    // Unrestricted UD recipients should have a zeroed access key sent to the multi-recipient endpoint
    // For a collection of mixed recipients, a zeroed key will have no effect composing keys with xor
    // For a collection of only unrestricted UD recipients, the server expects a zero access key
    public static var zeroedKey: SMKUDAccessKey {
        .init(keyData: Data(repeating: 0, count: kUDAccessKeyLength))
    }
}
