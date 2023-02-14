//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

/// OWSURLSessionProtocol mock instance that responds exclusively to TSRequest promises,
/// taking Response objects that it uses to respond to requests in FIFO order.
/// Every request made should have a response added to this mock, or it will
/// fatalError.
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
                fatalError("Failed to encode JSON with error: \(error)")
            }
            self.matcher = { $0.url?.relativeString.hasSuffix(urlSuffix) ?? false }
            self.statusCode = statusCode
            self.headers = OWSHttpHeaders(httpHeaders: headers, overwriteOnConflict: true)
            self.bodyData = bodyData
        }
    }

    public var responses = [(Response, Guarantee<Response>)]()

    public func addResponse(_ response: Response) {
        responses.append((response, .value(response)))
    }

    public func addResponse(_ response: Response, atTime t: Int, on scheduler: TestScheduler) {
        responses.append((response, scheduler.guarantee(resolvingWith: response, atTime: t)))
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
        guard let responseIndex = responses.firstIndex(where: { $0.0.matcher(rawRequest) }) else {
            fatalError("Got a request with no response set up!")
        }
        let response = responses.remove(at: responseIndex)
        return response.1.map(on: SyncScheduler()) {
            return HTTPResponseImpl(
                requestUrl: rawRequest.url!,
                status: $0.statusCode,
                headers: $0.headers,
                bodyData: $0.bodyData
            )
        }
    }
}
#endif
