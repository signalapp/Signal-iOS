//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class OWSUploadV2: NSObject {
    @objc
    public class func uploadObjc(data: Data,
                                 uploadForm: OWSUploadFormV2,
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

    private var signalService: OWSSignalService {
        return OWSSignalService.sharedInstance()
    }

    // MARK: -

    // These properties are only set for v2 uploads.
    // For other uploads we use these defaults.
    //
    // These properties are set on success;
    // They should not be accessed before.
    @objc
    public var encryptionKey: Data?
    @objc
    public var digest: Data?
    @objc
    public var serverId: UInt64 = 0

    // These properties are only set for v3 uploads.
    // For other uploads we use these defaults.
    //
    // These properties are set on success;
    // They should not be accessed before.
    @objc
    public var cdnKey: String = ""
    @objc
    public var cdnNumber: UInt32 = 0

    // These properties are set on success;
    // They should not be accessed before.
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

    @objc
    @available(swift, obsoleted: 1.0)
    public func upload(progressBlock: ((Progress) -> Void)? = nil) -> AnyPromise {
        return AnyPromise(upload(progressBlock: progressBlock))
    }

    public func upload(progressBlock: ((Progress) -> Void)? = nil) -> Promise<Void> {
        return (FeatureFlags.attachmentUploadV3
            ? uploadV3(progressBlock: progressBlock)
            : uploadV2(progressBlock: progressBlock))
    }

    // Performs a request, trying to use the websocket
    // and failing over to REST.
    private func performRequest(skipWebsocket: Bool = false,
                                requestBlock: @escaping () -> TSRequest) -> Promise<Any?> {
        return firstly(on: .global()) { () -> Promise<Any?> in
            let formRequest = requestBlock()
            let shouldUseWebsocket = self.socketManager.canMakeRequests() && !skipWebsocket
            if shouldUseWebsocket {
                return firstly(on: .global()) { () -> Promise<Any?> in
                    self.socketManager.makeRequestPromise(request: formRequest)
                }.recover(on: .global()) { (_) -> Promise<Any?> in
                    // Failover to REST request.
                    self.performRequest(skipWebsocket: true, requestBlock: requestBlock)
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

    // MARK: - V2

    public func uploadV2(progressBlock: ((Progress) -> Void)? = nil) -> Promise<Void> {
        return firstly(on: .global()) {
            // Fetch attachment upload form.
            return self.performRequest {
                return OWSRequestFactory.allocAttachmentRequestV2()
            }
        }.then(on: .global()) { [weak self] (formResponseObject: Any?) -> Promise<OWSUploadFormV2> in
            guard let self = self else {
                throw OWSAssertionError("Upload deallocated")
            }
            return self.parseUploadFormV2(formResponseObject: formResponseObject,
                                          progressBlock: progressBlock)
        }.then(on: .global()) { (form: OWSUploadFormV2) -> Promise<(form: OWSUploadFormV2, attachmentData: Data)> in
            return firstly {
                return self.attachmentData()
            }.map(on: .global()) { (attachmentData: Data) in
                return (form, attachmentData)
            }
        }.then(on: .global()) { (form: OWSUploadFormV2, attachmentData: Data) -> Promise<String> in
            let uploadUrlPath = "attachments/"
            return OWSUploadV2.upload(data: attachmentData,
                                      uploadForm: form,
                                      uploadUrlPath: uploadUrlPath,
                                      progressBlock: progressBlock)
        }.map(on: .global()) { [weak self] (_) throws -> Void in
            self?.uploadTimestamp = NSDate.ows_millisecondTimeStamp()
        }
    }

    private func parseUploadFormV2(formResponseObject: Any?,
                                   progressBlock: ((Progress) -> Void)? = nil) -> Promise<OWSUploadFormV2> {

        return firstly(on: .global()) { () -> OWSUploadFormV2 in
            guard let formDictionary = formResponseObject as? [AnyHashable: Any] else {
                Logger.warn("formResponseObject: \(String(describing: formResponseObject))")
                throw OWSAssertionError("Invalid form.")
            }
            guard let form = OWSUploadFormV2.parseDictionary(formDictionary) else {
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
        }
    }

    // MARK: - V3

    public func uploadV3(progressBlock: ((Progress) -> Void)? = nil) -> Promise<Void> {
        return firstly(on: .global()) {
            // Fetch attachment upload form.
            return self.performRequest {
                return OWSRequestFactory.allocAttachmentRequestV3()
            }
        }.map(on: .global()) { [weak self] (formResponseObject: Any?) -> OWSUploadFormV3 in
            guard let self = self else {
                throw OWSAssertionError("Upload deallocated")
            }
            // Parse upload form.
            let form = try OWSUploadFormV3(responseObject: formResponseObject)

            // TODO: Do we need to set other properties?
            self.cdnKey = form.cdnKey
            self.cdnNumber = form.cdnNumber

            return form
        }.then(on: .global()) { (form: OWSUploadFormV3) -> Promise<(form: OWSUploadFormV3, attachmentData: Data)> in
            return firstly {
                return self.attachmentData()
            }.map(on: .global()) { (attachmentData: Data) in
                return (form, attachmentData)
            }
        }.then(on: .global()) { (form: OWSUploadFormV3, attachmentData: Data) -> Promise<(form: OWSUploadFormV3, attachmentData: Data, locationUrl: URL)> in
            return firstly { () -> Promise<URL> in
                return self.fetchResumableUploadLocationV3(form: form,
                                                           attachmentData: attachmentData)
            }.map(on: .global()) { (locationUrl: URL) in
                //                return (form, attachmentData)
                return (form, attachmentData, locationUrl)
            }
        }.map(on: .global()) { (_) throws -> Void in
            //            let uploadUrlPath = "attachments/"
            //            return OWSUploadV3.upload(data: attachmentData,
            //                                      uploadForm: form,
            //                                      uploadUrlPath: uploadUrlPath,
            //                                      progressBlock: progressBlock)

            throw OWSAssertionError("TODO")
        }.map(on: .global()) { (_) throws -> Void in
            self.uploadTimestamp = NSDate.ows_millisecondTimeStamp()
        }
    }

    private func fetchResumableUploadLocationV3(form: OWSUploadFormV3,
                                                attachmentData: Data) -> Promise<URL> {
        return firstly(on: .global()) { () -> Promise<AFHTTPSessionManager.Response> in
            let urlString = form.signedUploadLocation
            let sessionManager = self.signalService.cdnSessionManager(forCdnNumber: form.cdnNumber)
            var headers = form.headers
            headers["Content-Length"] = OWSFormat.formatInt(attachmentData.count)
            headers["Content-Type"] = OWSMimeTypeApplicationOctetStream

            return sessionManager.postPromise(urlString)
        }.map(on: .global()) { (task: URLSessionDataTask, _: Any?) in
            guard let response = task.response as? HTTPURLResponse else {
                throw OWSAssertionError("Missing response.")
            }
            guard response.statusCode == 201 else {
                throw OWSAssertionError("Invalid statusCode: \(response.statusCode).")
            }
            guard let locationHeader = response.allHeaderFields["Location"] as? String else {
                throw OWSAssertionError("Missing location header.")
            }
            guard let locationUrl = URL(string: locationHeader) else {
                throw OWSAssertionError("Invalid location header.")
            }
            return locationUrl
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
                      uploadForm: OWSUploadFormV2,
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

public extension OWSUploadFormV2 {
    class func parse(proto attributesProto: GroupsProtoAvatarUploadAttributes) throws -> OWSUploadFormV2 {

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

        return OWSUploadFormV2(acl: acl,
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

// MARK: -

private class OWSUploadFormV3: NSObject {

    let headers: [String: String]
    let signedUploadLocation: String
    let cdnKey: String
    let cdnNumber: UInt32

    //    let
    //// These properties will be set for all uploads.
    //@property (nonatomic, readonly) NSString *acl;
    //@property (nonatomic, readonly) NSString *key;
    //@property (nonatomic, readonly) NSString *policy;
    //@property (nonatomic, readonly) NSString *algorithm;
    //@property (nonatomic, readonly) NSString *credential;
    //@property (nonatomic, readonly) NSString *date;
    //@property (nonatomic, readonly) NSString *signature;
    //
    //// These properties will be set for all attachment uploads.
    //@property (nonatomic, readonly, nullable) NSNumber *attachmentId;
    //@property (nonatomic, readonly, nullable) NSString *attachmentIdString;
    //
    //+ (instancetype)new NS_UNAVAILABLE;
    //- (instancetype)init NS_UNAVAILABLE;
    //
    //- (instancetype)initWithAcl:(NSString *)acl
    //key:(NSString *)key
    //policy:(NSString *)policy
    //algorithm:(NSString *)algorithm
    //credential:(NSString *)credential
    //date:(NSString *)date
    //signature:(NSString *)signature
    //attachmentId:(nullable NSNumber *)attachmentId
    //attachmentIdString:(nullable NSString *)attachmentIdString NS_DESIGNATED_INITIALIZER;
    //
    //+ (nullable OWSUploadFormV2 *)parseDictionary:(nullable NSDictionary *)formResponseObject;
    //
    //- (void)appendToForm:(id<AFMultipartFormData>)formData;
    //
    //@end
    //
    //
    //    // See: https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-UsingHTTPPOST.html
    //    @implementation OWSUploadFormV2
    //
    //    - (instancetype)initWithAcl:(NSString *)acl
    //    key:(NSString *)key
    //    policy:(NSString *)policy
    //    algorithm:(NSString *)algorithm
    //    credential:(NSString *)credential
    //    date:(NSString *)date
    //    signature:(NSString *)signature
    //    attachmentId:(nullable NSNumber *)attachmentId
    //    attachmentIdString:(nullable NSString *)attachmentIdString
    //    {
    //    self = [super init];
    //
    //    if (self) {
    //    _acl = acl;
    //    _key = key;
    //    _policy = policy;
    //    _algorithm = algorithm;
    //    _credential = credential;
    //    _date = date;
    //    _signature = signature;
    //    _attachmentId = attachmentId;
    //    _attachmentIdString = attachmentIdString;
    //    }
    //    return self;
    //    }

    required init(responseObject: Any?) throws {
        Logger.verbose("responseObject: \(responseObject)")

        guard let parser = ParamParser(responseObject: responseObject) else {
            throw OWSAssertionError("Invalid formResponseObject.")
        }
        cdnKey = try parser.required(key: "key")
        guard !cdnKey.isEmpty else {
            throw OWSAssertionError("Invalid cdnKey.")
        }
        cdnNumber = try parser.required(key: "cdn")
        guard cdnNumber > 0 else {
            throw OWSAssertionError("Invalid cdnNumber.")
        }
        signedUploadLocation = try parser.required(key: "signedUploadLocation")
        guard !signedUploadLocation.isEmpty else {
            throw OWSAssertionError("Invalid signedUploadLocation.")
        }
        headers = try parser.required(key: "headers")
    }
    //
    //
    //    - (void)appendToForm:(id<AFMultipartFormData>)formData
    //    {
    //    // We have to build up the form manually vs. simply passing in a paramaters dict
    //    // because AWS is sensitive to the order of the form params (at least the "key"
    //    // field must occur early on).
    //    //
    //    // For consistency, all fields are ordered here in a known working order.
    //    AppendMultipartFormPath(formData, @"key", self.key);
    //    AppendMultipartFormPath(formData, @"acl", self.acl);
    //    AppendMultipartFormPath(formData, @"x-amz-algorithm", self.algorithm);
    //    AppendMultipartFormPath(formData, @"x-amz-credential", self.credential);
    //    AppendMultipartFormPath(formData, @"x-amz-date", self.date);
    //    AppendMultipartFormPath(formData, @"policy", self.policy);
    //    AppendMultipartFormPath(formData, @"x-amz-signature", self.signature);
    //    }
    //
    //    @end
}
