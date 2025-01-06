//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct AccountAttributesRequestFactory {
    private let tsAccountManager: TSAccountManager

    public init(tsAccountManager: TSAccountManager) {
        self.tsAccountManager = tsAccountManager
    }

    /// If you are updating capabilities for a secondary device, use `updateLinkedDeviceCapabilitiesRequest` instead
    public func updatePrimaryDeviceAttributesRequest(
        _ attributes: AccountAttributes,
        auth: ChatServiceAuth
    ) -> TSRequest {
        owsPrecondition(
            tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? true,
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

        let result = TSRequest(
            url: url,
            method: "PUT",
            parameters: parameters
        )
        result.setAuth(auth)
        return result
    }

    public func updateLinkedDeviceCapabilitiesRequest(
        _ capabilities: AccountAttributes.Capabilities,
        auth: ChatServiceAuth
    ) -> TSRequest {
        owsPrecondition(
            (tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? false).negated,
            "Trying to set seconday device attributes from primary device"
        )

        let result = TSRequest(
            url: URL(string: "v1/devices/capabilities")!,
            method: "PUT",
            parameters: capabilities.requestParameters
        )
        result.setAuth(auth)
        return result
    }
}
