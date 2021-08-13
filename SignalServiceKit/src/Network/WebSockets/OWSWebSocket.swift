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

        let isUDRequest = request.isUDRequest
        let label = isUDRequest ? "UD request" : "Non-UD request"
        let canUseAuth = !isUDRequest
        if isUDRequest {
            owsAssert(!request.shouldHaveAuthorizationHeaders)
        } else {
            owsAssertDebug(request.shouldHaveAuthorizationHeaders)
        }

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

@objc
public class OWSHTTPResponseImpl: NSObject {

    @objc
    public let requestUrl: URL

    @objc
    public let status: UInt32

    @objc
    public let headers: OWSHttpHeaders

    @objc
    public let bodyData: Data?

    // TODO: Remove?
    @objc
    public let message: String?

    private struct JSONValue {
        let json: Any?
    }

    // This property should only be accessed with unfairLock acquired.
    //
    // TODO: Type?
    private var jsonValue: JSONValue?

    private static let unfairLock = UnfairLock()

    public required init(requestUrl: URL,
                         status: UInt32,
                         headers: OWSHttpHeaders,
                         bodyData: Data?,
                         message: String?) {
        self.requestUrl = requestUrl
        self.status = status
        self.headers = headers
        self.bodyData = bodyData
        self.message = message
    }

    @objc
    public var bodyJson: Any? {
        Self.unfairLock.withLock {
            if let jsonValue = self.jsonValue {
                return jsonValue.json
            }
            let jsonValue = Self.parseJSON(data: bodyData)
            self.jsonValue = jsonValue
            return jsonValue.json
        }
    }

    private static func parseJSON(data: Data?) -> JSONValue {
        guard let data = data else {
            return JSONValue(json: nil)
        }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return JSONValue(json: json)
        } catch {
            owsFailDebug("Could not parse JSON: \(error).")
            return JSONValue(json: nil)
        }
    }
}

// MARK: -

// TODO: Modify OWSHTTPResponse to confirm to HTTPResponse as well?
extension OWSHTTPResponseImpl: HTTPResponse {
    @objc
    public var responseStatusCode: Int { Int(status) }
    @objc
    public var responseHeaders: [String: String] { headers.headers }
    @objc
    public var responseBodyData: Data? { bodyData }
    @objc
    public var responseBodyJson: Any? { bodyJson }
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
    public func didSucceed(status: UInt32,
                           headers: OWSHttpHeaders,
                           bodyData: Data?,
                           message: String?) {
        let response = OWSHTTPResponseImpl(requestUrl: requestUrl,
                                           status: status,
                                           headers: headers,
                                           bodyData: bodyData,
                                           message: message)
        didSucceed(response: response)
    }

    @objc
    public func didSucceed(response: OWSHTTPResponseImpl) {
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
    public func didFail(responseStatus: UInt32,
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
