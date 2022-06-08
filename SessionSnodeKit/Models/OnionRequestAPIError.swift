// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

extension OnionRequestAPI {
    public enum Error: LocalizedError {
        case httpRequestFailedAtDestination(statusCode: UInt, data: Data, destination: Destination)
        case insufficientSnodes
        case invalidURL
        case missingSnodeVersion
        case snodePublicKeySetMissing
        case unsupportedSnodeVersion(String)
        case invalidRequestInfo

        public var errorDescription: String? {
            switch self {
                case .httpRequestFailedAtDestination(let statusCode, _, let destination):
                    if statusCode == 429 { return "Rate limited." }
                    
                    return "HTTP request failed at destination (\(destination)) with status code: \(statusCode)."
                    
                case .insufficientSnodes: return "Couldn't find enough Service Nodes to build a path."
                case .invalidURL: return "Invalid URL"
                case .missingSnodeVersion: return "Missing Service Node version."
                case .snodePublicKeySetMissing: return "Missing Service Node public key set."
                case .unsupportedSnodeVersion(let version): return "Unsupported Service Node version: \(version)."
                case .invalidRequestInfo: return "Invalid Request Info"
            }
        }
    }
}

extension SnodeAPI {
    public enum Error: LocalizedError {
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
}
