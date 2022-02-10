// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    struct Request {
        let verb: HTTP.Verb
        let room: String?
        let server: String
        let endpoint: Endpoint
        let queryParameters: [QueryParam: String]
        let body: Data?
        let headers: [Header: String]
        let isAuthRequired: Bool
        /// Always `true` under normal circumstances. You might want to disable
        /// this when running over Lokinet.
        let useOnionRouting: Bool

        init(
            verb: HTTP.Verb,
            room: String?,
            server: String,
            endpoint: Endpoint,
            queryParameters: [QueryParam: String] = [:],
            body: Data? = nil,
            headers: [Header: String] = [:],
            isAuthRequired: Bool = true,
            useOnionRouting: Bool = true
        ) {
            self.verb = verb
            self.room = room
            self.server = server
            self.endpoint = endpoint
            self.queryParameters = queryParameters
            self.body = body
            self.headers = headers
            self.isAuthRequired = isAuthRequired
            self.useOnionRouting = useOnionRouting
        }
        
        var url: URL? {
            guard verb == .get else { return URL(string: "\(server)/\(endpoint.path)") }
            
            return URL(
                string: [
                    "\(server)/\(endpoint.path)",
                    queryParameters
                        .map { key, value in "\(key.rawValue)=\(value)" }
                        .joined(separator: "&")
                ]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "?")
            )
        }
    }
}
