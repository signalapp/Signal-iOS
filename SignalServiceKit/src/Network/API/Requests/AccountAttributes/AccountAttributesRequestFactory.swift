//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public enum AccountAttributesRequestFactory {

    /// If you are updating capabilities for a secondary device, use `updateLinkedDeviceCapabilitiesRequest` instead
    public static func updatePrimaryDeviceAttributesRequest(_ attributes: AccountAttributes) -> TSRequest {

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

    public static func updateLinkedDeviceCapabilitiesRequest(
        _ capabilities: AccountAttributes.Capabilities,
        tsAccountManager: TSAccountManager
    ) -> TSRequest {
        owsAssert(
            (tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? false).negated,
            "Trying to set seconday device attributes from primary device"
        )

        return TSRequest(url: URL(string: "v1/devices/capabilities")!, method: "PUT", parameters: capabilities.requestParameters)
    }
}
