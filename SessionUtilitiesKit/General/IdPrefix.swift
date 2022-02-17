// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import Curve25519Kit

public enum IdPrefix: String, CaseIterable {
    case standard = "05"    // Used for identified users, open groups, etc.
    case blinded = "15"     // Used for participants in open groups with blinding enabled
    case unblinded = "00"   // Used for participants in open groups with blinding disabled
    
    public init?(with sessionId: String) {
        // TODO: Determine if we want this 'idPrefix' method (would need to validate both `ECKeyPair` and `Box.KeyPair` types)
        guard ECKeyPair.isValidHexEncodedPublicKey(candidate: sessionId) else { return nil }
        guard let targetPrefix: IdPrefix = IdPrefix(rawValue: String(sessionId.prefix(2))) else { return nil }
        
        self = targetPrefix
    }
    
    public func hexEncodedPublicKey(for publicKey: Bytes) -> String {
        
        return self.rawValue + publicKey.map { String(format: "%02hhx", $0) }.joined()
    }
}
