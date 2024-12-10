//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit

class DeviceProvisioningURL {

    public static let uuidParamName = "uuid"
    public static let publicKeyParamName = "pub_key"
    public static let capabilitiesParamName = "capabilities"

    /// Capabilities communicated in a provisioning QR code.
    /// NOT to be confused with Account Capabilities; this is a distinct set
    /// scoped specifically to provisioning to communicate between the primary
    /// and secondary device.
    public enum Capability: String {
        case linknsync = "backup"
    }

    let ephemeralDeviceId: String

    let publicKey: PublicKey

    let capabilities: [Capability]

    enum Constants {
        static let linkDeviceHost = "linkdevice"
    }

    init?(urlString: String) {
        guard let queryItems = URLComponents(string: urlString)?.queryItems else {
            return nil
        }

        var ephemeralDeviceId: String?
        var publicKey: PublicKey?
        var capabilities: [Capability] = []
        for queryItem in queryItems {
            switch queryItem.name {
            case Self.uuidParamName:
                ephemeralDeviceId = queryItem.value
            case Self.publicKeyParamName:
                publicKey = Self.decodePublicKey(queryItem.value)
            case Self.capabilitiesParamName:
                capabilities = queryItem.value?
                    .split(separator: ",")
                    .compactMap({
                        guard let capability = Capability(rawValue: String($0)) else {
                            Logger.warn("unknown capability in provisioning string \($0)")
                            return nil
                        }
                        return capability
                    })
                    ?? []
            default:
                Logger.warn("unknown query item in provisioning string: \(queryItem.name)")
            }
        }

        guard let ephemeralDeviceId, let publicKey else {
            return nil
        }

        self.ephemeralDeviceId = ephemeralDeviceId
        self.publicKey = publicKey
        self.capabilities = capabilities
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
