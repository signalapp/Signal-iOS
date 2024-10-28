//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit
import WebRTC

struct RTCIceServerFetcher {
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: -

    /// RTCIceServers are used when attempting to establish an optimal
    /// connection to the other party. SignalService supplies a list of servers.
    func getIceServers() async throws -> [RTCIceServer] {
        let request = OWSRequestFactory.callingRelaysRequest()
        let response = try await networkManager.asyncRequest(request)

        guard let jsonData = response.responseBodyData else {
            throw OWSAssertionError("Missing or invalid JSON!")
        }

        return try Self.parse(turnServerInfoJsonData: jsonData)
    }

    // MARK: -

    static func parse(turnServerInfoJsonData: Data) throws -> [RTCIceServer] {
        let relays = try JSONDecoder().decode(
            CallingRelays.self,
            from: turnServerInfoJsonData
        ).relays

        /// We want to order our returned ICE servers firstly by the order in
        /// which the server info objects appeared in the parsed response. Then,
        /// within each server-info object we want to return ICE servers for the
        /// contained URLs with IPs first, then for the URLs without IPs.
        return relays.flatMap { turnServer -> [RTCIceServer] in
            let serversWithIP = turnServer.urlsWithIps.map { urlWithIP in
                return RTCIceServer(
                    urlStrings: [urlWithIP],
                    username: turnServer.username,
                    credential: turnServer.password,
                    tlsCertPolicy: .secure,
                    hostname: turnServer.hostname ?? ""
                )
            }

            let serversWithoutIP = turnServer.urls.map { urlWithoutIP in
                return RTCIceServer(
                    urlStrings: [urlWithoutIP],
                    username: turnServer.username,
                    credential: turnServer.password
                )
            }

            return serversWithIP + serversWithoutIP
        }
    }
}

// MARK: -

/// Represents a calling relays response.
private struct CallingRelays: Decodable {
    struct TurnServer: Decodable {
        let username: String
        let password: String
        let urls: [String]
        let urlsWithIps: [String]
        let hostname: String?
    }

    let relays: [TurnServer]
}
