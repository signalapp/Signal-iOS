// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionUtilitiesKit
import SessionSnodeKit

extension OpenGroupAPI {
    // MARK: - BatchSubRequest
    
    struct BatchSubRequest: Encodable {
        enum CodingKeys: String, CodingKey {
            case method
            case path
            case headers
            case json
            case b64
            case bytes
        }
        
        let method: HTTP.Verb
        let path: String
        let headers: [String: String]?
        
        /// The `jsonBodyEncoder` is used to avoid having to make `BatchSubRequest` a generic type (haven't found a good way
        /// to keep `BatchSubRequest` encodable using protocols unfortunately so need this work around)
        private let jsonBodyEncoder: ((inout KeyedEncodingContainer<CodingKeys>, CodingKeys) throws -> ())?
        private let b64: String?
        private let bytes: [UInt8]?
        
        init<T: Encodable>(request: Request<T>) {
            self.method = request.method
            self.path = request.urlPathAndParamsString
            self.headers = (request.headers.isEmpty ? nil : request.headers.toHTTPHeaders())
            
            // Note: Need to differentiate between JSON, b64 string and bytes body values to ensure they are
            // encoded correctly so the server knows how to handle them
            switch request.body {
                case let bodyString as String:
                    self.jsonBodyEncoder = nil
                    self.b64 = bodyString
                    self.bytes = nil
                    
                case let bodyBytes as [UInt8]:
                    self.jsonBodyEncoder = nil
                    self.b64 = nil
                    self.bytes = bodyBytes
                    
                default:
                    self.jsonBodyEncoder = { [body = request.body] container, key in
                        try container.encodeIfPresent(body, forKey: key)
                    }
                    self.b64 = nil
                    self.bytes = nil
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(method, forKey: .method)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(headers, forKey: .headers)
            try jsonBodyEncoder?(&container, .json)
            try container.encodeIfPresent(b64, forKey: .b64)
            try container.encodeIfPresent(bytes, forKey: .bytes)
        }
    }
    
    // MARK: - BatchSubResponse<T>
    
    struct BatchSubResponse<T: Codable>: Codable {
        let code: Int32
        let headers: [String: String]
        let body: T
    }
    
    // MARK: - BatchRequestInfo<T, R>
    
    struct BatchRequestInfo<T: Encodable, R: Codable>: BatchRequestInfoType {
        let request: Request<T>
        let responseType: Codable.Type
        
        var endpoint: Endpoint { request.endpoint }
        
        init(request: Request<T>, responseType: R.Type) {
            self.request = request
            self.responseType = BatchSubResponse<R>.self
        }
        
        func toSubRequest() -> BatchSubRequest {
            return BatchSubRequest(request: request)
        }
    }
    
    // MARK: - BatchRequest
    
    typealias BatchRequest = [BatchSubRequest]
    typealias BatchResponseTypes = [Codable.Type]
    typealias BatchResponse = [(OnionRequestResponseInfoType, Codable)]
}

// MARK: - BatchRequestInfoType

/// This protocol is designed to erase the types from `BatchRequestInfo<T, R>` so multiple types can be used
/// in arrays when doing `/batch` and `/sequence` requests
protocol BatchRequestInfoType {
    var responseType: Codable.Type { get }
    var endpoint: OpenGroupAPI.Endpoint { get }
    
    func toSubRequest() -> OpenGroupAPI.BatchSubRequest
}

// MARK: - Convenience

public extension Decodable {
    static func decoded(from data: Data, customError: Error, using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies()) throws -> Self {
        return try data.decoded(as: Self.self, customError: customError, using: dependencies)
    }
}

extension Promise where T == (OnionRequestResponseInfoType, Data?) {
    func decoded(as types: OpenGroupAPI.BatchResponseTypes, on queue: DispatchQueue? = nil, error: Error, using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies()) -> Promise<OpenGroupAPI.BatchResponse> {
        self.map(on: queue) { responseInfo, maybeData -> OpenGroupAPI.BatchResponse in
            // Need to split the data into an array of data so each item can be Decoded correctly
            guard let data: Data = maybeData else { throw OpenGroupAPI.Error.parsingFailed }
            guard let jsonObject: Any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                throw OpenGroupAPI.Error.parsingFailed
            }
            guard let anyArray: [Any] = jsonObject as? [Any] else { throw OpenGroupAPI.Error.parsingFailed }
            
            let dataArray: [Data] = anyArray.compactMap { try? JSONSerialization.data(withJSONObject: $0) }
            guard dataArray.count == types.count else { throw OpenGroupAPI.Error.parsingFailed }
            
            do {
                return try zip(dataArray, types)
                    .map { data, type in try type.decoded(from: data, customError: error, using: dependencies) }
                    .map { data in (responseInfo, data) }
            }
            catch _ {
                throw error
            }
        }
    }
}
