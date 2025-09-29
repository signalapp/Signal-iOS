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
final public class TSRequestOWSURLSessionMock: BaseOWSURLSessionMock {

    public struct Response {
        let matcher: (TSRequest) -> Bool

        let statusCode: Int
        let headers: HttpHeaders
        let bodyData: Data?

        let error: Error?

        public init(
            matcher: @escaping (TSRequest) -> Bool,
            statusCode: Int = 200,
            headers: HttpHeaders = HttpHeaders(),
            bodyData: Data? = nil
        ) {
            self.matcher = matcher
            self.statusCode = statusCode
            self.headers = headers
            self.bodyData = bodyData
            self.error = nil
        }

        public init(
            matcher: @escaping (TSRequest) -> Bool,
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
            self.matcher = matcher
            self.statusCode = statusCode
            self.headers = HttpHeaders(httpHeaders: headers, overwriteOnConflict: true)
            self.bodyData = bodyData
            self.error = nil
        }

        public init(
            urlSuffix: String,
            statusCode: Int = 200,
            headers: [String: String] = [:],
            bodyJson: Codable? = nil
        ) {
            self.init(
                matcher: { $0.url.relativeString.hasSuffix(urlSuffix) },
                statusCode: statusCode,
                headers: headers,
                bodyJson: bodyJson
            )
        }

        private init(
            matcher: @escaping (TSRequest) -> Bool,
            error: Error
        ) {
            self.matcher = matcher
            self.statusCode = 0
            self.headers = .init()
            self.bodyData = nil
            self.error = error
        }

        public static func serviceResponseError(
            matcher: @escaping (TSRequest) -> Bool,
            statusCode: Int,
            headers: HttpHeaders = HttpHeaders(),
            bodyData: Data? = nil,
            url: URL
        ) -> Self {
            Self.init(
                matcher: matcher,
                error: OWSHTTPError.serviceResponse(.init(
                    requestUrl: url,
                    responseStatus: statusCode,
                    responseHeaders: headers,
                    responseData: bodyData
                ))
            )
        }

        public static func networkError(
            url: URL
        ) -> Self {
            Self.init(matcher: { $0.url == url }, error: OWSHTTPError.networkFailure(.unknownNetworkFailure))
        }

        public static func networkError(
            matcher: @escaping (TSRequest) -> Bool,
            url: URL
        ) -> Self {
            Self.init(matcher: matcher, error: OWSHTTPError.networkFailure(.unknownNetworkFailure))
        }
    }

    public var responses = [(Response, Guarantee<Response>)]()

    public func addResponse(_ response: Response) {
        responses.append((response, .value(response)))
    }

    public func addResponse(
        matcher: @escaping (TSRequest) -> Bool,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        bodyJson: Codable? = nil
    ) {
        addResponse(Response(
            matcher: matcher,
            statusCode: statusCode,
            headers: headers,
            bodyJson: bodyJson
        ))
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

    public override func performRequest(_ rawRequest: TSRequest) async throws -> any HTTPResponse {
        guard let responseIndex = responses.firstIndex(where: { $0.0.matcher(rawRequest) }) else {
            fatalError("Got a request with no response set up!")
        }
        let response = await responses.remove(at: responseIndex).1.awaitable()
        if let error = response.error {
            throw error
        }
        return HTTPResponseImpl(
            requestUrl: rawRequest.url,
            status: response.statusCode,
            headers: response.headers,
            bodyData: response.bodyData
        )
    }
}
#endif
