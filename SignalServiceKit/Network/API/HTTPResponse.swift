//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct HTTPResponse {
    public let requestUrl: URL
    public let responseStatusCode: Int
    public let headers: HttpHeaders
    public let responseBodyData: Data?

    private let responseStringEncoding: String.Encoding

    init(
        requestUrl: URL,
        status: Int,
        headers: HttpHeaders,
        bodyData: Data?,
        stringEncoding: String.Encoding? = nil,
    ) {
        self.requestUrl = requestUrl
        self.responseStatusCode = status
        self.headers = headers
        self.responseBodyData = bodyData
        self.responseStringEncoding = stringEncoding ?? .utf8
    }

    init(
        requestUrl: URL,
        httpUrlResponse: HTTPURLResponse,
        bodyData: Data?,
    ) {
        self.init(
            requestUrl: requestUrl,
            status: httpUrlResponse.statusCode,
            headers: HttpHeaders(response: httpUrlResponse),
            bodyData: bodyData,
            stringEncoding: httpUrlResponse.parseStringEncoding(),
        )
    }

    public var responseBodyParamParser: ParamParser? {
        responseBodyDict.map { ParamParser($0) }
    }

    public var responseBodyDict: [String: Any]? {
        responseBodyJson as? [String: Any]
    }

    public var responseBodyJson: Any? {
        responseBodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    public var responseBodyString: String? {
        responseBodyData.flatMap { String(data: $0, encoding: responseStringEncoding) }
    }

    /// Converts a response into an OWSHTTPError.
    public func asError() -> OWSHTTPError {
        return OWSHTTPError.serviceResponse(OWSHTTPError.ServiceResponse(
            requestUrl: self.requestUrl,
            responseStatus: self.responseStatusCode,
            responseHeaders: self.headers,
            responseData: self.responseBodyData,
        ))
    }
}

private extension HTTPURLResponse {
    func parseStringEncoding() -> String.Encoding? {
        guard let encodingName = textEncodingName else {
            return nil
        }
        let encoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
        guard encoding != kCFStringEncodingInvalidId else {
            return nil
        }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}
