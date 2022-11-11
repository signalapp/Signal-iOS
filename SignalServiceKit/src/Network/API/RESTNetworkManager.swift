//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

    private let urlSession: OWSURLSessionProtocol
    @objc
    public let createdDate = Date()

    @objc
    public override required init() {
        assertOnQueue(NetworkManagerQueue())

        self.urlSession = Self.signalService.urlSessionForMainSignalService()
    }

    @objc
    public func performRequest(_ request: TSRequest,
                               success: @escaping RESTNetworkManagerSuccess,
                               failure: @escaping RESTNetworkManagerFailure) {
        assertOnQueue(NetworkManagerQueue())
        owsAssertDebug(!FeatureFlags.deprecateREST || signalService.isCensorshipCircumventionActive)

        // We should only use the RESTSessionManager for requests to the Signal main service.
        let urlSession = self.urlSession
        owsAssertDebug(urlSession.unfrontedBaseUrl == URL(string: TSConstants.mainServiceURL))

        guard let requestUrl = request.url else {
            owsFailDebug("Missing requestUrl.")
            let url: URL = urlSession.baseUrl ?? URL(string: TSConstants.mainServiceURL)!
            failure(OWSHTTPErrorWrapper(error: .missingRequest(requestUrl: url)))
            return
        }

        firstly {
            urlSession.promiseForTSRequest(request)
        }.done(on: .global()) { (response: HTTPResponse) in
            success(response)
        }.catch(on: .global()) { error in
            // OWSUrlSession should only throw OWSHTTPError or OWSAssertionError.
            if let httpError = error as? OWSHTTPError {
                HTTPUtils.applyHTTPError(httpError)

                failure(OWSHTTPErrorWrapper(error: httpError))
            } else {
                owsFailDebug("Unexpected error: \(error)")

                failure(OWSHTTPErrorWrapper(error: OWSHTTPError.invalidRequest(requestUrl: requestUrl)))
            }
        }
    }
}

// MARK: -

extension OWSURLSessionProtocol {
    public func promiseForTSRequest(_ rawRequest: TSRequest) -> Promise<HTTPResponse> {

        guard let rawRequestUrl = rawRequest.url else {
            owsFailDebug("Missing requestUrl.")
            let url: URL = self.baseUrl ?? URL(string: TSConstants.mainServiceURL)!
            return Promise(error: OWSHTTPError.missingRequest(requestUrl: url))
        }
        guard !appExpiry.isExpired else {
            owsFailDebug("App is expired.")
            return Promise(error: OWSHTTPError.invalidAppState(requestUrl: rawRequestUrl))
        }

        let httpHeaders = OWSHttpHeaders()

        // Set User-Agent and Accept-Language headers.
        httpHeaders.addDefaultHeaders()

        // TODO: This is with the extraHeaders set in OWSSignalService.
        if signalService.isCensorshipCircumventionActive {
            httpHeaders.addHeader("Host", value: TSConstants.censorshipReflectorHost, overwriteOnConflict: true)
        }

        // Then apply any custom headers for the request
        httpHeaders.addHeaderMap(rawRequest.allHTTPHeaderFields, overwriteOnConflict: true)

        if rawRequest.canUseAuth,
           rawRequest.shouldHaveAuthorizationHeaders {
            owsAssertDebug(nil != rawRequest.authUsername?.nilIfEmpty)
            owsAssertDebug(nil != rawRequest.authPassword?.nilIfEmpty)
            do {
                try httpHeaders.addAuthHeader(username: rawRequest.authUsername ?? "",
                                              password: rawRequest.authPassword ?? "")
            } catch {
                owsFailDebug("Could not add auth header: \(error).")
                return Promise(error: OWSHTTPError.invalidAppState(requestUrl: rawRequestUrl))
            }
        }

        let method: HTTPMethod
        do {
            method = try HTTPMethod.method(for: rawRequest.httpMethod)
        } catch {
            owsFailDebug("Invalid HTTP method: \(rawRequest.httpMethod)")
            return Promise(error: OWSHTTPError.invalidRequest(requestUrl: rawRequestUrl))
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
                return Promise(error: OWSHTTPError.invalidRequest(requestUrl: rawRequestUrl))
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

        let urlSession = self
        let request: URLRequest
        do {
            request = try urlSession.buildRequest(rawRequestUrl.absoluteString,
                                                  method: method,
                                                  headers: httpHeaders.headers,
                                                  body: requestBody)
        } catch {
            owsFailDebug("Missing or invalid request: \(rawRequestUrl).")
            return Promise(error: OWSHTTPError.invalidRequest(requestUrl: rawRequestUrl))
        }

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)")

        Logger.verbose("Making request: \(rawRequest.description)")

        return firstly(on: .global()) { () throws -> Promise<HTTPResponse> in
            urlSession.uploadTaskPromise(request: request, data: requestBody)
        }.map(on: .global()) { (response: HTTPResponse) -> HTTPResponse in
            Logger.info("Success: \(rawRequest.description)")
            return response
        }.ensure(on: .global()) {
            owsAssertDebug(backgroundTask != nil)
            backgroundTask = nil
        }.recover(on: .global()) { error -> Promise<HTTPResponse> in
            Logger.warn("Failure: \(rawRequest.description), error: \(error)")
            throw error
        }
    }
}

// MARK: -

@objc
public extension TSRequest {
    var canUseAuth: Bool { !isUDRequest }
}
