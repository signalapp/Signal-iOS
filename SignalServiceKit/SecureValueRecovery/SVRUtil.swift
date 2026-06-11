//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum SVRUtil {

    public static func normalizePin(_ pin: String) -> String {
        // Trim leading and trailing whitespace
        var normalizedPin = pin.ows_stripped()

        // If this pin contains only numerals, ensure they are arabic numerals.
        if pin.digitsOnly() == normalizedPin { normalizedPin = normalizedPin.ensureArabicNumerals }

        // NFKD unicode normalization.
        return normalizedPin.decomposedStringWithCompatibilityMapping
    }

    static func deriveEncodedPINVerificationString(pin: String) throws -> String {
        let pinData = Data(normalizePin(pin).utf8)
        return try LibSignalClient.hashLocalPin(pinData)
    }

    static func verifyPIN(
        pin: String,
        againstEncodedPINVerificationString encodedPINVerificationString: String,
    ) -> Bool {
        let pinData = Data(normalizePin(pin).utf8)
        do {
            return try LibSignalClient.verifyLocalPin(pinData, againstEncodedHash: encodedPINVerificationString)
        } catch {
            owsFailDebug("Failed to validate encodedVerificationString with error: \(error)")
            return false
        }
    }
}
