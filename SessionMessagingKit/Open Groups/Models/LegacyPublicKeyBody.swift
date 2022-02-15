// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    struct LegacyPublicKeyBody: Codable {
        enum CodingKeys: String, CodingKey {
            case publicKey = "public_key"
        }
        
        let publicKey: String
    }
}
