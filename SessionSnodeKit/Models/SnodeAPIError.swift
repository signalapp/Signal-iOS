// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum SnodeAPIError: LocalizedError {
    case generic
    case clockOutOfSync
    case snodePoolUpdatingFailed
    case inconsistentSnodePools
    case noKeyPair
    case signingFailed
    case signatureVerificationFailed
    case invalidIP
    
    // ONS
    case decryptionFailed
    case hashingFailed
    case validationFailed

    public var errorDescription: String? {
        switch self {
            case .generic: return "An error occurred."
            case .clockOutOfSync: return "Your clock is out of sync with the Service Node network. Please check that your device's clock is set to automatic time."
            case .snodePoolUpdatingFailed: return "Failed to update the Service Node pool."
            case .inconsistentSnodePools: return "Received inconsistent Service Node pool information from the Service Node network."
            case .noKeyPair: return "Missing user key pair."
            case .signingFailed: return "Couldn't sign message."
            case .signatureVerificationFailed: return "Failed to verify the signature."
            case .invalidIP: return "Invalid IP."
                
            // ONS
            case .decryptionFailed: return "Couldn't decrypt ONS name."
            case .hashingFailed: return "Couldn't compute ONS name hash."
            case .validationFailed: return "ONS name validation failed."
        }
    }
}
