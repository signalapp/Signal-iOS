//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Upload {
    public struct CDN0 {
        public struct Form: Codable {
            let acl: String
            let key: String
            let policy: String
            let algorithm: String
            let credential: String
            let date: String
            let signature: String
            let attachmentId: UInt64?
            let attachmentIdString: String?
        }
    }
}

extension Upload.CDN0.Form {
    public enum ParsingError: Error {
        case missingField(String)
    }

    public static func parse(proto: GroupsProtoAvatarUploadAttributes) throws -> Self {
        guard let acl = proto.acl else { throw ParsingError.missingField("acl") }
        guard let key = proto.key else { throw ParsingError.missingField("key") }
        guard let policy = proto.policy else { throw ParsingError.missingField("policy") }
        guard let algorithm = proto.algorithm else { throw ParsingError.missingField("algorithm") }
        guard let credential = proto.credential else { throw ParsingError.missingField("credential") }
        guard let date = proto.date else { throw ParsingError.missingField("date") }
        guard let signature = proto.signature else { throw ParsingError.missingField("signature") }

        return .init(
            acl: acl,
            key: key,
            policy: policy,
            algorithm: algorithm,
            credential: credential,
            date: date,
            signature: signature,
            attachmentId: nil,
            attachmentIdString: nil
        )
    }
}

extension Upload.CDN0 {
    public static func upload(data: Data, uploadForm: Upload.CDN0.Form) async throws -> String {
        if DependenciesBridge.shared.appExpiry.isExpired {
            throw OWSAssertionError("App is expired.")
        }

        let dataFileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
        try data.write(to: dataFileUrl)

        let cdn0UrlSession = OWSAttachmentDownloads.signalService.urlSessionForCdn(cdnNumber: 0)
        // urlPath is "" for all endpoints that still use CDN0
        let request = try cdn0UrlSession.endpoint.buildRequest("", method: .post)

        // We have to build up the form manually vs. simply passing in a parameters dict
        // because AWS is sensitive to the order of the form params (at least the "key"
        // field must occur early on).
        //
        // For consistency, all fields are ordered here in a known working order.
        var textParts = uploadForm.asOrderedDictionary
        textParts.append(key: "Content-Type", value: OWSMimeTypeApplicationOctetStream)

        _ = try await cdn0UrlSession.multiPartUploadTaskPromise(
            request: request,
            fileUrl: dataFileUrl,
            name: "file",
            fileName: "file",
            mimeType: OWSMimeTypeApplicationOctetStream,
            textParts: textParts
        ).awaitable()

        return uploadForm.key
    }
}

// See: https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-UsingHTTPPOST.html
fileprivate extension Upload.CDN0.Form {
    var asOrderedDictionary: OrderedDictionary<String, String> {
        // We have to build up the form manually vs. simply passing in a parameters dict
        // because AWS is sensitive to the order of the form params (at least the "key"
        // field must occur early on).
        var result = OrderedDictionary<String, String>()

        // For consistency, all fields are ordered here in a known working order.
        result.append(key: "key", value: self.key)
        result.append(key: "acl", value: self.acl)
        result.append(key: "x-amz-algorithm", value: self.algorithm)
        result.append(key: "x-amz-credential", value: self.credential)
        result.append(key: "x-amz-date", value: self.date)
        result.append(key: "policy", value: self.policy)
        result.append(key: "x-amz-signature", value: self.signature)
        return result
    }

}
