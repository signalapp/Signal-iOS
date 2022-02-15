// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    struct UserDeleteMessagesRequest: Codable {
        let rooms: [String]?
        let global: Bool?
    }
}
