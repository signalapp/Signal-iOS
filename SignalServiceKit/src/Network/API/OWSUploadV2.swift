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
