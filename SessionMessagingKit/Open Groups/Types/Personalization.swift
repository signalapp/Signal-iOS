// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium

extension OpenGroupAPI {
    public enum Personalization: String {
        case sharedKeys = "sogs.shared_keys"
        case authHeader = "sogs.auth_header"
        
        var bytes: Bytes {
            return self.rawValue.bytes
        }
    }
}
