//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

public extension RESTNetworkManager {
    func makePromise(request: TSRequest) -> Promise<HTTPResponse> {
        let (promise, future) = Promise<HTTPResponse>.pending()
        self.makeRequest(request,
                         completionQueue: .global(),
                         success: { (response: HTTPResponse) in
                            future.resolve(response)
                         },
                         failure: { (error: OWSHTTPErrorWrapper) in
                            future.reject(error.error)
                         })
        return promise
    }
}

// MARK: -

@objc
public class RESTSessionManager: NSObject {

    private let urlSession: OWSURLSession
    @objc
    public let createdDate = Date()

    @objc
    public override required init() {
        assertOnQueue(NetworkManagerQueue())

        self.urlSession = Self.signalService.urlSessionForMainSignalService()
    }

    @objc
    public func performRequest(_ rawRequest: TSRequest,
                               canUseAuth: Bool,
                               success: @escaping RESTNetworkManagerSuccess,
                               failure: @escaping RESTNetworkManagerFailure) {
        assertOnQueue(NetworkManagerQueue())
        owsAssertDebug(!FeatureFlags.deprecateREST || signalService.isCensorshipCircumventionActive)

        guard let rawRequestUrl = rawRequest.url else {
            owsFailDebug("Missing requestUrl.")
            failure(OWSHTTPErrorWrapper(error: .invalidRequest(requestUrl: URL(string: "")!)))
            return
        }
        guard !appExpiry.isExpired else {
            owsFailDebug("App is expired.")
            failure(OWSHTTPErrorWrapper(error: .invalidAppState(requestUrl: rawRequestUrl)))
            return
        }

        let httpHeaders = OWSHttpHeaders()

        // Set User-Agent and Accept-Language headers.
        httpHeaders.addDefaultHeaders()

        if signalService.isCensorshipCircumventionActive {
            httpHeaders.addHeader("Host", value: TSConstants.censorshipReflectorHost, overwriteOnConflict: true)
        }

        // Then apply any custom headers for the request
        httpHeaders.addHeaderMap(rawRequest.allHTTPHeaderFields, overwriteOnConflict: true)

        if canUseAuth,
           rawRequest.shouldHaveAuthorizationHeaders {
            owsAssertDebug(nil != rawRequest.authUsername?.nilIfEmpty)
            owsAssertDebug(nil != rawRequest.authPassword?.nilIfEmpty)
            do {
                try httpHeaders.addAuthHeader(username: rawRequest.authUsername ?? "",
                                              password: rawRequest.authPassword ?? "")
            } catch {
                owsFailDebug("Could not add auth header: \(error).")
                failure(OWSHTTPErrorWrapper(error: .invalidAppState(requestUrl: rawRequestUrl)))
            }
        }

        let method: HTTPMethod
        do {
            method = try HTTPMethod.method(for: rawRequest.httpMethod)
        } catch {
            owsFailDebug("Invalid HTTP method: \(rawRequest.httpMethod)")
            failure(OWSHTTPErrorWrapper(error: OWSHTTPError.invalidRequest(requestUrl: rawRequestUrl)))
            return
        }

        var requestBody = Data()
        if let httpBody = rawRequest.httpBody {
            owsAssertDebug(rawRequest.parameters.isEmpty)

            requestBody = httpBody
        } else if !rawRequest.parameters.isEmpty {
            let jsonData: Data?
            do {
                jsonData = try JSONSerialization.data(withJSONObject: rawRequest.parameters, options: [])
            } catch {
                owsFailDebug("Could not serialize JSON parameters: \(error).")
                failure(OWSHTTPErrorWrapper(error: OWSHTTPError.invalidRequest(requestUrl: rawRequestUrl)))
                return
            }

            if let jsonData = jsonData {
                requestBody = jsonData
                // If we're going to use the json serialized parameters as our body, we should overwrite
                // the Content-Type on the request.
                httpHeaders.addHeader("Content-Type",
                                      value: "application/json",
                                      overwriteOnConflict: true)
            }
        }

        let urlSession = self.urlSession
        let request: URLRequest
        do {
            request = try urlSession.buildRequest(rawRequestUrl.absoluteString,
                                                  method: method,
                                                  headers: httpHeaders.headers,
                                                  body: requestBody,
                                                  customCensorshipCircumventionPrefix: rawRequest.customCensorshipCircumventionPrefix,
                                                  customHost: rawRequest.customHost)
        } catch {
            owsFailDebug("Missing or invalid request: \(rawRequestUrl).")
            failure(OWSHTTPErrorWrapper(error: .invalidRequest(requestUrl: rawRequestUrl)))
            return
        }

        guard let requestUrl = request.url else {
            owsFailDebug("Missing or invalid requestUrl: \(rawRequestUrl).")
            failure(OWSHTTPErrorWrapper(error: .invalidRequest(requestUrl: rawRequestUrl)))
            return
        }

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)")

        Logger.verbose("Request: \(request)")

        firstly(on: .global()) { () throws -> Promise<HTTPResponse> in
            urlSession.uploadTaskPromise(request: request, data: requestBody)
        }.done(on: .global()) { (response: HTTPResponse) in
            Logger.info("Success: \(request)")
            success(response)
        }.ensure(on: .global()) {
            owsAssertDebug(backgroundTask != nil)
            backgroundTask = nil
        }.catch(on: .global()) { error in
            Logger.warn("Failure: \(request), error: \(error)")

            if let httpError = error as? OWSHTTPError {
                failure(OWSHTTPErrorWrapper(error: httpError))
            } else {
                failure(OWSHTTPErrorWrapper(error: OWSHTTPError.invalidResponse(requestUrl: requestUrl)))
            }
        }
    }
}
