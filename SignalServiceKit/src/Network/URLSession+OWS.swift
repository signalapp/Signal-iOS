//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public enum HTTPVerb {
    case get
    case post
    case put
}

public extension URLSession {
    typealias Response = (response: HTTPURLResponse, data: Data?)

    func uploadTaskPromise(_ urlString: String,
                           verb: HTTPVerb,
                           headers: [String: String]? = nil,
                           data requestData: Data) -> Promise<Response> {
        guard let url = URL(string: urlString) else {
            return Promise(error: OWSAssertionError("Invalid url."))
        }
        var request = URLRequest(url: url)
        switch verb {
        case .get:
            request.httpMethod = "GET"
        case .post:
            request.httpMethod = "POST"
        case .put:
            request.httpMethod = "PUT"
        }
        if let headers = headers {
            for (headerField, headerValue) in headers {
                request.addValue(headerValue, forHTTPHeaderField: headerField)
            }
        }

        return uploadTaskPromise(request: request, data: requestData)
    }

    func uploadTaskPromise(request: URLRequest, data requestData: Data) -> Promise<Response> {

        let (promise, resolver) = Promise<Response>.pending()
        let task = uploadTask(with: request, from: requestData) { (responseData: Data?, response: URLResponse?, error: Error?) in
            if let error = error {
                if IsNetworkConnectivityFailure(error) {
                    Logger.warn("Request failed: \(error)")
                } else {
                    owsFailDebug("Request failed: \(error)")
                }
                resolver.reject(error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                resolver.reject(OWSAssertionError("Invalid response: \(type(of: response))."))
                return
            }
            resolver.fulfill((response: httpResponse, data: responseData))
        }
        task.resume()
        return promise
    }
}
