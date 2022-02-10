// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    struct RoomsResponse: Codable {
        let rooms: [RoomInfo]
    }
}
