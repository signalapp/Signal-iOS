// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    public enum Error: LocalizedError {
        case generic
        case parsingFailed
        case decryptionFailed
        case signingFailed
        case invalidURL
        case noPublicKey
        
        public var errorDescription: String? {
            switch self {
                case .generic: return "An error occurred."
                case .parsingFailed: return "Invalid response."
                case .decryptionFailed: return "Couldn't decrypt response."
                case .signingFailed: return "Couldn't sign message."
                case .invalidURL: return "Invalid URL."
                case .noPublicKey: return "Couldn't find server public key."
            }
        }
    }
}
