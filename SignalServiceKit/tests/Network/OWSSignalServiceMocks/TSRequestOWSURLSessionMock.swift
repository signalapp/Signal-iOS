//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit
import XCTest

/// OWSURLSessionProtocol mock instance that responds exclusively to TSRequest promises,
/// taking Response objects that it uses to respond to requests in FIFO order.
/// Every request made should have a response added to this mock, or it will
/// XCTFail.
public class TSRequestOWSURLSessionMock: BaseOWSURLSessionMock {

    public struct Response {
        let matcher: (TSRequest) -> Bool

        let statusCode: Int
        let headers: OWSHttpHeaders
        let bodyData: Data?

        public init(
            matcher: @escaping (TSRequest) -> Bool,
            statusCode: Int = 200,
            headers: OWSHttpHeaders = OWSHttpHeaders(),
            bodyData: Data? = nil
        ) {
            self.matcher = matcher
            self.statusCode = statusCode
            self.headers = headers
            self.bodyData = bodyData
        }

        public init(
            urlSuffix: String,
            statusCode: Int = 200,
            headers: [String: String] = [:],
            bodyJson: Codable? = nil
        ) {
            var bodyData: Data?
            do {
                if let bodyJson {
                    bodyData = try JSONEncoder().encode(bodyJson)
                }
            } catch {
                XCTFail("Failed to encode JSON with error: \(error)")
            }
            self.matcher = { $0.url?.relativeString.hasSuffix(urlSuffix) ?? false }
            self.statusCode = statusCode
            self.headers = OWSHttpHeaders(httpHeaders: headers, overwriteOnConflict: true)
            self.bodyData = bodyData
        }
    }

    public var responses = [Response]()

    public func addResponse(_ response: Response) {
        responses.append(response)
    }

    public func addResponse(
        forUrlSuffix: String,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        bodyJson: Codable? = nil,
        numRepeats: Int = 1
    ) {
        for _ in 0..<numRepeats {
            addResponse(Response(
                urlSuffix: forUrlSuffix,
                statusCode: statusCode,
                headers: headers,
                bodyJson: bodyJson
            ))
        }
    }

    public override func promiseForTSRequest(_ rawRequest: TSRequest) -> Promise<HTTPResponse> {
        guard let responseIndex = responses.firstIndex(where: { $0.matcher(rawRequest) }) else {
            XCTFail("Got a request with no response set up!")
            return .pending().0
        }
        let response = responses.remove(at: responseIndex)
        return .value(HTTPResponseImpl(
            requestUrl: rawRequest.url!,
            status: response.statusCode,
            headers: response.headers,
            bodyData: response.bodyData
        ))
    }
}
