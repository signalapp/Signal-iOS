// Copyright © 2021 Rangeproof Pty Ltd. All rights reserved.

import Foundation

struct TurnServerInfo {

    let password: String
    let username: String
    let urls: [String]

    init?(attributes: JSON) {
        if let passwordAttribute = (attributes["password"] as? String) {
            password = passwordAttribute
        } else {
            return nil
        }

        if let usernameAttribute = attributes["username"] as? String {
            username = usernameAttribute
        } else {
            return nil
        }

        if let urlsAttribute = attributes["urls"] as? [String] {
            urls = urlsAttribute
        } else {
            return nil
        }
    }
}
