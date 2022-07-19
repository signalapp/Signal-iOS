// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

@testable import SessionMessagingKit

// FIXME: Change 'OnionRequestAPIType' to have instance methods instead of static methods once everything is updated to use 'Dependencies'
class TestOnionRequestAPI: OnionRequestAPIType {
    struct RequestData: Codable {
        let urlString: String?
        let httpMethod: String
        let headers: [String: String]
        let snodeMethod: String?
        let body: Data?
        
        let server: String
        let version: OnionRequestAPIVersion
        let publicKey: String?
    }
    class ResponseInfo: OnionRequestResponseInfoType {
        let requestData: RequestData
        let code: Int
        let headers: [String: String]
        
        init(requestData: RequestData, code: Int, headers: [String: String]) {
            self.requestData = requestData
            self.code = code
            self.headers = headers
        }
    }
    
    class var mockResponse: Data? { return nil }
    
    static func sendOnionRequest(_ request: URLRequest, to server: String, using version: OnionRequestAPIVersion, with x25519PublicKey: String) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        let responseInfo: ResponseInfo = ResponseInfo(
            requestData: RequestData(
                urlString: request.url?.absoluteString,
                httpMethod: (request.httpMethod ?? "GET"),
                headers: (request.allHTTPHeaderFields ?? [:]),
                snodeMethod: nil,
                body: request.httpBody,
                
                server: server,
                version: version,
                publicKey: x25519PublicKey
            ),
            code: 200,
            headers: [:]
        )
        
        return Promise.value((responseInfo, mockResponse))
    }
    
    static func sendOnionRequest(to snode: Snode, invoking method: SnodeAPIEndpoint, with parameters: JSON, associatedWith publicKey: String?) -> Promise<Data> {
        return Promise.value(mockResponse!)
    }
}
