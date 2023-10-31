//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import LibSignalClient

@objc(ECKeyPair)
public final class ECKeyPair: NSObject, NSSecureCoding {
    public let keyPair: IdentityKeyPair
    public var identityKeyPair: IdentityKeyPair { keyPair }

    init(_ keyPair: IdentityKeyPair) {
        self.keyPair = keyPair
    }

    /**
     * Build a keypair from existing key data.
     * If you need a *new* keypair, user `ECKeyPair.generateKeyPair` instead.
     */
    convenience init(publicKeyData: Data, privateKeyData: Data) throws {
        let publicKey = try PublicKey(keyData: publicKeyData)
        let privateKey = try PrivateKey(privateKeyData)

        self.init(IdentityKeyPair(publicKey: publicKey, privateKey: privateKey))
    }

    private static let TSECKeyPairPublicKey = "TSECKeyPairPublicKey"
    private static let TSECKeyPairPrivateKey = "TSECKeyPairPrivateKey"

    public convenience init?(coder: NSCoder) {
        var returnedLength = 0
        let publicKeyBuffer = coder.decodeBytes(forKey: Self.TSECKeyPairPublicKey, returnedLength: &returnedLength)
        guard let publicKeyBuffer else {
            return nil
        }
        let publicKeyData = Data(bytes: publicKeyBuffer, count: returnedLength)

        returnedLength = 0
        let privateKeyBuffer = coder.decodeBytes(forKey: Self.TSECKeyPairPrivateKey, returnedLength: &returnedLength)
        guard let privateKeyBuffer else {
            return nil
        }
        let privateKeyData = Data(bytes: privateKeyBuffer, count: returnedLength)

        do {
            try self.init(publicKeyData: publicKeyData, privateKeyData: privateKeyData)
        } catch {
            Logger.warn("\(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        self.identityKeyPair.publicKey.keyBytes.withUnsafeBufferPointer {
            coder.encodeBytes($0.baseAddress, length: $0.count, forKey: Self.TSECKeyPairPublicKey)
        }
        self.identityKeyPair.privateKey.serialize().withUnsafeBufferPointer {
            coder.encodeBytes($0.baseAddress, length: $0.count, forKey: Self.TSECKeyPairPrivateKey)
        }
    }

    public class var supportsSecureCoding: Bool {
        return true
    }

    @objc
    public static func generateKeyPair() -> ECKeyPair {
        return ECKeyPair(IdentityKeyPair.generate())
    }

    private func sign(_ data: Data) throws -> Data {
        return Data(identityKeyPair.privateKey.generateSignature(message: data))
    }

    @objc
    public var publicKey: Data {
        return Data(identityKeyPair.publicKey.keyBytes)
    }

    public var privateKey: Data {
        return Data(identityKeyPair.privateKey.serialize())
    }
}
