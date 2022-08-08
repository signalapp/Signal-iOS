// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension PushNotificationAPI {
    struct PushServerResponse: Codable {
        let code: Int
        let message: String?
    }
}
