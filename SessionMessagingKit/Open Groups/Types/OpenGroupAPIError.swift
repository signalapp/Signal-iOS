// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum OpenGroupAPIError: LocalizedError {
    case decryptionFailed
    case signingFailed
    case noPublicKey
    case invalidEmoji
    
    public var errorDescription: String? {
        switch self {
            case .decryptionFailed: return "Couldn't decrypt response."
            case .signingFailed: return "Couldn't sign message."
            case .noPublicKey: return "Couldn't find server public key."
            case .invalidEmoji: return "The emoji is invalid."
        }
    }
}
