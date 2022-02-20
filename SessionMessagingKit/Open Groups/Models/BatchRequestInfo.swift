// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionUtilitiesKit
import SessionSnodeKit

extension OpenGroupAPI {
    // MARK: - BatchSubRequest
    
    struct BatchSubRequest: Codable {
        let method: HTTP.Verb
        let path: String
        let headers: [String: String]?
        let json: String?
        let b64: String?
        
        init(request: Request) {
            self.method = request.method
            self.path = request.urlPathAndParamsString
            self.headers = (request.headers.isEmpty ? nil : request.headers.toHTTPHeaders())
            
            // TODO: Differentiate between JSON and b64 body.
            if let body: Data = request.body, let bodyString: String = String(data: body, encoding: .utf8) {
                self.json = bodyString
            }
            else {
                self.json = nil
            }
            
            self.b64 = nil
        }
    }
    
    // MARK: - BatchSubResponse<T>
    
    struct BatchSubResponse<T: Codable>: Codable {
        let code: Int32
        let headers: [String: String]
        let body: T
    }
    
    // MARK: - BatchRequestInfo<T>
    
    struct BatchRequestInfo {
        let request: Request
        let responseType: Codable.Type
        
        init<T: Codable>(request: Request, responseType: T.Type) {
            self.request = request
            self.responseType = BatchSubResponse<T>.self
        }
    }
    
    // MARK: - BatchRequest
    
    typealias BatchRequest = [BatchSubRequest]
    typealias BatchResponseTypes = [Codable.Type]
    typealias BatchResponse = [(OnionRequestResponseInfoType, Codable)]
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
