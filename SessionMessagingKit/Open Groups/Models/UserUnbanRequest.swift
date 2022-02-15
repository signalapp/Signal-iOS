// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    struct UserUnbanRequest: Codable {
        let rooms: [String]?
        let global: Bool?
    }
}
