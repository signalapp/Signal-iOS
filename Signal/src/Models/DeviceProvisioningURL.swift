//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class DeviceProvisioningURL: NSObject {

    @objc
    let ephemeralDeviceId: String

    @objc
    let publicKey: Data

    @objc
    init?(urlString: String) {
        guard let queryItems = URLComponents(string: urlString)?.queryItems else {
            return nil
        }

        var ephemeralDeviceId: String?
        var publicKey: Data?
        for queryItem in queryItems {
            switch queryItem.name {
            case "uuid":
                ephemeralDeviceId = queryItem.value
            case "pub_key":
                publicKey = Self.decodePublicKey(queryItem.value)
            default:
                Logger.warn("unknown query item in provisioning string: \(queryItem.name)")
            }
        }

        guard let ephemeralDeviceId, let publicKey else {
            return nil
        }

        self.ephemeralDeviceId = ephemeralDeviceId
        self.publicKey = publicKey
    }

    private static func decodePublicKey(_ encodedPublicKey: String?) -> Data? {
        guard let encodedPublicKey else {
            return nil
        }
        guard let annotatedKey = Data(base64Encoded: encodedPublicKey, options: [.ignoreUnknownCharacters]) else {
            return nil
        }
        let publicKey: Data
        do {
            publicKey = try (annotatedKey as NSData).removeKeyType() as Data
        } catch {
            owsFailDebug("failed to strip key type: \(error)")
            return nil
        }
        return publicKey
    }

}
