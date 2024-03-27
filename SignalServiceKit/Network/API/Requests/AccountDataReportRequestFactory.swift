//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum AccountDataReportRequestFactory {
    public static func createAccountDataReportRequest() -> TSRequest {
        let url = URL(pathComponents: ["v2", "accounts", "data_report"])!
        let result = TSRequest(url: url, method: "GET", parameters: nil)
        result.shouldHaveAuthorizationHeaders = true
        return result
    }
}
