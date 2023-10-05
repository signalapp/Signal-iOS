//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MultipeerConnectivity
import SignalServiceKit

extension DeviceTransferService {
    private static let currentTransferVersion = 1

    private static let versionKey = "version"
    private static let peerIdKey = "peerId"
    private static let certificateHashKey = "certificateHash"
    private static let transferModeKey = "transferMode"

    func urlForTransfer(mode: TransferMode) throws -> URL {
        guard let identity = identity else {
            throw OWSAssertionError("unexpectedly missing identity")
        }

        var components = URLComponents()
        components.scheme = kURLSchemeSGNLKey
        components.host = kURLHostTransferPrefix

        guard let base64CertificateHash = try identity.computeCertificateHash().base64EncodedString().encodeURIComponent else {
            throw OWSAssertionError("failed to get base64 certificate hash")
        }

        guard let base64PeerId = try NSKeyedArchiver.archivedData(withRootObject: peerId, requiringSecureCoding: true).base64EncodedString().encodeURIComponent else {
            throw OWSAssertionError("failed to get base64 peerId")
        }

        let queryItems = [
            DeviceTransferService.versionKey: String(DeviceTransferService.currentTransferVersion),
            DeviceTransferService.transferModeKey: mode.rawValue,
            DeviceTransferService.certificateHashKey: base64CertificateHash,
            DeviceTransferService.peerIdKey: base64PeerId
        ]

        components.queryItems = queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }

        return components.url!
    }

    func parseTransferURL(_ url: URL) throws -> (peerId: MCPeerID, certificateHash: Data) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = components.queryItems else {
            throw OWSAssertionError("Invalid url")
        }

        let queryItemsDictionary = [String: String](uniqueKeysWithValues: queryItems.compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        guard let version = queryItemsDictionary[DeviceTransferService.versionKey],
            Int(version) == DeviceTransferService.currentTransferVersion else {
            throw Error.unsupportedVersion
        }

        let currentMode: TransferMode = DependenciesBridge.shared.tsAccountManager
            .registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true ? .primary : .linked

        guard let rawMode = queryItemsDictionary[DeviceTransferService.transferModeKey],
            rawMode == currentMode.rawValue else {
            throw Error.modeMismatch
        }

        guard let base64CertificateHash = queryItemsDictionary[DeviceTransferService.certificateHashKey],
            let uriDecodedHash = base64CertificateHash.removingPercentEncoding,
            let certificateHash = Data(base64Encoded: uriDecodedHash) else {
                throw OWSAssertionError("failed to decode certificate hash")
        }

        guard let base64PeerId = queryItemsDictionary[DeviceTransferService.peerIdKey],
            let uriDecodedPeerId = base64PeerId.removingPercentEncoding,
            let peerIdData = Data(base64Encoded: uriDecodedPeerId),
            let peerId = try NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: peerIdData) else {
                throw OWSAssertionError("failed to decode MCPeerId")
        }

        return (peerId, certificateHash)
    }
}
