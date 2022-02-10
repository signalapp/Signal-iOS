// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension PushNotificationAPI {
    struct UnregisterResponse: Codable {
        let body: String
        let code: Int
        let message: String?
    }
}
