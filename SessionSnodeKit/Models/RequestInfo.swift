// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OnionRequestAPI {
    struct RequestInfo: Codable {
        let method: String
        let endpoint: String
        let headers: [String: String]
    }
}
