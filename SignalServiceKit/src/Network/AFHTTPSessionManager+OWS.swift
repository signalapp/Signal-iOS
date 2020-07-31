//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension AFHTTPSessionManager {
    typealias Response = (task: URLSessionDataTask, responseObject: Any?)
    typealias ProgressBlock = (Progress) -> Void

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

    func putPromise(_ urlString: String,
                     headers: [String: String]? = nil,
                     parameters: [String: AnyObject]? = nil) -> Promise<Response> {

        performRequest(urlString, verb: .put, headers: headers, parameters: parameters)
    }

    private func performRequest(_ urlString: String,
                                verb: HTTPVerb,
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
                    #if TESTABLE_BUILD
                    TSNetworkManager.logCurl(for: task)
                    #endif
                }
                owsFailDebug("Request failed: \(error)")
            }
            resolver.reject(error)
        }
        switch verb {
        case .get:
            get(urlString, parameters: parameters, progress: progress, success: success, failure: failure)
        case .post:
            post(urlString, parameters: parameters, progress: progress, success: success, failure: failure)
        case .put:
            put(urlString, parameters: parameters, success: success, failure: failure)
        }
        return promise
    }

    // MARK: - Download Tasks

    typealias DownloadTaskProgressBlock = (Progress, URLSessionDownloadTask) -> Void

    func downloadTaskPromise(_ urlString: String,
                             verb: HTTPVerb,
                             headers: [String: String]? = nil,
                             parameters: [String: AnyObject]? = nil,
                             dstFileUrl: URL?,
                             progress: DownloadTaskProgressBlock? = nil) -> Promise<URL> {

        return firstly(on: .global()) { () -> URLRequest in
            try self.buildDownloadTaskRequest(urlString: urlString,
                                              verb: verb,
                                              headers: headers,
                                              parameters: parameters)
        }.then(on: .global()) { (request: URLRequest) in
            self.downloadTaskPromise(request: request,
                                     dstFileUrl: dstFileUrl,
                                     progress: progress)
        }
    }

    func downloadTaskPromise(request: URLRequest,
                             dstFileUrl dstFileUrlParam: URL? = nil,
                             progress progressBlock: DownloadTaskProgressBlock? = nil) -> Promise<URL> {
        let dstFileUrl: URL
        if let dstFileUrlParam = dstFileUrlParam {
            dstFileUrl = dstFileUrlParam
        } else {
            dstFileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
        }

        let (promise, resolver) = Promise<URL>.pending()
        var taskReference: URLSessionDownloadTask?
        let task = downloadTask(with: request,
                                progress: { (progress: Progress) in
                                    guard let task = taskReference else {
                                        owsFailDebug("Missing task.")
                                        return
                                    }
                                    progressBlock?(progress, task)
        },
                                destination: { (_: URL, _: URLResponse) -> URL in
                                    dstFileUrl
        },
                                completionHandler: { (_: URLResponse, completionUrl: URL?, error: Error?) in
                                    if let error = error {
                                        resolver.reject(error)
                                        return
                                    }
                                    if dstFileUrl != completionUrl {
                                        resolver.reject(OWSAssertionError("Unexpected url."))
                                        return
                                    }
                                    resolver.fulfill(dstFileUrl)
        })
        taskReference = task
        task.resume()
        return promise
    }

    private func buildDownloadTaskRequest(urlString: String,
                                          verb: HTTPVerb,
                                          headers: [String: String]? = nil,
                                          parameters: [String: AnyObject]? = nil) throws -> URLRequest {
        guard let url = URL(string: urlString, relativeTo: baseURL) else {
            throw OWSAssertionError("Invalid URL.")
        }

        var nsError: NSError?
        let request = requestSerializer.request(withMethod: verb.httpMethod,
                                                urlString: url.absoluteString,
                                                parameters: parameters,
                                                error: &nsError)
        if let error = nsError {
            throw error
        }
        if let headers = headers {
            for (headerField, headerValue) in headers {
                request.addValue(headerValue, forHTTPHeaderField: headerField)
            }
        }
        return request as URLRequest
    }
}
