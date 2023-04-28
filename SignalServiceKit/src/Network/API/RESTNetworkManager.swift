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
        owsAssertDebug(!FeatureFlags.deprecateREST)

        // We should only use the RESTSessionManager for requests to the Signal main service.
        let urlSession = self.urlSession
        owsAssertDebug(urlSession.unfrontedBaseUrl == URL(string: TSConstants.mainServiceIdentifiedURL))

        guard let requestUrl = request.url else {
            owsFailDebug("Missing requestUrl.")
            failure(OWSHTTPErrorWrapper(error: .missingRequest))
            return
        }

        firstly {
            urlSession.promiseForTSRequest(request)
        }.done(on: DispatchQueue.global()) { (response: HTTPResponse) in
            success(response)
        }.catch(on: DispatchQueue.global()) { error in
            // OWSUrlSession should only throw OWSHTTPError or OWSAssertionError.
            if let httpError = error as? OWSHTTPError {
                HTTPUtils.applyHTTPError(httpError)

                let wrappedError = OWSHTTPErrorWrapper(error: httpError)
                if httpError.httpStatusCode == 401, request.shouldCheckDeregisteredOn401 {
                    NetworkManagerQueue().async {
                        self.makeIsDeregisteredRequest(
                            originalRequestFailureHandler: failure,
                            originalRequestFailure: wrappedError
                        )
                    }
                } else {
                    failure(wrappedError)
                }
            } else {
                owsFailDebug("Unexpected error: \(error)")

                failure(OWSHTTPErrorWrapper(error: OWSHTTPError.invalidRequest(requestUrl: requestUrl)))
            }
        }
    }

    private func makeIsDeregisteredRequest(
        originalRequestFailureHandler: @escaping RESTNetworkManagerFailure,
        originalRequestFailure: OWSHTTPErrorWrapper
    ) {
        let isDeregisteredRequest = WhoAmIRequestFactory.amIDeregisteredRequest()

        let handleDeregisteredResponse: (WhoAmIRequestFactory.Responses.AmIDeregistered?) -> Void = { [tsAccountManager] response in
            switch response {
            case .deregistered:
                Logger.warn("AmIDeregistered response says we are deregistered, marking as such.")
                tsAccountManager.isDeregistered = true
            case .notDeregistered:
                Logger.info("AmIDeregistered response says not deregistered; account probably disabled. Doing nothing.")
            case .none, .unexpectedError:
                Logger.error("Got unexpected AmIDeregistered response. Doing nothing.")
            }
        }

        self.performRequest(
            isDeregisteredRequest,
            success: { rawResponse in
                let response = WhoAmIRequestFactory.Responses.AmIDeregistered(rawValue: rawResponse.responseStatusCode)
                handleDeregisteredResponse(response)
                originalRequestFailureHandler(originalRequestFailure)
            }, failure: { rawFailure in
                let response = WhoAmIRequestFactory.Responses.AmIDeregistered(rawValue: rawFailure.error.responseStatusCode)
                handleDeregisteredResponse(response)
                originalRequestFailureHandler(originalRequestFailure)
            }
        )
    }
}

// MARK: -

@objc
public extension TSRequest {
    var canUseAuth: Bool { !isUDRequest }
}
