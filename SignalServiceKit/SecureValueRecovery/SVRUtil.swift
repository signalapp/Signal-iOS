//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Just a container for simple static helper methods on SVR
/// that can be shared with other classes (incl. objc classes).
@objc
public final class SVRUtil: NSObject {

    @objc
    public static func normalizePin(_ pin: String) -> String {
        // Trim leading and trailing whitespace
        var normalizedPin = pin.ows_stripped()

        // If this pin contains only numerals, ensure they are arabic numerals.
        if pin.digitsOnly() == normalizedPin { normalizedPin = normalizedPin.ensureArabicNumerals }

        // NFKD unicode normalization.
        return normalizedPin.decomposedStringWithCompatibilityMapping
    }

    internal enum Constants {
        static let pinSaltLengthBytes: UInt = 16
    }

    internal static func deriveEncodedPINVerificationString(pin: String) throws -> String {
        guard let pinData = normalizePin(pin).data(using: .utf8) else { throw SVR.SVRError.assertion }
        return try LibSignalClient.hashLocalPin(pinData)
    }

    internal static func verifyPIN(
        pin: String,
        againstEncodedPINVerificationString encodedPINVerificationString: String
    ) -> Bool {
        guard let pinData = normalizePin(pin).data(using: .utf8) else {
            owsFailDebug("failed to determine pin data")
            return false
        }

        do {
            return try LibSignalClient.verifyLocalPin(pinData, againstEncodedHash: encodedPINVerificationString)
        } catch {
            owsFailDebug("Failed to validate encodedVerificationString with error: \(error)")
            return false
        }
    }

    internal static func deriveSVR1EncryptionKeyAndAccessKey(
        pin: String,
        backupId: Data
    ) throws -> (encryptionKey: Data, accessKey: Data) {
        guard let pinData = normalizePin(pin).data(using: .utf8) else { throw SVR.SVRError.assertion }
        guard backupId.count == 32 else { throw SVR.SVRError.assertion }

        // From method documentation:
        // Note: This should be used with SVR1 only. For SVR1, the salt should be the backup id.
        // For SVR2 clients, use ``Svr2Client/hashPin(_:forUser:)`` which handles salt selection internally.
        let pinHash = try LibSignalClient.PinHash(pin: pinData, salt: backupId)

        return (encryptionKey: Data(pinHash.encryptionKey), accessKey: Data(pinHash.accessKey))
    }
}
