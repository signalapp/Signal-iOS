//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension AFHTTPSessionManager {
    typealias Response = (task: URLSessionDataTask, responseObject: Any?)
    typealias ProgressBlock = (Progress) -> Void

    private enum Verb {
        case get
        case post
    }

    func getPromise(_ urlString: String,
                     headers: [String: String]? = nil,
                     parameters: [String: AnyObject]? = nil,
                     progress: ProgressBlock? = nil) -> Promise<Response> {

        performRequest(urlString, verb: .get, headers: headers, parameters: parameters, progress: progress)
    }

    func postPromise(_ urlString: String,
                     headers: [String: String]? = nil,
                     parameters: [String: AnyObject]? = nil,
                     progress: ProgressBlock? = nil) -> Promise<Response> {

        performRequest(urlString, verb: .post, headers: headers, parameters: parameters, progress: progress)
    }

    private func performRequest(_ urlString: String,
                                verb: Verb,
                                headers: [String: String]? = nil,
                                parameters: [String: AnyObject]? = nil,
                                progress: ProgressBlock? = nil) -> Promise<Response> {

        if let headers = headers {
            for (headerField, headerValue) in headers {
                requestSerializer.setValue(headerValue,
                                           forHTTPHeaderField: headerField)
            }
        }

        let (promise, resolver) = Promise<Response>.pending()

        let success = { (task: URLSessionDataTask, responseObject: Any?) in
            resolver.fulfill((task: task, responseObject: responseObject))
        }
        let failure = { (task: URLSessionDataTask?, error: Error) in
            if IsNetworkConnectivityFailure(error) {
                Logger.warn("Request failed: \(error)")
            } else {
                if let task = task {
                    Logger.info("---- task: \(task)")
                    #if TESTABLE_BUILD
                    TSNetworkManager.logCurl(for: task)
                    #endif
                }
                owsFailDebug("Request failed: \(error)")
            }
            resolver.reject(error)
        }
        switch verb {
        case .post:
            post(urlString, parameters: parameters, progress: progress, success: success, failure: failure)
        case .get:
            get(urlString, parameters: parameters, progress: progress, success: success, failure: failure)
        }
        return promise
    }
}
