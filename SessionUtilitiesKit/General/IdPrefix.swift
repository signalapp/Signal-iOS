// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Curve25519Kit

/// The `BlindedECKeyPair` is essentially the same as the `ECKeyPair` except it allows us to more easily distinguish between the two,
/// additionally when generating the `hexEncodedPublicKey` value it will apply the correct prefix
public class BlindedECKeyPair: ECKeyPair {}

public enum IdPrefix: String, CaseIterable {
    case standard = "05"    // Used for identified users, open groups, etc.
    case blinded = "15"     // Used for participants in open groups
    
    public init?(with sessionId: String) {
        guard ECKeyPair.isValidHexEncodedPublicKey(candidate: sessionId) else { return nil }
        guard let targetPrefix: IdPrefix = IdPrefix(rawValue: String(sessionId.prefix(2))) else { return nil }
        
        self = targetPrefix
    }
}
