// Copyright © 2021 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

struct TurnServerInfo {

    let password: String
    let username: String
    let urls: [String]

    init?(attributes: JSON, random: Int? = nil) {
        guard
            let passwordAttribute = attributes["password"] as? String,
            let usernameAttribute = attributes["username"] as? String,
            let urlsAttribute = attributes["urls"] as? [String]
        else {
            return nil
        }
        
        password = passwordAttribute
        username = usernameAttribute
        urls = {
            guard let random: Int = random else { return urlsAttribute }
            
            return Array(urlsAttribute.shuffled()[0..<random])
        }()
    }
}
