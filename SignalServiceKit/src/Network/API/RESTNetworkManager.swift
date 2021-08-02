//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import AFNetworking

public extension RESTNetworkManager {
    func makePromise(request: TSRequest) -> Promise<HTTPResponse> {
        let (promise, resolver) = Promise<HTTPResponse>.pending()
        self.makeRequest(request,
                         completionQueue: DispatchQueue.global(),
                         success: { (response: HTTPResponse) in
                            resolver.fulfill(response)
                         },
                         failure: { (error: OWSHTTPErrorWrapper) in
                            resolver.reject(error.error)
                         })
        return promise
    }
}

// MARK: -

@objc
public class RESTSessionManager: NSObject {

    private let sessionManager: AFHTTPSessionManager
    private let defaultHeaders: [String: String]
    @objc
    public let createdDate = Date()

    @objc
    public override required init() {
        assertOnQueue(NetworkManagerQueue())

        // TODO: Use OWSUrlSession instead.
        self.sessionManager = Self.signalService.sessionManagerForMainSignalService()
        self.sessionManager.completionQueue = .global()
        // NOTE: We could enable HTTPShouldUsePipelining here.
        // Make a copy of the default headers for this session manager.
        self.defaultHeaders = sessionManager.requestSerializer.httpRequestHeaders
    }

    @objc
    public func performRequest(_ request: TSRequest,
                               canUseAuth: Bool,
                               success: @escaping RESTNetworkManagerSuccess,
                               failure: @escaping RESTNetworkManagerFailure) {
        assertOnQueue(NetworkManagerQueue())

        guard let rawRequestUrl = request.url else {
            owsFailDebug("Missing requestUrl.")
            failure(OWSHTTPErrorWrapper(error: .invalidRequest(requestUrl: URL(string: "")!)))
            return
        }
        guard !appExpiry.isExpired else {
            owsFailDebug("App is expired.")
            failure(OWSHTTPErrorWrapper(error: .invalidAppState(requestUrl: rawRequestUrl)))
            return
        }

        // Clear all headers so that we don't retain headers from previous requests.
        let oldHeaderFields: [String] = Array(sessionManager.requestSerializer.httpRequestHeaders.keys)
        for headerField in oldHeaderFields {
            sessionManager.requestSerializer.setValue(nil, forKey: headerField)
        }

        let httpHeaders = OWSHttpHeaders()

        // Apply the default headers for this session manager.
        httpHeaders.addHeaders(defaultHeaders, overwriteOnConflict: false)

        // Set User-Agent header.
        httpHeaders.addHeader(OWSURLSession.kUserAgentHeader,
                              value: OWSURLSession.signalIosUserAgent,
                              overwriteOnConflict: true)

        // Then apply any custom headers for the request
        httpHeaders.addHeaders(request.allHTTPHeaderFields, overwriteOnConflict: true)

        if canUseAuth,
           request.shouldHaveAuthorizationHeaders {
            owsAssertDebug(nil != request.authUsername?.nilIfEmpty)
            owsAssertDebug(nil != request.authPassword?.nilIfEmpty)
            sessionManager.requestSerializer.setAuthorizationHeaderFieldWithUsername(request.authUsername ?? "",
                                                                                     password: request.authPassword ?? "")
        }

        // Most of TSNetwork requests are destined for the Signal Service.
        // When we are domain fronting, we have to target a different host and add a path prefix.
        // For common Signal-Service requests the host/path-prefix logic is handled by the
        // sessionManager.
        //
        // However, for CDS requests, we need to:
        //  With CC enabled, use the service fronting Hostname but a custom path-prefix
        //  With CC disabled, use the custom directory host, and no path-prefix
        func buildRequestURL() -> URL? {
            if signalService.isCensorshipCircumventionActive,
               let customCensorshipCircumventionPrefix = request.customCensorshipCircumventionPrefix?.nilIfEmpty {
                // All fronted requests go through the same host
                let customBaseUrl: URL = signalService.domainFrontBaseURL.appendingPathComponent(customCensorshipCircumventionPrefix)
                guard let requestUrl = OWSURLSession.buildUrl(urlString: rawRequestUrl.absoluteString,
                                                              baseUrl: customBaseUrl) else {
                    owsFailDebug("Could not apply baseUrl.")
                    return nil
                }
                return requestUrl
            } else if let customHost = request.customHost?.nilIfEmpty {
                guard let customBaseUrl = URL(string: customHost) else {
                    owsFailDebug("Invalid customHost.")
                    return nil
                }
                guard let requestUrl = OWSURLSession.buildUrl(urlString: rawRequestUrl.absoluteString,
                                                              baseUrl: customBaseUrl) else {
                    owsFailDebug("Could not apply baseUrl.")
                    return nil
                }
                return requestUrl
            } else {
                // requests for the signal-service (with or without censorship circumvention)
                return rawRequestUrl
            }
        }
        guard let requestUrl = buildRequestURL(),
              let requestUrlString = requestUrl.absoluteString.nilIfEmpty else {
            owsFailDebug("Missing or invalid requestUrl.")
            failure(OWSHTTPErrorWrapper(error: .invalidRequest(requestUrl: rawRequestUrl)))
            return
        }

        // Honor the request's headers.
        for (key, value) in httpHeaders.headers {
            sessionManager.requestSerializer.setValue(value, forKey: key)
        }

        func parseResponse(task: URLSessionDataTask?, error: Error? = nil) -> HTTPURLResponse? {
            if let response = task?.response as? HTTPURLResponse {
                return response
            }
            if let error = error,
               let response = (error as NSError).afFailingHTTPURLResponse {
                return response
            }
            return nil
        }
        func parseResponseHeaders(task: URLSessionDataTask?) -> OWSHttpHeaders {
            let parsedHeaders = OWSHttpHeaders()
            guard let response = parseResponse(task: task) else {
                owsFailDebug("Invalid response.")
                return parsedHeaders
            }
            for (key, value) in response.allHeaderFields {
                guard let key = key as? String,
                      let value = value as? String else {
                    owsFailDebug("Invalid header: \(key), \(value)")
                    continue
                }
                parsedHeaders.addHeader(key, value: value, overwriteOnConflict: false)
            }
            return parsedHeaders
        }

        let afSuccess = { (task: URLSessionDataTask?, responseObject: Any?) in
            var responseStatus: UInt32 = 0
            let responseHeaders = parseResponseHeaders(task: task)
            // TODO: Can we extract a response body?
            var responseData: Data?
            if let response = parseResponse(task: task) {
                responseStatus = UInt32(response.statusCode)
                if let responseObject = responseObject {
                    if let data = responseObject as? Data {
                        responseData = data
                    } else {
                        owsFailDebug("Invalid response: \(type(of: responseObject))")
                    }
                }
            } else {
                owsFailDebug("Invalid response.")
            }
            let response = OWSHTTPResponseImpl(requestUrl: requestUrl,
                                               status: responseStatus,
                                               headers: responseHeaders,
                                               bodyData: responseData,
                                               message: nil)
            success(response)
        }

        let afFailure = { (task: URLSessionDataTask?, error: Error) in
            var responseStatus: UInt32 = 0
            let responseHeaders = parseResponseHeaders(task: task)
            // TODO: Can we extract a response body?
            let responseData: Data? = nil

            if let response = parseResponse(task: task) {
                responseStatus = UInt32(response.statusCode)
            } else {
                owsFailDebug("Invalid response.")
            }
            let error = HTTPUtils.preprocessMainServiceHTTPError(request: request,
                                                                 requestUrl: requestUrl,
                                                                 responseStatus: responseStatus,
                                                                 responseHeaders: responseHeaders,
                                                                 responseError: error,
                                                                 responseData: responseData)
            failure(OWSHTTPErrorWrapper(error: error))
        }

        switch request.httpMethod {
        case "GET":
            sessionManager.get(requestUrlString,
                               parameters: request.parameters,
                               progress: nil,
                               success: afSuccess,
                               failure: afFailure)
        case "POST":
            sessionManager.post(requestUrlString,
                                parameters: request.parameters,
                                progress: nil,
                                success: afSuccess,
                                failure: afFailure)
        case "PUT":
            sessionManager.put(requestUrlString,
                               parameters: request.parameters,
                               success: afSuccess,
                               failure: afFailure)
        case "DELETE":
            sessionManager.delete(requestUrlString,
                                  parameters: request.parameters,
                                  success: afSuccess,
                                  failure: afFailure)
        default:
            owsFailDebug("Invalid request.")
            failure(OWSHTTPErrorWrapper(error: .invalidRequest(requestUrl: rawRequestUrl)))
        }
    }
}
