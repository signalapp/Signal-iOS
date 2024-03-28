//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct TurnServerInfo {

    let password: String
    let username: String
    let urls: [String]
    let urlsWithIps: [String]
    let hostname: String

    init?(attributes: [String: AnyObject]) {
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

        switch attributes["urls"] {
        case let urlsAttribute as [String]:
            urls = urlsAttribute
        case is NSNull:
            urls = []
        default:
            return nil
        }

        switch attributes["urlsWithIps"] {
        case let urlsWithIpsAttribute as [String]:
            urlsWithIps = urlsWithIpsAttribute
        case is NSNull:
            urlsWithIps = []
        default:
            return nil
        }

        if let hostnameAttribute = attributes["hostname"] as? String {
            hostname = hostnameAttribute
        } else {
            return nil
        }
    }
}
