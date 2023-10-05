//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum AccountAttributesRequestFactory {

    public static func updatePrimaryDeviceAttributesRequest(_ attributes: AccountAttributes) -> TSRequest {
        // If you are updating capabilities for a secondary device, use `updateSecondaryDeviceCapabilities` instead
        owsAssert(
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? true,
            "Trying to set primary device attributes from secondary/linked device"
        )

        let urlPathComponents = URLPathComponents(
            ["v1", "accounts", "attributes"]
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        // The request expects the AccountAttributes to be the root object.
        // Serialize it to JSON then get the key value dict to do that.
        let data = try! JSONEncoder().encode(attributes)
        let parameters = try! JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as! [String: Any]

        let result = TSRequest(url: url, method: "PUT", parameters: parameters)
        result.shouldHaveAuthorizationHeaders = true
        return result
    }
}
