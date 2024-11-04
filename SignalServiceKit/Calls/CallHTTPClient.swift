//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalRingRTC

public class CallHTTPClient {
    public let ringRtcHttpClient: SignalRingRTC.HTTPClient

    public init() {
        self.ringRtcHttpClient = SignalRingRTC.HTTPClient()
        self.ringRtcHttpClient.delegate = self
    }
}

// MARK: - HTTPDelegate

extension CallHTTPClient: HTTPDelegate {
    /**
     * A HTTP request should be sent to the given url.
     * Invoked on the main thread, asychronously.
     * The result of the call should be indicated by calling the receivedHttpResponse() function.
     */
    public func sendRequest(requestId: UInt32, request: HTTPRequest) {
        AssertIsOnMainThread()

        let session = OWSURLSession(
            securityPolicy: OWSURLSession.signalServiceSecurityPolicy,
            configuration: OWSURLSession.defaultConfigurationWithoutCaching,
            canUseSignalProxy: true
        )
        session.require2xxOr3xx = false
        session.allowRedirects = true
        session.customRedirectHandler = { redirectedRequest in
            var redirectedRequest = redirectedRequest
            if let authHeader = request.headers.first(where: {
                $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
            }) {
                redirectedRequest.setValue(authHeader.value, forHTTPHeaderField: authHeader.key)
            }
            return redirectedRequest
        }

        Task { @MainActor in
            do {
                let response = try await session.performRequest(
                    request.url,
                    method: request.method.httpMethod,
                    headers: request.headers,
                    body: request.body
                )
                self.ringRtcHttpClient.receivedResponse(
                    requestId: requestId,
                    response: response.asRingRTCResponse
                )
            } catch {
                if error.isNetworkFailureOrTimeout {
                    Logger.warn("Peek client HTTP request had network error: \(error)")
                } else {
                    owsFailDebug("Peek client HTTP request failed \(error)")
                }
                self.ringRtcHttpClient.httpRequestFailed(requestId: requestId)
            }
        }
    }
}

extension SignalRingRTC.HTTPMethod {
    var httpMethod: SignalServiceKit.HTTPMethod {
        switch self {
        case .get: return .get
        case .post: return .post
        case .put: return .put
        case .delete: return .delete
        }
    }
}

extension SignalServiceKit.HTTPResponse {
    var asRingRTCResponse: SignalRingRTC.HTTPResponse {
        return SignalRingRTC.HTTPResponse(
            statusCode: UInt16(responseStatusCode),
            body: responseBodyData
        )
    }
}
