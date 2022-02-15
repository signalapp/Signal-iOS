// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

extension OpenGroupAPI {
    struct Request {
        let method: HTTP.Verb
        let server: String
        let room: String?   // TODO: Remove this?
        let endpoint: Endpoint
        let queryParameters: [QueryParam: String]
        let headers: [Header: String]
        let body: Data?
        let isAuthRequired: Bool
        /// Always `true` under normal circumstances. You might want to disable
        /// this when running over Lokinet.
        let useOnionRouting: Bool

        init(
            method: HTTP.Verb = .get,
            server: String,
            room: String? = nil,
            endpoint: Endpoint,
            queryParameters: [QueryParam: String] = [:],
            headers: [Header: String] = [:],
            body: Data? = nil,
            isAuthRequired: Bool = true,
            useOnionRouting: Bool = true
        ) {
            self.method = method
            self.server = server
            self.room = room
            self.endpoint = endpoint
            self.queryParameters = queryParameters
            self.headers = headers
            self.body = body
            self.isAuthRequired = isAuthRequired
            self.useOnionRouting = useOnionRouting
        }
        
        var url: URL? {
            return URL(string: "\(server)\(urlPathAndParamsString)")
        }
        
        var urlPathAndParamsString: String {
            return [
                "/\(endpoint.path)",
                queryParameters
                    .map { key, value in "\(key.rawValue)=\(value)" }
                    .joined(separator: "&")
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "?")
        }
    }
}
