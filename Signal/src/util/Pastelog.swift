//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

@objc
public class DebugLogUploader: NSObject {
    public typealias SuccessBlock = (DebugLogUploader, URL) -> Void
    public typealias FailureBlock = (DebugLogUploader, Error) -> Void

    deinit {
        Logger.verbose("")
    }

    @objc
    public func uploadFile(fileUrl: URL,
                           mimeType: String,
                           success: @escaping SuccessBlock,
                           failure: @escaping FailureBlock) {
        firstly(on: .global()) {
            self.getUploadParameters(fileUrl: fileUrl)
        }.then(on: .global()) { [weak self] (uploadParameters: UploadParameters) -> Promise<URL> in
            guard let self = self else { throw OWSGenericError("Missing self.") }
            return self.uploadFile(fileUrl: fileUrl,
                                   mimeType: mimeType,
                                   uploadParameters: uploadParameters)
        }.done(on: .global()) { [weak self] (uploadedUrl: URL) in
            guard let self = self else { throw OWSGenericError("Missing self.") }
            success(self, uploadedUrl)
        }.catch(on: .global()) { [weak self] error in
            owsFailDebugUnlessNetworkFailure(error)
            guard let self = self else { return }
            failure(self, error)
        }
    }

    private func buildOWSURLSession() -> OWSURLSession {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.urlCache = nil
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        let urlSession = OWSURLSession(baseUrl: nil,
                                       securityPolicy: OWSURLSession.defaultSecurityPolicy,
                                       configuration: sessionConfig)
        return urlSession
    }

    private func getUploadParameters(fileUrl: URL) -> Promise<UploadParameters> {
        let url = URL(string: "https://debuglogs.org/")!
        return firstly(on: .global()) { () -> Promise<(HTTPResponse)> in
            self.buildOWSURLSession().dataTaskPromise(url.absoluteString, method: .get)
        }.map(on: .global()) { (response: HTTPResponse) -> (UploadParameters) in
            guard let responseObject = response.responseBodyJson else {
                throw OWSAssertionError("Invalid response.")
            }
            guard let params = ParamParser(responseObject: responseObject) else {
                throw OWSAssertionError("Invalid response: \(String(describing: responseObject))")
            }
            let uploadUrl: String = try params.required(key: "url")
            let fieldMap: [String: String] = try params.required(key: "fields")
            guard !fieldMap.isEmpty else {
                throw OWSAssertionError("Invalid response: \(String(describing: responseObject))")
            }
            for (key, value) in fieldMap {
                guard nil != key.nilIfEmpty,
                      nil != value.nilIfEmpty else {
                          throw OWSAssertionError("Invalid response: \(String(describing: responseObject))")
                      }
            }
            guard let rawUploadKey = fieldMap["key"]?.nilIfEmpty else {
                throw OWSAssertionError("Invalid response: \(String(describing: responseObject))")
            }
            guard let fileExtension = (fileUrl.lastPathComponent as NSString).pathExtension.nilIfEmpty else {
                throw OWSAssertionError("Invalid fileUrl: \(fileUrl)")
            }
            guard let uploadKey: String = (rawUploadKey as NSString).appendingPathExtension(fileExtension) else {
                throw OWSAssertionError("Could not modify uploadKey.")
            }
            var orderedFieldMap = OrderedDictionary<String, String>()
            for (key, value) in fieldMap {
                orderedFieldMap.append(key: key, value: value)
            }
            orderedFieldMap.replace(key: "key", value: uploadKey)
            return UploadParameters(uploadUrl: uploadUrl, fieldMap: orderedFieldMap, uploadKey: uploadKey)
        }
    }

    private struct UploadParameters {
        let uploadUrl: String
        let fieldMap: OrderedDictionary<String, String>
        let uploadKey: String
    }

    private func uploadFile(fileUrl: URL,
                            mimeType: String,
                            uploadParameters: UploadParameters) -> Promise<URL> {
        firstly(on: .global()) { () -> Promise<(HTTPResponse)> in
            let urlSession = self.buildOWSURLSession()

            guard let url = URL(string: uploadParameters.uploadUrl) else {
                throw OWSAssertionError("Invalid url: \(uploadParameters.uploadUrl)")
            }
            let request = URLRequest(url: url)

            var textParts = uploadParameters.fieldMap
            let mimeType = OWSMimeTypeApplicationZip
            textParts.append(key: "Content-Type", value: mimeType)

            return urlSession.multiPartUploadTaskPromise(request: request,
                                                         fileUrl: fileUrl,
                                                         name: "file",
                                                         fileName: fileUrl.lastPathComponent,
                                                         mimeType: mimeType,
                                                         textParts: textParts,
                                                         progress: nil)
        }.map(on: .global()) { (response: HTTPResponse) -> URL in
            let statusCode = response.responseStatusCode
            // We'll accept any 2xx status code.
            let statusCodeClass = statusCode - (statusCode % 100)
            guard statusCodeClass == 200 else {
                Logger.error("statusCode: \(statusCode), \(statusCodeClass)")
                Logger.error("headers: \(response.responseHeaders)")
                throw OWSAssertionError("Invalid status code: \(statusCode), \(statusCodeClass)")
            }

            let urlString = "https://debuglogs.org/\(uploadParameters.uploadKey)"
            guard let url = URL(string: urlString) else {
                throw OWSAssertionError("Invalid url: \(urlString)")
            }
            return url
        }
    }
}
