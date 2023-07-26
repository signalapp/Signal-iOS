//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension OWSRequestFactory {
    static func reportSpam(
        from sender: UntypedServiceId,
        withServerGuid serverGuid: String,
        reportingToken: SpamReportingToken?
    ) -> TSRequest {
        let url: URL = {
            let urlWithGuid = URL(
                pathComponents: ["v1", "messages", "report", sender.uuidValue.uuidString, serverGuid]
            )!
            if serverGuid.isEmpty {
                // This will probably never happen, but the server should be allowed to provide an
                // empty message ID.
                return URL(string: urlWithGuid.path + "/")!
            } else {
                return urlWithGuid
            }
        }()

        let parameters: [String: String]?
        if let reportingTokenString = reportingToken?.base64EncodedString().nilIfEmpty {
            parameters = ["token": reportingTokenString]
        } else {
            parameters = nil
        }

        return .init(url: url, method: "POST", parameters: parameters)
    }
}
