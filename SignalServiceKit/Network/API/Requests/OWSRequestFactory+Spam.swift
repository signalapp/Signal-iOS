//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public extension OWSRequestFactory {
    static func reportSpam(
        from sender: Aci,
        withServerGuid serverGuid: String,
        reportingToken: SpamReportingToken?,
    ) -> TSRequest {
        // If serverGuid is empty, this produces a trailing slash (e.g.
        // "v1/messages/report/<serviceId>/"). This will probably never happen, but the server should
        // be allowed to provide an empty message ID.
        let url = URL(string: "v1/messages/report/\(sender.serviceIdString)/\(serverGuid)")!

        let parameters: [String: String]?
        if let reportingTokenString = reportingToken?.base64EncodedString().nilIfEmpty {
            parameters = ["token": reportingTokenString]
        } else {
            parameters = nil
        }

        return .init(url: url, method: "POST", parameters: parameters)
    }
}
