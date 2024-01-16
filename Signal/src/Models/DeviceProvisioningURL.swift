//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

class DeviceProvisioningURL {

    let ephemeralDeviceId: String

    let publicKey: PublicKey

    enum Constants {
        static let linkDeviceHost = "linkdevice"
    }

    init?(urlString: String) {
        guard let queryItems = URLComponents(string: urlString)?.queryItems else {
            return nil
        }

        var ephemeralDeviceId: String?
        var publicKey: PublicKey?
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

    private static func decodePublicKey(_ encodedPublicKey: String?) -> PublicKey? {
        guard let encodedPublicKey else {
            return nil
        }
        guard let annotatedPublicKey = Data(base64Encoded: encodedPublicKey, options: [.ignoreUnknownCharacters]) else {
            return nil
        }
        let publicKey: PublicKey
        do {
            publicKey = try PublicKey(annotatedPublicKey)
        } catch {
            owsFailDebug("failed to parse key: \(error)")
            return nil
        }
        return publicKey
    }
}
