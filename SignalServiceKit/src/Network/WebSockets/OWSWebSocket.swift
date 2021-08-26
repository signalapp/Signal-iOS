//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension OWSWebSocket {

    // TODO: Combine with makeRequestInternal().
    @objc
    public func makeRequest(_ request: TSRequest,
                            success successParam: @escaping TSSocketMessageSuccess,
                            failure failureParam: @escaping TSSocketMessageFailure) {

        guard !appExpiry.isExpired else {
            DispatchQueue.global().async {
                guard let requestUrl = request.url else {
                    owsFail("Missing requestUrl.")
                }
                let error = OWSHTTPError.invalidAppState(requestUrl: requestUrl)
                let failure = OWSHTTPErrorWrapper(error: error)
                failureParam(failure)
            }
            return
        }

        switch webSocketType {
        case .identified:
            owsAssertDebug(!request.isUDRequest)
            owsAssertDebug(request.shouldHaveAuthorizationHeaders)
        case .unidentified:
            owsAssertDebug(request.isUDRequest || !request.shouldHaveAuthorizationHeaders)
        }
        let label = "\(webSocketType) request"
        let canUseAuth = webSocketType == .identified && !request.isUDRequest
        Logger.info("Making \(label): \(request)")

        self.makeRequestInternal(request,
                                 success: { (response: HTTPResponse) in
                                    Logger.info("Succeeded \(label): \(request)")

                                    if canUseAuth,
                                       request.shouldHaveAuthorizationHeaders {
                                        Self.tsAccountManager.setIsDeregistered(false)
                                    }

                                    successParam(response)

                                    Self.outageDetection.reportConnectionSuccess()
                                 },
                                 failure: { (failure: OWSHTTPErrorWrapper) in
                                    if failure.error.responseStatusCode == AppExpiry.appExpiredStatusCode {
                                        Self.appExpiry.setHasAppExpiredAtCurrentVersion()
                                    }

                                    failureParam(failure)
                                 })
    }

    @objc
    public static func parseServiceHeaders(_ headers: [String]) -> OWSHttpHeaders {
        let result = OWSHttpHeaders()
        for header in headers {
            guard let header = header.strippedOrNil else {
                owsFailDebug("Empty header.")
                continue
            }
            guard let index = header.firstIndex(of: ":") else {
                Logger.warn("Invalid header: \(header).")
                owsFailDebug("Invalid header.")
                continue
            }
            let beforeColonIndex = index
            let afterColonIndex = header.index(index, offsetBy: 1)
            guard let key = String(header.prefix(upTo: beforeColonIndex)).strippedOrNil else {
                Logger.warn("Invalid header key: \(header).")
                owsFailDebug("Invalid header key.")
                continue
            }
            guard let value = String(header.suffix(from: afterColonIndex)).strippedOrNil else {
                Logger.warn("Invalid header value: \(header), key: \(key).")
                owsFailDebug("Invalid header value.")
                continue
            }
            result.addHeader(key, value: value, overwriteOnConflict: true)
        }
        return result
    }
}

// MARK: -

// TODO: Make this private, rename class.
@objc
public class SocketMessageInfo: NSObject {

    @objc
    public let request: TSRequest

    @objc
    public let requestUrl: URL

    @objc
    public let requestId: UInt64 = Cryptography.randomUInt64()

    // We use an enum to ensure that the completion handlers are
    // released as soon as the message completes.
    private enum Status {
        case incomplete(success: TSSocketMessageSuccess, failure: TSSocketMessageFailure)
        case complete
    }

    private static let unfairLock = UnfairLock()

    // This property should only be accessed with unfairLock acquired.
    private var status: Status

    private let backgroundTask: OWSBackgroundTask

    @objc
    public required init(request: TSRequest,
                         requestUrl: URL,
                         success: @escaping TSSocketMessageSuccess,
                         failure: @escaping TSSocketMessageFailure) {
        self.request = request
        self.requestUrl = requestUrl
        self.status = .incomplete(success: success, failure: failure)
        self.backgroundTask = OWSBackgroundTask(label: "TSSocketMessage")
    }

    @objc
    public func didSucceed(status: Int,
                           headers: OWSHttpHeaders,
                           bodyData: Data?,
                           message: String?) {
        let response = HTTPResponseImpl(requestUrl: requestUrl,
                                        status: status,
                                        headers: headers,
                                        bodyData: bodyData)
        didSucceed(response: response)
    }

    @objc
    public func didSucceed(response: HTTPResponse) {
        Self.unfairLock.withLock {
            switch status {
            case .complete:
                return
            case .incomplete(let success, _):
                // Ensure that we only complete once.
                status = .complete

                DispatchQueue.global().async {
                    success(response)
                }
            }
        }
    }

    @objc
    public func timeoutIfNecessary() {
        didFail(error: OWSHTTPError.networkFailure(requestUrl: requestUrl))
    }

    @objc
    public func didFailInvalidRequest() {
        didFail(error: OWSHTTPError.invalidRequest(requestUrl: requestUrl))
    }

    @objc
    public func didFailDueToNetwork() {
        didFail(error: OWSHTTPError.networkFailure(requestUrl: requestUrl))
    }

    @objc
    public func didFail(responseStatus: Int,
                        responseHeaders: OWSHttpHeaders,
                        responseError: Error?,
                        responseData: Data?) {
        let error = HTTPUtils.preprocessMainServiceHTTPError(request: request,
                                                             requestUrl: requestUrl,
                                                             responseStatus: responseStatus,
                                                             responseHeaders: responseHeaders,
                                                             responseError: responseError,
                                                             responseData: responseData)
        didFail(error: error)
    }

    private func didFail(error: Error) {
        Self.unfairLock.withLock {
            switch status {
            case .complete:
                return
            case .incomplete(_, let failure):
                // Ensure that we only complete once.
                status = .complete

                DispatchQueue.global().async {
                    let statusCode = HTTPStatusCodeForError(error) ?? 0
                    Logger.warn("didFail, status: \(statusCode), error: \(error)")

                    let error = error as! OWSHTTPError
                    let socketFailure = OWSHTTPErrorWrapper(error: error)
                    failure(socketFailure)
                }
            }
        }
    }
}
