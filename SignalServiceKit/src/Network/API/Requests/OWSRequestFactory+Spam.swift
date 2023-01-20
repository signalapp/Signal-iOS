//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension OWSRequestFactory {
    static func reportSpam(from sender: UUID, withServerGuid serverGuid: String) -> TSRequest {
        let url: URL = {
            let pathComponents = ["v1", "messages", "report", sender.uuidString, serverGuid]
            let urlWithGuid = URL(pathComponents: pathComponents)!
            if serverGuid.isEmpty {
                // This will probably never happen, but the server should be allowed to provide an
                // empty message ID.
                return URL(string: urlWithGuid.path + "/")!
            } else {
                return urlWithGuid
            }
        }()

        return .init(url: url, method: "POST", parameters: nil)
    }
}
