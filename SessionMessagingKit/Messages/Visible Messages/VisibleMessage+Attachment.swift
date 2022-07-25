// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import CoreGraphics
import SessionUtilitiesKit

public extension VisibleMessage {
    class VMAttachment: Codable {
        public enum Kind: String, Codable {
            case voiceMessage, generic
        }
        
        public var fileName: String?
        public var contentType: String?
        public var key: Data?
        public var digest: Data?
        public var kind: Kind?
        public var caption: String?
        public var size: CGSize?
        public var sizeInBytes: UInt?
        public var url: String?

        public var isValid: Bool {
            // key and digest can be nil for open group attachments
            contentType != nil && kind != nil && size != nil && sizeInBytes != nil && url != nil
        }
        
        // MARK: - Initialization

        internal init(
            fileName: String?,
            contentType: String?,
            key: Data?,
            digest: Data?,
            kind: Kind?,
            caption: String?,
            size: CGSize?,
            sizeInBytes: UInt?,
            url: String?
        ) {
            self.fileName = fileName
            self.contentType = contentType
            self.key = key
            self.digest = digest
            self.kind = kind
            self.caption = caption
            self.size = size
            self.sizeInBytes = sizeInBytes
            self.url = url
        }
        
        // MARK: - Proto Conversion

        public static func fromProto(_ proto: SNProtoAttachmentPointer) -> VMAttachment? {
            func inferContentType() -> String {
                guard
                    let fileName: String = proto.fileName,
                    let fileExtension: String = URL(string: fileName)?.pathExtension
                else { return OWSMimeTypeApplicationOctetStream }
                
                return (MIMETypeUtil.mimeType(forFileExtension: fileExtension) ?? OWSMimeTypeApplicationOctetStream)
            }
            
            return VMAttachment(
                fileName: proto.fileName,
                contentType: (proto.contentType ?? inferContentType()),
                key: proto.key,
                digest: proto.digest,
                kind: {
                    if proto.hasFlags && (proto.flags & UInt32(SNProtoAttachmentPointer.SNProtoAttachmentPointerFlags.voiceMessage.rawValue)) > 0 {
                        return .voiceMessage
                    }
                    
                    return .generic
                }(),
                caption: (proto.hasCaption ? proto.caption : nil),
                size: {
                    if proto.hasWidth && proto.width > 0 && proto.hasHeight && proto.height > 0 {
                        return CGSize(width: Int(proto.width), height: Int(proto.height))
                    }
                    
                    return .zero
                }(),
                sizeInBytes: (proto.size > 0 ? UInt(proto.size) : nil),
                url: proto.url
            )
        }

        public func toProto() -> SNProtoDataMessageQuote? {
            fatalError("Not implemented.")
        }
    }
}
