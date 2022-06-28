// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension PushNotificationAPI {
    struct UpdateRegistrationResponse: Codable {
        struct Body: Codable {
            let code: Int
            let message: String?
        }
        
        let status: Int
        let body: Body
    }
}
