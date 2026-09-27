//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum ProvisioningRequestFactory {

    public static func verifySecondaryDeviceRequest(
        verificationCode: String,
        aci: Aci,
        aciPreKeyBundle: RegistrationPreKeyUploadBundle,
        pniPreKeyBundle: RegistrationPreKeyUploadBundle,
        authPassword: String,
        attributes: AccountAttributes,
        apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
    ) -> TSRequest {
        owsAssertDebug(!verificationCode.isEmpty)
        owsAssertDebug((apnRegistrationId != nil) != attributes.isManualMessageFetchEnabled)

        let urlPathComponents = URLPathComponents(
            ["v1", "devices", "link"],
        )

        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let request = LinkDeviceRequest(
            verificationCode: verificationCode,
            accountAttributes: attributes,
            aciSignedPreKey: OWSRequestFactory.SignedPreKey(aciPreKeyBundle.signedPreKey),
            aciPqLastResortPreKey: OWSRequestFactory.KyberPreKey(aciPreKeyBundle.lastResortPreKey),
            pniSignedPreKey: OWSRequestFactory.SignedPreKey(pniPreKeyBundle.signedPreKey),
            pniPqLastResortPreKey: OWSRequestFactory.KyberPreKey(pniPreKeyBundle.lastResortPreKey),
            apnToken: apnRegistrationId,
        )

        var result = TSRequest(url: url, method: "PUT", body: .encodable(request))
        // The "verify code" request handles auth differently.
        result.auth = .registration((username: aci.serviceIdString, password: authPassword))
        return result
    }

    private struct LinkDeviceRequest: Encodable {
        var verificationCode: String
        var accountAttributes: AccountAttributes
        var aciSignedPreKey: OWSRequestFactory.SignedPreKey
        var aciPqLastResortPreKey: OWSRequestFactory.KyberPreKey
        var pniSignedPreKey: OWSRequestFactory.SignedPreKey
        var pniPqLastResortPreKey: OWSRequestFactory.KyberPreKey
        var apnToken: RegistrationRequestFactory.ApnRegistrationId?
    }
}
