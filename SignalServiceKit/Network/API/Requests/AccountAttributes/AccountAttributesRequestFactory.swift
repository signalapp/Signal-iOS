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
        auth: ChatServiceAuth,
    ) -> TSRequest {
        owsPrecondition(
            tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? true,
            "Trying to set primary device attributes from secondary/linked device",
        )

        let urlPathComponents = URLPathComponents(
            ["v1", "accounts", "attributes"],
        )
        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        var result = TSRequest(
            url: url,
            method: "PUT",
            body: .encodable(attributes),
        )
        result.headers["X-Signal-Agent"] = "OWI"
        result.auth = .identified(auth)
        return result
    }

    public func updateLinkedDeviceCapabilitiesRequest(
        _ capabilities: AccountAttributes.Capabilities,
        auth: ChatServiceAuth,
    ) -> TSRequest {
        owsPrecondition(
            !(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? false),
            "Trying to set secondary device attributes from primary device",
        )

        var result = TSRequest(
            url: URL(string: "v1/devices/capabilities")!,
            method: "PUT",
            body: .encodable(capabilities),
        )
        result.auth = .identified(auth)
        return result
    }
}
