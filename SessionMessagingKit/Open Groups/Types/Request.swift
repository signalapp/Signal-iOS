// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

extension OpenGroupAPI {
    struct Empty: Codable {}
    
    typealias NoBody = Empty
    typealias NoResponse = Empty
    
    struct Request<T: Encodable> {
        let method: HTTP.Verb
        let server: String
        let room: String?   // TODO: Remove this?
        let endpoint: Endpoint
        let queryParameters: [QueryParam: String]
        let headers: [Header: String]
        /// This is the body value sent during the request
        ///
        /// **Warning:** The `bodyData` value should be used to when making the actual request instead of this as there
        /// is custom handling for certain data types
        let body: T?
        let isAuthRequired: Bool
        /// Always `true` under normal circumstances. You might want to disable
        /// this when running over Lokinet.
        let useOnionRouting: Bool
        
        // MARK: - Initialization

        init(
            method: HTTP.Verb = .get,
            server: String,
            room: String? = nil,
            endpoint: Endpoint,
            queryParameters: [QueryParam: String] = [:],
            headers: [Header: String] = [:],
            body: T? = nil,
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
        
        // MARK: - Convenience
        
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
        
        func bodyData() throws -> Data? {
            // Note: Need to differentiate between JSON, b64 string and bytes body values to ensure they are
            // encoded correctly so the server knows how to handle them
            switch body {
                case let bodyString as String:
                    // The only acceptable string body is a base64 encoded one
                    guard let encodedData: Data = Data(base64Encoded: bodyString) else {
                        throw OpenGroupAPI.Error.parsingFailed
                    }
                    
                    return encodedData
                    
                case let bodyBytes as [UInt8]:
                    return Data(bodyBytes)
                    
                default:
                    // Having no body is fine so just return nil
                    guard let body: T = body else { return nil }

                    return try JSONEncoder().encode(body)
            }
        }
    }
}
