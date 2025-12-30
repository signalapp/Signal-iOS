//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum ProvisioningRequestFactory {

    public static func verifySecondaryDeviceRequest(
        verificationCode: String,
        phoneNumber: String,
        authPassword: String,
        attributes: AccountAttributes,
        apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
        prekeyBundles: RegistrationPreKeyUploadBundles,
    ) -> TSRequest {
        owsAssertDebug(verificationCode.isEmpty.negated)
        owsAssertDebug(phoneNumber.isEmpty.negated)
        owsAssertDebug((apnRegistrationId != nil) != attributes.isManualMessageFetchEnabled)

        let urlPathComponents = URLPathComponents(
            ["v1", "devices", "link"],
        )

        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let jsonEncoder = JSONEncoder()
        let accountAttributesData = try! jsonEncoder.encode(attributes)
        let accountAttributesDict = try! JSONSerialization.jsonObject(with: accountAttributesData, options: .fragmentsAllowed) as! [String: Any]

        var parameters: [String: Any] = [
            "verificationCode": verificationCode,
            "accountAttributes": accountAttributesDict,
            "aciSignedPreKey": OWSRequestFactory.signedPreKeyRequestParameters(prekeyBundles.aci.signedPreKey),
            "pniSignedPreKey": OWSRequestFactory.signedPreKeyRequestParameters(prekeyBundles.pni.signedPreKey),
            "aciPqLastResortPreKey": OWSRequestFactory.pqPreKeyRequestParameters(prekeyBundles.aci.lastResortPreKey),
            "pniPqLastResortPreKey": OWSRequestFactory.pqPreKeyRequestParameters(prekeyBundles.pni.lastResortPreKey),
        ]

        if let apnRegistrationId {
            let apnRegistrationIdData = try! jsonEncoder.encode(apnRegistrationId)
            let apnRegistrationIdDict = try! JSONSerialization.jsonObject(with: apnRegistrationIdData, options: .fragmentsAllowed) as! [String: Any]
            parameters["apnToken"] = apnRegistrationIdDict
        }

        var result = TSRequest(url: url, method: "PUT", parameters: parameters)
        // The "verify code" request handles auth differently.
        result.auth = .registration((username: phoneNumber, password: authPassword))
        return result
    }
}
