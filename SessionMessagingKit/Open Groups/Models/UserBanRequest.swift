// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    struct UserBanRequest: Codable {
        let rooms: [String]?
        let global: Bool?
        let timeout: TimeInterval?
    }
}
