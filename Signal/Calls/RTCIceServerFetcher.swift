//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit
import WebRTC

struct RTCIceServerFetcher {
    private let networkManager: NetworkManager

    /// A cache to limit requests for relay servers.
    private struct Cache {
        let servers: [RTCIceServer]
        let expirationTimestamp: MonotonicDate

        var isValid: Bool {
            return MonotonicDate() < expirationTimestamp
        }

        static func update(servers: [RTCIceServer], ttl: Int) -> Cache {
            return Cache(
                servers: servers,
                expirationTimestamp: MonotonicDate().adding(TimeInterval(ttl)),
            )
        }
    }

    private static let lock = NSRecursiveLock()

    /// Should only be accessed while holding `lock`.
    private static var _cache: Cache?
    private static var cache: Cache? {
        get {
            return lock.withLock {
                return _cache
            }
        }
        set {
            lock.withLock {
                _cache = newValue
            }
        }
    }

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: -

    /// RTCIceServers are used when attempting to establish an optimal
    /// connection to the other party. SignalService supplies a list of servers.
    func getIceServers() async throws -> [RTCIceServer] {
        if let cache = Self.cache, cache.isValid {
            return cache.servers
        }

        let request = OWSRequestFactory.callingRelaysRequest()
        let response = try await networkManager.asyncRequest(request)

        guard let jsonData = response.responseBodyData else {
            throw OWSAssertionError("Missing or invalid JSON!")
        }

        let (servers, ttl) = try Self.parse(turnServerInfoJsonData: jsonData)

        Self.cache = Cache.update(servers: servers, ttl: ttl)

        return servers
    }

    // MARK: -

    static func parse(turnServerInfoJsonData: Data) throws -> ([RTCIceServer], Int) {
        let relays = try JSONDecoder().decode(
            CallingRelays.self,
            from: turnServerInfoJsonData,
        ).relays

        var minTTL: Int = Int.max

        /// We want to order our returned ICE servers firstly by the order in
        /// which the server info objects appeared in the parsed response. Then,
        /// within each server-info object we want to return ICE servers for the
        /// contained URLs with IPs first, then for the URLs without IPs.
        let servers = relays.flatMap { turnServer -> [RTCIceServer] in
            // Use *any* provided ttl values as long as they are valid.
            if let ttl = turnServer.ttl, ttl > 0 {
                minTTL = min(minTTL, ttl)
            }

            let serversWithIP = turnServer.urlsWithIps.map { urlWithIP in
                return RTCIceServer(
                    urlStrings: [urlWithIP],
                    username: turnServer.username,
                    credential: turnServer.password,
                    tlsCertPolicy: .secure,
                    hostname: turnServer.hostname ?? "",
                )
            }

            let serversWithoutIP = turnServer.urls.map { urlWithoutIP in
                return RTCIceServer(
                    urlStrings: [urlWithoutIP],
                    username: turnServer.username,
                    credential: turnServer.password,
                )
            }

            return serversWithIP + serversWithoutIP
        }

        // If no ttl value was found, 0 will disable the cache.
        return (servers, minTTL == Int.max ? 0 : minTTL)
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
        let ttl: Int?
    }

    let relays: [TurnServer]
}
