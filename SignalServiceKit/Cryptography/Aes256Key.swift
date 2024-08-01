//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Key appropriate for use with AES-256.
@objc(OWSAES256Key)
public final class Aes256Key: NSObject, NSSecureCoding {

    @objc
    public static let keyByteLength: UInt = 32

    @objc
    public let keyData: Data

    /// Generates a new secure random key.
    public override init() {
        self.keyData = Randomness.generateRandomBytes(Self.keyByteLength)
    }

    /// Generates a new secure random key.
    ///
    /// Equivalent to calling ``Aes256Key/init()``.
    @objc(generateRandomKey)
    public static func generateRandom() -> Aes256Key {
        return Aes256Key()
    }

    /// Returns a new instance if `data` is of appropriate length for an AES-256 key.
    ///
    /// - Parameters:
    ///   - data: the raw key bytes
    ///
    /// - Returns: `nil` if the input `data` is not the correct length for an AES-256 key
    public init?(data: Data) {
        if data.count == Self.keyByteLength {
            self.keyData = data
        } else {
            Logger.error("Invalid key length: \(data.count)")
            return nil
        }
    }

    // MARK: Secure Coding

    public static let supportsSecureCoding: Bool = true

    public init?(coder: NSCoder) {
        let keyData = coder.decodeObject(of: NSData.self, forKey: "keyData")
        guard let keyData, keyData.count == Self.keyByteLength else {
            Logger.error("Invalid key length: \(keyData?.count ?? 0)")
            return nil
        }

        self.keyData = keyData as Data
    }

    public func encode(with coder: NSCoder) {
        coder.encode(self.keyData as NSData, forKey: "keyData")
    }

    // MARK: Equatable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherKey = object as? Aes256Key else {
            return false
        }

        return otherKey.keyData.ows_constantTimeIsEqual(to: self.keyData)
    }

    // MARK: Hashable

    public override var hash: Int {
        return (self.keyData as NSData).hash
    }
}
