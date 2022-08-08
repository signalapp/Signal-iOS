// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum MessageSenderError: LocalizedError {
    case invalidMessage
    case protoConversionFailed
    case noUserX25519KeyPair
    case noUserED25519KeyPair
    case signingFailed
    case encryptionFailed
    case noUsername
    
    // Closed groups
    case noThread
    case noKeyPair
    case invalidClosedGroupUpdate
    
    case other(Error)

    internal var isRetryable: Bool {
        switch self {
            case .invalidMessage, .protoConversionFailed, .invalidClosedGroupUpdate, .signingFailed, .encryptionFailed: return false
            default: return true
        }
    }
    
    public var errorDescription: String? {
        switch self {
            case .invalidMessage: return "Invalid message."
            case .protoConversionFailed: return "Couldn't convert message to proto."
            case .noUserX25519KeyPair: return "Couldn't find user X25519 key pair."
            case .noUserED25519KeyPair: return "Couldn't find user ED25519 key pair."
            case .signingFailed: return "Couldn't sign message."
            case .encryptionFailed: return "Couldn't encrypt message."
            case .noUsername: return "Missing username."
            
            // Closed groups
            case .noThread: return "Couldn't find a thread associated with the given group public key."
            case .noKeyPair: return "Couldn't find a private key associated with the given group public key."
            case .invalidClosedGroupUpdate: return "Invalid group update."
            case .other(let error): return error.localizedDescription
        }
    }
}
