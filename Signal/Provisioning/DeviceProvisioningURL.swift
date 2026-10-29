//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
public import LibSignalClient
import SignalServiceKit

public class DeviceProvisioningURL {

    /// Capabilities communicated in a provisioning QR code.
    /// NOT to be confused with Account Capabilities; this is a distinct set
    /// scoped specifically to provisioning to communicate between the primary
    /// and secondary device.
    public enum Capability: String {
        case linknsync = "backup5"
        case wifiaware = "wifiaware"
        case nopni = "nopni2"
    }

    public let linkType: LinkType

    let ephemeralDeviceId: String

    let publicKey: PublicKey

    public let capabilities: [Capability]

    public enum Constants {
        static let sgnlPrefix = "sgnl"
        static let uuidParamName = "uuid"
        static let publicKeyParamName = "pub_key"
        static let capabilitiesParamName = "capabilities"
    }

    public enum LinkType: String {
        case linkDevice = "linkdevice"
        case quickRestore = "rereg"
    }

    public init(
        type: LinkType,
        ephemeralDeviceId: String,
        publicKey: PublicKey,
        capabilities: [Capability] = [],
    ) {
        self.linkType = type
        self.ephemeralDeviceId = ephemeralDeviceId
        self.publicKey = publicKey
        self.capabilities = capabilities
    }

    public func buildUrl() throws -> URL {
        let publicKeyTemplate = Randomness.generateRandomBytes(32).hexadecimalString
        var components = URLComponents()
        components.scheme = Constants.sgnlPrefix
        components.host = linkType.rawValue
        components.queryItems = [
            URLQueryItem(name: Constants.uuidParamName, value: ephemeralDeviceId),
            URLQueryItem(name: Constants.publicKeyParamName, value: publicKeyTemplate),
            URLQueryItem(name: Constants.capabilitiesParamName, value: capabilities.map(\.rawValue).joined(separator: ",")),
        ]
        guard let templateUrl = components.url else {
            throw OWSGenericError("couldn't encode url")
        }
        var urlString = templateUrl.absoluteString
        // We don't use queryItems to generate this parameter because it encodes
        // '+' and '/' in the pub_key in a way the Android doesn't tolerate.
        let encodedPublicKey = try Self.encodePublicKey(publicKey)
        urlString = urlString.replacingOccurrences(of: publicKeyTemplate, with: encodedPublicKey)
        guard let url = URL(string: urlString) else {
            throw OWSGenericError("couldn't re-encode url")
        }
        return url
    }

    public init?(urlString: String) {
        guard
            let urlComponents = URLComponents(string: urlString),
            urlComponents.scheme == Constants.sgnlPrefix,
            let host = urlComponents.host,
            let type = LinkType(rawValue: host),
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

        self.linkType = type
        self.ephemeralDeviceId = ephemeralDeviceId
        self.publicKey = publicKey
        self.capabilities = capabilities
    }

    private static func encodePublicKey(_ publicKey: PublicKey) throws -> String {
        let base64PubKey: String = publicKey.serialize().base64EncodedString()
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
