//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class OWSUploadV2: NSObject {
    @objc
    public class func uploadObjc(data: Data,
                                 uploadForm: OWSUploadForm,
                                 uploadUrlPath: String,
                                 progressBlock: ((Progress) -> Void)?) -> AnyPromise {
        return AnyPromise(upload(data: data,
                                 uploadForm: uploadForm,
                                 uploadUrlPath: uploadUrlPath,
                                 progressBlock: progressBlock))
    }
}

// MARK: -

// A strong reference should be maintained to this object
// until it completes.  If it is deallocated, the upload
// may be cancelled.
//
// This class can be safely accessed and used from any thread.
@objc
public class OWSAttachmentUploadV2: NSObject {

    // MARK: - Dependencies

    private var socketManager: TSSocketManager {
        return SSKEnvironment.shared.socketManager
    }

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    // MARK: -

    // These properties are set on success;
    // They should not be accessed before.
    @objc
    public var encryptionKey: Data?
    @objc
    public var digest: Data?
    @objc
    public var serverId: UInt64 = 0
    @objc
    public var uploadTimestamp: UInt64 = 0

    private let attachmentStream: TSAttachmentStream

    @objc
    public required init(attachmentStream: TSAttachmentStream) {
        self.attachmentStream = attachmentStream
    }

    private func attachmentData() -> Promise<Data> {
        return firstly(on: .global()) { () -> Data in
            let attachmentData = try self.attachmentStream.readDataFromFile()

            var nsEncryptionKey = NSData()
            var nsDigest = NSData()
            guard let encryptedAttachmentData = Cryptography.encryptAttachmentData(attachmentData,
                                                                                   shouldPad: true,
                                                                                   outKey: &nsEncryptionKey,
                                                                                   outDigest: &nsDigest) else {
                                                                                    throw OWSAssertionError("Could not encrypt attachment data.")
            }
            let encryptionKey = nsEncryptionKey as Data
            let digest = nsDigest as Data
            guard !encryptionKey.isEmpty,
                !digest.isEmpty else {
                    throw OWSAssertionError("Could not encrypt attachment data.")
            }

            self.encryptionKey = encryptionKey
            self.digest = digest

            return encryptedAttachmentData
        }
    }

    private func parseFormAndUpload(formResponseObject: Any?,
                                    progressBlock: ((Progress) -> Void)? = nil) -> Promise<Void> {

        return firstly(on: .global()) { () -> OWSUploadForm in
            guard let formDictionary = formResponseObject as? [AnyHashable: Any] else {
                Logger.warn("formResponseObject: \(String(describing: formResponseObject))")
                throw OWSAssertionError("Invalid form.")
            }
            guard let form = OWSUploadForm.parseDictionary(formDictionary) else {
                Logger.warn("formDictionary: \(formDictionary)")
                throw OWSAssertionError("Invalid form dictionary.")
            }
            let serverId: UInt64 = form.attachmentId?.uint64Value ?? 0
            guard serverId > 0 else {
                Logger.warn("serverId: \(serverId)")
                throw OWSAssertionError("Invalid serverId.")
            }

            self.serverId = serverId

            return form
        }.then(on: .global()) { (form: OWSUploadForm) -> Promise<(form: OWSUploadForm, attachmentData: Data)> in
            return firstly {
                return self.attachmentData()
            }.map(on: .global()) { (attachmentData: Data) in
                return (form, attachmentData)
            }
        }.then(on: .global()) { (form: OWSUploadForm, attachmentData: Data) -> Promise<String> in
            let uploadUrlPath = "attachments/"
            return OWSUploadV2.upload(data: attachmentData,
                                      uploadForm: form,
                                      uploadUrlPath: uploadUrlPath,
                                      progressBlock: progressBlock)
        }.map(on: .global()) { [weak self] (_) throws -> Void in
            self?.uploadTimestamp = NSDate.ows_millisecondTimeStamp()
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    func upload(progressBlock: ((Progress) -> Void)? = nil) -> AnyPromise {
        return AnyPromise(upload(progressBlock: progressBlock))
    }

    func upload(progressBlock: ((Progress) -> Void)? = nil) -> Promise<Void> {

        return firstly(on: .global()) {
            self.fetchUploadForm()
        }.then(on: .global()) { [weak self] (formResponseObject: Any?) -> Promise<Void> in
            guard let self = self else {
                throw OWSAssertionError("Upload deallocated")
            }
            return self.parseFormAndUpload(formResponseObject: formResponseObject,
                                           progressBlock: progressBlock).asVoid()
        }
    }

    private func fetchUploadForm(skipWebsocket: Bool = false) -> Promise<Any?> {
        return firstly(on: .global()) { () -> Promise<Any?> in
            let formRequest: TSRequest = OWSRequestFactory.allocAttachmentRequest()
            let shouldUseWebsocket = self.socketManager.canMakeRequests() && !skipWebsocket
            if shouldUseWebsocket {
                return firstly(on: .global()) { () -> Promise<Any?> in
                    self.socketManager.makeRequestPromise(request: formRequest)
                }.recover(on: .global()) { (_) -> Promise<Any?> in
                    // Failover to REST request.
                    self.fetchUploadForm(skipWebsocket: true)
                }
            } else {
                return firstly(on: .global()) {
                    return self.networkManager.makePromise(request: formRequest)
                }.map(on: .global()) { (_: URLSessionDataTask, responseObject: Any?) -> Any? in
                    return responseObject
                }
            }
        }
    }
}

// MARK: -

public extension OWSUploadV2 {

    // MARK: - Dependencies

    private class var uploadSessionManager: AFHTTPSessionManager {
        OWSSignalService.sharedInstance().cdnSessionManager(forCdnNumber: 0)
    }

    // MARK: -

    class func upload(data: Data,
                      uploadForm: OWSUploadForm,
                      uploadUrlPath: String,
                      progressBlock: ((Progress) -> Void)? = nil) -> Promise<String> {
        let (promise, resolver) = Promise<String>.pending()
        DispatchQueue.global().async {
            self.uploadSessionManager.post(uploadUrlPath,
                                           parameters: nil,
                                           constructingBodyWith: { (formData: AFMultipartFormData) -> Void in

                                            // We have to build up the form manually vs. simply passing in a parameters dict
                                            // because AWS is sensitive to the order of the form params (at least the "key"
                                            // field must occur early on).
                                            //
                                            // For consistency, all fields are ordered here in a known working order.
                                            uploadForm.append(toForm: formData)

                                            AppendMultipartFormPath(formData, "Content-Type", OWSMimeTypeApplicationOctetStream)

                                            formData.appendPart(withForm: data, name: "file")
            },
                                           progress: { progress in
                                            Logger.verbose("progress: \(progress.fractionCompleted)")

                                            if let progressBlock = progressBlock {
                                                progressBlock(progress)
                                            }
            },
                                           success: { (_, _) in
                                            Logger.verbose("Success.")
                                            let uploadedUrlPath = uploadForm.key
                                            resolver.fulfill(uploadedUrlPath)
            }, failure: { (task, error) in
                if let task = task {
                    #if TESTABLE_BUILD
                    TSNetworkManager.logCurl(for: task)
                    #endif
                } else {
                    owsFailDebug("Missing task.")
                }

                if IsNetworkConnectivityFailure(error) {
                    Logger.warn("Error: \(error)")
                } else {
                    owsFailDebug("Error: \(error)")
                }
                resolver.reject(error)
            })
        }
        return promise
    }
}

// MARK: -

public extension OWSUploadForm {
    class func parse(proto attributesProto: GroupsProtoAvatarUploadAttributes) throws -> OWSUploadForm {

        guard let acl = attributesProto.acl else {
            throw OWSAssertionError("Missing acl.")
        }
        guard let key = attributesProto.key else {
            throw OWSAssertionError("Missing key.")
        }
        guard let policy = attributesProto.policy else {
            throw OWSAssertionError("Missing policy.")
        }
        guard let algorithm = attributesProto.algorithm else {
            throw OWSAssertionError("Missing algorithm.")
        }
        guard let credential = attributesProto.credential else {
            throw OWSAssertionError("Missing credential.")
        }
        guard let date = attributesProto.date else {
            throw OWSAssertionError("Missing acl.")
        }
        guard let signature = attributesProto.signature else {
            throw OWSAssertionError("Missing signature.")
        }

        return OWSUploadForm(acl: acl,
                             key: key,
                             policy: policy,
                             algorithm: algorithm,
                             credential: credential,
                             date: date,
                             signature: signature,
                             attachmentId: nil,
                             attachmentIdString: nil)
    }
}
