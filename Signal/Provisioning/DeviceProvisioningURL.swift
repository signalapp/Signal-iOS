//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import LibSignalClient

public class DeviceProvisioningURL {

    /// Capabilities communicated in a provisioning QR code.
    /// NOT to be confused with Account Capabilities; this is a distinct set
    /// scoped specifically to provisioning to communicate between the primary
    /// and secondary device.
    public enum Capability: String {
        case linknsync = "backup3"
    }

    let ephemeralDeviceId: String

    let publicKey: PublicKey

    public let capabilities: [Capability]

    public enum Constants {
        public static let linkDeviceHost = "linkdevice"
        static let sgnlPrefix = "sgnl"
        static let uuidParamName = "uuid"
        static let publicKeyParamName = "pub_key"
        static let capabilitiesParamName = "capabilities"
    }

    public init(
        ephemeralDeviceId: String,
        publicKey: PublicKey,
        capabilities: [Capability] = []
    ) {
        self.ephemeralDeviceId = ephemeralDeviceId
        self.publicKey = publicKey
        self.capabilities = capabilities
    }

    // We don't use URLComponents to generate this URL as it encodes '+' and '/'
    // in the base64 pub_key in a way the Android doesn't tolerate.
    public func buildUrl() throws -> URL {
        var urlString = Constants.sgnlPrefix
        urlString.append("://")
        urlString.append(Constants.linkDeviceHost)
        urlString.append("?\(Constants.uuidParamName)=\(ephemeralDeviceId)")
        urlString.append("&\(Constants.publicKeyParamName)=\(try Self.encodePublicKey(publicKey))")
        urlString.append("&\(Constants.capabilitiesParamName)=\(capabilities.map(\.rawValue).joined(separator: ","))")
        guard let url = URL(string: urlString) else {
            throw OWSAssertionError("invalid url: \(urlString)")
        }
        return url
    }

    public init?(urlString: String) {
        guard
            let urlComponents = URLComponents(string: urlString),
            urlComponents.scheme == Constants.sgnlPrefix,
            urlComponents.host == Constants.linkDeviceHost,
            let queryItems = urlComponents.queryItems
        else {
            return nil
        }

        var ephemeralDeviceId: String?
        var publicKey: PublicKey?
        var capabilities: [Capability] = []
        for queryItem in queryItems {
            switch queryItem.name {
            case Constants.uuidParamName:
                ephemeralDeviceId = queryItem.value
            case Constants.publicKeyParamName:
                publicKey = Self.decodePublicKey(queryItem.value)
            case Constants.capabilitiesParamName:
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

    private static func encodePublicKey(_ publicKey: PublicKey) throws -> String {
        let base64PubKey: String = Data(publicKey.serialize()).base64EncodedString()
        guard let encodedPubKey = base64PubKey.encodeURIComponent else {
            throw OWSAssertionError("Failed to url encode query params")
        }
        return encodedPubKey
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
