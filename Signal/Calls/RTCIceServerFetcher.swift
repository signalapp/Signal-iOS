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
        let request = OWSRequestFactory.turnServerInfoRequest()
        let response = try await networkManager.makePromise(request: request).awaitable()

        guard let jsonData = response.responseBodyData else {
            throw OWSAssertionError("Missing or invalid JSON!")
        }

        return Self.parse(turnServerInfoJsonData: jsonData)
    }

    // MARK: -

    static func parse(turnServerInfoJsonData: Data) -> [RTCIceServer] {
        /// At the time of writing, the calling relays may send requests with
        /// either a single or multiple TURN servers, or both in the same
        /// request. In the future, when all clients are reading the
        /// multiple-TURN-server format and the server stops returning single
        /// TURN servers in the response, we can stop parsing them.
        var aggregatedTurnServers = [SingleTurnServer]()

        if let singleTurnServer = try? JSONDecoder().decode(
            SingleTurnServer.self,
            from: turnServerInfoJsonData
        ) {
            aggregatedTurnServers.append(singleTurnServer)
        }

        if let multipleTurnServers = try? JSONDecoder().decode(
            MultipleTurnServers.self,
            from: turnServerInfoJsonData
        ) {
            aggregatedTurnServers.append(contentsOf: multipleTurnServers.turnServers)
        }

        /// We want to order our returned ICE servers firstly by the order in
        /// which the server info objects appeared in the parsed response. Then,
        /// within each server-info object we want to return ICE servers for the
        /// contained URLs with IPs first, then for the URLs without IPs.
        return aggregatedTurnServers.flatMap { turnServer -> [RTCIceServer] in
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

/// Represents a single-TURN-server response. At the time of writing, the
/// calling relays may send requests with either a single or multiple TURN
/// servers, or both in the same request.
private struct SingleTurnServer: Decodable, Hashable {
    let username: String
    let password: String
    let urls: [String]
    let urlsWithIps: [String]
    let hostname: String?
}

/// Represents a multiple-turn-server response.
private struct MultipleTurnServers: Decodable {
    private enum CodingKeys: String, CodingKey {
        case turnServers = "iceServers"
    }

    let turnServers: [SingleTurnServer]
}
