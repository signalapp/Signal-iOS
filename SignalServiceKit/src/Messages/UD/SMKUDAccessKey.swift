//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

@objc
public class SMKUDAccessKey: NSObject {

    @objc
    public static let kUDAccessKeyLength: Int = 16

    @objc
    public let keyData: Data

    @objc
    public init(profileKey: Data) throws {
        let cipher = try Aes256GcmEncryption(
            key: profileKey,
            nonce: Data(count: Aes256GcmEncryptedData.nonceLength),
            associatedData: []
        )
        // We derive the "ud access key" from the private key by encrypting zeroes.
        var message = Data(count: Self.kUDAccessKeyLength)
        try cipher.encrypt(&message)
        self.keyData = message
    }

    @objc
    public init(randomKeyData: ()) {
        self.keyData = Randomness.generateRandomBytes(Int32(SMKUDAccessKey.kUDAccessKeyLength))
    }

    private init(keyData: Data) {
        self.keyData = keyData
    }

    /// Used to compose multiple Unidentified-Access-Keys for the multiRecipient endpoint
    public static func ^ (lhs: SMKUDAccessKey, rhs: SMKUDAccessKey) -> SMKUDAccessKey {
        owsAssert(lhs.keyData.count == SMKUDAccessKey.kUDAccessKeyLength)
        owsAssert(rhs.keyData.count == SMKUDAccessKey.kUDAccessKeyLength)

        let xoredBytes = zip(lhs.keyData, rhs.keyData).map(^)
        return .init(keyData: Data(xoredBytes))
    }

    // MARK: 

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SMKUDAccessKey else { return false }
        return self.keyData == other.keyData
    }

    // Unrestricted UD recipients should have a zeroed access key sent to the multi-recipient endpoint
    // For a collection of mixed recipients, a zeroed key will have no effect composing keys with xor
    // For a collection of only unrestricted UD recipients, the server expects a zero access key
    public static var zeroedKey: SMKUDAccessKey {
        .init(keyData: Data(repeating: 0, count: kUDAccessKeyLength))
    }
}
